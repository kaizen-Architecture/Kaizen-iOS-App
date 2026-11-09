import SwiftUI

public struct RequestAvailabilityState: Sendable, Equatable {
    public var isChecking: Bool = false
    public var hasChecked: Bool = false
    public var results: [RemoteSearchResult] = []
    public var selectedSourceId: String?
    public var targetMinChapters: Int = 50
    public var error: String?
    
    public var selectedResult: RemoteSearchResult? {
        if let selectedSourceId, let found = results.first(where: { $0.id == selectedSourceId }) {
            return found
        }
        return results.first
    }
}

@MainActor
@Observable
public final class MangaRequestsStore {
    public var requests: [MangaRequestItem] = []
    public var plannedMangas: [KaizenPlannedManga] = []
    public var coverCache: [String: String] = [:]
    public var availabilityByRequestId: [Int: RequestAvailabilityState] = [:]
    public var processingRequestIds: Set<Int> = []
    
    public var titleInput: String = ""
    public var startChapterInput: Int = 50
    public var isSubmitting: Bool = false
    public var isLoading: Bool = false
    public var errorMessage: String?
    public var successMessage: String?
    
    public init() {}
    
    public func loadAll(apiClient: KaizenAPIClient, session: UserSession?, existingMangas: [Manga]) async {
        guard let session else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        async let reqsTask = apiClient.fetchRequests(serverUrl: session.serverUrl, token: session.apiToken)
        async let plannedTask = apiClient.fetchPlannedMangas(serverUrl: session.serverUrl, token: session.apiToken)
        
        do {
            let fetchedReqs = try await reqsTask
            self.requests = fetchedReqs
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        if let fetchedPlanned = try? await plannedTask {
            self.plannedMangas = fetchedPlanned
        }
        
        // Pre-poblar portadas conocidas desde la biblioteca local o series planeadas
        let baseStr = session.serverUrl.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for req in requests {
            let key = req.title.lowercased()
            if coverCache[key] == nil {
                if let libMatch = existingMangas.first(where: { $0.title.localizedCaseInsensitiveCompare(req.title) == .orderedSame }) {
                    coverCache[key] = "\(baseStr)/api/v1/mangas/\(libMatch.id)/cover"
                } else if let planMatch = plannedMangas.first(where: { $0.title.localizedCaseInsensitiveCompare(req.title) == .orderedSame }),
                          let cov = planMatch.coverUrl {
                    coverCache[key] = cov
                }
            }
        }
        
        // Resolver portadas restantes en segundo plano vía AniList para que todas las tarjetas tengan portada 2:3
        let reqTitles = requests.map(\.title)
        let plannedTitles = plannedMangas.filter { $0.coverUrl == nil }.map(\.title)
        let missingTitles = Array(Set(reqTitles + plannedTitles))
            .filter { coverCache[$0.lowercased()] == nil }
        
        for title in missingTitles.prefix(20) {
            let key = title.lowercased()
            if let cover = await apiClient.fetchAniListCover(title: title) {
                coverCache[key] = cover
            }
        }
    }
    
    public func checkAvailability(
        for req: MangaRequestItem,
        apiClient: KaizenAPIClient,
        session: UserSession?,
        isEn: Bool
    ) async {
        guard let session else { return }
        let defaultThreshold = req.startChapter > 1 ? req.startChapter : 50
        var state = availabilityByRequestId[req.id] ?? RequestAvailabilityState(targetMinChapters: defaultThreshold)
        state.isChecking = true
        state.error = nil
        availabilityByRequestId[req.id] = state
        
        do {
            let found = try await apiClient.searchMangaRemote(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                keyword: req.title,
                source: "all"
            )
            // Ordenar priorizando las fuentes con más capítulos disponibles
            let sorted = found.sorted { $0.chapters > $1.chapters }
            state.isChecking = false
            state.hasChecked = true
            state.results = sorted
            state.selectedSourceId = sorted.first?.id
            availabilityByRequestId[req.id] = state
            
            // Si alguna fuente trae portada y no teníamos una, guardarla
            if let firstCover = sorted.compactMap(\.cover).first(where: { $0.hasPrefix("http") }) {
                coverCache[req.title.lowercased()] = firstCover
            }
        } catch {
            state.isChecking = false
            state.hasChecked = true
            state.error = isEn ? "Error checking sources: \(error.localizedDescription)" : "Error al consultar fuentes: \(error.localizedDescription)"
            availabilityByRequestId[req.id] = state
        }
    }
    
    public func approveAndAddRequest(
        _ req: MangaRequestItem,
        apiClient: KaizenAPIClient,
        appState: AppState,
        isEn: Bool
    ) async {
        guard let session = appState.session else { return }
        processingRequestIds.insert(req.id)
        errorMessage = nil
        defer { processingRequestIds.remove(req.id) }
        
        let availState = availabilityByRequestId[req.id]
        let chosenResult = availState?.selectedResult
        let minChapters = availState?.targetMinChapters ?? (req.startChapter > 1 ? req.startChapter : 50)
        let finalTitle = chosenResult?.title ?? req.title
        
        do {
            // Si hay una fuente seleccionada de la comprobación de disponibilidad, dar de alta en el motor de Kaizen
            if let chosenResult {
                do {
                    try await apiClient.addMangaRemote(
                        serverUrl: session.serverUrl,
                        token: session.apiToken,
                        source: chosenResult.source,
                        title: chosenResult.title,
                        interval: "0 */6 * * *",
                        minChapters: minChapters
                    )
                } catch let nsErr as NSError where nsErr.code == 409 {
                    // Ya existe en la biblioteca de Kaizen; continuamos marcándola como aprobada
                }
            }
            
            try await apiClient.updateRequestStatus(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                requestId: req.id,
                status: "APPROVED",
                title: finalTitle
            )
            
            successMessage = isEn
                ? "Approved '\(finalTitle)' (Threshold: \(minChapters) ch.)"
                : "Aprobada '\(finalTitle)' (Umbral: \(minChapters) caps.)"
            
            await loadAll(apiClient: apiClient, session: session, existingMangas: appState.mangas)
            await appState.loadLibrary(client: apiClient, force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func submitRequest(apiClient: KaizenAPIClient, appState: AppState, isEn: Bool) async {
        let cleanTitle = titleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session = appState.session, !cleanTitle.isEmpty else {
            errorMessage = isEn ? "Please enter manga title" : "Introduce el título del manga"
            return
        }
        
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        
        do {
            try await apiClient.createRequest(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                title: cleanTitle,
                startChapter: startChapterInput
            )
            titleInput = ""
            startChapterInput = 50
            successMessage = isEn ? "Request registered successfully!" : "¡Petición registrada correctamente!"
            await loadAll(apiClient: apiClient, session: session, existingMangas: appState.mangas)
        } catch {
            errorMessage = isEn ? "Error registering request: \(error.localizedDescription)" : "Error al registrar la petición: \(error.localizedDescription)"
        }
    }
    
    public func updateStatus(apiClient: KaizenAPIClient, appState: AppState, requestId: Int, status: String) async {
        guard let session = appState.session else { return }
        processingRequestIds.insert(requestId)
        defer { processingRequestIds.remove(requestId) }
        do {
            try await apiClient.updateRequestStatus(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                requestId: requestId,
                status: status
            )
            await loadAll(apiClient: apiClient, session: session, existingMangas: appState.mangas)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func forceDownloadPlannedManga(_ item: KaizenPlannedManga, apiClient: KaizenAPIClient, appState: AppState, isEn: Bool) async {
        guard let session = appState.session else { return }
        processingRequestIds.insert(item.id)
        defer { processingRequestIds.remove(item.id) }
        do {
            try await apiClient.updateMangaMinChapters(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: item.id,
                minChapters: 0
            )
            try? await apiClient.syncManga(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: item.id
            )
            successMessage = isEn
                ? "Started downloading '\(item.title)' immediately!"
                : "¡Descarga inmediata iniciada para '\(item.title)'!"
            await loadAll(apiClient: apiClient, session: session, existingMangas: appState.mangas)
            await appState.loadLibrary(client: apiClient, force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum RequestFilter: String, CaseIterable, Identifiable {
    case pending
    case waitingChapters
    case approved
    case rejected
    var id: String { rawValue }
}

public struct MangaRequestsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppState.self) private var appState
    @State private var store = MangaRequestsStore()
    @State private var filter: RequestFilter = .pending
    @State private var showNewRequest = false
    @State private var inspectingRequest: MangaRequestItem? = nil
    let apiClient: KaizenAPIClient
    public var isEmbedded: Bool = false
    
    public init(apiClient: KaizenAPIClient, isEmbedded: Bool = false) {
        self.apiClient = apiClient
        self.isEmbedded = isEmbedded
    }
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    private var isPad: Bool { horizontalSizeClass == .regular }
    
    private var posterGridColumns: [GridItem] {
        if isPad {
            return [GridItem(.adaptive(minimum: 135, maximum: 185), spacing: 16, alignment: .top)]
        } else {
            return [GridItem(.adaptive(minimum: 98, maximum: 130), spacing: 10, alignment: .top)]
        }
    }
    
    private func bucket(_ status: String) -> RequestFilter {
        switch status.uppercased() {
        case "PENDING": return .pending
        case "APPROVED", "DOWNLOADING", "AVAILABLE": return .approved
        default: return .rejected
        }
    }
    
    private var pendingCount: Int {
        store.requests.filter { bucket($0.status) == .pending }.count
    }
    
    private var approvedCount: Int {
        store.requests.filter { bucket($0.status) == .approved }.count
    }
    
    private var rejectedCount: Int {
        store.requests.filter { bucket($0.status) == .rejected }.count
    }
    
    private var visibleRequests: [MangaRequestItem] {
        store.requests.filter { bucket($0.status) == filter }
    }
    
    private func title(for f: RequestFilter) -> String {
        switch f {
        case .pending:
            return (isEn ? "Pending" : "Pendientes") + " (\(pendingCount))"
        case .waitingChapters:
            return (isEn ? "Waiting 50 ch." : "En espera (50 caps.)") + " (\(store.plannedMangas.count))"
        case .approved:
            return (isEn ? "Approved" : "Aprobadas") + " (\(approvedCount))"
        case .rejected:
            return (isEn ? "Rejected" : "Rechazadas") + " (\(rejectedCount))"
        }
    }
    
    public var body: some View {
        if isEmbedded {
            requestsMainContent
                .refreshable {
                    await store.loadAll(apiClient: apiClient, session: appState.session, existingMangas: appState.mangas)
                }
                .task {
                    await store.loadAll(apiClient: apiClient, session: appState.session, existingMangas: appState.mangas)
                }
                .sheet(isPresented: $showNewRequest) {
                    newRequestSheet
                }
                .sheet(item: $inspectingRequest) { req in
                    requestAvailabilitySheet(for: req)
                }
        } else {
            NavigationStack {
                requestsMainContent
                    .navigationTitle(isEn ? "Requests" : "Peticiones")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showNewRequest = true } label: { Image(systemName: "plus") }
                                .accessibilityLabel(isEn ? "New request" : "Nueva petición")
                        }
                    }
                    .refreshable {
                        await store.loadAll(apiClient: apiClient, session: appState.session, existingMangas: appState.mangas)
                    }
                    .task {
                        await store.loadAll(apiClient: apiClient, session: appState.session, existingMangas: appState.mangas)
                    }
                    .sheet(isPresented: $showNewRequest) {
                        newRequestSheet
                    }
                    .sheet(item: $inspectingRequest) { req in
                        requestAvailabilitySheet(for: req)
                    }
            }
        }
    }
    
    // MARK: - Contenido Principal Cyberpunk Glass (Cuadrícula Póster 2:3 igual que Library)
    
    private var requestsMainContent: some View {
        ZStack {
            if !isEmbedded {
                Color.clear.ambientGlowBackground()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    unifiedTopBar
                    
                    if let error = store.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button {
                                store.errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(.red)
                        .padding(12)
                        .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.red.opacity(0.35), lineWidth: 1))
                    }
                    
                    if let success = store.successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                            Text(success)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button {
                                store.successMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(.cyan)
                        .padding(12)
                        .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                    }
                    
                    if store.isLoading && store.requests.isEmpty && store.plannedMangas.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.cyan)
                                .padding(.vertical, 48)
                            Spacer()
                        }
                    } else if filter == .waitingChapters {
                        plannedMangasGridSection
                    } else if visibleRequests.isEmpty {
                        emptyRequestsState
                    } else {
                        requestsGridSection
                    }
                }
                .padding(.horizontal, isPad ? 18 : 12)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
        }
    }
    
