import Foundation

/// Manga de la biblioteca de Kaizen, decodificado desde `GET /api/v1/mangas` o `GET /api/v1/mangas/:id`.
public struct Manga: Identifiable, Decodable, Sendable, Equatable, Hashable {
    public let id: Int
    public let title: String
    public let altTitles: [String]?
    public let coverUrl: String?
    public let synopsis: String?
    public let authors: [String]?
    public let genres: [String]?
    public let status: String?
    public let libraryId: Int?
    public let source: String?
    public let isLocked: Bool
    public let interval: String?
    public let totalChapters: Int
    public let unreadCount: Int
    public let readingPercentage: Double
    public var isFavorite: Bool
    public var chapters: [Chapter]?
    public var lastReadChapter: Chapter? = nil
    public var isOrphaned: Bool = false
    public var isSourceMissing: Bool = false
    public var isSourceFailed: Bool = false
    public var isAcceptedStandalone: Bool = false
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Manga, rhs: Manga) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.readingPercentage == rhs.readingPercentage &&
        lhs.unreadCount == rhs.unreadCount &&
        lhs.totalChapters == rhs.totalChapters &&
        lhs.chapters == rhs.chapters &&
        lhs.isLocked == rhs.isLocked &&
        lhs.source == rhs.source &&
        lhs.isOrphaned == rhs.isOrphaned &&
        lhs.isSourceMissing == rhs.isSourceMissing &&
        lhs.isSourceFailed == rhs.isSourceFailed &&
        lhs.isAcceptedStandalone == rhs.isAcceptedStandalone
    }
    
    public init(
        id: Int,
        title: String,
        altTitles: [String]? = nil,
        coverUrl: String? = nil,
        synopsis: String? = nil,
        authors: [String]? = nil,
        genres: [String]? = nil,
        status: String? = nil,
        libraryId: Int? = nil,
        source: String? = nil,
        isLocked: Bool = false,
        interval: String? = nil,
        totalChapters: Int = 0,
        unreadCount: Int = 0,
        readingPercentage: Double = 0.0,
        isFavorite: Bool = false,
        chapters: [Chapter]? = nil
    ) {
        self.id = id
        self.title = title
        self.altTitles = altTitles
        self.coverUrl = coverUrl
        self.synopsis = synopsis
        self.authors = authors
        self.genres = genres
        self.status = status
        self.libraryId = libraryId
        self.source = source
        self.isLocked = isLocked
        self.interval = interval
        self.totalChapters = totalChapters
        self.unreadCount = unreadCount
        self.readingPercentage = readingPercentage
        self.isFavorite = isFavorite
        self.chapters = chapters
    }
    
    private enum Keys: String, CodingKey {
        case id, title, isFavorite, libraryId, source, isLocked, interval, metadata, readingStatus, chapters
    }
    private enum MetadataKeys: String, CodingKey {
        case cover, summary, authors, genres, status, synonyms
    }
    private enum ProgressKeys: String, CodingKey {
        case totalChapters, unreadChapters, percentageComplete, lastReadChapter
    }
    
    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: Keys.self)
        id = try root.decode(Int.self, forKey: .id)
        title = try root.decode(String.self, forKey: .title)
        isFavorite = try root.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        libraryId = try root.decodeIfPresent(Int.self, forKey: .libraryId)
        source = try root.decodeIfPresent(String.self, forKey: .source)
        isLocked = try root.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        interval = try root.decodeIfPresent(String.self, forKey: .interval)
        if let lossyList = try? root.decodeIfPresent([LossyDecodable<Chapter>].self, forKey: .chapters) {
            chapters = lossyList.compactMap(\.value)
        } else {
            chapters = nil
        }
        
        let meta = try? root.nestedContainer(keyedBy: MetadataKeys.self, forKey: .metadata)
        let cover = try meta?.decodeIfPresent(String.self, forKey: .cover)
        let summary = try meta?.decodeIfPresent(String.self, forKey: .summary)
        coverUrl = (cover?.isEmpty == false) ? cover : nil
        synopsis = (summary?.isEmpty == false) ? summary : nil
        authors = try meta?.decodeIfPresent([String].self, forKey: .authors)
        genres = try meta?.decodeIfPresent([String].self, forKey: .genres)
        status = try meta?.decodeIfPresent(String.self, forKey: .status)
        altTitles = try meta?.decodeIfPresent([String].self, forKey: .synonyms)
        
        let progress = try? root.nestedContainer(keyedBy: ProgressKeys.self, forKey: .readingStatus)
        let total = try progress?.decodeIfPresent(Int.self, forKey: .totalChapters)
        let unread = try progress?.decodeIfPresent(Int.self, forKey: .unreadChapters)
        let pct = try progress?.decodeIfPresent(Double.self, forKey: .percentageComplete)
        lastReadChapter = try? progress?.decodeIfPresent(Chapter.self, forKey: .lastReadChapter)
        
        totalChapters = total ?? (chapters?.count ?? 0)
        unreadCount = unread ?? (chapters?.filter { !$0.isRead }.count ?? 0)
        let rawPct = pct ?? (totalChapters > 0 ? Double(totalChapters - unreadCount) / Double(totalChapters) * 100.0 : 0.0)
        if rawPct.isNaN || rawPct.isInfinite {
            readingPercentage = 0.0
        } else {
            readingPercentage = min(max(rawPct, 0.0), 100.0)
        }
    }
    
    /// Indica si la publicación de la serie ha finalizado por completo
    public var isCompleted: Bool {
        guard let s = status?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return s == "completed" || s == "finished" || s == "complete" || s == "finalizado" || s == "completado"
    }
    
    /// Indica si la publicación de la serie se encuentra en pausa temporal (Hiatus)
    public var isHiatus: Bool {
        guard let s = status?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return s == "hiatus" || s == "pausado" || s == "en pausa"
    }
    
    /// Indica si la serie continúa en emisión activa
    public var isOngoing: Bool {
        !isCompleted && !isHiatus
    }
    
    public var safeReadingPercentage: Double {
        if readingPercentage.isNaN || readingPercentage.isInfinite { return 0.0 }
        return min(max(readingPercentage, 0.0), 100.0)
    }
}

