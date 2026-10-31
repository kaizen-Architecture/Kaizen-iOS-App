import Foundation
import UIKit

/// Gestor de precarga predictiva en segundo plano para capítulos de manga.
/// Permite transiciones instantáneas descargando preventivamente las listas de páginas
/// y las imágenes en la caché de disco/memoria antes de que el usuario las solicite.
public actor ChapterPrefetchManager {
    public static let shared = ChapterPrefetchManager()
    
    // Caché en memoria de URLs de páginas por chapterId
    private var pagesCache: [Int: [String]] = [:]
    
    // Tareas en progreso para evitar descargas duplicadas
    private var inFlightTasks: [Int: Task<Void, Never>] = [:]
    
    // Conjunto de capítulos que ya están completamente precargados
    private var completedChapters: Set<Int> = []
    
    private init() {}
    
    /// Devuelve las páginas en caché si ya fueron precargadas
    public func cachedPages(for chapterId: Int) -> [String]? {
        pagesCache[chapterId]
    }
    
    /// Almacena manualmente las páginas de un capítulo
    public func storePages(_ pages: [String], for chapterId: Int) {
        pagesCache[chapterId] = pages
    }
    
    /// Comprueba si un capítulo ya ha sido precargado completamente
    public func isChapterFullyCached(_ chapterId: Int) -> Bool {
        completedChapters.contains(chapterId)
    }
    
    /// Precarga el siguiente capítulo mientras el usuario lee el capítulo actual
    public func prefetchNextChapter(
        mangaId: Int,
        nextChapter: Chapter,
        apiClient: KaizenAPIClient,
        session: UserSession?
    ) async {
        guard let session else { return }
        let chapterId = nextChapter.id
        
        // Si ya está completado o en vuelo, no duplicar trabajo
        if completedChapters.contains(chapterId) || inFlightTasks[chapterId] != nil {
            return
        }
        
        let task = Task(priority: .medium) {
            await KaizenLogger.shared.info(
                "Prefetch",
                "Iniciando precarga predictiva del siguiente capítulo (Cap. \(nextChapter.index), ID: \(chapterId))"
            )
            
            do {
                // 1. Obtener URLs de páginas si no están en caché
                let pageUrls: [String]
                if let cached = pagesCache[chapterId], !cached.isEmpty {
                    pageUrls = cached
                } else {
                    pageUrls = try await apiClient.fetchChapterPages(
                        serverUrl: session.serverUrl,
                        token: session.apiToken,
                        mangaId: mangaId,
                        chapterId: chapterId
                    )
                    pagesCache[chapterId] = pageUrls
                }
                
                guard !pageUrls.isEmpty else { return }
                
                // 2. Descargar las imágenes en la caché local (ImageLoader)
                let token = session.apiToken
                await withTaskGroup(of: Void.self) { group in
                    for urlStr in pageUrls {
                        guard let url = URL(string: urlStr) else { continue }
                        group.addTask {
                            _ = await ImageLoader.shared.image(for: url, token: token)
                        }
                    }
                }
                
                completedChapters.insert(chapterId)
                await KaizenLogger.shared.info(
                    "Prefetch",
                    "Capítulo \(nextChapter.index) (ID: \(chapterId)) precargado con éxito (\(pageUrls.count) páginas listas en caché)."
                )
            } catch {
                await KaizenLogger.shared.debug(
                    "Prefetch",
                    "Aviso al precargar Cap. \(nextChapter.index): \(error.localizedDescription)"
                )
            }
            
            inFlightTasks.removeValue(forKey: chapterId)
        }
        
        inFlightTasks[chapterId] = task
    }
    
    /// Precarga en segundo plano el primer capítulo no leído de los mangas en curso
    public func prefetchFirstUnreadChapters(
        mangas: [Manga],
        apiClient: KaizenAPIClient,
        session: UserSession?
    ) async {
        guard let session else { return }
        
        // Limitar a los 3 mangas prioritarios para optimizar batería y red
        let candidateMangas = Array(mangas.prefix(3))
        
        for manga in candidateMangas {
            // Localizar el capítulo no leído más antiguo (menor índice)
            guard let chapters = manga.chapters, !chapters.isEmpty else { continue }
            guard let oldestUnread = chapters.sorted(by: { $0.index < $1.index }).first(where: { !$0.isRead }) else {
                continue
            }
            
            let chapterId = oldestUnread.id
            if completedChapters.contains(chapterId) || inFlightTasks[chapterId] != nil {
                continue
            }
            
            let task = Task(priority: .utility) {
                await KaizenLogger.shared.info(
                    "Prefetch",
                    "Precargando primer capítulo pendiente de '\(manga.title)' (Cap. \(oldestUnread.index))"
                )
                
                do {
                    let pageUrls = try await apiClient.fetchChapterPages(
                        serverUrl: session.serverUrl,
                        token: session.apiToken,
                        mangaId: manga.id,
                        chapterId: chapterId
                    )
                    pagesCache[chapterId] = pageUrls
                    
                    let token = session.apiToken
                    for urlStr in pageUrls {
                        guard let url = URL(string: urlStr) else { continue }
                        _ = await ImageLoader.shared.image(for: url, token: token)
                    }
                    
                    completedChapters.insert(chapterId)
                    await KaizenLogger.shared.info(
                        "Prefetch",
                        "Listo para lectura instantánea: '\(manga.title)' Cap. \(oldestUnread.index)"
                    )
                } catch {
                    // Silencioso en segundo plano
                }
                
                inFlightTasks.removeValue(forKey: chapterId)
            }
            
            inFlightTasks[chapterId] = task
        }
    }
    
    /// Limpia la caché en memoria al cerrar sesión
    public func clear() {
        pagesCache.removeAll()
        completedChapters.removeAll()
        for task in inFlightTasks.values {
            task.cancel()
        }
        inFlightTasks.removeAll()
    }
}
