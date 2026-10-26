import Foundation
import Security

/// Servicio nativo de Keychain siguiendo la skill `swift-security`
public final class KeychainService: Sendable {
    public static let shared = KeychainService()
    private let serviceName = "com.kaizen.manga.ios"
    
    public init() {}
    
    public func save(key: String, data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]
        
        SecItemDelete(query as CFDictionary)
        
        var newQuery = query
        newQuery[kSecValueData] = data
        newQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        
        let status = SecItemAdd(newQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.statusError(status)
        }
    }
    
    public func load(key: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.statusError(status)
        }
        return data
    }
    
    public func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    public func saveSession(_ session: UserSession) throws {
        let data = try JSONEncoder().encode(session)
        try save(key: "current_user_session", data: data)
    }
    
    public func loadSession() throws -> UserSession? {
        guard let data = try load(key: "current_user_session") else { return nil }
        return try JSONDecoder().decode(UserSession.self, from: data)
    }
    
    public func clearSession() {
        delete(key: "current_user_session")
    }
}

public enum KeychainError: Error {
    case statusError(OSStatus)
}