    // MARK: - Barra Superior Unificada (Título + Píldoras de Filtro + Botón Compacto)
    
    private var unifiedTopBar: some View {
        Group {
            if isPad {
                HStack(alignment: .center, spacing: 12) {
                    Text(isEn ? "Requests & Backlog" : "Peticiones")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    filterPillBar
                    
                    Spacer(minLength: 8)
                    
                    requestNewButton
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        Text(isEn ? "Requests & Backlog" : "Peticiones")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        requestNewButton
                    }
                    filterPillBar
                }
            }
        }
    }
    
    private var requestNewButton: some View {
        Button {
            showNewRequest = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption.weight(.black))
                Text(isEn ? "Request (50 ch.)" : "Solicitar (50 caps.)")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.35, green: 0.98, blue: 1.0), Color.cyan],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Capsule()
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.65), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private var filterPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RequestFilter.allCases) { f in
                    let isSelected = filter == f
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            filter = f
                        }
                    } label: {
                        Text(title(for: f))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.88))
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.cyan)
                                } else {
                                    Capsule()
                                        .fill(Color.white.opacity(0.07))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - Grid de Tarjetas Póster 2:3 de Peticiones (Misma estructura que Library)
    
    private var requestsGridSection: some View {
        LazyVGrid(columns: posterGridColumns, spacing: isPad ? 18 : 12) {
            ForEach(visibleRequests) { req in
                requestPosterCard(req)
            }
        }
    }
    
    private func resolveCoverURL(for title: String) -> URL? {
        if let cached = store.coverCache[title.lowercased()], let url = URL(string: cached) {
            return url
        }
        if let matched = appState.mangas.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }),
           let session = appState.session {
            let baseStr = session.serverUrl.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return URL(string: "\(baseStr)/api/v1/mangas/\(matched.id)/cover")
        }
        return nil
    }
    
    private func formattedDate(_ isoString: String?) -> String {
        guard let isoString else { return isEn ? "Recently" : "Reciente" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString)
        guard let date else { return isEn ? "Recently" : "Reciente" }
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: isEn ? "en_US" : "es_ES")
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
    
    private func requestPosterCard(_ req: MangaRequestItem) -> some View {
        let coverURL = resolveCoverURL(for: req.title)
        let avail = store.availabilityByRequestId[req.id]
        let isProcessing = store.processingRequestIds.contains(req.id)
        let targetChapters = avail?.targetMinChapters ?? (req.startChapter > 1 ? req.startChapter : 50)
        let chosenSource = avail?.selectedResult
        let sourceLabel = chosenSource?.source ?? "@\(req.username ?? (isEn ? "reader" : "lector"))"
        let availableChapters = chosenSource?.chapters ?? 0
        let progressRatio: Double = {
            guard targetChapters > 0 else { return 1.0 }
            if availableChapters > 0 {
                return min(Double(availableChapters) / Double(targetChapters), 1.0)
            }
            return bucket(req.status) == .approved ? 1.0 : 0.08
        }()
        let topBadgeText: String = {
            if let chosenSource, chosenSource.chapters > 0 {
                return "\(chosenSource.chapters)/\(targetChapters)"
            }
            switch bucket(req.status) {
            case .pending: return isEn ? "Pending" : "Pendiente"
            case .waitingChapters: return "0/\(targetChapters)"
            case .approved: return isEn ? "Approved" : "Aprobada"
            case .rejected: return isEn ? "Rejected" : "Rechazada"
            }
        }()
        let subtitleText: String = {
            if let chosenSource, chosenSource.chapters > 0 {
                let pct = min(Int((Double(chosenSource.chapters) / Double(max(targetChapters, 1)) * 100).rounded()), 100)
                return "@\(req.username ?? "admin") · \(pct)% (\(chosenSource.chapters)/\(targetChapters) ch.)"
            }
            return "@\(req.username ?? "admin") · " + (isEn ? "Wait \(targetChapters) ch." : "Espera \(targetChapters) caps.")
        }()
        
        return VStack(alignment: .leading, spacing: isPad ? 7 : 5) {
            // Portada 2:3 protagonista con píldoras superiores y barra de progreso neón inferior
            posterCoverView(
                url: coverURL,
                title: req.title,
                topLeftText: sourceLabel,
                topRightText: topBadgeText,
                topRightColor: bucket(req.status) == .rejected ? .red : .cyan,
                progressRatio: progressRatio
            )
            .onTapGesture {
                if appState.isManagement && bucket(req.status) == .pending {
                    inspectingRequest = req
                    if store.availabilityByRequestId[req.id] == nil {
                        Task {
                            await store.checkAvailability(for: req, apiClient: apiClient, session: appState.session, isEn: isEn)
                        }
                    }
                }
            }
            
            // Título 1 línea
            Text(req.title)
                .font(isPad ? .footnote.weight(.bold) : .caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 2)
            
            // Subtítulo compacto 1 línea
            Text(subtitleText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .padding(.horizontal, 2)
            
            // Fila de acciones compacta (28pt de alto)
            if appState.isManagement {
                if bucket(req.status) == .pending {
                    HStack(spacing: 6) {
                        if let chosen = chosenSource {
                            // Si ya comprobó disponibilidad y encontró fuente -> Botón directo "Aceptar"
                            Button {
                                Task {
                                    await store.approveAndAddRequest(req, apiClient: apiClient, appState: appState, isEn: isEn)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if isProcessing {
                                        ProgressView().tint(.cyan).scaleEffect(0.65)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2.weight(.bold))
                                    }
                                    Text(isEn ? "Add (\(chosen.source))" : "Añadir (\(chosen.source))")
                                        .font(.caption2.weight(.bold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.cyan)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(Color.cyan.opacity(0.16), in: Capsule())
                                .overlay(Capsule().stroke(Color.cyan.opacity(0.55), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(isProcessing)
                        } else {
                            // Botón compacto "📡 Check" que abre el selector de fuentes y comprueba disponibilidad
                            Button {
                                inspectingRequest = req
                                Task {
                                    await store.checkAvailability(for: req, apiClient: apiClient, session: appState.session, isEn: isEn)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if avail?.isChecking == true {
                                        ProgressView().tint(.cyan).scaleEffect(0.65)
                                    } else {
                                        Image(systemName: "dot.radiowaves.left.and.right")
                                            .font(.caption2.weight(.bold))
                                    }
                                    Text(isEn ? "Check" : "Fuentes")
                                        .font(.caption2.weight(.bold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.cyan)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(Color.cyan.opacity(0.15), in: Capsule())
                                .overlay(Capsule().stroke(Color.cyan.opacity(0.48), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(isProcessing)
                        }
                        
                        // Botón circular compacto "✕" para rechazar
                        Button {
                            Task {
                                await store.updateStatus(apiClient: apiClient, appState: appState, requestId: req.id, status: "CANCELLED")
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08), in: Circle())
                                .overlay(Circle().stroke(Color.cyan.opacity(0.38), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing)
                    }
                    .padding(.top, 2)
                } else if bucket(req.status) == .rejected {
                    Button {
                        Task {
                            await store.updateStatus(apiClient: apiClient, appState: appState, requestId: req.id, status: "PENDING")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                            Text(isEn ? "Restore" : "Restaurar")
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Color.cyan.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.42), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                } else if let matched = appState.mangas.first(where: { $0.title.localizedCaseInsensitiveCompare(req.title) == .orderedSame }) {
                    NavigationLink(value: matched) {
                        HStack(spacing: 4) {
                            Image(systemName: "book.fill")
                            Text(isEn ? "Open" : "Abrir")
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Color.cyan.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.42), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                        Text(isEn ? "Approved" : "Aprobada")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Color.green.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(Color.green.opacity(0.38), lineWidth: 1))
                    .padding(.top, 2)
                }
            }
        }
        .padding(isPad ? 8 : 6)
        .frame(maxHeight: .infinity, alignment: .top)
        .kaizenCardGlass(in: RoundedRectangle(cornerRadius: isPad ? 18 : 14, style: .continuous))
    }
    
    // MARK: - Hoja Inspector de Disponibilidad en Fuentes (al pulsar "📡 Check" en una tarjeta)
    
    private func requestAvailabilitySheet(for req: MangaRequestItem) -> some View {
        let avail = store.availabilityByRequestId[req.id] ?? RequestAvailabilityState(targetMinChapters: req.startChapter > 1 ? req.startChapter : 50)
        let targetChapters = avail.targetMinChapters
        let isProcessing = store.processingRequestIds.contains(req.id)
        let coverURL = resolveCoverURL(for: req.title)
        
        return NavigationStack {
            ZStack {
                Color.clear.ambientGlowBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            posterCoverView(
                                url: coverURL,
                                title: req.title,
                                topLeftText: "@\(req.username ?? "admin")",
                                topRightText: "\(targetChapters) ch.",
                                topRightColor: .cyan,
                                progressRatio: 0.4
                            )
                            .frame(width: 96)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(req.title)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                
                                Text(
                                    isEn
                                        ? "Select an available scraper source and chapter threshold before approving."
                                        : "Selecciona una fuente disponible y el umbral de capítulos antes de aprobar."
                                )
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        
                        availabilityDetailsPanel(for: req, avail: avail, targetChapters: targetChapters)
                        
                        HStack(spacing: 10) {
                            if let chosen = avail.selectedResult {
                                Button {
                                    Task {
                                        await store.approveAndAddRequest(req, apiClient: apiClient, appState: appState, isEn: isEn)
                                        inspectingRequest = nil
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        if isProcessing {
                                            ProgressView().tint(.black).scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                        }
                                        Text(
                                            isEn
                                                ? "Approve on \(chosen.source) (\(targetChapters) ch.)"
                                                : "Aprobar en \(chosen.source) (\(targetChapters) caps.)"
                                        )
                                    }
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                }
                                .kaizenGlassButton(prominent: true)
                                .disabled(isProcessing)
                            }
                            
                            Button {
                                Task {
                                    await store.updateStatus(apiClient: apiClient, appState: appState, requestId: req.id, status: "CANCELLED")
                                    inspectingRequest = nil
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "xmark")
                                    Text(isEn ? "Reject" : "Rechazar")
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            .kaizenGlassButton(prominent: false)
                            .disabled(isProcessing)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isEn ? "Check Availability" : "Comprobar Disponibilidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Close" : "Cerrar") { inspectingRequest = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Panel de Disponibilidad en Fuentes y Umbral de 50 Capítulos
    
    @ViewBuilder
    private func availabilityDetailsPanel(
        for req: MangaRequestItem,
        avail: RequestAvailabilityState,
        targetChapters: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if avail.isChecking {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.cyan)
                    Text(
                        isEn
                            ? "Searching '\(req.title)' across all active scrapers..."
                            : "Comprobando disponibilidad de '\(req.title)' en todas las fuentes..."
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let err = avail.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if avail.results.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isEn ? "No sources found for this title" : "No se encontró en ninguna fuente activa")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                        Text(
                            isEn
                                ? "You can reject this request or keep it pending until a source adds it."
                                : "Puedes rechazar la petición o dejarla pendiente para más adelante."
                        )
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.orange.opacity(0.35), lineWidth: 1))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(
                            isEn ? "Select source (\(avail.results.count) available):" : "Elige fuente disponible (\(avail.results.count)):",
                            systemImage: "checkmark.shield.fill"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        
                        Spacer()
                        
                        Button {
                            Task {
                                await store.checkAvailability(for: req, apiClient: apiClient, session: appState.session, isEn: isEn)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(isEn ? "Rescan" : "Reescanear")
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Píldoras horizontales de fuentes encontradas
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(avail.results.prefix(8)) { res in
                                let isChosen = (avail.selectedResult?.id == res.id)
                                Button {
                                    store.availabilityByRequestId[req.id]?.selectedSourceId = res.id
                                    if let cov = res.cover, cov.hasPrefix("http") {
                                        store.coverCache[req.title.lowercased()] = cov
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 5) {
                                            Image(systemName: isChosen ? "checkmark.circle.fill" : "globe")
                                                .font(.caption2.weight(.bold))
                                            Text(res.source)
                                                .font(.caption.weight(.bold))
                                        }
                                        Text(
                                            res.chapters > 0
                                                ? "\(res.chapters) " + (isEn ? "chapters" : "capítulos")
                                                : res.title
                                        )
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .opacity(0.85)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(isChosen ? Color.black : Color.white)
                                    .background {
                                        if isChosen {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.cyan)
                                                .shadow(color: .cyan.opacity(0.45), radius: 6)
                                        } else {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.white.opacity(0.07))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                                )
                                        }
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Selector rápido del umbral de capítulos (ej. 50 capítulos)
                    HStack(spacing: 8) {
                        Text(isEn ? "Min. chapters:" : "Mín. capítulos:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        
                        ForEach([0, 25, 50, 100], id: \.self) { preset in
                            let isActivePreset = targetChapters == preset
                            Button {
                                store.availabilityByRequestId[req.id]?.targetMinChapters = preset
                            } label: {
                                Text(preset == 0 ? (isEn ? "Now (0)" : "Ya (0)") : "\(preset) caps.")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .foregroundStyle(isActivePreset ? Color.black : Color.white.opacity(0.85))
                                    .background(
                                        isActivePreset ? Color.cyan : Color.white.opacity(0.08),
                                        in: Capsule()
                                    )
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.cyan.opacity(0.28), lineWidth: 1))
            }
        }
    }
    
    // MARK: - Botones de Acción de Petición Pendiente
    
    @ViewBuilder
    private func pendingActionButtons(
        for req: MangaRequestItem,
        avail: RequestAvailabilityState?,
        isProcessing: Bool,
        targetChapters: Int
    ) -> some View {
        let hasChecked = avail?.hasChecked == true
        let hasAvailableSources = !(avail?.results.isEmpty ?? true)
        
        VStack(spacing: 8) {
            if !hasChecked {
                // Paso 1 recomendado: Ver disponibilidad o Rechazar (con opción de aprobar directo en menú secundario)
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await store.checkAvailability(
                                for: req,
                                apiClient: apiClient,
                                session: appState.session,
                                isEn: isEn
                            )
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if avail?.isChecking == true {
                                ProgressView().tint(.black).scaleEffect(0.8)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(isEn ? "Check Availability" : "Ver disponibilidad")
                        }
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Capsule())
                    }
                    .kaizenGlassButton(prominent: true)
                    .disabled(avail?.isChecking == true || isProcessing)
                    
                    Button {
                        Task {
                            await store.updateStatus(
                                apiClient: apiClient,
                                appState: appState,
                                requestId: req.id,
                                status: "CANCELLED"
                            )
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                            Text(isEn ? "Reject" : "Rechazar")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Capsule())
                    }
                    .kaizenGlassButton(prominent: false)
                    .disabled(isProcessing)
                }
            } else if hasAvailableSources, let chosen = avail?.selectedResult {
                // Paso 2: Disponible en fuente -> Aprobar en la fuente elegida con el umbral de 50 caps. o Rechazar
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await store.approveAndAddRequest(
                                req,
                                apiClient: apiClient,
                                appState: appState,
                                isEn: isEn
                            )
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isProcessing {
                                ProgressView().tint(.black).scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(
                                isEn
                                    ? "Accept on \(chosen.source) (\(targetChapters) ch.)"
                                    : "Aceptar en \(chosen.source) (\(targetChapters) caps.)"
                            )
                            .lineLimit(1)
                        }
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Capsule())
                    }
                    .kaizenGlassButton(prominent: true)
                    .disabled(isProcessing)
                    
                    Button {
                        Task {
                            await store.updateStatus(
                                apiClient: apiClient,
                                appState: appState,
                                requestId: req.id,
                                status: "CANCELLED"
                            )
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                            Text(isEn ? "Reject" : "Rechazar")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Capsule())
                    }
                    .kaizenGlassButton(prominent: false)
                    .disabled(isProcessing)
                }
            } else {
                // Paso 2 alternativo: No disponible en ninguna fuente -> Rechazar o Reintentar
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await store.updateStatus(
                                apiClient: apiClient,
                                appState: appState,
                                requestId: req.id,
                                status: "CANCELLED"
                            )
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text(isEn ? "Reject (Unavailable)" : "Rechazar (Sin fuente)")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Capsule())
                    }
                    .kaizenGlassButton(prominent: false)
                    .disabled(isProcessing)
                    
                    Button {
                        Task {
                            await store.checkAvailability(
                                for: req,
                                apiClient: apiClient,
                                session: appState.session,
                                isEn: isEn
                            )
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                            Text(isEn ? "Retry" : "Reintentar")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Capsule())
                    }
                    .kaizenGlassButton(prominent: false)
                    .disabled(isProcessing)
                }
            }
        }
    }
    
    // MARK: - Sección Backlog: Series en espera de alcanzar 50 capítulos (`minChaptersForDownload > 0`)
    
    private var plannedMangasGridSection: some View {
        Group {
            if store.plannedMangas.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "hourglass.badge.plus")
                        .font(.system(size: 44))
                        .foregroundStyle(.cyan.opacity(0.8))
                    Text(isEn ? "No series waiting for chapter threshold" : "Ninguna serie esperando umbral de capítulos")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(
                        isEn
                            ? "Series approved with a 50-chapter minimum will appear here until they reach 50 chapters on their source."
                            : "Las series aceptadas con umbral (ej. hasta tener 50 capítulos) aparecerán aquí con su progreso hasta alcanzar los 50 capítulos."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 44)
                .frame(maxWidth: .infinity)
                .kaizenGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                LazyVGrid(columns: posterGridColumns, spacing: isPad ? 18 : 12) {
                    ForEach(store.plannedMangas) { item in
                        plannedMangaPosterCard(item)
                    }
                }
            }
        }
    }
    
    private func plannedMangaPosterCard(_ item: KaizenPlannedManga) -> some View {
        let coverURL = item.coverUrl.flatMap { URL(string: $0) } ?? resolveCoverURL(for: item.title)
        let isProcessing = store.processingRequestIds.contains(item.id)
        let pct = Int((item.progressRatio * 100).rounded())
        let subtitle = "@admin · \(pct)% (\(item.remoteChaptersCount)/\(item.minChaptersForDownload) " + (isEn ? "ch." : "caps.") + ")"
        
        return VStack(alignment: .leading, spacing: isPad ? 7 : 5) {
            posterCoverView(
                url: coverURL,
                title: item.title,
                topLeftText: item.source,
                topRightText: "\(item.remoteChaptersCount)/\(item.minChaptersForDownload)",
                topRightColor: .cyan,
                progressRatio: item.progressRatio
            )
            
            Text(item.title)
                .font(isPad ? .footnote.weight(.bold) : .caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 2)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .padding(.horizontal, 2)
            
            if appState.isManagement {
                Button {
                    Task {
                        await store.forceDownloadPlannedManga(
                            item,
                            apiClient: apiClient,
                            appState: appState,
                            isEn: isEn
                        )
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isProcessing {
                            ProgressView().tint(.cyan).scaleEffect(0.65)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.caption2.weight(.bold))
                        }
                        Text(isEn ? "Force Download" : "Descargar ya")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Color.cyan.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.50), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                .padding(.top, 2)
            }
        }
        .padding(isPad ? 8 : 6)
        .frame(maxHeight: .infinity, alignment: .top)
        .kaizenCardGlass(in: RoundedRectangle(cornerRadius: isPad ? 18 : 14, style: .continuous))
    }
    
    // MARK: - Portada Vertical 2:3 con Badges Superiores y Barra Neón Inferior
    
    private func posterCoverView(
        url: URL?,
        title: String,
        topLeftText: String,
        topRightText: String,
        topRightColor: Color,
        progressRatio: Double
    ) -> some View {
        let radius: CGFloat = isPad ? 12 : 10
        let clampedRatio = CGFloat(min(max(progressRatio, 0.04), 1.0))
        
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.14, green: 0.22, blue: 0.36), Color(red: 0.07, green: 0.10, blue: 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(2/3, contentMode: .fit)
            .overlay {
                if let url {
                    RemoteImage(
                        url: url,
                        token: appState.session?.apiToken,
                        contentMode: .fill
                    )
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan.opacity(0.8))
                        Text(String(title.prefix(2)).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                HStack(spacing: 4) {
                    Text(topLeftText)
                        .font(.system(size: isPad ? 10 : 9, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, isPad ? 7 : 5)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.74), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
                    
                    Spacer(minLength: 2)
                    
                    Text(topRightText)
                        .font(.system(size: isPad ? 10 : 9, weight: .heavy).monospacedDigit())
                        .foregroundStyle(topRightColor == .cyan ? Color.cyan : Color.white)
                        .lineLimit(1)
                        .padding(.horizontal, isPad ? 7 : 5)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.76), in: Capsule())
                        .overlay(Capsule().stroke(topRightColor.opacity(0.75), lineWidth: 1))
                }
                .padding(isPad ? 6 : 4)
            }
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.68))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.35, green: 0.98, blue: 1.0), Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * clampedRatio)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
    }
    
    private var emptyRequestsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 44))
                .foregroundStyle(.cyan.opacity(0.8))
            Text(isEn ? "No requests in this category" : "No hay peticiones en esta sección")
                .font(.headline)
                .foregroundStyle(.white)
            Text(
                isEn
                    ? "Tap 'Request Manga (50 ch.)' above to add a new series to the request queue."
                    : "Pulsa 'Solicitar Manga (50 caps.)' arriba para registrar una nueva petición."
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    // MARK: - Hoja de Nueva Petición (por defecto 50 capítulos)
    
    private var newRequestSheet: some View {
        NavigationStack {
            ZStack {
                Color.clear.ambientGlowBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isEn ? "Manga Title" : "Título del Manga")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                            
                            TextField(
                                isEn ? "e.g. Vagabond, Solo Leveling..." : "Ej: Vagabond, Solo Leveling...",
                                text: $store.titleInput
                            )
                            .padding(12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
                            .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text(isEn ? "Minimum Chapters Threshold" : "Umbral de capítulos para descargar")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                            
                            Text(
                                isEn
                                    ? "Hold download in backlog until the series has at least this many chapters available (default: 50 chapters)."
                                    : "Espera a que el manga tenga este número de capítulos publicados antes de descargarlo (por defecto: 50 capítulos)."
                            )
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                            
                            HStack(spacing: 8) {
                                ForEach([1, 25, 50, 100], id: \.self) { preset in
                                    let isSelected = store.startChapterInput == preset
                                    Button {
                                        store.startChapterInput = preset
                                    } label: {
                                        Text(preset == 1 ? (isEn ? "1 (Now)" : "1 (Ya)") : "\(preset) caps.")
                                            .font(.caption.weight(.bold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 9)
                                            .foregroundStyle(isSelected ? Color.black : Color.white)
                                            .background(isSelected ? Color.cyan : Color.white.opacity(0.08), in: Capsule())
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Stepper(
                                (isEn ? "Wait until: " : "Esperar hasta tener: ") + "\(store.startChapterInput) " + (isEn ? "chapters" : "capítulos"),
                                value: $store.startChapterInput,
                                in: 1...2000
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .padding(12)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        
                        Button {
                            Task {
                                await store.submitRequest(apiClient: apiClient, appState: appState, isEn: isEn)
                                if store.errorMessage == nil {
                                    showNewRequest = false
                                }
                            }
                        } label: {
                            HStack {
                                if store.isSubmitting {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                    Text(isEn ? "Submit Request" : "Enviar Petición")
                                }
                            }
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Capsule())
                        }
                        .kaizenGlassButton(prominent: true)
                        .disabled(store.isSubmitting || store.titleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(20)
                    .kaizenGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(16)
                }
            }
            .navigationTitle(isEn ? "New Request" : "Nueva Petición")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Cancel" : "Cancelar") { showNewRequest = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Insignia de Estado
    
    @ViewBuilder
    private func statusBadge(for status: String) -> some View {
        let (text, color): (String, Color) = {
            switch status.uppercased() {
            case "PENDING": return (isEn ? "Pending" : "Pendiente", .cyan)
            case "APPROVED": return (isEn ? "Approved" : "Aprobada", .green)
            case "DOWNLOADING": return (isEn ? "Downloading" : "Descargando", .cyan)
            case "AVAILABLE": return (isEn ? "Available" : "Disponible", .green)
            default: return (isEn ? "Rejected" : "Rechazada", .red)
            }
        }()
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
            .foregroundStyle(color)
    }
}
