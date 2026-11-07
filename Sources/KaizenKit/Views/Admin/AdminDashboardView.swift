import SwiftUI

public enum AdminSection: String, CaseIterable, Identifiable {
    case operations = "operations"
    case failures = "failures"
    case sources = "sources"
    case queues = "queues"
    
    public var id: String { rawValue }
    
    public func label(isEn: Bool, failureCount: Int, sourceCount: Int) -> String {
        switch self {
        case .operations:
            return isEn ? "Operations" : "Operaciones"
        case .failures:
            return isEn ? "Failures (\(failureCount))" : "Fallos (\(failureCount))"
        case .sources:
            return isEn ? "Sources (\(sourceCount))" : "Fuentes (\(sourceCount))"
        case .queues:
            return isEn ? "Queues" : "Colas"
        }
    }
}

public enum SourceFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case active = "active"
    case failed = "failed"
    
    public var id: String { rawValue }
    
    public func label(isEn: Bool) -> String {
        switch self {
        case .all: return isEn ? "All" : "Todas"
        case .active: return isEn ? "Active" : "Activas"
        case .failed: return isEn ? "Blocked / Failed" : "Bloqueadas"
        }
    }
}

@MainActor
@Observable
public final class AdminStore {
    public var queuesResponse: QueuesResponse?
    public var downloadQueueJobs: [DownloadQueueJob] = []
    public var sources: [KaizenSourceItem] = []
    public var failedJobs: [FailedDownloadJob] = []
    
    public var selectedSection: AdminSection = .operations
    public var sourceFilter: SourceFilter = .all
    public var sourceSearchText: String = ""
    
    public var isLoading: Bool = false
    public var isLoadingSources: Bool = false
    public var isLoadingFailedJobs: Bool = false
    public var activeAction: String?
    public var isTogglingSource: String?
    public var errorMessage: String?
    public var successMessage: String?
    
    public init() {}
    
    public var totalFailuresCount: Int {
        failedJobs.count + sources.filter { $0.isFailed }.count
    }
    