/// Helper para decodificar colecciones de forma tolerante a fallos individuales
private struct LossyDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(T.self)
    }
}

/// Capítulo real de un manga en Kaizen
public struct Chapter: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: Int
    public let mangaId: Int?
    public let index: Int
    public let fileName: String?
    public let size: Int?
    public let createdAt: String?
    public var isFavorite: Bool
    public var isRead: Bool
    public var lastReadPage: Int
    public let lastReadAt: String?
    public let source: String?
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public init(
        id: Int,
        mangaId: Int? = nil,
        index: Int,
        fileName: String? = nil,
        size: Int? = nil,
        createdAt: String? = nil,
        isFavorite: Bool = false,
        isRead: Bool = false,
        lastReadPage: Int = 0,
        lastReadAt: String? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.mangaId = mangaId
        self.index = index
        self.fileName = fileName
        self.size = size
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.isRead = isRead
        self.lastReadPage = lastReadPage
        self.lastReadAt = lastReadAt
        self.source = source
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, mangaId, index, fileName, size, createdAt, isFavorite, isRead, lastReadPage, lastReadAt, source
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.mangaId = try? container.decodeIfPresent(Int.self, forKey: .mangaId)
        
        // Soporte para index como Int o Double
        if let intVal = try? container.decode(Int.self, forKey: .index) {
            self.index = intVal
        } else if let dblVal = try? container.decode(Double.self, forKey: .index) {
            self.index = Int(dblVal)
        } else {
            self.index = 0
        }
        
        self.fileName = try? container.decodeIfPresent(String.self, forKey: .fileName)
        self.size = try? container.decodeIfPresent(Int.self, forKey: .size)
        self.createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        self.isFavorite = (try? container.decodeIfPresent(Bool.self, forKey: .isFavorite)) ?? false
        self.isRead = (try? container.decodeIfPresent(Bool.self, forKey: .isRead)) ?? false
        self.lastReadPage = (try? container.decodeIfPresent(Int.self, forKey: .lastReadPage)) ?? 0
        self.lastReadAt = try? container.decodeIfPresent(String.self, forKey: .lastReadAt)
        let rawSource = try? container.decodeIfPresent(String.self, forKey: .source)
        self.source = (rawSource?.isEmpty == false) ? rawSource : nil
    }
    
    public var displayName: String {
        "Capítulo \(index)"
    }
    
    public var uniqueKey: String {
        "\(id)_\(index)"
    }
    
    public var formattedSize: String? {
        guard let size, size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// Fuente o scraper configurado específicamente para un manga en Kaizen
public struct MangaConfiguredSource: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: Int
    public let mangaId: Int
    public let source: String
    public let title: String
    public var priority: Int
    
    public init(id: Int, mangaId: Int, source: String, title: String, priority: Int) {
        self.id = id
        self.mangaId = mangaId
        self.source = source
        self.title = title
        self.priority = priority
    }
}

/// Biblioteca en el servidor Kaizen
public struct KaizenLibrary: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let path: String
    public let name: String?
    public let description: String?
    
    public init(id: Int, path: String, name: String? = nil, description: String? = nil) {
        self.id = id
        self.path = path
        self.name = name
        self.description = description
    }
    
    public var displayTitle: String {
        if let name, !name.isEmpty { return name }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

/// Solicitud de manga en Kaizen
public struct MangaRequestItem: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public let startChapter: Int
    public let status: String
    public let userId: Int?
    public let username: String?
    public let createdAt: String?
    
    public init(
        id: Int,
        title: String,
        startChapter: Int = 1,
        status: String = "PENDING",
        userId: Int? = nil,
        username: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startChapter = startChapter
        self.status = status
        self.userId = userId
        self.username = username
        self.createdAt = createdAt
    }
    
    public var statusBadgeColor: String {
        switch status.uppercased() {
        case "AVAILABLE": return "green"
        case "APPROVED": return "blue"
        case "DOWNLOADING": return "orange"
        case "CANCELLED", "REJECTED": return "red"
        default: return "yellow"
        }
    }
}

