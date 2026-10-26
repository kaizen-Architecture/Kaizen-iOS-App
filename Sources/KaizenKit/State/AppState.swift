import Foundation
import SwiftUI

/// Estado global de la aplicación Kaizen, reactivo con @Observable (Swift 6)
@MainActor
@Observable
public final class AppState {
    public var session: UserSession?
    public var currentLanguage: String = "es"
    public var isConnecting: Bool = false
    public var errorMessage: String?
    
    public var isAuthenticated: Bool {
        session != nil
    }
    
    public var isManagement: Bool {
        session?.role.isManagement ?? false
    }
    
    public init() {
        // Intentar restaurar sesión guardada de forma segura en Keychain
        if let savedSession = try? KeychainService.shared.loadSession() {
            self.session = savedSession
            self.currentLanguage = savedSession.language
        }
    }
    
    public func setSession(_ session: UserSession) {
        self.session = session
        self.currentLanguage = session.language
        try? KeychainService.shared.saveSession(session)
    }
    
    public func logout() {
        self.session = nil
        KeychainService.shared.clearSession()
    }
    
    public func switchLanguage(to language: String, client: KaizenAPIClient) async {
        self.currentLanguage = language
        if var current = session {
            current.language = language
            self.session = current
            try? KeychainService.shared.saveSession(current)
            try? await client.updateUserLanguage(
                serverUrl: current.serverUrl,
                token: current.apiToken,
                userId: current.id,
                language: language
            )
        }
    }
}
