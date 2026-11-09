import Foundation

/// Información de un capítulo descargado y almacenado de forma permanente en el dispositivo.
public struct OfflineDownloadedChapter: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let mangaId: Int
    public let index: Int
    public let title: String
    public let pageCount: Int
    public let totalSizeBytes: Int64
    public let downloadedAt: Date
    public var lastReadPage: Int
    public var isRead: Bool
    
    public init(
        id: Int,
        mangaId: Int,
        index: Int,
        title: String,
        pageCount: Int,
        totalSizeBytes: Int64,
        downloadedAt: Date = Date(),
        lastReadPage: Int = 1,
        isRead: Bool = false
    ) {
        self.id = id
        self.mangaId = mangaId
        self.index = index
        self.title = title
        self.pageCount = pageCount
        self.totalSizeBytes = totalSizeBytes
        self.downloadedAt = downloadedAt
        self.lastReadPage = lastReadPage
        self.isRead = isRead
    }
}

/// Metadatos de un manga con capítulos guardados en local para lectura sin conexión.
public struct OfflineMangaMetadata: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public var title: String
    public var coverLocalFileName: String?
    public var coverRemoteUrl: String?
    public var synopsis: String?
    public var authors: [String]?
    public var genres: [String]?
    public var status: String?
    public var chapters: [OfflineDownloadedChapter]
    
    public init(
        id: Int,
        title: String,
        coverLocalFileName: String? = nil,
        coverRemoteUrl: String? = nil,
        synopsis: String? = nil,
        authors: [String]? = nil,
        genres: [String]? = nil,
        status: String? = nil,
        chapters: [OfflineDownloadedChapter] = []
    ) {
        self.id = id
        self.title = title
        self.coverLocalFileName = coverLocalFileName
        self.coverRemoteUrl = coverRemoteUrl
        self.synopsis = synopsis
        self.authors = authors
        self.genres = genres
        self.status = status
        self.chapters = chapters
    }
    
    public var totalSizeBytes: Int64 {
        chapters.reduce(0) { $0 + $1.totalSizeBytes }
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
    
    public var chapterCount: Int {
        chapters.count
    }
}

/// Tarea de sincronización diferida cuando se lee sin conexión.
public struct PendingSyncReadAction: Identifiable, Codable, Sendable, Equatable {
    public var id: String { "\(mangaId)_\(chapterId)_\(timestamp.timeIntervalSince1970)" }
    public let mangaId: Int
    public let chapterId: Int
    public let page: Int
    public let totalPages: Int
    public let isRead: Bool
    public let timestamp: Date
    
    public init(
        mangaId: Int,
        chapterId: Int,
        page: Int,
        totalPages: Int,
        isRead: Bool,
        timestamp: Date = Date()
    ) {
        self.mangaId = mangaId
        self.chapterId = chapterId
        self.page = page
        self.totalPages = totalPages
        self.isRead = isRead
        self.timestamp = timestamp
    }
}

/// Configuración de usuario para descargas y almacenamiento local.
public struct OfflineStorageSettings: Codable, Sendable, Equatable {
    /// Opciones de retención temporal: 0 = para siempre, o días (7, 30, 90)
    public var retentionDays: Int = 0
    /// Auto-borrado de capítulos una vez leídos (tras sincronizar con servidor)
    public var autoDeleteWhenRead: Bool = false
    /// Permitir descargas solo mediante Wi-Fi
    public var downloadWifiOnly: Bool = true
    
    public init(
        retentionDays: Int = 0,
        autoDeleteWhenRead: Bool = false,
        downloadWifiOnly: Bool = true
    ) {
        self.retentionDays = retentionDays
        self.autoDeleteWhenRead = autoDeleteWhenRead
        self.downloadWifiOnly = downloadWifiOnly
    }
}