/// Métricas de una cola BullMQ de Kaizen
public struct QueueMetric: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let label: String
    public let active: Int
    public let waiting: Int
    public let delayed: Int
    public let failed: Int
    public let completed: Int
    public let total: Int
    public let isPaused: Bool
}

/// Resumen global de colas
public struct QueueMetricsSummary: Codable, Sendable, Equatable {
    public let totalActive: Int
    public let totalWaiting: Int
    public let totalDelayed: Int
    public let totalFailed: Int
}

public struct QueuesResponse: Codable, Sendable, Equatable {
    public let summary: QueueMetricsSummary
    public let queues: [QueueMetric]
}

/// Configuración del servidor Kaizen (AniList, etc.)
public struct KaizenServerSettings: Codable, Sendable, Equatable {
    public let anilistEnabled: Bool
    public let anilistUsername: String?
    public let anilistAutoSync: Bool
    public let discordEnabled: Bool
    public let whatsappEnabled: Bool
    
    public init(
        anilistEnabled: Bool = false,
        anilistUsername: String? = nil,
        anilistAutoSync: Bool = false,
        discordEnabled: Bool = false,
        whatsappEnabled: Bool = false
    ) {
        self.anilistEnabled = anilistEnabled
        self.anilistUsername = anilistUsername
        self.anilistAutoSync = anilistAutoSync
        self.discordEnabled = discordEnabled
        self.whatsappEnabled = whatsappEnabled
    }
}

/// Estantería o colección lógica personalizada por el lector (independiente de carpetas del servidor)
public struct UserShelf: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var mangaIds: [Int]
    
    public init(id: UUID = UUID(), name: String, icon: String = "books.vertical.fill", mangaIds: [Int] = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.mangaIds = mangaIds
    }
}

/// Registro en el historial de lectura del usuario (inspirado en Paperback)
public struct ReadingHistoryEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var mangaId: Int
    public var mangaTitle: String
    public var coverUrl: String?
    public var chapterId: Int
    public var chapterIndex: Int
    public var chapterFileName: String?
    public var pageIndex: Int
    public var totalPages: Int
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        mangaId: Int,
        mangaTitle: String,
        coverUrl: String? = nil,
        chapterId: Int,
        chapterIndex: Int,
        chapterFileName: String? = nil,
        pageIndex: Int,
        totalPages: Int,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mangaId = mangaId
        self.mangaTitle = mangaTitle
        self.coverUrl = coverUrl
        self.chapterId = chapterId
        self.chapterIndex = chapterIndex
        self.chapterFileName = chapterFileName
        self.pageIndex = pageIndex
        self.totalPages = totalPages
        self.updatedAt = updatedAt
    }
    
    public var progressPercentage: Double {
        guard totalPages > 0 else { return 0 }
        return min(100.0, max(0.0, (Double(pageIndex + 1) / Double(totalPages)) * 100.0))
    }
}

/// Modos de lectura soportados (Webtoon, LTR, RTL)
public enum ReaderMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case webtoon = "Webtoon (Cascada)"
    case horizontalLTR = "Páginas (Izquierda a Derecha)"
    case horizontalRTL = "Manga (Derecha a Izquierda)"
    
    public var id: String { rawValue }
    
    public func label(language: String) -> String {
        switch self {
        case .webtoon: return language == "en" ? "Webtoon (Vertical scroll)" : "Webtoon (Cascada)"
        case .horizontalLTR: return language == "en" ? "Left to Right (Comic)" : "Páginas (Izquierda a Derecha)"
        case .horizontalRTL: return language == "en" ? "Right to Left (Manga)" : "Manga (Derecha a Izquierda)"
        }
    }
    
    public var iconName: String {
        switch self {
        case .webtoon: return "arrow.up.and.down"
        case .horizontalLTR: return "arrow.right"
        case .horizontalRTL: return "arrow.left"
        }
    }
}

public typealias ReadingDirection = ReaderMode

public extension ReaderMode {
    static var rightToLeft: ReaderMode { .horizontalRTL }
    static var leftToRight: ReaderMode { .horizontalLTR }
}

/// Temas de fondo para el lector
public enum ReaderTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case black = "Negro OLED"
    case darkGray = "Gris Oscuro"
    case light = "Blanco"
    
    public var id: String { rawValue }
}

/// Resultado de búsqueda remota en fuentes de Kaizen (`trpc/manga.search`)
public struct RemoteSearchResult: Identifiable, Codable, Sendable, Equatable {
    public var id: String { "\(source)_\(title)" }
    public let title: String
    public let source: String
    public let status: String?
    public let chapters: Int
    public let cover: String?
    
