import Foundation
import SwiftData

/// Entidad SwiftData persistida para almacenar el catálogo local offline
@Model
public final class LocalManga {
    @Attribute(.unique) public var id: String
    public var title: String
    public var altTitles: [String]
    public var coverUrl: String?
    public var synopsis: String?
    public var authors: [String]
    public var genres: [String]
    public var status: String?
    public var totalChapters: Int
    public var unreadCount: Int
    public var readingPercentage: Double
    public var isFavorite: Bool
    public var lastUpdated: Date
    
    @Relationship(deleteRule: .cascade, inverse: \LocalChapter.manga)
    public var chapters: [LocalChapter]
    
    public init(
        id: String,
        title: String,
        altTitles: [String] = [],
        coverUrl: String? = nil,
        synopsis: String? = nil,
        authors: [String] = [],
        genres: [String] = [],
        status: String? = nil,
        totalChapters: Int = 0,
        unreadCount: Int = 0,
        readingPercentage: Double = 0.0,
        isFavorite: Bool = false,
        lastUpdated: Date = Date()
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
        self.lastUpdated = lastUpdated
        self.chapters = []
    }
}

/// Entidad SwiftData para almacenar capítulos y progreso de lectura en disco
@Model
public final class LocalChapter {
    @Attribute(.unique) public var id: String
    public var title: String
    public var chapterNumber: Double
    public var isRead: Bool
    public var lastReadPage: Int
    public var totalPages: Int
    public var isDownloaded: Bool
    public var localPath: String?
    
    public var manga: LocalManga?
    
    public init(
        id: String,
        title: String,
        chapterNumber: Double,
        isRead: Bool = false,
        lastReadPage: Int = 1,
        totalPages: Int = 1,
        isDownloaded: Bool = false,
        localPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.chapterNumber = chapterNumber
        self.isRead = isRead
        self.lastReadPage = lastReadPage
        self.totalPages = totalPages
        self.isDownloaded = isDownloaded
        self.localPath = localPath
    }
}
