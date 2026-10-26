import Foundation

/// Modelo representativo de un manga en la biblioteca de Kaizen
public struct Manga: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let altTitles: [String]?
    public let coverUrl: String?
    public let synopsis: String?
    public let authors: [String]?
    public let genres: [String]?
    public let status: String?
    public let totalChapters: Int
    public let unreadCount: Int
    public let readingPercentage: Double
    public let isFavorite: Bool
    
    public init(
        id: String,
        title: String,
        altTitles: [String]? = nil,
        coverUrl: String? = nil,
        synopsis: String? = nil,
        authors: [String]? = nil,
        genres: [String]? = nil,
        status: String? = nil,
        totalChapters: Int = 0,
        unreadCount: Int = 0,
        readingPercentage: Double = 0.0,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.altTitles = altTitles
        self.coverUrl = coverUrl
        self.synopsis = synopsis
        self.authors = authors
        self.genres = genres
        self.status = status
        self.totalChapters = totalChapters
        self.unreadCount = unreadCount
        self.readingPercentage = readingPercentage
        self.isFavorite = isFavorite
    }
}

/// Modelo de capítulo
public struct Chapter: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let mangaId: String
    public let title: String
    public let chapterNumber: Double
    public let isRead: Bool
    public let lastReadPage: Int?
    public let totalPages: Int?
    public let releaseDate: Date?
    
    public init(
        id: String,
        mangaId: String,
        title: String,
        chapterNumber: Double,
        isRead: Bool = false,
        lastReadPage: Int? = nil,
        totalPages: Int? = nil,
        releaseDate: Date? = nil
    ) {
        self.id = id
        self.mangaId = mangaId
        self.title = title
        self.chapterNumber = chapterNumber
        self.isRead = isRead
        self.lastReadPage = lastReadPage
        self.totalPages = totalPages
        self.releaseDate = releaseDate
    }
}

/// Estado de solicitud de manga
public enum RequestStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case downloading = "DOWNLOADING"
    case available = "AVAILABLE"
    case rejected = "REJECTED"
}

/// Solicitud de manga creada por un usuario
public struct MangaRequestItem: Identifiable, Codable, Sendable {
    public let id: Int
    public let title: String
    public let startChapter: Int
    public let status: RequestStatus
    public let requestedBy: String
    public let requestedAt: Date
    public let downloadProgress: Double?
    
    public init(
        id: Int,
        title: String,
        startChapter: Int = 1,
        status: RequestStatus = .pending,
        requestedBy: String,
        requestedAt: Date = Date(),
        downloadProgress: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.startChapter = startChapter
        self.status = status
        self.requestedBy = requestedBy
        self.requestedAt = requestedAt
        self.downloadProgress = downloadProgress
    }
}
