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
        let missingTitles = requests
            .map(\.title)
            .filter { coverCache[$0.lowercased()] == nil }
        
        for title in missingTitles.prefix(15) {
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
    let apiClient: KaizenAPIClient
    public var isEmbedded: Bool = false
    
    public init(apiClient: KaizenAPIClient, isEmbedded: Bool = false) {
        self.apiClient = apiClient
        self.isEmbedded = isEmbedded
    }
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    private var isPad: Bool { horizontalSizeClass == .regular }
    
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
            }
        }
    }
    
    // MARK: - Contenido Principal Cyberpunk Glass
    
    private var requestsMainContent: some View {
        ZStack {
            if !isEmbedded {
                Color.clear.ambientGlowBackground()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    filterPillBar
                    
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
                .padding(.horizontal, isPad ? 22 : 16)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
        }
    }
    
    // MARK: - Cabecera + Filtros
    
    private var headerSection: some View {
        Group {
            if isPad {
                HStack(alignment: .center, spacing: 14) {
                    headerTitleBlock
                    Spacer(minLength: 12)
                    requestNewButton
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    headerTitleBlock
                    requestNewButton
                }
            }
        }
    }
    
    private var headerTitleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(isEn ? "Requests & Backlog" : "Peticiones")
                    .font(.system(size: isPad ? 28 : 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(isEn ? "\(pendingCount) pending" : "\(pendingCount) pendientes")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.cyan, in: Capsule())
                    .shadow(color: .cyan.opacity(0.55), radius: 8)
            }
            
            Text(
                isEn
                    ? "Check source availability, set chapter threshold (e.g. 50 chapters) and approve or reject."
                    : "Comprueba disponibilidad en fuentes, fija el umbral (ej. hasta tener 50 capítulos) y aprueba o rechaza."
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.68))
        }
    }
    
    private var requestNewButton: some View {
        Button {
            showNewRequest = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle.fill")
                Text(isEn ? "Request Manga (50 ch.)" : "Solicitar Manga (50 caps.)")
            }
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Capsule())
        }
        .kaizenGlassButton(prominent: true)
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.88))
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.cyan)
                                        .shadow(color: .cyan.opacity(0.5), radius: 8)
                                } else {
                                    Capsule()
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
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
    
    // MARK: - Grid de Tarjetas de Peticiones
    
    private var requestsGridSection: some View {
        let columns = isPad
            ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
            : [GridItem(.flexible(), spacing: 14)]
        
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(visibleRequests) { req in
                requestCard(req)
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
        rel.unitsStyle = .short
        return rel.localizedString(for: date, relativeTo: Date())
    }
    
    private func requestCard(_ req: MangaRequestItem) -> some View {
        let coverURL = resolveCoverURL(for: req.title)
        let avail = store.availabilityByRequestId[req.id]
        let isProcessing = store.processingRequestIds.contains(req.id)
        let targetChapters = avail?.targetMinChapters ?? (req.startChapter > 1 ? req.startChapter : 50)
        
        return VStack(alignment: .leading, spacing: 14) {
            // Bloque superior: Portada 2:3 + Metadatos de la petición
            HStack(alignment: .top, spacing: 14) {
                coverThumbnail(url: coverURL, title: req.title)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(req.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        
                        Spacer(minLength: 4)
                        
                        statusBadge(for: req.status)
                    }
                    
                    // Usuario y fecha
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.cyan)
                        Text("@\(req.username ?? (isEn ? "reader" : "lector"))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("• \(formattedDate(req.createdAt))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    
                    // Píldora del requisito de capítulos (ej. "Hasta tener 50 capítulos")
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered.2.crossed")
                            .font(.caption2.weight(.bold))
                        Text(
                            targetChapters > 1
                                ? (isEn ? "Wait until \(targetChapters) chapters" : "Hasta tener \(targetChapters) capítulos")
                                : (isEn ? "From Chapter 1 (Immediate)" : "Desde capítulo 1 (Inmediato)")
                        )
                        .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.cyan.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.45), lineWidth: 1))
                    
                    // Si ya se comprobó disponibilidad, resumen rápido de estado
                    if let avail, avail.hasChecked {
                        if avail.results.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark.octagon.fill")
                                Text(isEn ? "Not available in active sources" : "No disponible en ninguna fuente activa")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                        } else if let chosen = avail.selectedResult {
                            let meetsThreshold = chosen.chapters >= targetChapters
                            HStack(spacing: 5) {
                                Image(systemName: meetsThreshold ? "checkmark.seal.fill" : "clock.badge.checkmark.fill")
                                Text(
                                    chosen.chapters > 0
                                        ? (isEn
                                            ? "Available on \(chosen.source) (\(chosen.chapters) ch.)"
                                            : "Disponible en \(chosen.source) (\(chosen.chapters) caps.)")
                                        : (isEn
                                            ? "Found on \(avail.results.count) source(s)"
                                            : "Disponible en \(avail.results.count) fuente(s)")
                                )
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(meetsThreshold ? .green : .cyan)
                            .padding(.top, 2)
                        }
                    }
                }
            }
            
            // Panel desplegable de Disponibilidad en Fuentes cuando se pulsa "Ver disponibilidad"
            if let avail, avail.isChecking || avail.hasChecked {
                availabilityDetailsPanel(for: req, avail: avail, targetChapters: targetChapters)
            }
            
            // Botonera de Acción para el Administrador
            if appState.isManagement {
                if bucket(req.status) == .pending {
                    pendingActionButtons(for: req, avail: avail, isProcessing: isProcessing, targetChapters: targetChapters)
                } else if bucket(req.status) == .rejected {
                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await store.updateStatus(apiClient: apiClient, appState: appState, requestId: req.id, status: "PENDING")
                            }
                        } label: {
                            Label(isEn ? "Move back to Pending" : "Devolver a Pendientes", systemImage: "arrow.uturn.backward.circle.fill")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .kaizenGlassButton(prominent: false)
                    }
                } else if let matched = appState.mangas.first(where: { $0.title.localizedCaseInsensitiveCompare(req.title) == .orderedSame }) {
                    NavigationLink(value: matched) {
                        HStack {
                            Image(systemName: "book.fill")
                            Text(isEn ? "Open in Library" : "Abrir en la Biblioteca")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background {
            if let coverURL {
                RemoteImage(
                    url: coverURL,
                    token: appState.session?.apiToken,
                    contentMode: .fill
                )
                .blur(radius: 36)
                .opacity(0.20)
                .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                let columns = isPad
                    ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    : [GridItem(.flexible(), spacing: 14)]
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.plannedMangas) { item in
                        plannedMangaCard(item)
                    }
                }
            }
        }
    }
    
    private func plannedMangaCard(_ item: KaizenPlannedManga) -> some View {
        let coverURL = item.coverUrl.flatMap { URL(string: $0) }
        let isProcessing = store.processingRequestIds.contains(item.id)
        let pct = Int((item.progressRatio * 100).rounded())
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                coverThumbnail(url: coverURL, title: item.title)
                
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        Text(item.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        
                        Spacer(minLength: 4)
                        
                        Text(item.source)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.16), in: Capsule())
                    }
                    
                    Text(
                        isEn
                            ? "Waiting for \(item.minChaptersForDownload) chapters before downloading"
                            : "Esperando hasta tener \(item.minChaptersForDownload) capítulos para descargar"
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    
                    // Barra de progreso hacia los 50 capítulos
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(item.remoteChaptersCount) / \(item.minChaptersForDownload) " + (isEn ? "chapters available" : "capítulos en fuente"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.cyan)
                            Spacer()
                            Text("\(pct)%")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.cyan, Color(red: 0.2, green: 0.6, blue: 1.0)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(geo.size.width * item.progressRatio, 8))
                                    .shadow(color: .cyan.opacity(0.6), radius: 5)
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding(.top, 2)
                }
            }
            
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
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView().tint(.black).scaleEffect(0.8)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(
                            isEn
                                ? "Download Now (Remove \(item.minChaptersForDownload) ch. wait)"
                                : "Descargar ya (No esperar a \(item.minChaptersForDownload) caps.)"
                        )
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Capsule())
                }
                .kaizenGlassButton(prominent: true)
                .disabled(isProcessing)
            }
        }
        .padding(16)
        .background {
            if let coverURL {
                RemoteImage(
                    url: coverURL,
                    token: appState.session?.apiToken,
                    contentMode: .fill
                )
                .blur(radius: 36)
                .opacity(0.18)
                .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    // MARK: - Subvistas Auxiliares
    
    private func coverThumbnail(url: URL?, title: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.14, green: 0.22, blue: 0.36), Color(red: 0.07, green: 0.10, blue: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            if let url {
                RemoteImage(
                    url: url,
                    token: appState.session?.apiToken,
                    contentMode: .fill
                )
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "book.closed.fill")
                        .font(.title3)
                        .foregroundStyle(.cyan.opacity(0.8))
                    Text(String(title.prefix(2)).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(width: 76, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 4)
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