    public init(title: String, source: String, status: String? = nil, chapters: Int = 0, cover: String? = nil) {
        self.title = title
        self.source = source
        self.status = status
        self.chapters = chapters
        self.cover = cover
    }
}

/// Fuente o scraper de Kaizen con estado de activación y fallos (útil ante bloqueos de La Liga / ISPs)
public struct KaizenSourceItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public var isInstalled: Bool
    public var isActive: Bool
    public var isFailed: Bool
    public let origin: String?
    
    public init(name: String, isInstalled: Bool = true, isActive: Bool = true, isFailed: Bool = false, origin: String? = nil) {
        self.name = name
        self.isInstalled = isInstalled
        self.isActive = isActive
        self.isFailed = isFailed
        self.origin = origin
    }
}

/// Trabajo de descarga fallido en Kaizen
public struct FailedDownloadJob: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let mangaId: Int
    public let mangaTitle: String
    public let chapterIndex: Double
    public let source: String
    public let failedReason: String?
    public let attempts: Int
    public let isPaused: Bool
    
    public init(
        id: String,
        mangaId: Int,
        mangaTitle: String,
        chapterIndex: Double,
        source: String,
        failedReason: String? = nil,
        attempts: Int = 1,
        isPaused: Bool = false
    ) {
        self.id = id
        self.mangaId = mangaId
        self.mangaTitle = mangaTitle
        self.chapterIndex = chapterIndex
        self.source = source
        self.failedReason = failedReason
        self.attempts = attempts
        self.isPaused = isPaused
    }
}


/// Elemento en vivo de la cola de descargas (`trpc/manga.downloadQueue`)
public struct DownloadQueueJob: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let mangaId: Int
    public let mangaTitle: String
    public let source: String
    public let chapterIndex: Double
    public let status: String // "active", "waiting", "completed", "failed"
    public let progress: Int
    public let failedReason: String?
    public let timestamp: Double?
    
    public init(
        id: String,
        mangaId: Int,
        mangaTitle: String,
        source: String,
        chapterIndex: Double,
        status: String,
        progress: Int = 0,
        failedReason: String? = nil,
        timestamp: Double? = nil
    ) {
        self.id = id
        self.mangaId = mangaId
        self.mangaTitle = mangaTitle
        self.source = source
        self.chapterIndex = chapterIndex
        self.status = status
        self.progress = progress
        self.failedReason = failedReason
        self.timestamp = timestamp
    }
}

/// Estadísticas globales del Dashboard (`trpc/manga.activity`)
public struct KaizenActivityStats: Codable, Sendable, Equatable {
    public let active: Int
    public let queued: Int
    public let scheduled: Int
    public let failed: Int
    public let completed: Int
    public let outOfSync: Int
    
    public init(
        active: Int = 0,
        queued: Int = 0,
        scheduled: Int = 0,
        failed: Int = 0,
        completed: Int = 0,
        outOfSync: Int = 0
    ) {
        self.active = active
        self.queued = queued
        self.scheduled = scheduled
        self.failed = failed
        self.completed = completed
        self.outOfSync = outOfSync
    }
}

/// Punto de historial de descargas de los últimos 14 días (`trpc/manga.activityHistory`)
public struct KaizenActivityHistoryItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { date }
    public let date: String
    public let label: String
    public let count: Int
    
    public init(date: String, label: String, count: Int) {
        self.date = date
        self.label = label
        self.count = count
    }
}

