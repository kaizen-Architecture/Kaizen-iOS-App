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
    /// `true` en datos móviles / punto de acceso personal (red "costosa").
    public private(set) var isExpensive: Bool = false
    
    /// Progreso de una descarga por lotes en curso (nil si no hay ninguna).
    public struct BatchProgress: Equatable {
        public var mangaTitle: String
        public var done: Int
        public var total: Int
        public var currentChapterProgress: Double
        public var fraction: Double {
            total == 0 ? 0 : (Double(done) + currentChapterProgress) / Double(total)
        }
    }
    public private(set) var batch: BatchProgress?
    /// Último error de descarga, mostrado al usuario (nunca se traga en silencio).
    public var lastError: String?
    /// Idioma de la app ("es"/"en"), sincronizado desde `RootAppView` para los mensajes de error.
    public var language: String = "es"
    private func tr(_ es: String, _ en: String) -> String { language == "en" ? en : es }
    
    /// Petición pendiente de confirmar por el usuario (tamaño estimado + aviso de datos móviles).
    public struct DownloadRequest: Identifiable {
        public let id = UUID()
        public let manga: Manga
        public let chapters: [Chapter]
        public let apiClient: KaizenAPIClient
        public let session: UserSession?
        /// Estimación: media de 9 MB por capítulo, o el tamaño real si el servidor lo informa.
        public var estimatedBytes: Int64 { Int64(chapters.count) * 9_000_000 }
    }
    public var pendingRequest: DownloadRequest?
    private var cancelRequested = false
    
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
                self.isExpensive = path.isExpensive
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
    
    /// Descarga una página a disco y devuelve su tamaño en bytes. No depende del actor principal.
    private nonisolated static func fetchPage(
        url: URL,
        token: String,
        destination: URL,
        failureMessage: @Sendable (Int) -> String
    ) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw NSError(domain: "KaizenOffline", code: 4003, userInfo: [NSLocalizedDescriptionKey: failureMessage(status)])
        }
        try data.write(to: destination, options: .atomic)
        return Int64(data.count)
    }
    
    public func downloadChapter(
        manga: Manga,
        chapter: Chapter,
        apiClient: KaizenAPIClient,
        session: UserSession?
    ) async throws {
        guard let session else {
            throw NSError(domain: "KaizenOffline", code: 4000, userInfo: [NSLocalizedDescriptionKey: tr("No hay sesión activa con el servidor Kaizen.", "No active session with the Kaizen server.")])
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
        
        // 3. INTENTO DIRECTO: Descargar archivo CBZ completo en 1 petición HTTP en streaming
        var didDownloadArchive = false
        var totalBytes: Int64 = 0
        var pageCount: Int = 0
        
        do {
            let tempCbz = chDir.appendingPathComponent("temp_\(chapter.id).cbz")
            defer { try? fileManager.removeItem(at: tempCbz) }
            
            try await apiClient.downloadChapterArchive(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: manga.id,
                chapterId: chapter.id,
                destination: tempCbz
            )
            
            let extracted = try ZipArchiveExtractor.extract(archiveURL: tempCbz, to: chDir)
            if !extracted.isEmpty {
                totalBytes = extracted.reduce(0) { $0 + $1.size }
                pageCount = extracted.count
                didDownloadArchive = true
                activeDownloads[downloadKey] = 1.0
                batch?.currentChapterProgress = 1.0
            }
        } catch is CancellationError {
            try? fileManager.removeItem(at: chDir)
            throw CancellationError()
        } catch {
            // Si el servidor no tiene el endpoint /download o falla la extracción,
            // limpiamos la carpeta y pasamos al fallback por páginas
            try? fileManager.removeItem(at: chDir)
            try? fileManager.createDirectory(at: chDir, withIntermediateDirectories: true)
        }
        
        // 4. FALLBACK: Si no se pudo descargar como archivo CBZ, usar el método de páginas paralelas
        if !didDownloadArchive {
            let pageUrls = try await apiClient.fetchChapterPages(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: manga.id,
                chapterId: chapter.id,
                isPrefetch: true
            )
            guard !pageUrls.isEmpty else {
                throw NSError(domain: "KaizenOffline", code: 4002, userInfo: [NSLocalizedDescriptionKey: tr("El capítulo \(chapter.displayName) no tiene páginas disponibles en el servidor.", "Chapter \(chapter.displayName) has no pages available on the server.")])
            }
            
            let total = Double(pageUrls.count)
            let token = session.apiToken
            let maxConcurrent = 6
            pageCount = pageUrls.count
            
            do {
                try await withThrowingTaskGroup(of: Int64.self) { group in
                    var next = 0
                    var finished = 0
                    
                    @MainActor func enqueue() {
                        while next < pageUrls.count, !cancelRequested {
                            let idx = next
                            next += 1
                            guard let pageURL = URL(string: pageUrls[idx]) else { finished += 1; continue }
                            let ext = pageURL.pathExtension.isEmpty ? "jpg" : pageURL.pathExtension
                            let destination = chDir.appendingPathComponent(String(format: "page_%03d.%@", idx + 1, ext))
                            let en = language == "en"
                            let name = chapter.displayName
                            let pageNumber = idx + 1
                            group.addTask {
                                try await Self.fetchPage(url: pageURL, token: token, destination: destination) { status in
                                    en ? "The server answered \(status) while downloading page \(pageNumber) of \(name)."
                                       : "El servidor respondió \(status) al bajar la página \(pageNumber) de \(name)."
                                }
                            }
                            return
                        }
                    }
                    
                    for _ in 0..<min(maxConcurrent, pageUrls.count) { enqueue() }
                    
                    while let bytes = try await group.next() {
                        if cancelRequested { throw CancellationError() }
                        totalBytes += bytes
                        finished += 1
                        let fraction = Double(finished) / total
                        activeDownloads[downloadKey] = fraction
                        batch?.currentChapterProgress = fraction
                        enqueue()
                    }
                }
            } catch {
                // Capítulo incompleto: no dejar páginas a medias en disco
                try? fileManager.removeItem(at: chDir)
                throw error
            }
        }
        
        // 5. Registrar en metadatos
        let downloadedChapter = OfflineDownloadedChapter(
            id: chapter.id,
            mangaId: manga.id,
            index: chapter.index,
            title: chapter.displayName,
            pageCount: pageCount,
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
    
    /// Punto de entrada único desde la UI. Un capítulo suelto en red no costosa se baja directo;
    /// en el resto de casos se pide confirmación (tamaño estimado y aviso de datos móviles).
    /// Los capítulos siempre se ordenan de menor a mayor (orden de lectura cronológico: Cap. 1, 2, 3...).
    public func requestDownload(manga: Manga, chapters: [Chapter], apiClient: KaizenAPIClient, session: UserSession?) {
        let pending = chapters
            .sorted(by: { $0.index < $1.index })
            .filter { !isChapterDownloaded(mangaId: manga.id, chapterId: $0.id) }
        guard !pending.isEmpty else { return }
        guard batch == nil else {
            lastError = tr("Ya hay una descarga en curso. Espera a que termine o cancélala.", "A download is already in progress. Wait for it to finish or cancel it.")
            return
        }
        let request = DownloadRequest(manga: manga, chapters: pending, apiClient: apiClient, session: session)
        if pending.count == 1 && !isExpensive {
            start(request)
        } else {
            pendingRequest = request
        }
    }
    
    public func confirmPendingRequest() {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        start(request)
    }
    
    public func requestDownload(manga: Manga, chapter: Chapter, apiClient: KaizenAPIClient, session: UserSession?) {
        requestDownload(manga: manga, chapters: [chapter], apiClient: apiClient, session: session)
    }
    
    public func cancelBatch() {
        cancelRequested = true
    }
    
    private func start(_ request: DownloadRequest) {
        Task {
            await downloadManga(request.manga, chapters: request.chapters, apiClient: request.apiClient, session: request.session)
        }
    }
    
    public func downloadManga(
        _ manga: Manga,
        chapters: [Chapter],
        apiClient: KaizenAPIClient,
        session: UserSession?,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async {
        let pending = chapters
            .sorted(by: { $0.index < $1.index })
            .filter { !isChapterDownloaded(mangaId: manga.id, chapterId: $0.id) }
        guard !pending.isEmpty else { return }
        cancelRequested = false
        lastError = nil
        batch = BatchProgress(mangaTitle: manga.title, done: 0, total: pending.count, currentChapterProgress: 0)
        defer { batch = nil; cancelRequested = false }
        var skipped = 0
        
        for (idx, ch) in pending.enumerated() {
            if cancelRequested { break }
            batch?.currentChapterProgress = 0
            do {
                try await downloadChapter(manga: manga, chapter: ch, apiClient: apiClient, session: session)
                batch?.done = idx + 1
                progressHandler?(idx + 1, pending.count)
            } catch is CancellationError {
                break
            } catch KaizenError.server(status: 404) {
                // El capítulo existe en la base de datos pero su archivo no está en el servidor: se omite.
                skipped += 1
            } catch {
                // Un fallo (servidor caído, token, página rota) detiene el lote y se informa.
                lastError = (error as? KaizenError)?.userMessage(language: language) ?? error.localizedDescription
                break
            }
        }
        if skipped > 0, lastError == nil, !cancelRequested {
            lastError = tr("\(skipped) capítulo(s) no están disponibles en el servidor y se han omitido.",
                           "\(skipped) chapter(s) are not available on the server and were skipped.")
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
                        isRead: isRead
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
                    isRead: action.isRead
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