    public func loadMetrics(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            queuesResponse = try await apiClient.fetchQueueMetrics(serverUrl: session.serverUrl, token: session.apiToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func loadSources(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        isLoadingSources = true
        defer { isLoadingSources = false }
        do {
            sources = try await apiClient.fetchSourcesList(serverUrl: session.serverUrl, token: session.apiToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func loadFailedJobs(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        isLoadingFailedJobs = true
        defer { isLoadingFailedJobs = false }
        do {
            failedJobs = try await apiClient.fetchFailedJobs(serverUrl: session.serverUrl, token: session.apiToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func loadDownloadQueue(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        if let jobs = try? await apiClient.fetchDownloadQueue(serverUrl: session.serverUrl, token: session.apiToken) {
            downloadQueueJobs = jobs
        }
    }
    
    public func refreshAllData(apiClient: KaizenAPIClient, session: UserSession?) async {
        async let m: () = loadMetrics(apiClient: apiClient, session: session)
        async let q: () = loadDownloadQueue(apiClient: apiClient, session: session)
        async let s: () = loadSources(apiClient: apiClient, session: session)
        async let f: () = loadFailedJobs(apiClient: apiClient, session: session)
        _ = await (m, q, s, f)
    }
    
    public func syncSources(apiClient: KaizenAPIClient, session: UserSession?, isEn: Bool) async {
        guard let session else { return }
        activeAction = "syncSources"
        errorMessage = nil
        successMessage = nil
        defer { activeAction = nil }
        
        do {
            try await apiClient.syncScrapers(serverUrl: session.serverUrl, token: session.apiToken)
            successMessage = isEn ? "Sources synchronized successfully from GitHub!" : "¡Fuentes sincronizadas exitosamente desde GitHub!"
            await loadSources(apiClient: apiClient, session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func toggleSource(source: KaizenSourceItem, apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        isTogglingSource = source.name
        errorMessage = nil
        defer { isTogglingSource = nil }
        
        let newActive = !source.isActive
        do {
            try await apiClient.toggleSource(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                name: source.name,
                activate: newActive,
                isFailed: source.isFailed
            )
            await loadSources(apiClient: apiClient, session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func reactivateAllFailedSources(apiClient: KaizenAPIClient, session: UserSession?, isEn: Bool) async {
        guard let session else { return }
        activeAction = "reactivateSources"
        errorMessage = nil
        successMessage = nil
        defer { activeAction = nil }
        
        do {
            try await apiClient.resetAllCircuitBreakers(serverUrl: session.serverUrl, token: session.apiToken)
            for src in sources where src.isFailed {
                try? await apiClient.toggleSource(serverUrl: session.serverUrl, token: session.apiToken, name: src.name, activate: true, isFailed: true)
            }
            successMessage = isEn ? "All blocked and failed sources reactivated!" : "¡Todas las fuentes bloqueadas o fallidas han sido reactivadas!"
            await loadSources(apiClient: apiClient, session: session)
            await loadMetrics(apiClient: apiClient, session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func retryFailedJob(jobId: String, apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        do {
            try await apiClient.retryJob(serverUrl: session.serverUrl, token: session.apiToken, jobId: jobId)
            await loadFailedJobs(apiClient: apiClient, session: session)
            await loadMetrics(apiClient: apiClient, session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func cancelFailedJob(jobId: String, apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        do {
            try await apiClient.cancelJob(serverUrl: session.serverUrl, token: session.apiToken, jobId: jobId)
            await loadFailedJobs(apiClient: apiClient, session: session)
            await loadMetrics(apiClient: apiClient, session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func executeAction(
        name: String,
        apiClient: KaizenAPIClient,
        session: UserSession?,
        successText: String,
        action: @escaping (KaizenAPIClient, UserSession) async throws -> Void
    ) async {
        guard let session else { return }
        activeAction = name
        errorMessage = nil
        successMessage = nil
        defer { activeAction = nil }
        
        do {
            try await action(apiClient, session)
            successMessage = successText
            await loadMetrics(apiClient: apiClient, session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Operaciones del servidor Kaizen (solo administradores): acciones, fallos, fuentes y colas.
public struct AdminDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var store = AdminStore()
    @State private var showAddMangaSheet = false
    @State private var showLiveQueueSheet = false
    let apiClient: KaizenAPIClient
    
    public var isEmbedded: Bool = false
    public var defaultSection: AdminSection? = nil
    
    public init(apiClient: KaizenAPIClient, isEmbedded: Bool = false, defaultSection: AdminSection? = nil) {
        self.apiClient = apiClient
        self.isEmbedded = isEmbedded
        self.defaultSection = defaultSection
    }
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    
    private var blockedSources: [KaizenSourceItem] {
        store.sources.filter { $0.isFailed }
    }
    
    private var filteredSources: [KaizenSourceItem] {
        var list = store.sources
        switch store.sourceFilter {
        case .all: break
        case .active: list = list.filter { $0.isActive }
        case .failed: list = list.filter { $0.isFailed }
        }
        let q = store.sourceSearchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        if !q.isEmpty {
            list = list.filter { $0.name.localizedLowercase.contains(q) }
        }
        return list
    }
    
    public var body: some View {
        if isEmbedded {
            content
                .task {
                    if let defaultSection {
                        store.selectedSection = defaultSection
                    }
                    await store.refreshAllData(apiClient: apiClient, session: appState.session)
                }
        } else {
            NavigationStack {
                Group {
                    if !appState.isManagement {
                        ContentUnavailableView(
                            isEn ? "Access Restricted" : "Acceso Restringido",
                            systemImage: "lock.shield",
                            description: Text(isEn ? "Only available for Kaizen administrators." : "Solo disponible para administradores de Kaizen.")
                        )
                    } else {
                        content
                    }
                }
                .background(Color.black.ignoresSafeArea())
                .navigationTitle(isEn ? "Operations" : "Operaciones")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAddMangaSheet = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel(isEn ? "Add Manga" : "Añadir Manga")
                    }
                }
                .sheet(isPresented: $showAddMangaSheet) {
                    AddMangaRemoteSheet(apiClient: apiClient)
                }
                .sheet(isPresented: $showLiveQueueSheet) {
                    LiveDownloadQueueSheet(apiClient: apiClient)
                }
                .task {
                    if let defaultSection {
                        store.selectedSection = defaultSection
                    }
                    await store.refreshAllData(apiClient: apiClient, session: appState.session)
                }
            }
        }
    }
    
    private var content: some View {
        List {
            if let success = store.successMessage {
                Label(success, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            } else if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }
            
            if !isEmbedded || defaultSection == nil {
                Section {
                    Picker("", selection: $store.selectedSection) {
                        ForEach(AdminSection.allCases) { section in
                            Text(section.label(isEn: isEn, failureCount: store.totalFailuresCount, sourceCount: store.sources.count))
                                .tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            
            switch store.selectedSection {
            case .operations: operationsSections
            case .failures: failuresSections
            case .sources: sourcesSections
            case .queues: queuesSections
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refreshAllData(apiClient: apiClient, session: appState.session)
        }
    }
    
    // MARK: - Fila con icono (estilo Ajustes de iOS)
    
    private func iconTile(_ icon: String, _ color: Color, spinning: Bool = false) -> some View {
        Group {
            if spinning {
                ProgressView().tint(.white)
            } else {
                Image(systemName: icon).font(.body.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 32, height: 32)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    private func actionRow(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        key: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 14) {
                iconTile(icon, color, spinning: store.activeAction == key)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.white)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.activeAction != nil)
    }
    
    private func run(_ key: String, ok: String, okEn: String, _ call: @escaping (KaizenAPIClient, UserSession) async throws -> Void) async {
        await store.executeAction(
            name: key,
            apiClient: apiClient,
            session: appState.session,
            successText: isEn ? okEn : ok,
            action: call
        )
    }
    
    // MARK: - Operaciones
    
    @ViewBuilder
    private var operationsSections: some View {
        Section(isEn ? "Library" : "Biblioteca") {
            actionRow(title: isEn ? "Check new chapters" : "Comprobar capítulos",
                      subtitle: isEn ? "Runs the crawler on every series" : "Lanza el crawler en todas las series",
                      icon: "arrow.triangle.2.circlepath", color: .cyan, key: "syncAll") {
                await run("syncAll", ok: "¡Comprobación lanzada en todas las series!", okEn: "Chapter check launched on all series!") { c, s in
                    try await c.syncAllMangas(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
            actionRow(title: isEn ? "Refresh metadata" : "Actualizar metadatos",
                      subtitle: isEn ? "Covers, genres, synopsis" : "Portadas, géneros y sinopsis",
                      icon: "photo.stack.fill", color: .purple, key: "refreshMeta") {
                await run("refreshMeta", ok: "¡Actualización de metadatos encolada!", okEn: "Metadata refresh queued!") { c, s in
                    try await c.refreshAllMetadata(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
            actionRow(title: isEn ? "Remove duplicates" : "Limpiar duplicados",
                      subtitle: isEn ? "Deletes repeated chapter files" : "Elimina capítulos repetidos",
                      icon: "trash.fill", color: .orange, key: "cleanupDupes") {
                await run("cleanupDupes", ok: "¡Capítulos duplicados depurados!", okEn: "Duplicate chapters cleaned up!") { c, s in
                    try await c.cleanupDuplicates(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
            actionRow(title: isEn ? "Audit integrity" : "Auditar integridad",
                      subtitle: isEn ? "Checks series consistency" : "Comprueba la coherencia de las series",
                      icon: "stethoscope", color: .blue, key: "statusAudit") {
                await run("statusAudit", ok: "¡Auditoría completada!", okEn: "Status audit completed!") { c, s in
                    try await c.triggerStatusAudit(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
        }
        
        Section(isEn ? "Sources & sync" : "Fuentes y sincronización") {
            actionRow(title: isEn ? "Sync sources" : "Sincronizar fuentes",
                      subtitle: isEn ? "Pull scrapers from GitHub" : "Actualiza los scrapers desde GitHub",
                      icon: "arrow.down.doc.fill", color: .teal, key: "syncSources") {
                await store.syncSources(apiClient: apiClient, session: appState.session, isEn: isEn)
            }
            actionRow(title: isEn ? "Reset breakers" : "Resetear disyuntores",
                      subtitle: isEn ? "Unblock paused sources" : "Desbloquea las fuentes pausadas",
                      icon: "bolt.badge.clock.fill", color: .yellow, key: "resetBreakers") {
                await run("resetBreakers", ok: "¡Disyuntores reseteados!", okEn: "All circuit breakers reset!") { c, s in
                    try await c.resetAllCircuitBreakers(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
            actionRow(title: isEn ? "Sync AniList" : "Sincronizar AniList",
                      subtitle: isEn ? "Push reading progress" : "Envía el progreso de lectura",
                      icon: "arrow.triangle.swap", color: .indigo, key: "syncAniList") {
                await run("syncAniList", ok: "¡Progreso de AniList sincronizado!", okEn: "AniList progress synchronized!") { c, s in
                    try await c.syncAniList(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
        }
    }
    
    // MARK: - Fallos
    
    @ViewBuilder
    private var failuresSections: some View {
        Section {
            if blockedSources.isEmpty {
                Label(isEn ? "All scrapers are working" : "Todos los scrapers funcionan", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(blockedSources) { src in
                    HStack {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text(src.name).foregroundStyle(.white)
                        Spacer()
                        SecondaryButton(
                            title: isEn ? "Reactivate" : "Reactivar",
                            systemImage: nil,
                            tint: .white
                        ) {
                            Task { await store.toggleSource(source: src, apiClient: apiClient, session: appState.session) }
                        }
                    }
                }
                Button {
                    Task { await store.reactivateAllFailedSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
                } label: {
                    Label(isEn ? "Unblock all" : "Desbloquear todas", systemImage: "bolt.fill")
                }
                .disabled(store.activeAction != nil)
            }
        } header: {
            Text(isEn ? "Blocked sources" : "Fuentes bloqueadas")
        }
        
        Section {
            if store.isLoadingFailedJobs && store.failedJobs.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if store.failedJobs.isEmpty {
                Label(isEn ? "No failed downloads" : "Sin descargas fallidas", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(store.failedJobs) { job in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(job.mangaTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                            Text((isEn ? "Ch. " : "Cap. ") + String(format: "%g", job.chapterIndex))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.cyan)
                        }
                        HStack(spacing: 6) {
                            Text(job.source).font(.footnote).foregroundStyle(.secondary)
                            if job.isPaused {
                                Text(isEn ? "· Paused by breaker" : "· Pausado por disyuntor")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                        if let reason = job.failedReason, !reason.isEmpty {
                            Text(reason).font(.caption).foregroundStyle(.red).lineLimit(2)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await store.cancelFailedJob(jobId: job.id, apiClient: apiClient, session: appState.session) }
                        } label: {
                            Label(isEn ? "Discard" : "Descartar", systemImage: "trash")
                        }
                        Button {
                            Task { await store.retryFailedJob(jobId: job.id, apiClient: apiClient, session: appState.session) }
                        } label: {
                            Label(isEn ? "Retry" : "Reintentar", systemImage: "arrow.clockwise")
                        }
                        .tint(.cyan)
                    }
                }
                Button {
                    Task {
                        await run("retryAllFailed", ok: "¡Reintentando todas las descargas fallidas!", okEn: "All failed downloads sent to retry!") { c, s in
                            try await c.retryAllFailedJobs(serverUrl: s.serverUrl, token: s.apiToken)
                        }
                        await store.loadFailedJobs(apiClient: apiClient, session: appState.session)
                    }
                } label: {
                    Label(isEn ? "Retry all" : "Reintentar todas", systemImage: "arrow.clockwise")
                }
                .disabled(store.activeAction != nil)
            }
        } header: {
            Text(isEn ? "Failed downloads (\(store.failedJobs.count))" : "Descargas fallidas (\(store.failedJobs.count))")
        }
    }
    
    // MARK: - Fuentes
    
    @ViewBuilder
    private var sourcesSections: some View {
        if !blockedSources.isEmpty {
            Section {
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(isEn ? "\(blockedSources.count) blocked sources" : "\(blockedSources.count) fuentes bloqueadas")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        SecondaryButton(
                            title: isEn ? "Unblock all" : "Desbloquear todas",
                            systemImage: nil,
                            tint: .orange
                        ) {
                            Task { await store.reactivateAllFailedSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
                        }
                        .disabled(store.activeAction != nil)
                    }
                    .padding(16)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
        }
        
        Section {
            GlassCard {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                    TextField(isEn ? "Search sources" : "Buscar fuente", text: $store.sourceSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                }
                .padding(16)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            SegmentedGlass(
                items: SourceFilter.allCases.map { $0.label(isEn: isEn) },
                selectedIndex: Binding(
                    get: { SourceFilter.allCases.firstIndex(of: store.sourceFilter) ?? 0 },
                    set: { store.sourceFilter = SourceFilter.allCases[$0] }
                )
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
        }
        
        Section {
            if store.isLoadingSources && store.sources.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if filteredSources.isEmpty {
                Text(isEn ? "No sources match." : "No hay fuentes que coincidan.")
                    .foregroundStyle(.white.opacity(0.6))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredSources) { source in
                    sourceRow(source)
                }
            }
        } footer: {
            SecondaryButton(
                title: isEn ? "Sync sources from GitHub" : "Sincronizar fuentes desde GitHub",
                systemImage: "arrow.down.doc",
                tint: .kaizenCyan
            ) {
                Task { await store.syncSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
            }
            .disabled(store.activeAction != nil)
            .padding(.top, 16)
        }
    }
    
    private func sourceRow(_ source: KaizenSourceItem) -> some View {
        let statusText = source.isActive
            ? (isEn ? "Active" : "Activa")
            : (source.isFailed ? (isEn ? "Blocked" : "Bloqueada") : (isEn ? "Disabled" : "Deshabilitada"))
        let badgeColor: Color = source.isActive ? .green : (source.isFailed ? .red : .gray)
        
        return GlassCard {
            HStack(spacing: 12) {
                StatusDot(status: source.isActive ? .completed : (source.isFailed ? .failed : .waiting))

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name).foregroundStyle(.white)
                    Text(statusText + (source.origin.map { " · \($0)" } ?? ""))
                        .font(.footnote)
                        .foregroundStyle(badgeColor)
                }
                Spacer()
                if store.isTogglingSource == source.name {
                    ProgressView()
                } else {
                    Toggle("", isOn: Binding(
                        get: { source.isActive },
                        set: { _ in
                            Task { await store.toggleSource(source: source, apiClient: apiClient, session: appState.session) }
                        }
                    ))
                    .labelsHidden()
                    .tint(.kaizenCyan)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
    
    // MARK: - Colas
    
    @ViewBuilder
    private var queuesSections: some View {
        if let summary = store.queuesResponse?.summary {
            Section(isEn ? "Summary" : "Resumen") {
                LabeledContent(isEn ? "Active" : "Activos", value: "\(summary.totalActive)")
                LabeledContent(isEn ? "Waiting" : "En espera", value: "\(summary.totalWaiting)")
                LabeledContent(isEn ? "Delayed" : "Retrasados", value: "\(summary.totalDelayed)")
                LabeledContent(isEn ? "Failed" : "Fallidos") {
                    Text("\(summary.totalFailed)")
                        .foregroundStyle(summary.totalFailed > 0 ? Color.red : Color.green)
                }
            }
        }
        
        Section(isEn ? "Chapter downloads" : "Descargas de capítulos") {
            if store.downloadQueueJobs.isEmpty {
                Text(isEn ? "Queue is empty." : "La cola está vacía.").foregroundStyle(.secondary)
            } else {
                ForEach(store.downloadQueueJobs.prefix(6)) { job in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.mangaTitle).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                            Text((isEn ? "Ch. " : "Cap. ") + String(format: "%g", job.chapterIndex) + " · " + job.source)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(job.status == "active" ? "\(max(job.progress, 1))%" : job.status.capitalized)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(job.status == "active" ? Color.cyan : (job.status == "failed" ? Color.red : Color.secondary))
                    }
                }
            }
            Button {
                showLiveQueueSheet = true
            } label: {
                Label(isEn ? "Open full queue" : "Abrir cola completa", systemImage: "arrow.down.circle")
            }
        }
        
        if let queues = store.queuesResponse?.queues {
            Section(isEn ? "System queues" : "Colas del sistema") {
                ForEach(queues) { queue in
                    HStack {
                        Text(queue.label).foregroundStyle(.white)
                        Spacer()
                        if queue.active == 0 && queue.waiting == 0 && queue.failed == 0 {
                            Text(isEn ? "Idle" : "Inactiva").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("\(queue.active) · \(queue.waiting) · \(queue.failed)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(queue.failed > 0 ? Color.red : Color.cyan)
                        }
                    }
                }
                Button {
                    Task {
                        await run("cleanCompleted", ok: "¡Colas completadas limpiadas!", okEn: "Completed jobs cleaned!") { c, s in
                            try await c.cleanQueue(serverUrl: s.serverUrl, token: s.apiToken, type: "completed")
                        }
                    }
                } label: {
                    Label(isEn ? "Clear completed" : "Limpiar completados", systemImage: "trash")
                }
                .disabled(store.activeAction != nil)
            }
        }
    }
}