/// Estadísticas de series y almacenamiento en disco por fuente (`trpc/manga.sourceStats`)
public struct KaizenSourceStatItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { source }
    public let source: String
    public let mangaCount: Int
    public let totalSize: Int64
    
    public init(source: String, mangaCount: Int, totalSize: Int64) {
        self.source = source
        self.mangaCount = mangaCount
        self.totalSize = totalSize
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

/// Capítulo recién descargado en el servidor (`trpc/manga.history`)
public struct KaizenServerRecentDownload: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let index: Double
    public let fileName: String?
    public let size: Int?
    public let createdAt: String?
    public let mangaId: Int?
    public let mangaTitle: String
    public let coverUrl: String?
    
    public init(
        id: Int,
        index: Double,
        fileName: String? = nil,
        size: Int? = nil,
        createdAt: String? = nil,
        mangaId: Int? = nil,
        mangaTitle: String,
        coverUrl: String? = nil
    ) {
        self.id = id
        self.index = index
        self.fileName = fileName
        self.size = size
        self.createdAt = createdAt
        self.mangaId = mangaId
        self.mangaTitle = mangaTitle
        self.coverUrl = coverUrl
    }
    
    public var formattedSize: String? {
        guard let size, size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

extension Chapter {
    public var lastReadDate: Date? {
        guard let lastReadAt, !lastReadAt.isEmpty else { return nil }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFractional.date(from: lastReadAt) {
            return d
        }
        let isoStandard = ISO8601DateFormatter()
        isoStandard.formatOptions = [.withInternetDateTime]
        return isoStandard.date(from: lastReadAt)
    }
}

/// Serie programada en el planificador de Kaizen (`trpc/manga.getSchedules`)
public struct KaizenScheduledManga: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public var interval: String
    public let source: String
    public var isLocked: Bool
    public let status: String?
    public let coverUrl: String?
    
    public init(
        id: Int,
        title: String,
        interval: String,
        source: String,
        isLocked: Bool = false,
        status: String? = nil,
        coverUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.interval = interval
        self.source = source
        self.isLocked = isLocked
        self.status = status
        self.coverUrl = coverUrl
    }
}

/// Serie en espera de alcanzar un umbral de capítulos (ej. 50 capítulos) en Kaizen (`Plan to Read` / Backlog)
public struct KaizenPlannedManga: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public let source: String
    public let interval: String
    public var minChaptersForDownload: Int
    public let remoteChaptersCount: Int
    public let downloadedChaptersCount: Int
    public let status: String?
    public let coverUrl: String?
    
    public init(
        id: Int,
        title: String,
        source: String,
        interval: String = "0 */6 * * *",
        minChaptersForDownload: Int,
        remoteChaptersCount: Int = 0,
        downloadedChaptersCount: Int = 0,
        status: String? = nil,
        coverUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.interval = interval
        self.minChaptersForDownload = minChaptersForDownload
        self.remoteChaptersCount = remoteChaptersCount
        self.downloadedChaptersCount = downloadedChaptersCount
        self.status = status
        self.coverUrl = coverUrl
    }
    
    public var progressRatio: Double {
        guard minChaptersForDownload > 0 else { return 1.0 }
        return min(1.0, max(0.0, Double(remoteChaptersCount) / Double(minChaptersForDownload)))
    }
}

/// Estado de orfandad de un manga respecto a su scraper/fuente en el servidor (`trpc/manga.query`)
public struct MangaOrphanStatus: Sendable, Equatable {
    public let isOrphaned: Bool
    public let isSourceMissing: Bool
    public let isSourceFailed: Bool
    public let isAcceptedStandalone: Bool

    public init(
        isOrphaned: Bool,
        isSourceMissing: Bool,
        isSourceFailed: Bool,
        isAcceptedStandalone: Bool
    ) {
        self.isOrphaned = isOrphaned
        self.isSourceMissing = isSourceMissing
        self.isSourceFailed = isSourceFailed
        self.isAcceptedStandalone = isAcceptedStandalone
    }
}

/// Resultado individual de migración en lote de fuente (`trpc/manga.batchMigrateSource`)
public struct BatchMigrationItemResult: Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public let success: Bool
    public let matchedTitle: String?
    public let chaptersCount: Int?
    public let reason: String?

    public init(
        id: Int,
        title: String,
        success: Bool,
        matchedTitle: String? = nil,
        chaptersCount: Int? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.success = success
        self.matchedTitle = matchedTitle
        self.chaptersCount = chaptersCount
        self.reason = reason
    }
}

/// Resultado global de migración en lote (`trpc/manga.batchMigrateSource`)
public struct BatchMigrationResult: Sendable, Equatable {
    public let total: Int
    public let successCount: Int
    public let failedCount: Int
    public let results: [BatchMigrationItemResult]

    public init(
        total: Int,
        successCount: Int,
        failedCount: Int,
        results: [BatchMigrationItemResult]
    ) {
        self.total = total
        self.successCount = successCount
        self.failedCount = failedCount
        self.results = results
    }
}

// MARK: - Acciones en Lote sobre Capítulos (REST v1 - Kaizen v2.1.0+)

/// Acción soportada por `POST /api/v1/mangas/{id}/chapters/batch`
public enum ChapterBatchAction: String, Codable, Sendable, CaseIterable {
    case markRead
    case markUnread
    case reportCorrupt
    case delete
    case redownload
}

/// Respuesta de `POST /api/v1/mangas/{id}/chapters/batch`
public struct ChapterBatchResponse: Codable, Sendable, Equatable {
    public let success: Bool
    public let action: String
    public let mangaId: Int
    public let processedCount: Int
    public let failedIds: [Int]

    public init(
        success: Bool,
        action: String,
        mangaId: Int,
        processedCount: Int,
        failedIds: [Int] = []
    ) {
        self.success = success
        self.action = action
        self.mangaId = mangaId
        self.processedCount = processedCount
        self.failedIds = failedIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.success = (try? c.decodeIfPresent(Bool.self, forKey: .success)) ?? true
        self.action = (try? c.decodeIfPresent(String.self, forKey: .action)) ?? ""
        self.mangaId = (try? c.decodeIfPresent(Int.self, forKey: .mangaId)) ?? 0
        self.processedCount = (try? c.decodeIfPresent(Int.self, forKey: .processedCount)) ?? 0
        self.failedIds = (try? c.decodeIfPresent([Int].self, forKey: .failedIds)) ?? []
    }
}

