import SwiftUI

@MainActor
@Observable
public final class AIStudioStore {
    public var targetUrl: String = "https://example-manga.com"
    public var scraperName: String = "CustomMangaSource"
    public var testQuery: String = "one piece"
    public var generatedLuaCode: String = ""
    public var isAnalyzing: Bool = false
    public var isTesting: Bool = false
    public var isDeploying: Bool = false
    public var isCleaningUp: Bool = false
    public var testResult: ScraperTestResult?
    public var testStatusMessage: String?
    public var errorMessage: String?
    public var isDeployed: Bool = false
    public var uploadedForTest: Bool = false
    public var repairIteration: Int = 0

    public init() {}

    /// Deriva un nombre seguro de scraper a partir de la URL introducida.
    public func syncScraperNameFromURL() {
        guard let url = URL(string: targetUrl.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host else { return }
        let cleaned = host
            .replacingOccurrences(of: "www.", with: "")
            .split(separator: ".")
            .first
            .map(String.init) ?? "CustomSource"
        let alnum = cleaned.filter { $0.isLetter || $0.isNumber }
        if !alnum.isEmpty {
            scraperName = alnum.prefix(1).uppercased() + alnum.dropFirst()
        }
    }

    /// Genera un scraper Lua conforme al contrato global de `kaizen-mangal v1.2+`
    /// (`SearchManga`, `MangaChapters`, `ChapterPages`, `Http.client()` + fallback lazy `Headless.browser()`).
    public func analyzeAndGenerate(isEn: Bool) async {
        isAnalyzing = true
        errorMessage = nil
        testStatusMessage = nil
        testResult = nil
        isDeployed = false
        repairIteration = 0
        defer { isAnalyzing = false }

        syncScraperNameFromURL()
        let base = targetUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        generatedLuaCode = Self.buildKaizenMangalTemplate(baseURL: base, forceHeadlessFallback: false)
        testStatusMessage = isEn
            ? "Generated kaizen-mangal v1.2+ Lua contract template. Ready to test on Kaizen."
            : "Plantilla Lua generada con contrato kaizen-mangal v1.2+. Lista para probar en Kaizen."
    }

    /// Bucle de autorreparación usando el diagnóstico estructurado devuelto por `sources.testScraper`.
    public func repairFromLastTest(isEn: Bool) async {
        guard let result = testResult, !result.success else { return }
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        repairIteration += 1
        let base = targetUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let joinedLogs = (result.logs + [result.errorKey ?? "", result.errorDetail ?? ""]).joined(separator: "\n").lowercased()
        let needsHeadless = joinedLogs.contains("403") || joinedLogs.contains("503") || joinedLogs.contains("cloudflare") || joinedLogs.contains("empty")

        let headerComment = """
        -- Auto-repair iteration #\(repairIteration)
        -- Previous failed phase: \(result.failedPhase ?? "unknown") (\(result.errorKey ?? "error"))
        -- Detail: \((result.errorDetail ?? "none").replacingOccurrences(of: "\n", with: " "))
        """
        generatedLuaCode = headerComment + "\n" + Self.buildKaizenMangalTemplate(baseURL: base, forceHeadlessFallback: needsHeadless)
        testStatusMessage = isEn
            ? "Applied AI repair #\(repairIteration) for phase '\(result.failedPhase ?? "unknown")'. Re-run Live Test to verify."
            : "Reparación IA #\(repairIteration) aplicada para la fase '\(result.failedPhase ?? "desconocida")'. Vuelve a probar en el servidor."
    }

    /// Flujo real contra el servidor Kaizen: `sources.upload` -> `sources.testScraper`.
    public func uploadAndTestOnServer(apiClient: KaizenAPIClient, session: UserSession?, isEn: Bool) async {
        guard let session else {
            errorMessage = isEn ? "No active Kaizen session." : "No hay sesión activa de Kaizen."
            return
        }
        let name = scraperName.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = testQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !generatedLuaCode.isEmpty else { return }

        isTesting = true
        errorMessage = nil
        testStatusMessage = nil
        defer { isTesting = false }

        do {
            try await apiClient.uploadLuaScraper(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                name: name,
                content: generatedLuaCode
            )
            uploadedForTest = true

            let result = try await apiClient.testLuaScraper(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                sourceName: name,
                query: query.isEmpty ? "one piece" : query,
                selectedMangaIndex: 0
            )
            testResult = result
            if result.success {
                testStatusMessage = isEn
                    ? "Server test passed (search, chapters & pages verified; \(result.searchResultsCount) matches)."
                    : "Prueba en servidor superada (búsqueda, capítulos y páginas OK; \(result.searchResultsCount) resultados)."
            } else {
                let phase = result.failedPhase ?? "unknown"
                testStatusMessage = isEn
                    ? "Server test failed at phase '\(phase)'. Review logs or run AI Repair."
                    : "La prueba falló en la fase '\(phase)'. Revisa los logs o ejecuta Reparar con IA."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Despliega (sube definitivamente) el scraper en el servidor Kaizen.
    public func deployToServer(apiClient: KaizenAPIClient, session: UserSession?, isEn: Bool) async {
        guard let session else {
            errorMessage = isEn ? "No active Kaizen session." : "No hay sesión activa de Kaizen."
            return
        }
        let name = scraperName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !generatedLuaCode.isEmpty else { return }

        isDeploying = true
        errorMessage = nil
        defer { isDeploying = false }

        do {
            try await apiClient.uploadLuaScraper(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                name: name,
                content: generatedLuaCode
            )
            uploadedForTest = true
            isDeployed = true
            testStatusMessage = isEn
                ? "Scraper '\(name)' deployed to Kaizen server."
                : "Scraper '\(name)' desplegado en el servidor Kaizen."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Limpia el scraper temporal del servidor si se descarta antes de desplegar.
    public func discardAndCleanup(apiClient: KaizenAPIClient, session: UserSession?, isEn: Bool) async {
        if uploadedForTest && !isDeployed, let session {
            let name = scraperName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                isCleaningUp = true
                defer { isCleaningUp = false }
                try? await apiClient.removeLuaScraper(
                    serverUrl: session.serverUrl,
                    token: session.apiToken,
                    name: name
                )
            }
        }
        uploadedForTest = false
        isDeployed = false
        testResult = nil
        testStatusMessage = isEn ? "Draft discarded." : "Borrador descartado."
        generatedLuaCode = ""
    }

    /// Contrato global `kaizen-mangal v1.2+`:
    /// - `Http.client()` primario con TLS/HTTP2 impersonation y cookie jar compartido.
    /// - Fallback lazy a `Headless.browser()` únicamente ante 403/503 o cuerpo vacío,
    ///   con `browser:sync_cookies()` y `page:close()`.
    /// - Arrays 1-based contiguos mediante `table.insert(...)`.
    public static func buildKaizenMangalTemplate(baseURL: String, forceHeadlessFallback: Bool) -> String {
        let clientLine = forceHeadlessFallback
            ? "    -- Headless fallback prioritized after server 403/503 diagnostics"
            : "    -- Primary resilient HTTP client (TLS/HTTP2 impersonation + shared cookie jar)"
        return """
        -- Kaizen Core (kaizen-mangal v1.2+) Lua Scraper
        local Base = "\(baseURL)"
        local Client = Http.client()

        local function fetchHTML(url)
        \(clientLine)
            local req = Http.request("GET", url)
            req:header("Referer", Base .. "/")
            local res, err = Client:do_request(req)
            if not err and res and res.status == 200 and res.body and #res.body > 0 then
                return res.body
            end

            -- Lazy headless fallback only on 403/503 or empty body
            if err or not res or res.status == 403 or res.status == 503 or not res.body or #res.body == 0 then
                local browser = Headless.browser()
                local page = browser:page()
                page:navigate(url)
                page:wait_load()
                local html = page:html()
                browser:sync_cookies()
                page:close()
                return html or ""
            end
            return ""
        end

        function SearchManga(query)
            local html = fetchHTML(Base .. "/?s=" .. query)
            local doc = Html.parse(html)
            local mangas = {}
            doc:find(".manga-card, article"):each(function(_, el)
                local link = el:find("a"):first()
                local title = link:attr("title")
                if not title or title == "" then
                    title = el:find(".title, h2, h3"):first():text()
                end
                local url = link:attr("href")
                if title and title ~= "" and url and url ~= "" then
                    table.insert(mangas, {
                        name = title,
                        url = url
                    })
                end
            end)
            return mangas
        end

        function MangaChapters(mangaURL)
            local html = fetchHTML(mangaURL)
            local doc = Html.parse(html)
            local chapters = {}
            doc:find(".chapter-item a, ul.chapters li a"):each(function(_, el)
                local name = el:text()
                local url = el:attr("href")
                if name and name ~= "" and url and url ~= "" then
                    table.insert(chapters, {
                        name = name,
                        url = url
                    })
                end
            end)
            return chapters
        end

        function ChapterPages(chapterURL)
            local html = fetchHTML(chapterURL)
            local doc = Html.parse(html)
            local pages = {}
            doc:find(".page-image img, .reading-content img"):each(function(_, el)
                local src = el:attr("data-src")
                if not src or src == "" then
                    src = el:attr("src")
                end
                if src and src ~= "" then
                    table.insert(pages, { url = src })
                end
            end)
            return pages
        end
        """
    }
}

/// AI Studio: Generación, prueba en vivo contra Kaizen y autorreparación de scrapers Lua `kaizen-mangal v1.2+`
public struct AIStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var store = AIStudioStore()
    let apiClient: KaizenAPIClient

    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }

    private var isEn: Bool {
        appState.currentLanguage == "en"
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if !appState.isManagement {
                    ContentUnavailableView(
                        isEn ? "Admin Only" : "Solo Administradores",
                        systemImage: "lock.shield",
                        description: Text(isEn ? "AI Studio is restricted to administrators and managers." : "AI Studio es una herramienta de ingeniería de scrapers restringida a administradores.")
                    )
                } else {
                    mainStudioView
                }
            }
            .navigationTitle("AI Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Close" : "Cerrar") {
                        Task {
                            if store.uploadedForTest && !store.isDeployed {
                                await store.discardAndCleanup(apiClient: apiClient, session: appState.session, isEn: isEn)
                            }
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var mainStudioView: some View {
        VStack(spacing: 0) {
            // Configuración del scraper (URL, nombre y consulta de prueba)
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    TextField("https://sitio-manga.com", text: $store.targetUrl)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await store.analyzeAndGenerate(isEn: isEn) }
                    } label: {
                        HStack(spacing: 4) {
                            if store.isAnalyzing {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "sparkles")
                                Text(isEn ? "Generate" : "Generar")
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.black)
                    }
                    .disabled(store.isAnalyzing || store.targetUrl.isEmpty)
                }

                HStack(spacing: 8) {
                    TextField(isEn ? "Scraper name" : "Nombre scraper", text: $store.scraperName)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField(isEn ? "Test query (e.g. one piece)" : "Consulta test (ej. one piece)", text: $store.testQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Badge de contrato Kaizen Core v1.2+
            HStack {
                Label(
                    isEn ? "kaizen-mangal v1.2+ Contract (Http + Lazy Headless)" : "Contrato kaizen-mangal v1.2+ (Http + Headless Lazy)",
                    systemImage: "cpu.fill"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Editor de código Lua
            ZStack {
                Color.black

                if store.generatedLuaCode.isEmpty {
                    ContentUnavailableView(
                        isEn ? "No Code Generated" : "Sin código generado",
                        systemImage: "curlybraces",
                        description: Text(
                            isEn
                                ? "Enter a manga site URL to generate a kaizen-mangal v1.2+ Lua scraper and validate it live against your Kaizen server."
                                : "Introduce una URL para generar un scraper Lua kaizen-mangal v1.2+ y validarlo en vivo contra tu servidor Kaizen."
                        )
                    )
                } else {
                    TextEditor(text: $store.generatedLuaCode)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.green.opacity(0.95))
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.03))
                        .padding(.horizontal, 10)
                }
            }

            // Diagnóstico / Logs del test en servidor
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }

            if let msg = store.testStatusMessage {
                Text(msg)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.testResult?.success == false ? .orange : .cyan)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            if let result = store.testResult, !result.logs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if let detail = result.errorDetail, !detail.isEmpty {
                            Text("[\(result.failedPhase ?? "error")] \(detail)")
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(.orange)
                        }
                        ForEach(Array(result.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(maxHeight: 96)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 4)
            }

            // Botones de acción
            if !store.generatedLuaCode.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await store.uploadAndTestOnServer(
                                apiClient: apiClient,
                                session: appState.session,
                                isEn: isEn
                            )
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if store.isTesting {
                                ProgressView().scaleEffect(0.75).tint(.white)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(store.isTesting ? (isEn ? "Testing..." : "Probando...") : (isEn ? "Live Test" : "Probar en Kaizen"))
                        }
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .disabled(store.isTesting || store.isDeploying)

                    if store.testResult?.success == false {
                        Button {
                            Task { await store.repairFromLastTest(isEn: isEn) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "wrench.and.sparkles.fill")
                                Text(isEn ? "AI Repair" : "Reparar IA")
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Color.orange.opacity(0.25), in: Capsule())
                            .foregroundStyle(.orange)
                        }
                        .disabled(store.isAnalyzing || store.isTesting)
                    }

                    Button {
                        Task {
                            await store.deployToServer(
                                apiClient: apiClient,
                                session: appState.session,
                                isEn: isEn
                            )
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if store.isDeploying {
                                ProgressView().scaleEffect(0.75).tint(.black)
                            } else {
                                Image(systemName: store.isDeployed ? "checkmark.circle.fill" : "cloud.fill")
                            }
                            Text(store.isDeployed ? (isEn ? "Deployed" : "Desplegado") : (isEn ? "Deploy" : "Desplegar"))
                        }
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.cyan, in: Capsule())
                        .foregroundStyle(.black)
                    }
                    .disabled(store.isTesting || store.isDeploying)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.9))
            }
        }
    }
}
