import Foundation

/// Cliente HTTP asíncrono y Sendable para la API REST y tRPC de Kaizen
public actor KaizenAPIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }
    
    // MARK: - Autenticación
    
    public func login(serverUrl: URL, username: String, password: String) async throws -> UserSession {
        let endpoint = serverUrl.appendingPathComponent("api/trpc/auth.login")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["username": username, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(code: httpResponse.statusCode)
        }
        
        // Mapear respuesta tRPC
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let resData = result["data"] as? [String: Any],
              let userObj = resData["user"] as? [String: Any],
              let userId = userObj["id"] as? Int,
              let roleStr = userObj["role"] as? String,
              let role = UserRole(rawValue: roleStr) else {
            throw NetworkError.parsingError
        }
        
        let lang = (userObj["language"] as? String) ?? "es"
        let token = (userObj["apiToken"] as? String) ?? ""
        
        return UserSession(
            id: userId,
            username: username,
            role: role,
            language: lang,
            apiToken: token,
            serverUrl: serverUrl
        )
    }
    
    // MARK: - Biblioteca
    
    public func fetchLibrary(serverUrl: URL, token: String) async throws -> [Manga] {
        let endpoint = serverUrl.appendingPathComponent("api/v1/mangas")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(code: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        return try decoder.decode([Manga].self, from: data)
    }
    
    // MARK: - Capítulos y Páginas
    
    public func fetchChapterPages(serverUrl: URL, token: String, mangaId: String, chapterId: String) async throws -> [String] {
        let endpoint = serverUrl.appendingPathComponent("api/v1/mangas/\(mangaId)/chapters/\(chapterId)/pages")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(code: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        // La API devuelve un array de URLs o nombres de archivo
        if let pageUrls = try? decoder.decode([String].self, from: data) {
            return pageUrls
        }
        return []
    }
    
    public func updateReadingProgress(serverUrl: URL, token: String, mangaId: String, chapterId: String, page: Int) async throws {
        let endpoint = serverUrl.appendingPathComponent("api/v1/mangas/\(mangaId)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "chapters": [
                ["id": chapterId, "isRead": true, "lastReadPage": page]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try await session.data(for: request)
    }
    
    // MARK: - Ajustes de Usuario Remotos
    
    public func fetchUserSettings(serverUrl: URL, token: String, userId: Int) async throws -> RemoteUserSettings {
        let endpoint = serverUrl.appendingPathComponent("api/trpc/auth.getUserSettings?input=\(encodeQueryInput(["userId": userId]))")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(code: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let userDict = result["data"] as? [String: Any] else {
            throw NetworkError.parsingError
        }
        
        let rawData = try JSONSerialization.data(withJSONObject: userDict)
        return try decoder.decode(RemoteUserSettings.self, from: rawData)
    }
    
    public func updateUserLanguage(serverUrl: URL, token: String, userId: Int, language: String) async throws {
        let endpoint = serverUrl.appendingPathComponent("api/trpc/auth.updateUserSettings")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "userId": userId,
            "key": "language",
            "value": language
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try await session.data(for: request)
    }
    
    private func encodeQueryInput(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }
}

public enum NetworkError: Error {
    case invalidResponse
    case serverError(code: Int)
    case parsingError
    case unauthorized
}