// MARK: - Better Source Advisor (REST v1 & tRPC)

/// Recomendación individual de una mejor fuente en `GET /api/v1/system/better-sources`
public struct BetterSourceRecommendation: Identifiable, Codable, Sendable, Equatable {
    public var id: Int { mangaId }
    public let mangaId: Int
    public let title: String
    public let currentSource: String
    public let currentMaxChapter: Int
    public let bestSource: String
    public let bestMatchedTitle: String
    public let bestMaxChapter: Int
    public let delta: Int
    public let isReading: Bool

    public init(
        mangaId: Int,
        title: String,
        currentSource: String,
        currentMaxChapter: Int,
        bestSource: String,
        bestMatchedTitle: String,
        bestMaxChapter: Int,
        delta: Int,
        isReading: Bool = false
    ) {
        self.mangaId = mangaId
        self.title = title
        self.currentSource = currentSource
        self.currentMaxChapter = currentMaxChapter
        self.bestSource = bestSource
        self.bestMatchedTitle = bestMatchedTitle
        self.bestMaxChapter = bestMaxChapter
        self.delta = delta
        self.isReading = isReading
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.mangaId = try c.decode(Int.self, forKey: .mangaId)
        self.title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        self.currentSource = (try? c.decodeIfPresent(String.self, forKey: .currentSource)) ?? ""
        self.currentMaxChapter = (try? c.decodeIfPresent(Int.self, forKey: .currentMaxChapter)) ?? 0
        self.bestSource = (try? c.decodeIfPresent(String.self, forKey: .bestSource)) ?? ""
        self.bestMatchedTitle = (try? c.decodeIfPresent(String.self, forKey: .bestMatchedTitle)) ?? self.title
        self.bestMaxChapter = (try? c.decodeIfPresent(Int.self, forKey: .bestMaxChapter)) ?? 0
        self.delta = (try? c.decodeIfPresent(Int.self, forKey: .delta)) ?? max(0, self.bestMaxChapter - self.currentMaxChapter)
        self.isReading = (try? c.decodeIfPresent(Bool.self, forKey: .isReading)) ?? false
    }
}

/// Estado en vivo del escaneo global de Better Source Advisor (`GET /api/v1/system/better-sources`)
public struct BetterSourceScanStatus: Codable, Sendable, Equatable {
    public let isRunning: Bool
    public let cancelled: Bool
    public let processedCount: Int
    public let totalCount: Int
    public let totalReleasingInLibrary: Int
    public let totalReadingReleasingInLibrary: Int
    public let currentMangaTitle: String?
    public let startedAt: String?
    public let finishedAt: String?
    public let recommendations: [BetterSourceRecommendation]

    public var progressRatio: Double {
        guard totalCount > 0 else { return 0 }
        return min(1.0, max(0.0, Double(processedCount) / Double(totalCount)))
    }

    public init(
        isRunning: Bool = false,
        cancelled: Bool = false,
        processedCount: Int = 0,
        totalCount: Int = 0,
        totalReleasingInLibrary: Int = 0,
        totalReadingReleasingInLibrary: Int = 0,
        currentMangaTitle: String? = nil,
        startedAt: String? = nil,
        finishedAt: String? = nil,
        recommendations: [BetterSourceRecommendation] = []
    ) {
        self.isRunning = isRunning
        self.cancelled = cancelled
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.totalReleasingInLibrary = totalReleasingInLibrary
        self.totalReadingReleasingInLibrary = totalReadingReleasingInLibrary
        self.currentMangaTitle = currentMangaTitle
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.recommendations = recommendations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isRunning = (try? c.decodeIfPresent(Bool.self, forKey: .isRunning)) ?? false
        self.cancelled = (try? c.decodeIfPresent(Bool.self, forKey: .cancelled)) ?? false
        self.processedCount = (try? c.decodeIfPresent(Int.self, forKey: .processedCount)) ?? 0
        self.totalCount = (try? c.decodeIfPresent(Int.self, forKey: .totalCount)) ?? 0
        self.totalReleasingInLibrary = (try? c.decodeIfPresent(Int.self, forKey: .totalReleasingInLibrary)) ?? 0
        self.totalReadingReleasingInLibrary = (try? c.decodeIfPresent(Int.self, forKey: .totalReadingReleasingInLibrary)) ?? 0
        self.currentMangaTitle = try? c.decodeIfPresent(String.self, forKey: .currentMangaTitle)
        self.startedAt = try? c.decodeIfPresent(String.self, forKey: .startedAt)
        self.finishedAt = try? c.decodeIfPresent(String.self, forKey: .finishedAt)
        self.recommendations = (try? c.decodeIfPresent([BetterSourceRecommendation].self, forKey: .recommendations)) ?? []
    }
}

