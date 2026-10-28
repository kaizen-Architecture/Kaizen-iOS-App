import Foundation

/// Manga de la biblioteca de Kaizen, decodificado desde `GET /api/v1/mangas` o `GET /api/v1/mangas/:id`.
public struct Manga: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public let altTitles: [String]?
    public let coverUrl: String?
    public let synopsis: String?
    public let authors: [String]?
    public let genres: [String]?
    public let status: String?
    public let libraryId: Int?
    public let totalChapters: Int
    public let unreadCount: Int
    public let readingPercentage: Double
    public var isFavorite: Bool
    public var chapters: [Chapter]?
    
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
        self.totalChapters = totalChapters
        self.unreadCount = unreadCount
        self.readingPercentage = readingPercentage
        self.isFavorite = isFavorite
        self.chapters = chapters
    }
    
    private enum Keys: String, CodingKey {
        case id, title, isFavorite, libraryId, metadata, readingStatus, chapters
    }
    private enum MetadataKeys: String, CodingKey {
        case cover, summary, authors, genres, status, synonyms
    }
    private enum ProgressKeys: String, CodingKey {
        case totalChapters, unreadChapters, percentageComplete
    }
    
    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: Keys.self)
        id = try root.decode(Int.self, forKey: .id)
        title = try root.decode(String.self, forKey: .title)
        isFavorite = try root.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        libraryId = try root.decodeIfPresent(Int.self, forKey: .libraryId)
        chapters = try root.decodeIfPresent([Chapter].self, forKey: .chapters)
        
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
        
        totalChapters = total ?? (chapters?.count ?? 0)
        unreadCount = unread ?? (chapters?.filter { !$0.isRead }.count ?? 0)
        readingPercentage = pct ?? (totalChapters > 0 ? Double(totalChapters - unreadCount) / Double(totalChapters) * 100.0 : 0.0)
    }
}

/// Capítulo real de un manga en Kaizen
public struct Chapter: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let mangaId: Int?
    public let index: Int
    public let fileName: String?
    public var isFavorite: Bool
    public var isRead: Bool
    public var lastReadPage: Int
    public let lastReadAt: String?
    
    public init(
        id: Int,
        mangaId: Int? = nil,
        index: Int,
        fileName: String? = nil,
        isFavorite: Bool = false,
        isRead: Bool = false,
        lastReadPage: Int = 0,
        lastReadAt: String? = nil
    ) {
        self.id = id
        self.mangaId = mangaId
        self.index = index
        self.fileName = fileName
        self.isFavorite = isFavorite
        self.isRead = isRead
        self.lastReadPage = lastReadPage
        self.lastReadAt = lastReadAt
    }
    
    public var displayName: String {
        "Capítulo \(index)"
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


