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
    @Environment(\.horizontalSizeClass) private var sizeClass
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
    private var isPad: Bool { sizeClass == .regular }
    
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
    
    @ViewBuilder
    private var content: some View {
        if store.selectedSection == .operations && isEmbedded {
            cyberpunkOperationsGridView
        } else if store.selectedSection == .sources && isEmbedded {
            cyberpunkSourcesGridView
        } else {
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
    }
    
    // MARK: - Vista Cyberpunk 2x2 de Operaciones del Servidor (Mockup 2)
    
    private var cyberpunkOperationsGridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Cabecera: "Operaciones del Servidor" + píldora verde neón "Servidor En Línea"
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 14) {
                        Text(isEn ? "Server Operations" : "Operaciones del Servidor")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        serverOnlinePill
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isEn ? "Server Operations" : "Operaciones del Servidor")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        serverOnlinePill
                    }
                }
                
                if let success = store.successMessage {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .kaizenGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .kaizenGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                
                let columns = isPad
                    ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    : [GridItem(.flexible(), spacing: 16)]
                
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    circuitBreakersGlassPanel
                    realtimeMetricsGlassPanel
                    quickActionsGlassPanel
                    terminalStatusGlassPanel
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .refreshable {
            await store.refreshAllData(apiClient: apiClient, session: appState.session)
        }
    }
    
    private var serverOnlinePill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(red: 0.25, green: 0.98, blue: 0.55))
                .frame(width: 8, height: 8)
                .shadow(color: .green, radius: 5)
            Text(isEn ? "Server Online (v1.2.0 · Active)" : "Servidor En Línea (v1.2.0 · Activo)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.45, green: 1.0, blue: 0.65))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(Color.green.opacity(0.55), lineWidth: 1))
        .shadow(color: Color.green.opacity(0.3), radius: 8)
    }
    
    // Panel 1: Circuit Breakers de Scrapers
    private var circuitBreakersGlassPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isEn ? "Scraper Circuit Breakers" : "Circuit Breakers de Scrapers")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                if !blockedSources.isEmpty {
                    Button(isEn ? "Unblock all" : "Reactivar") {
                        Task { await store.reactivateAllFailedSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
                }
            }
            
            if store.sources.isEmpty {
                Text(isEn ? "Loading scrapers..." : "Cargando scrapers...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(store.sources.prefix(5)) { source in
                        HStack(spacing: 10) {
                            Text(source.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(source.isActive ? (isEn ? "Operational" : "Operativo") : (source.isFailed ? (isEn ? "Degraded" : "Degradado") : (isEn ? "Paused" : "Pausado")))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(source.isActive ? Color(red: 0.25, green: 0.98, blue: 0.55) : (source.isFailed ? .orange : .secondary))
                            
                            Toggle("", isOn: Binding(
                                get: { source.isActive },
                                set: { _ in
                                    Task { await store.toggleSource(source: source, apiClient: apiClient, session: appState.session) }
                                }
                            ))
                            .labelsHidden()
                            .tint(source.isActive ? .green : .orange)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    // Panel 2: Métricas en Tiempo Real y Estado de Colas
    private var realtimeMetricsGlassPanel: some View {
        let summary = store.queuesResponse?.summary
        let totalSeries = appState.mangas.count
        let totalChapters = appState.mangas.reduce(0) { $0 + $1.totalChapters }
        
        return VStack(alignment: .leading, spacing: 14) {
            Text(isEn ? "Real-Time Queue & Catalog Metrics" : "Métricas y Colas en Tiempo Real")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(isEn ? "Active Jobs" : "Activas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(summary?.totalActive ?? 0)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.cyan)
                    }
                    HStack {
                        Text(isEn ? "Waiting" : "En Espera")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(summary?.totalWaiting ?? 0)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.indigo)
                    }
                    HStack {
                        Text(isEn ? "Scheduled" : "Programadas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(summary?.totalDelayed ?? 0)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.purple)
                    }
                    HStack {
                        Text(isEn ? "Failed" : "Fallidas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(summary?.totalFailed ?? 0)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle((summary?.totalFailed ?? 0) > 0 ? .red : .green)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Anillo Neón Cian de Series y Capítulos
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 10)
                    
                    Circle()
                        .trim(from: 0, to: 0.78)
                        .stroke(
                            LinearGradient(
                                colors: [Color(red: 0.30, green: 0.96, blue: 1.0), Color.cyan, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Color.cyan.opacity(0.75), radius: 8)
                    
                    VStack(spacing: 2) {
                        Text("\(totalChapters)")
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                        Text("\(totalSeries) " + (isEn ? "series" : "series"))
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                    }
                }
                .frame(width: 112, height: 112)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    // Panel 3: Acciones Rápidas con Botones Biselados de Cristal
    private var quickActionsGlassPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEn ? "Quick Actions" : "Acciones Rápidas")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            
            bevelGlassActionButton(
                title: isEn ? "Sync Complete Library" : "Sincronizar Biblioteca Completa",
                icon: "arrow.triangle.2.circlepath",
                key: "syncAll"
            ) {
                await run("syncAll", ok: "¡Comprobación lanzada en todas las series!", okEn: "Chapter check launched on all series!") { c, s in
                    try await c.syncAllMangas(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
            
            bevelGlassActionButton(
                title: isEn ? "Refresh Metadata & Covers" : "Actualizar Metadatos y Portadas",
                icon: "photo.stack.fill",
                key: "refreshMeta"
            ) {
                await run("refreshMeta", ok: "¡Actualización de metadatos encolada!", okEn: "Metadata refresh queued!") { c, s in
                    try await c.refreshAllMetadata(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
            
            bevelGlassActionButton(
                title: isEn ? "Purge Duplicate Chapters" : "Depurar Capítulos Duplicados",
                icon: "trash.fill",
                key: "cleanupDupes"
            ) {
                await run("cleanupDupes", ok: "¡Capítulos duplicados depurados!", okEn: "Duplicate chapters cleaned up!") { c, s in
                    try await c.cleanupDuplicates(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
            
            bevelGlassActionButton(
                title: isEn ? "Audit Series Integrity & Breakers" : "Auditar Integridad y Disyuntores",
                icon: "bolt.shield.fill",
                key: "statusAudit"
            ) {
                await run("statusAudit", ok: "¡Auditoría completada!", okEn: "Status audit completed!") { c, s in
                    try await c.triggerStatusAudit(serverUrl: s.serverUrl, token: s.apiToken)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    private func bevelGlassActionButton(title: String, icon: String, key: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 10) {
                if store.activeAction == key {
                    ProgressView().tint(.cyan)
                } else {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.50), Color.white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(store.activeAction != nil)
    }
    
    // Panel 4: Terminal & Estado de BullMQ
    private var terminalStatusGlassPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Terminal & BullMQ")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    Task {
                        await store.syncSources(apiClient: apiClient, session: appState.session, isEn: isEn)
                    }
                } label: {
                    Label(isEn ? "Sync GitHub" : "Sincronizar GitHub", systemImage: "arrow.down.doc.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("[INFO]")
                        .foregroundStyle(.cyan)
                    Text("Kaizen Engine Online · \(store.sources.filter { $0.isActive }.count)/\(store.sources.count) scrapers ready")
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                if let queues = store.queuesResponse?.queues {
                    ForEach(queues.prefix(4)) { q in
                        HStack(spacing: 6) {
                            Text("[QUEUE]")
                                .foregroundStyle(q.failed > 0 ? .orange : .green)
                            Text("\(q.label): \(q.active) active · \(q.waiting) waiting · \(q.failed) failed")
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                }
                
                if let activeJob = store.downloadQueueJobs.first(where: { $0.status == "active" }) {
                    HStack(spacing: 6) {
                        Text("[WORKER]")
                            .foregroundStyle(.cyan)
                        Text("Downloading \(activeJob.mangaTitle) Ch. \(String(format: "%g", activeJob.chapterIndex)) (\(activeJob.progress)%)")
                            .foregroundStyle(.white)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text("[WORKER]")
                            .foregroundStyle(.green)
                        Text(isEn ? "BullMQ Workers idle and listening for jobs" : "Workers de BullMQ en espera y listos")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption.monospaced())
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.cyan.opacity(0.22), lineWidth: 1)
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    // MARK: - Vista Cyberpunk de Fuentes & Scrapers en Grid de Cristal
    
    private var cyberpunkSourcesGridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isEn ? "Scrapers & Sources" : "Scrapers y Fuentes")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text(isEn ? "\(store.sources.filter { $0.isActive }.count) active · \(blockedSources.count) blocked" : "\(store.sources.filter { $0.isActive }.count) activas · \(blockedSources.count) bloqueadas")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !blockedSources.isEmpty {
                        Button(isEn ? "Unblock all" : "Desbloquear todas") {
                            Task { await store.reactivateAllFailedSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
                        }
                        .font(.footnote.weight(.bold))
                        .kaizenGlassButton(prominent: true)
                    }
                }
                
                // Buscador y filtro en píldoras de cristal
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.cyan)
                    TextField(isEn ? "Search scraper..." : "Buscar scraper...", text: $store.sourceSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .kaizenGlass(in: Capsule())
                
                HStack(spacing: 8) {
                    ForEach(SourceFilter.allCases) { f in
                        let isSelected = (store.sourceFilter == f)
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                store.sourceFilter = f
                            }
                        } label: {
                            Text(f.label(isEn: isEn))
                                .font(.caption.weight(isSelected ? .bold : .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .foregroundStyle(isSelected ? Color.black : Color.white)
                                .kaizenGlass(interactive: true, tint: isSelected ? .cyan : nil, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                
                let columns = isPad
                    ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
                    : [GridItem(.flexible(), spacing: 12)]
                
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredSources) { source in
                        sourceRow(source)
                            .padding(14)
                            .kaizenGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
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
                        Button(isEn ? "Reactivate" : "Reactivar") {
                            Task { await store.toggleSource(source: src, apiClient: apiClient, session: appState.session) }
                        }
                        .kaizenGlassButton(prominent: false)
                        .font(.footnote.weight(.semibold))
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
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(isEn ? "\(blockedSources.count) blocked sources" : "\(blockedSources.count) fuentes bloqueadas")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(isEn ? "Unblock all" : "Desbloquear todas") {
                        Task { await store.reactivateAllFailedSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
                    }
                    .font(.footnote.weight(.semibold))
                    .kaizenGlassButton(prominent: false)
                    .disabled(store.activeAction != nil)
                }
            }
            .listRowBackground(Color.orange.opacity(0.18))
        }
        
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(isEn ? "Search sources" : "Buscar fuente", text: $store.sourceSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Picker("", selection: $store.sourceFilter) {
                ForEach(SourceFilter.allCases) { f in
                    Text(f.label(isEn: isEn)).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        
        Section {
            if store.isLoadingSources && store.sources.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if filteredSources.isEmpty {
                Text(isEn ? "No sources match." : "No hay fuentes que coincidan.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredSources) { source in
                    sourceRow(source)
                }
            }
        } footer: {
            Button {
                Task { await store.syncSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
            } label: {
                Label(isEn ? "Sync sources from GitHub" : "Sincronizar fuentes desde GitHub", systemImage: "arrow.down.doc")
                    .font(.footnote.weight(.semibold))
            }
            .disabled(store.activeAction != nil)
            .padding(.top, 8)
        }
    }
    
    private func sourceRow(_ source: KaizenSourceItem) -> some View {
        let statusColor: Color = source.isActive ? .green : (source.isFailed ? .red : .gray)
        let statusText = source.isActive
            ? (isEn ? "Active" : "Activa")
            : (source.isFailed ? (isEn ? "Blocked" : "Bloqueada") : (isEn ? "Disabled" : "Deshabilitada"))
        
        return HStack(spacing: 12) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).foregroundStyle(.white)
                Text(statusText + (source.origin.map { " · \($0)" } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(statusColor == .gray ? Color.secondary : statusColor)
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
                .tint(.cyan)
            }
        }
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