/// Sugerencia por manga individual (`trpc/manga.suggestBetterSources`)
public struct MangaBetterSourceSuggestion: Identifiable, Codable, Sendable, Equatable {
    public var id: String { source }
    public let source: String
    public let matchedTitle: String
    public let remoteMaxChapter: Int
    public let remoteTotalEntries: Int
    public let chapterGain: Int

    public init(
        source: String,
        matchedTitle: String,
        remoteMaxChapter: Int,
        remoteTotalEntries: Int,
        chapterGain: Int
    ) {
        self.source = source
        self.matchedTitle = matchedTitle
        self.remoteMaxChapter = remoteMaxChapter
        self.remoteTotalEntries = remoteTotalEntries
        self.chapterGain = chapterGain
    }
}

/// Respuesta de `trpc/manga.suggestBetterSources`
public struct MangaBetterSourceReport: Sendable, Equatable {
    public let currentSource: String
    public let currentMaxChapter: Int
    public let suggestions: [MangaBetterSourceSuggestion]

    public init(currentSource: String, currentMaxChapter: Int, suggestions: [MangaBetterSourceSuggestion]) {
        self.currentSource = currentSource
        self.currentMaxChapter = currentMaxChapter
        self.suggestions = suggestions
    }
}

// MARK: - Kaizen Core (`kaizen-mangal`) REST v1 (`/api/v1/system/core`)

public struct KaizenCoreDoctorTLS: Codable, Sendable, Equatable {
    public let configured: String?
    public let resolved: String?
    public let chromeMajor: Int?

    private enum CodingKeys: String, CodingKey {
        case configured, resolved
        case chromeMajor = "chrome_major"
    }
}

public struct KaizenCoreDoctorBrowser: Codable, Sendable, Equatable {
    public let available: Bool
    public let mode: String?
    public let target: String?
    public let error: String?

    public init(available: Bool = false, mode: String? = nil, target: String? = nil, error: String? = nil) {
        self.available = available
        self.mode = mode
        self.target = target
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.available = (try? c.decodeIfPresent(Bool.self, forKey: .available)) ?? false
        self.mode = try? c.decodeIfPresent(String.self, forKey: .mode)
        self.target = try? c.decodeIfPresent(String.self, forKey: .target)
        self.error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

public struct KaizenCoreDoctorSolver: Codable, Sendable, Equatable {
    public let configured: Bool
    public let reachable: Bool
    public let fallbackEnabled: Bool
    public let error: String?

    private enum CodingKeys: String, CodingKey {
        case configured, reachable, error
        case fallbackEnabled = "fallback_enabled"
    }

    public init(configured: Bool = false, reachable: Bool = false, fallbackEnabled: Bool = false, error: String? = nil) {
        self.configured = configured
        self.reachable = reachable
        self.fallbackEnabled = fallbackEnabled
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.configured = (try? c.decodeIfPresent(Bool.self, forKey: .configured)) ?? false
        self.reachable = (try? c.decodeIfPresent(Bool.self, forKey: .reachable)) ?? false
        self.fallbackEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .fallbackEnabled)) ?? false
        self.error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

public struct KaizenCoreDoctorInfo: Codable, Sendable, Equatable {
    public let ok: Bool
    public let tlsProfile: KaizenCoreDoctorTLS?
    public let browser: KaizenCoreDoctorBrowser?
    public let solver: KaizenCoreDoctorSolver?
    public let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case ok, browser, solver, warnings
        case tlsProfile = "tls_profile"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = (try? c.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
        self.tlsProfile = try? c.decodeIfPresent(KaizenCoreDoctorTLS.self, forKey: .tlsProfile)
        self.browser = try? c.decodeIfPresent(KaizenCoreDoctorBrowser.self, forKey: .browser)
        self.solver = try? c.decodeIfPresent(KaizenCoreDoctorSolver.self, forKey: .solver)
        self.warnings = (try? c.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    }
}

public struct KaizenCoreBinaryStatus: Codable, Sendable, Equatable {
    public let available: Bool
    public let version: String?
    public let contractVersion: Int?
    public let binaryPath: String?
    public let doctor: KaizenCoreDoctorInfo?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.available = (try? c.decodeIfPresent(Bool.self, forKey: .available)) ?? false
        self.version = try? c.decodeIfPresent(String.self, forKey: .version)
        self.contractVersion = try? c.decodeIfPresent(Int.self, forKey: .contractVersion)
        self.binaryPath = try? c.decodeIfPresent(String.self, forKey: .binaryPath)
        self.doctor = try? c.decodeIfPresent(KaizenCoreDoctorInfo.self, forKey: .doctor)
    }
}

public struct KaizenCoreVersionCheck: Codable, Sendable, Equatable {
    public let checkedAt: String?
    public let installedCoreVersion: String?
    public let installedContractVersion: Int?
    public let activeBinaryPath: String?
    public let usingManagedBinary: Bool
    public let canRollback: Bool
    public let autoUpdateEnabled: Bool
    public let latestCoreVersion: String?
    public let coreUpdateAvailable: Bool
    public let currentKaizenVersion: String?
    public let latestKaizenVersion: String?
    public let kaizenUpdateAvailable: Bool
    public let expectedContractVersion: Int?
    public let contractCompatible: Bool
    public let compatibilityStatus: String
    public let compatibilityMessage: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.checkedAt = try? c.decodeIfPresent(String.self, forKey: .checkedAt)
        self.installedCoreVersion = try? c.decodeIfPresent(String.self, forKey: .installedCoreVersion)
        self.installedContractVersion = try? c.decodeIfPresent(Int.self, forKey: .installedContractVersion)
        self.activeBinaryPath = try? c.decodeIfPresent(String.self, forKey: .activeBinaryPath)
        self.usingManagedBinary = (try? c.decodeIfPresent(Bool.self, forKey: .usingManagedBinary)) ?? false
        self.canRollback = (try? c.decodeIfPresent(Bool.self, forKey: .canRollback)) ?? false
        self.autoUpdateEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .autoUpdateEnabled)) ?? false
        self.latestCoreVersion = try? c.decodeIfPresent(String.self, forKey: .latestCoreVersion)
        self.coreUpdateAvailable = (try? c.decodeIfPresent(Bool.self, forKey: .coreUpdateAvailable)) ?? false
        self.currentKaizenVersion = try? c.decodeIfPresent(String.self, forKey: .currentKaizenVersion)
        self.latestKaizenVersion = try? c.decodeIfPresent(String.self, forKey: .latestKaizenVersion)
        self.kaizenUpdateAvailable = (try? c.decodeIfPresent(Bool.self, forKey: .kaizenUpdateAvailable)) ?? false
        self.expectedContractVersion = try? c.decodeIfPresent(Int.self, forKey: .expectedContractVersion)
        self.contractCompatible = (try? c.decodeIfPresent(Bool.self, forKey: .contractCompatible)) ?? true
        self.compatibilityStatus = (try? c.decodeIfPresent(String.self, forKey: .compatibilityStatus)) ?? "up_to_date"
        self.compatibilityMessage = try? c.decodeIfPresent(String.self, forKey: .compatibilityMessage)
    }
}

