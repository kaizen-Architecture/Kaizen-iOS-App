import Foundation

/// Roles del sistema Kaizen compatibles con el backend
public enum UserRole: String, Codable, Sendable, CaseIterable {
    case superadmin = "SUPERADMIN"
    case manager = "MANAGER"
    case reader = "READER"
    case service = "SERVICE"
    
    public init?(rawValue: String) {
        let upper = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch upper {
        case "SUPERADMIN", "ADMIN":
            self = .superadmin
        case "MANAGER":
            self = .manager
        case "READER", "USER":
            self = .reader
        case "SERVICE":
            self = .service
        default:
            return nil
        }
    }
    
    public var isManagement: Bool {
        self == .superadmin || self == .manager
    }
}

/// Sesión activa del usuario autenticado
public struct UserSession: Codable, Sendable, Equatable {
    public let id: Int
    public let username: String
    public let role: UserRole
    public var language: String
    public let apiToken: String
    public let serverUrl: URL
    
    public init(id: Int, username: String, role: UserRole, language: String, apiToken: String, serverUrl: URL) {
        self.id = id
        self.username = username
        self.role = role
        self.language = language
        self.apiToken = apiToken
        self.serverUrl = serverUrl
    }
}

/// Ajustes de usuario sincronizados remotamente con Kaizen
public struct RemoteUserSettings: Codable, Sendable {
    public let id: Int
    public let username: String
    public let role: UserRole
    public var language: String
    public var anilistEnabled: Bool
    public var anilistUsername: String?
    public var anilistAutoSync: Bool
    public var notificationsEnabled: Bool
    public var whatsappEnabled: Bool
    public var whatsappPhone: String?
    public var whatsappApiKey: String?
    public var discordEnabled: Bool
    public var discordWebhookUrl: String?
    public var telegramEnabled: Bool
    public var telegramChatId: String?
    public var notifyEvents: [String]?
    
    public init(
        id: Int,
        username: String,
        role: UserRole,
        language: String,
        anilistEnabled: Bool = false,
        anilistUsername: String? = nil,
        anilistAutoSync: Bool = true,
        notificationsEnabled: Bool = false,
        whatsappEnabled: Bool = false,
        whatsappPhone: String? = nil,
        whatsappApiKey: String? = nil,
        discordEnabled: Bool = false,
        discordWebhookUrl: String? = nil,
        telegramEnabled: Bool = false,
        telegramChatId: String? = nil,
        notifyEvents: [String]? = nil
    ) {
        self.id = id
        self.username = username
        self.role = role
        self.language = language
        self.anilistEnabled = anilistEnabled
        self.anilistUsername = anilistUsername
        self.anilistAutoSync = anilistAutoSync
        self.notificationsEnabled = notificationsEnabled
        self.whatsappEnabled = whatsappEnabled
        self.whatsappPhone = whatsappPhone
        self.whatsappApiKey = whatsappApiKey
        self.discordEnabled = discordEnabled
        self.discordWebhookUrl = discordWebhookUrl
        self.telegramEnabled = telegramEnabled
        self.telegramChatId = telegramChatId
        self.notifyEvents = notifyEvents
    }
}
