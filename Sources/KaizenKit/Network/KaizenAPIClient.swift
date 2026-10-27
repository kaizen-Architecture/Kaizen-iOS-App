import Foundation

/// Cliente HTTP asíncrono para la API de Kaizen.
///
/// - tRPC (`/api/trpc/*`): el servidor usa el transformer `superjson`, así que el
///   cuerpo de las mutaciones es `{"json": {...}}` y la respuesta llega en `result.data.json`.
/// - REST (`/api/v1/*`): requiere `Authorization: Bearer <API Token>` cuando la
///   autenticación está activada en el servidor.
public actor KaizenAPIClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Autenticación

    /// Valida usuario y contraseña contra tRPC. El login de Kaizen no devuelve el API Token,
    /// así que se recibe aparte (`apiToken`) y se guarda en la sesión para las llamadas REST.
    public func login(serverUrl: URL, username: String, password: String, apiToken: String = "") async throws -> UserSession {
        let url = try endpoint(serverUrl, path: "/api/trpc/auth.login")
        let req = try request(url, method: "POST", json: ["json": ["username": username, "password": password]])
        let (data, http) = try await send(req)

        switch http.statusCode {
        case 200...299: break
        case 401: throw KaizenError.invalidCredentials
        default: throw KaizenError.server(status: http.statusCode)
        }

        guard let payload = trpcPayload(data),
              let user = payload["user"] as? [String: Any],
              let userId = user["id"] as? Int,
              let roleString = user["role"] as? String,
              let role = UserRole(rawValue: roleString) else {
            throw KaizenError.unexpectedResponse
        }

        let language = await fetchLanguage(serverUrl: serverUrl, userId: userId)
        return UserSession(
            id: userId,
            username: (user["username"] as? String) ?? username,
            role: role,
            language: language,
            apiToken: (user["apiToken"] as? String) ?? apiToken,
            serverUrl: serverUrl
        )
    }

    // MARK: - Biblioteca

    public func fetchLibrary(serverUrl: URL, token: String) async throws -> [Manga] {
        let req = request(try endpoint(serverUrl, path: "/api/v1/mangas"), token: token)
        let (data, http) = try await send(req)
        try checkREST(http)
        do {
            return try decoder.decode([Manga].self, from: data)
        } catch {
            throw KaizenError.unexpectedResponse
        }
    }

    // MARK: - Capítulos y páginas

    /// Devuelve las URLs absolutas de las páginas de un capítulo.
    public func fetchChapterPages(serverUrl: URL, token: String, mangaId: String, chapterId: String) async throws -> [String] {
        let req = request(try endpoint(serverUrl, path: "/api/v1/mangas/\(mangaId)/chapters/\(chapterId)/pages"), token: token)
        let (data, http) = try await send(req)
        try checkREST(http)

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let pages = root["pages"] as? [[String: Any]] else {
            throw KaizenError.unexpectedResponse
        }
        var base = serverUrl.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return pages.compactMap { ($0["url"] as? String).map { base + $0 } }
    }

    public func updateReadingProgress(serverUrl: URL, token: String, mangaId: String, chapterId: String, page: Int) async throws {
        let payload: [String: Any] = [
            "chapters": [["id": chapterId, "isRead": true, "lastReadPage": page]]
        ]
        let req = try request(
            try endpoint(serverUrl, path: "/api/v1/mangas/\(mangaId)"),
            method: "PATCH", token: token, json: payload
        )
        let (_, http) = try await send(req)
        try checkREST(http)
    }

    // MARK: - Ajustes de usuario remotos (tRPC)

    public func fetchUserSettings(serverUrl: URL, token: String, userId: Int) async throws -> RemoteUserSettings {
        let req = request(try trpcQueryURL(serverUrl, procedure: "auth.getUserSettings", input: ["userId": userId]))
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let payload = trpcPayload(data) else { throw KaizenError.unexpectedResponse }

        do {
            let raw = try JSONSerialization.data(withJSONObject: payload)
            return try decoder.decode(RemoteUserSettings.self, from: raw)
        } catch {
            throw KaizenError.unexpectedResponse
        }
    }

    public func updateUserLanguage(serverUrl: URL, token: String, userId: Int, language: String) async throws {
        let body: [String: Any] = ["json": ["userId": userId, "key": "language", "value": language]]
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/auth.updateUserSettings"), method: "POST", json: body)
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }

    // MARK: - Helpers privados

    /// Construye `<base>/<path>` respetando un posible prefijo en la URL del servidor.
    private func endpoint(_ base: URL, path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw KaizenError.invalidServerURL
        }
        var basePath = comps.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        comps.path = basePath + path
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url else { throw KaizenError.invalidServerURL }
        return url
    }

    /// URL de una query tRPC con superjson: `?input={"json":{...}}`.
    private func trpcQueryURL(_ base: URL, procedure: String, input: [String: Any]) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: ["json": input])
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return try endpoint(base, path: "/api/trpc/\(procedure)", query: [URLQueryItem(name: "input", value: text)])
    }

    private func request(_ url: URL, method: String = "GET", token: String? = nil, json: Any? = nil) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return req
    }

    /// Variante sin cuerpo (no lanza), para peticiones GET.
    private func request(_ url: URL, token: String? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let host = req.url?.host ?? req.url?.absoluteString ?? "?"
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw KaizenError.unexpectedResponse }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw error
            case .timedOut: throw KaizenError.timedOut(host: host)
            default: throw KaizenError.cannotReachServer(host: host)
            }
        }
    }

    private func checkREST(_ http: HTTPURLResponse) throws {
        switch http.statusCode {
        case 200...299: return
        case 401: throw KaizenError.tokenRejected
        case 403: throw KaizenError.apiDisabled
        default: throw KaizenError.server(status: http.statusCode)
        }
    }

    /// Extrae `result.data.json` de una respuesta tRPC (superjson).
    private func trpcPayload(_ data: Data) -> [String: Any]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let payload = result["data"] as? [String: Any] else { return nil }
        return (payload["json"] as? [String: Any]) ?? payload
    }

    /// El login no devuelve el idioma; se consulta aparte y, si falla, se usa español.
    private func fetchLanguage(serverUrl: URL, userId: Int) async -> String {
        guard let url = try? trpcQueryURL(serverUrl, procedure: "auth.getUserSettings", input: ["userId": userId]),
              let (data, http) = try? await send(request(url)),
              (200...299).contains(http.statusCode),
              let payload = trpcPayload(data),
              let language = payload["language"] as? String,
              language == "es" || language == "en" else { return "es" }
        return language
    }
}