public struct KaizenCoreDiagnostics: Codable, Sendable, Equatable {
    public let kaizenMangal: KaizenCoreBinaryStatus
    public let versionCheck: KaizenCoreVersionCheck?
}

/// Clave de configuración de Kaizen Core (`GET /api/v1/system/core` -> `config[]`)
public struct KaizenCoreConfigItem: Identifiable, Sendable, Equatable {
    public var id: String { key }
    public let key: String
    public let value: String
    public let valueType: String // "string", "number", "boolean"
    public let description: String?

    public init(key: String, value: String, valueType: String = "string", description: String? = nil) {
        self.key = key
        self.value = value
        self.valueType = valueType
        self.description = description
    }
}

/// Respuesta completa de `GET /api/v1/system/core`
public struct KaizenCoreSystemResponse: Sendable, Equatable {
    public let diagnostics: KaizenCoreDiagnostics
    public let config: [KaizenCoreConfigItem]

    public init(diagnostics: KaizenCoreDiagnostics, config: [KaizenCoreConfigItem]) {
        self.diagnostics = diagnostics
        self.config = config
    }
}

/// Resultado de `POST /api/v1/system/core` (`update` / `rollback`)
public struct KaizenCoreMutationResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let updated: Bool?
    public let message: String?
    public let version: String?
    public let error: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.success = (try? c.decodeIfPresent(Bool.self, forKey: .success)) ?? false
        self.updated = try? c.decodeIfPresent(Bool.self, forKey: .updated)
        self.message = try? c.decodeIfPresent(String.self, forKey: .message)
        self.version = try? c.decodeIfPresent(String.self, forKey: .version)
        self.error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

// MARK: - AI Studio Server-Side Scraper Test (`trpc/sources.testScraper`)

/// Resultado de `POST /api/trpc/sources.testScraper`
public struct ScraperTestResult: Sendable, Equatable {
    public let success: Bool
    public let failedPhase: String? // "search" | "chapters" | "pages"
    public let logs: [String]
    public let searchResultsCount: Int
    public let errorKey: String?
    public let errorDetail: String?

    public init(
        success: Bool,
        failedPhase: String? = nil,
        logs: [String] = [],
        searchResultsCount: Int = 0,
        errorKey: String? = nil,
        errorDetail: String? = nil
    ) {
        self.success = success
        self.failedPhase = failedPhase
        self.logs = logs
        self.searchResultsCount = searchResultsCount
        self.errorKey = errorKey
        self.errorDetail = errorDetail
    }
}
