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
    
    public func fetchMangaDetail(serverUrl: URL, token: String, mangaId: Int) async throws -> Manga {
        let req = request(try endpoint(serverUrl, path: "/api/v1/mangas/\(mangaId)"), token: token)
        let (data, http) = try await send(req)
        try checkREST(http)
        do {
            return try decoder.decode(Manga.self, from: data)
        } catch {
            throw KaizenError.unexpectedResponse
        }
    }
    
    public func toggleMangaFavorite(serverUrl: URL, token: String, mangaId: Int, isFavorite: Bool) async throws {
        let body: [String: Any] = ["json": ["id": mangaId, "isFavorite": isFavorite]]
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.toggleMangaFavorite"), method: "POST", token: token, json: body)
        let (_, http) = try await send(req)
        try checkREST(http)
    }

    // MARK: - Capítulos y páginas

    /// Devuelve las URLs absolutas de las páginas de un capítulo.
    public func fetchChapterPages(serverUrl: URL, token: String, mangaId: Int, chapterId: Int) async throws -> [String] {
        let req = request(try endpoint(serverUrl, path: "/api/v1/mangas/\(mangaId)/chapters/\(chapterId)/pages"), token: token)
        let (data, http) = try await send(req)
        try checkREST(http)

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let pages = root["pages"] as? [[String: Any]] else {
            throw KaizenError.unexpectedResponse
        }
        var base = serverUrl.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return pages.compactMap { pageDict -> String? in
            guard let url = pageDict["url"] as? String else { return nil }
            return url.hasPrefix("http") ? url : base + url
        }
    }

    public func updateReadingProgress(serverUrl: URL, token: String, mangaId: Int, chapterId: Int, page: Int, isRead: Bool? = nil) async throws {
        var chDict: [String: Any] = ["id": chapterId, "lastReadPage": page]
        if let isRead { chDict["isRead"] = isRead }
        let payload: [String: Any] = ["chapters": [chDict]]
        let req = try request(
            try endpoint(serverUrl, path: "/api/v1/mangas/\(mangaId)"),
            method: "PATCH", token: token, json: payload
        )
        let (_, http) = try await send(req)
        try checkREST(http)
    }
    
    public func toggleChapterRead(serverUrl: URL, token: String, mangaId: Int, chapterId: Int, isRead: Bool) async throws {
        let payload: [String: Any] = [
            "chapters": [["id": chapterId, "isRead": isRead]]
        ]
        let req = try request(
            try endpoint(serverUrl, path: "/api/v1/mangas/\(mangaId)"),
            method: "PATCH", token: token, json: payload
        )
        let (_, http) = try await send(req)
        try checkREST(http)
    }
    
    public func markAllChaptersRead(serverUrl: URL, token: String, mangaId: Int, isRead: Bool) async throws {
        let payload: [String: Any] = ["isRead": isRead]
        let req = try request(
            try endpoint(serverUrl, path: "/api/v1/mangas/\(mangaId)"),
            method: "PATCH", token: token, json: payload
        )
        let (_, http) = try await send(req)
        try checkREST(http)
    }
    
    // MARK: - Peticiones (mangaRequest)
    
    public func fetchRequests(serverUrl: URL, token: String) async throws -> [MangaRequestItem] {
        let req = request(try trpcQueryURL(serverUrl, procedure: "mangaRequest.list", input: [:]), token: token)
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let list = trpcRawData(data) as? [[String: Any]] else { return [] }
        
        return list.compactMap { item in
            guard let id = item["id"] as? Int,
                  let title = item["title"] as? String else { return nil }
            let start = item["startChapter"] as? Int ?? 1
            let status = item["status"] as? String ?? "PENDING"
            let userId = item["userId"] as? Int
            let user = item["user"] as? [String: Any]
            let username = user?["username"] as? String
            let createdAt = item["createdAt"] as? String
            return MangaRequestItem(id: id, title: title, startChapter: start, status: status, userId: userId, username: username, createdAt: createdAt)
        }
    }
    
    public func createRequest(serverUrl: URL, token: String, title: String, startChapter: Int) async throws {
        let body: [String: Any] = ["json": ["title": title, "startChapter": startChapter]]
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/mangaRequest.create"), method: "POST", token: token, json: body)
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    // MARK: - Bibliotecas
    
    public func fetchLibraries(serverUrl: URL, token: String) async throws -> [KaizenLibrary] {
        let req = request(try trpcQueryURL(serverUrl, procedure: "library.list", input: [:]), token: token)
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let raw = trpcRawData(data) else { return [] }
        let bytes = try JSONSerialization.data(withJSONObject: raw)
        return (try? decoder.decode([KaizenLibrary].self, from: bytes)) ?? []
    }
    
    public func createLibrary(serverUrl: URL, token: String, path: String) async throws -> KaizenLibrary {
        let body: [String: Any] = ["json": ["path": path]]
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/library.create"), method: "POST", token: token, json: body)
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let payload = trpcPayload(data) else { throw KaizenError.unexpectedResponse }
        let bytes = try JSONSerialization.data(withJSONObject: payload)
        return try decoder.decode(KaizenLibrary.self, from: bytes)
    }

    // MARK: - Administración y Ajustes
    
    public func fetchServerSettings(serverUrl: URL, token: String) async throws -> KaizenServerSettings {
        let req = request(try trpcQueryURL(serverUrl, procedure: "settings.query", input: [:]), token: token)
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let payload = trpcPayload(data),
              let appConfig = payload["appConfig"] as? [String: Any] else {
            return KaizenServerSettings()
        }
        let raw = try JSONSerialization.data(withJSONObject: appConfig)
        return (try? decoder.decode(KaizenServerSettings.self, from: raw)) ?? KaizenServerSettings()
    }
    
    public func fetchQueueMetrics(serverUrl: URL, token: String) async throws -> QueuesResponse? {
        let req = request(try trpcQueryURL(serverUrl, procedure: "queues.getMetrics", input: [:]), token: token)
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let payload = trpcPayload(data) else { return nil }
        let raw = try JSONSerialization.data(withJSONObject: payload)
        return try? decoder.decode(QueuesResponse.self, from: raw)
    }
    
    public func syncAllMangas(serverUrl: URL, token: String) async throws {
        let body: [String: Any] = ["json": [:]]
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.syncAll"), method: "POST", token: token, json: body)
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    // MARK: - Control Remoto del Servidor Kaizen (tRPC)
    
    public func refreshAllMetadata(serverUrl: URL, token: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.refreshAllMetadata"), method: "POST", token: token, json: ["json": [:]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func cleanupDuplicates(serverUrl: URL, token: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.cleanupDuplicates"), method: "POST", token: token, json: ["json": [:]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func resetAllCircuitBreakers(serverUrl: URL, token: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.resetAllCircuitBreakers"), method: "POST", token: token, json: ["json": [:]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func triggerStatusAudit(serverUrl: URL, token: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.triggerStatusAudit"), method: "POST", token: token, json: ["json": [:]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func syncScrapers(serverUrl: URL, token: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/sources.sync"), method: "POST", token: token, json: ["json": [:]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func syncAniList(serverUrl: URL, token: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/settings.syncAniListProgress"), method: "POST", token: token, json: ["json": [:]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func retryAllFailedJobs(serverUrl: URL, token: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.retryAllFailedJobs"), method: "POST", token: token, json: ["json": [:]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func cleanQueue(serverUrl: URL, token: String, queueName: String = "downloadQueue", type: String = "completed") async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/queues.cleanQueue"), method: "POST", token: token, json: ["json": ["queueName": queueName, "type": type]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func fetchFailedJobs(serverUrl: URL, token: String) async throws -> [FailedDownloadJob] {
        let req = request(try trpcQueryURL(serverUrl, procedure: "manga.failedJobs", input: [:]), token: token)
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let list = trpcRawData(data) as? [[String: Any]] else { return [] }
        
        return list.compactMap { dict in
            guard let idVal = dict["id"],
                  let mangaId = dict["mangaId"] as? Int,
                  let mangaTitle = dict["mangaTitle"] as? String else { return nil }
            let id = String(describing: idVal)
            let chapterIndex: Double
            if let ci = dict["chapterIndex"] as? Double {
                chapterIndex = ci
            } else if let ci = dict["chapterIndex"] as? Int {
                chapterIndex = Double(ci)
            } else if let ci = dict["chapterIndex"] as? String {
                chapterIndex = Double(ci.replacingOccurrences(of: "@", with: "")) ?? 0.0
            } else {
                chapterIndex = 0.0
            }
            let source = (dict["source"] as? String) ?? "Unknown"
            let failedReason = dict["failedReason"] as? String
            let attempts = (dict["attempts"] as? Int) ?? 1
            let isPaused = (dict["isPaused"] as? Bool) ?? false
            return FailedDownloadJob(
                id: id,
                mangaId: mangaId,
                mangaTitle: mangaTitle,
                chapterIndex: chapterIndex,
                source: source,
                failedReason: failedReason,
                attempts: attempts,
                isPaused: isPaused
            )
        }
    }
    
    public func retryJob(serverUrl: URL, token: String, jobId: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.retryJob"), method: "POST", token: token, json: ["json": ["jobId": jobId]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func cancelJob(serverUrl: URL, token: String, jobId: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.cancelJob"), method: "POST", token: token, json: ["json": ["jobId": jobId]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    public func updateRequestStatus(serverUrl: URL, token: String, requestId: Int, status: String) async throws {
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/mangaRequest.updateStatus"), method: "POST", token: token, json: ["json": ["id": requestId, "status": status]])
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
    }
    
    // MARK: - Añadir Manga Remoto (tRPC)
    
    public func fetchAvailableSources(serverUrl: URL, token: String) async throws -> [String] {
        let req = request(try trpcQueryURL(serverUrl, procedure: "manga.sources", input: [:]), token: token)
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let list = trpcRawData(data) as? [String] else { return [] }
        return list
    }
    
    public func searchMangaRemote(serverUrl: URL, token: String, keyword: String, source: String) async throws -> [RemoteSearchResult] {
        var req = request(try trpcQueryURL(serverUrl, procedure: "manga.search", input: ["keyword": keyword, "source": source]), token: token)
        req.timeoutInterval = 60 // Permite búsquedas globales en múltiples fuentes sin timeout prematuro
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let items = trpcRawData(data) as? [[String: Any]] else { return [] }
        
        return items.compactMap { dict in
            guard let title = dict["title"] as? String else { return nil }
            let src = (dict["source"] as? String) ?? source
            let status = dict["status"] as? String
            let chapters = (dict["chapters"] as? Int) ?? 0
            let cover = dict["cover"] as? String
            return RemoteSearchResult(title: title, source: src, status: status, chapters: chapters, cover: cover)
        }
    }
    
    public func addMangaRemote(
        serverUrl: URL,
        token: String,
        source: String,
        title: String,
        interval: String = "0 * * * *",
        minChapters: Int = 0
    ) async throws {
        let body: [String: Any] = [
            "json": [
                "source": source,
                "title": title,
                "interval": interval,
                "minChapters": minChapters
            ]
        ]
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/manga.add"), method: "POST", token: token, json: body)
        let (data, http) = try await send(req)
        if !(200...299).contains(http.statusCode) {
            if let str = String(data: data, encoding: .utf8), str.contains("CONFLICT") {
                throw NSError(domain: "Kaizen", code: 409, userInfo: [NSLocalizedDescriptionKey: "Esta serie ya existe en la biblioteca de Kaizen"])
            }
            throw KaizenError.server(status: http.statusCode)
        }
    }

    // MARK: - Gestión de Fuentes y Scrapers (tRPC)
    
    public func fetchSourcesList(serverUrl: URL, token: String) async throws -> [KaizenSourceItem] {
        let req = request(try trpcQueryURL(serverUrl, procedure: "sources.list", input: [:]), token: token)
        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
        guard let list = trpcRawData(data) as? [[String: Any]] else { return [] }
        
        return list.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let isInstalled = (dict["isInstalled"] as? Bool) ?? true
            let isActive = (dict["isActive"] as? Bool) ?? false
            let isFailed = (dict["isFailed"] as? Bool) ?? false
            let origin = dict["origin"] as? String
            return KaizenSourceItem(name: name, isInstalled: isInstalled, isActive: isActive, isFailed: isFailed, origin: origin)
        }
    }
    
    public func toggleSource(serverUrl: URL, token: String, name: String, activate: Bool, isFailed: Bool = false) async throws {
        let body: [String: Any] = [
            "json": [
                "name": name,
                "activate": activate,
                "isFailed": isFailed
            ]
        ]
        let req = try request(try endpoint(serverUrl, path: "/api/trpc/sources.toggle"), method: "POST", token: token, json: body)
        let (_, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else { throw KaizenError.server(status: http.statusCode) }
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

    /// Extrae `result.data.json` o `result.data` de una respuesta tRPC (superjson), sea objeto o array.
    private func trpcRawData(_ data: Data) -> Any? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let payload = result["data"] as? [String: Any] else { return nil }
        return payload["json"] ?? payload
    }

    /// Extrae `result.data.json` de una respuesta tRPC cuando es diccionario.
    private func trpcPayload(_ data: Data) -> [String: Any]? {
        trpcRawData(data) as? [String: Any]
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
