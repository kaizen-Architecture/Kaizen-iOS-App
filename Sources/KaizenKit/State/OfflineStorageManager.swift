import Foundation
import UIKit
import Network

/// Gestor integral de descargas locales, almacenamiento seguro en Sandbox y sincronización diferida.
/// Los archivos se guardan en `Application Support/KaizenOffline/{mangaId}/{chapterId}/`
/// y se marcan como excluidos del backup de iCloud (`isExcludedFromBackup = true`).
@MainActor
@Observable
public final class OfflineStorageManager {
    public static let shared = OfflineStorageManager()
    
    public private(set) var offlineMangas: [OfflineMangaMetadata] = []
    public private(set) var activeDownloads: [String: Double] = [:] // key: "{mangaId}_{chapterId}", value: 0.0...1.0
    public private(set) var pendingSyncActions: [PendingSyncReadAction] = []
    public var settings: OfflineStorageSettings = OfflineStorageSettings()
    
    private let fileManager = FileManager.default
    private let baseOfflineDir: URL
    private let metadataFile: URL
    private let pendingSyncFile: URL
    private let settingsFile: URL
    
    // Monitor de red para reconexión y sincronización automática
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "io.kaizen.networkMonitor")
    public private(set) var isOnline: Bool = true
    public private(set) var isWifi: Bool = true
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseOfflineDir = appSupport.appendingPathComponent("KaizenOffline", isDirectory: true)
        metadataFile = baseOfflineDir.appendingPathComponent("offline_metadata.json")
        pendingSyncFile = baseOfflineDir.appendingPathComponent("pending_sync.json")
        settingsFile = baseOfflineDir.appendingPathComponent("offline_settings.json")
        
        try? fileManager.createDirectory(at: baseOfflineDir, withIntermediateDirectories: true)
        
        // Excluir toda la carpeta de descargas de la copia de iCloud
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDir = baseOfflineDir
        try? mutableDir.setResourceValues(values)
        
        loadSettings()
        loadMetadata()
        loadPendingSync()
        startNetworkMonitoring()
        enforceRetentionPolicy()
    }
    
    // MARK: - Estado de Red y Sincronización Diferida
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isOnline = (path.status == .satisfied)
                self.isWifi = path.usesInterfaceType(.wifi)
                if self.isOnline {
                    Task { await self.flushPendingSyncsIfNeeded() }
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    // MARK: - Rutas de Archivos en Disco
    
    public func mangaDirectory(mangaId: Int) -> URL {
        baseOfflineDir.appendingPathComponent("manga_\(mangaId)", isDirectory: true)
    }
    
    public func chapterDirectory(mangaId: Int, chapterId: Int) -> URL {
        mangaDirectory(mangaId: mangaId).appendingPathComponent("ch_\(chapterId)", isDirectory: true)
    }
    
    public func coverLocalURL(mangaId: Int) -> URL? {
        guard let manga = offlineMangas.first(where: { $0.id == mangaId }),
              let coverName = manga.coverLocalFileName else { return nil }
        let file = mangaDirectory(mangaId: mangaId).appendingPathComponent(coverName)
        return fileManager.fileExists(atPath: file.path) ? file : nil
    }
    
    public func isChapterDownloaded(mangaId: Int, chapterId: Int) -> Bool {
        guard let manga = offlineMangas.first(where: { $0.id == mangaId }) else { return false }
        return manga.chapters.contains(where: { $0.id == chapterId })
    }
    
    public func isMangaFullyDownloaded(mangaId: Int, totalAvailableChapters: Int) -> Bool {
        guard let manga = offlineMangas.first(where: { $0.id == mangaId }), totalAvailableChapters > 0 else { return false }
        return manga.chapters.count >= totalAvailableChapters
    }
    
    public func localChapterPages(mangaId: Int, chapterId: Int) -> [URL]? {
        let chDir = chapterDirectory(mangaId: mangaId, chapterId: chapterId)
        guard fileManager.fileExists(atPath: chDir.path) else { return nil }
        guard let items = try? fileManager.contentsOfDirectory(at: chDir, includingPropertiesForKeys: nil) else { return nil }
        
        let imageFiles = items.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "webp"
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        
        return imageFiles.isEmpty ? nil : imageFiles
    }
    
    // MARK: - Descarga de Capítulos
    
    public func downloadChapter(
        manga: Manga,
        chapter: Chapter,
        apiClient: KaizenAPIClient,
        session: UserSession?
    ) async throws {
        guard let session else { return }
        if settings.downloadWifiOnly && !isWifi {
            throw NSError(domain: "KaizenOffline", code: 4001, userInfo: [NSLocalizedDescriptionKey: "Descarga pausada: Configurado solo para Wi-Fi"])
        }
        
        let downloadKey = "\(manga.id)_\(chapter.id)"
        activeDownloads[downloadKey] = 0.01
        defer { activeDownloads.removeValue(forKey: downloadKey) }
        
        // 1. Crear directorios
        let chDir = chapterDirectory(mangaId: manga.id, chapterId: chapter.id)
        try fileManager.createDirectory(at: chDir, withIntermediateDirectories: true)
        
        // 2. Descargar y guardar carátula si aún no existe
        var savedCoverFileName: String? = nil
        let mangaDir = mangaDirectory(mangaId: manga.id)
        try fileManager.createDirectory(at: mangaDir, withIntermediateDirectories: true)
        let localCover = mangaDir.appendingPathComponent("cover.jpg")
        if fileManager.fileExists(atPath: localCover.path) {
            savedCoverFileName = "cover.jpg"
        } else if let coverStr = manga.coverUrl, let coverURL = URL(string: coverStr),
                  let coverImg = await ImageLoader.shared.image(for: coverURL, token: session.apiToken),
                  let coverData = coverImg.jpegData(compressionQuality: 0.88) {
            try? coverData.write(to: localCover, options: .atomic)
            savedCoverFileName = "cover.jpg"
        }
        
        // 3. Obtener URLs de páginas del capítulo
        let pageUrls = try await apiClient.fetchChapterPages(
            serverUrl: session.serverUrl,
            token: session.apiToken,
            mangaId: manga.id,
            chapterId: chapter.id,
            isPrefetch: true
        )
        guard !pageUrls.isEmpty else { return }
        
        // 4. Descargar páginas en secuencia y guardarlas en disco
        var totalBytes: Int64 = 0
        let total = Double(pageUrls.count)
        
        for (idx, pageStr) in pageUrls.enumerated() {
            guard let pageURL = URL(string: pageStr) else { continue }
            let pageExt = pageURL.pathExtension.isEmpty ? "jpg" : pageURL.pathExtension
            let pageName = String(format: "page_%03d.%@", idx + 1, pageExt)
            let destination = chDir.appendingPathComponent(pageName)
            
            // Reutilizar o descargar imagen
            var request = URLRequest(url: pageURL)
            request.timeoutInterval = 25
            if !session.apiToken.isEmpty {
                request.setValue("Bearer \(session.apiToken)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            
            try data.write(to: destination, options: .atomic)
            totalBytes += Int64(data.count)
            
            activeDownloads[downloadKey] = Double(idx + 1) / total
        }
        
        // 5. Registrar en metadatos
        let downloadedChapter = OfflineDownloadedChapter(
            id: chapter.id,
            mangaId: manga.id,
            index: chapter.index,
            title: chapter.displayName,
            pageCount: pageUrls.count,
            totalSizeBytes: totalBytes,
            downloadedAt: Date(),
            lastReadPage: chapter.lastReadPage,
            isRead: chapter.isRead
        )
        
        if let existingIdx = offlineMangas.firstIndex(where: { $0.id == manga.id }) {
            offlineMangas[existingIdx].chapters.removeAll(where: { $0.id == chapter.id })
            offlineMangas[existingIdx].chapters.append(downloadedChapter)
            offlineMangas[existingIdx].chapters.sort { $0.index < $1.index }
            if savedCoverFileName != nil {
                offlineMangas[existingIdx].coverLocalFileName = savedCoverFileName
            }
        } else {
            let newMeta = OfflineMangaMetadata(
                id: manga.id,
                title: manga.title,
                coverLocalFileName: savedCoverFileName,
                coverRemoteUrl: manga.coverUrl,
                synopsis: manga.synopsis,
                authors: manga.authors,
                genres: manga.genres,
                status: manga.status,
                chapters: [downloadedChapter]
            )
            offlineMangas.append(newMeta)
        }
        
        saveMetadata()
    }
    
    public func downloadManga(
        _ manga: Manga,
        chapters: [Chapter],
        apiClient: KaizenAPIClient,
        session: UserSession?,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async {
        let pending = chapters.filter { !isChapterDownloaded(mangaId: manga.id, chapterId: $0.id) }
        for (idx, ch) in pending.enumerated() {
            do {
                try await downloadChapter(manga: manga, chapter: ch, apiClient: apiClient, session: session)
                progressHandler?(idx + 1, pending.count)
            } catch {
                // Continuar con los siguientes si uno falla
            }
        }
    }
    
    // MARK: - Eliminación de Capítulos / Mangas Locales
    
    public func deleteChapter(mangaId: Int, chapterId: Int) {
        let chDir = chapterDirectory(mangaId: mangaId, chapterId: chapterId)
        try? fileManager.removeItem(at: chDir)
        
        if let mIdx = offlineMangas.firstIndex(where: { $0.id == mangaId }) {
            offlineMangas[mIdx].chapters.removeAll(where: { $0.id == chapterId })
            if offlineMangas[mIdx].chapters.isEmpty {
                deleteManga(mangaId: mangaId)
                return
            }
        }
        saveMetadata()
    }
    
    public func deleteManga(mangaId: Int) {
        let mDir = mangaDirectory(mangaId: mangaId)
        try? fileManager.removeItem(at: mDir)
        offlineMangas.removeAll(where: { $0.id == mangaId })
        saveMetadata()
    }
    
    public func deleteAllReadChapters() {
        for manga in offlineMangas {
            for ch in manga.chapters where ch.isRead {
                deleteChapter(mangaId: manga.id, chapterId: ch.id)
            }
        }
    }
    
    public var totalStorageUsedBytes: Int64 {
        offlineMangas.reduce(0) { $0 + $1.totalSizeBytes }
    }
    
    public var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: totalStorageUsedBytes, countStyle: .file)
    }
    
    // MARK: - Registro de Lectura Offline y Sincronización Diferida
    
    public func recordOfflineReading(
        mangaId: Int,
        chapterId: Int,
        page: Int,
        totalPages: Int,
        isRead: Bool,
        apiClient: KaizenAPIClient,
        session: UserSession?
    ) {
        // 1. Actualizar estado en metadatos locales
        if let mIdx = offlineMangas.firstIndex(where: { $0.id == mangaId }),
           let cIdx = offlineMangas[mIdx].chapters.firstIndex(where: { $0.id == chapterId }) {
            offlineMangas[mIdx].chapters[cIdx].lastReadPage = page
            if isRead {
                offlineMangas[mIdx].chapters[cIdx].isRead = true
            }
            saveMetadata()
        }
        
        // 2. Si hay conexión directa, enviar inmediatamente al servidor Kaizen
        if isOnline, let session {
            Task {
                do {
                    if isRead {
                        try await apiClient.toggleChapterRead(
                            serverUrl: session.serverUrl,
                            token: session.apiToken,
                            mangaId: mangaId,
                            chapterId: chapterId,
                            isRead: true
                        )
                    }
                    try await apiClient.updateReadingProgress(
                        serverUrl: session.serverUrl,
                        token: session.apiToken,
                        mangaId: mangaId,
                        chapterId: chapterId,
                        page: page,
                        totalPages: totalPages
                    )
                    
                    if settings.autoDeleteWhenRead && isRead {
                        deleteChapter(mangaId: mangaId, chapterId: chapterId)
                    }
                } catch {
                    // Fallback a cola offline si la llamada en vivo falla
                    enqueuePendingSync(action: PendingSyncReadAction(
                        mangaId: mangaId,
                        chapterId: chapterId,
                        page: page,
                        totalPages: totalPages,
                        isRead: isRead
                    ))
                }
            }
            return
        }
        
        // 3. Encolar en disco si estamos sin conexión
        enqueuePendingSync(action: PendingSyncReadAction(
            mangaId: mangaId,
            chapterId: chapterId,
            page: page,
            totalPages: totalPages,
            isRead: isRead
        ))
    }
    
    private func enqueuePendingSync(action: PendingSyncReadAction) {
        pendingSyncActions.removeAll(where: { $0.mangaId == action.mangaId && $0.chapterId == action.chapterId })
        pendingSyncActions.append(action)
        savePendingSync()
    }
    
    public func flushPendingSyncsIfNeeded(client: KaizenAPIClient? = nil, session: UserSession? = nil) async {
        guard !pendingSyncActions.isEmpty else { return }
        let currentSession = session ?? (try? KeychainService.shared.loadSession())
        guard let currentSession else { return }
        let apiClient = client ?? KaizenAPIClient()
        
        var remainingActions: [PendingSyncReadAction] = []
        
        for action in pendingSyncActions {
            do {
                if action.isRead {
                    try await apiClient.toggleChapterRead(
                        serverUrl: currentSession.serverUrl,
                        token: currentSession.apiToken,
                        mangaId: action.mangaId,
                        chapterId: action.chapterId,
                        isRead: true
                    )
                }
                try await apiClient.updateReadingProgress(
                    serverUrl: currentSession.serverUrl,
                    token: currentSession.apiToken,
                    mangaId: action.mangaId,
                    chapterId: action.chapterId,
                    page: action.page,
                    totalPages: action.totalPages
                )
                
                if settings.autoDeleteWhenRead && action.isRead {
                    deleteChapter(mangaId: action.mangaId, chapterId: action.chapterId)
                }
            } catch {
                remainingActions.append(action)
            }
        }
        
        pendingSyncActions = remainingActions
        savePendingSync()
    }
    
    // MARK: - Política de Retención Temporal
    
    private func enforceRetentionPolicy() {
        guard settings.retentionDays > 0 else { return }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -settings.retentionDays, to: Date()) ?? Date()
        
        for manga in offlineMangas {
            for ch in manga.chapters where ch.downloadedAt < cutoffDate {
                deleteChapter(mangaId: manga.id, chapterId: ch.id)
            }
        }
    }
    
    // MARK: - Persistencia JSON
    
    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(offlineMangas) else { return }
        try? data.write(to: metadataFile, options: .atomic)
    }
    
    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataFile),
              let list = try? JSONDecoder().decode([OfflineMangaMetadata].self, from: data) else { return }
        self.offlineMangas = list
    }
    
    private func savePendingSync() {
        guard let data = try? JSONEncoder().encode(pendingSyncActions) else { return }
        try? data.write(to: pendingSyncFile, options: .atomic)
    }
    
    private func loadPendingSync() {
        guard let data = try? Data(contentsOf: pendingSyncFile),
              let list = try? JSONDecoder().decode([PendingSyncReadAction].self, from: data) else { return }
        self.pendingSyncActions = list
    }
    
    public func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile, options: .atomic)
    }
    
    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsFile),
              let loaded = try? JSONDecoder().decode(OfflineStorageSettings.self, from: data) else { return }
        self.settings = loaded
    }
}
