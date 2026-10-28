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
    
    public func refreshAllData(apiClient: KaizenAPIClient, session: UserSession?) async {
        async let m: () = loadMetrics(apiClient: apiClient, session: session)
        async let s: () = loadSources(apiClient: apiClient, session: session)
        async let f: () = loadFailedJobs(apiClient: apiClient, session: session)
        _ = await (m, s, f)
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

/// Centro de Control Remoto del Servidor Kaizen (exclusivo para Administradores)
public struct AdminDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var store = AdminStore()
    @State private var showAddMangaSheet = false
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
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
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if !appState.isManagement {
                    ContentUnavailableView(
                        isEn ? "Access Restricted" : "Acceso Restringido",
                        systemImage: "lock.shield",
                        description: Text(isEn ? "This remote control panel is only available for Kaizen administrators." : "Este panel de control remoto solo está disponible para administradores de Kaizen.")
                    )
                } else {
                    mainContentView
                }
            }
            .navigationTitle(isEn ? "Server Remote Control" : "Control Remoto de Kaizen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddMangaSheet = true
                    } label: {
                        Label(isEn ? "Add Manga" : "Añadir Manga", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .sheet(isPresented: $showAddMangaSheet) {
                AddMangaRemoteSheet(apiClient: apiClient)
            }
            .task {
                await store.refreshAllData(apiClient: apiClient, session: appState.session)
            }
        }
    }
    
    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header de Conexión del Servidor
                serverConnectionHeader
                
                // Mensajes de estado
                statusMessagesView
                
                // Selector de Sección Segmentado
                Picker("Sección", selection: $store.selectedSection) {
                    ForEach(AdminSection.allCases) { section in
                        Text(section.label(
                            isEn: isEn,
                            failureCount: store.totalFailuresCount,
                            sourceCount: store.sources.count
                        ))
                        .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Vista según la sección elegida
                switch store.selectedSection {
                case .operations:
                    serverOperationsSection
                case .failures:
                    failuresAndErrorsSection
                case .sources:
                    sourcesManagementSection
                case .queues:
                    queuesAndMetricsSection
                }
            }
            .padding(.vertical, 16)
        }
        .refreshable {
            await store.refreshAllData(apiClient: apiClient, session: appState.session)
        }
    }
    
    // MARK: - Subcomponentes
    
    private var serverConnectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(isEn ? "Kaizen Backend Server" : "Servidor Kaizen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.session?.serverUrl.host ?? (isEn ? "Connected" : "Conectado"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    showAddMangaSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(isEn ? "Add Manga" : "Añadir Manga")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cyan, in: Capsule())
                }
                
                Label(isEn ? "Online" : "En línea", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var statusMessagesView: some View {
        if let success = store.successMessage {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text(success)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.green)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12))
        } else if let error = store.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(error)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.red)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12))
        }
    }
    
    // MARK: - Sección 1: Operaciones del Servidor
    
    private var serverOperationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEn ? "Remote Server Operations" : "Operaciones Remotas del Servidor")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                actionButton(
                    title: isEn ? "Sync All Chapters" : "Comprobar Capítulos",
                    subtitle: isEn ? "Runs crawler on all series" : "Dispara crawler en todas las series",
                    icon: "arrow.triangle.2.circlepath",
                    color: .cyan,
                    actionKey: "syncAll"
                ) {
                    await store.executeAction(
                        name: "syncAll",
                        apiClient: apiClient,
                        session: appState.session,
                        successText: isEn ? "Chapter check launched on all series!" : "¡Comprobación de capítulos lanzada en todas las series!"
                    ) { client, session in
                        try await client.syncAllMangas(serverUrl: session.serverUrl, token: session.apiToken)
                    }
                }
                
                actionButton(
                    title: isEn ? "Sync Sources" : "Sincronizar Fuentes",
                    subtitle: isEn ? "Pull scrapers from GitHub" : "Actualiza scrapers desde GitHub",
                    icon: "arrow.down.doc.fill",
                    color: .teal,
                    actionKey: "syncSources"
                ) {
                    await store.syncSources(apiClient: apiClient, session: appState.session, isEn: isEn)
                }
                
                actionButton(
                    title: isEn ? "Refresh Metadata" : "Actualizar Metadatos",
                    subtitle: isEn ? "Covers, genres, synopsis" : "Portadas, géneros y sinopsis",
                    icon: "photo.stack.fill",
                    color: .purple,
                    actionKey: "refreshMeta"
                ) {
                    await store.executeAction(
                        name: "refreshMeta",
                        apiClient: apiClient,
                        session: appState.session,
                        successText: isEn ? "Metadata refresh job queued!" : "¡Actualización de metadatos encolada!"
                    ) { client, session in
                        try await client.refreshAllMetadata(serverUrl: session.serverUrl, token: session.apiToken)
                    }
                }
                
                actionButton(
                    title: isEn ? "Cleanup Duplicates" : "Limpiar Duplicados",
                    subtitle: isEn ? "Remove repeated chapters" : "Elimina archivos repetidos",
                    icon: "trash.fill",
                    color: .orange,
                    actionKey: "cleanupDupes"
                ) {
                    await store.executeAction(
                        name: "cleanupDupes",
                        apiClient: apiClient,
                        session: appState.session,
                        successText: isEn ? "Duplicate chapters cleaned up!" : "¡Capítulos duplicados depurados!"
                    ) { client, session in
                        try await client.cleanupDuplicates(serverUrl: session.serverUrl, token: session.apiToken)
                    }
                }
                
                actionButton(
                    title: isEn ? "Reset Breakers" : "Resetear Disyuntores",
                    subtitle: isEn ? "Unblock paused sources" : "Desbloquea fuentes pausadas",
                    icon: "bolt.badge.clock.fill",
                    color: .yellow,
                    actionKey: "resetBreakers"
                ) {
                    await store.executeAction(
                        name: "resetBreakers",
                        apiClient: apiClient,
                        session: appState.session,
                        successText: isEn ? "All circuit breakers reset!" : "¡Disyuntores de fuentes reseteados!"
                    ) { client, session in
                        try await client.resetAllCircuitBreakers(serverUrl: session.serverUrl, token: session.apiToken)
                    }
                }
                
                actionButton(
                    title: isEn ? "Audit Integrity" : "Auditoría de Integridad",
                    subtitle: isEn ? "Check series consistency" : "Comprueba coherencia de series",
                    icon: "stethoscope",
                    color: .blue,
                    actionKey: "statusAudit"
                ) {
                    await store.executeAction(
                        name: "statusAudit",
                        apiClient: apiClient,
                        session: appState.session,
                        successText: isEn ? "Status audit completed!" : "¡Auditoría de series completada!"
                    ) { client, session in
                        try await client.triggerStatusAudit(serverUrl: session.serverUrl, token: session.apiToken)
                    }
                }
                
                actionButton(
                    title: isEn ? "Sync AniList" : "Sincronizar AniList",
                    subtitle: isEn ? "Push reading progress" : "Envía progreso de lectura",
                    icon: "arrow.triangle.swap",
                    color: .indigo,
                    actionKey: "syncAniList"
                ) {
                    await store.executeAction(
                        name: "syncAniList",
                        apiClient: apiClient,
                        session: appState.session,
                        successText: isEn ? "AniList progress synchronized!" : "¡Progreso de AniList sincronizado!"
                    ) { client, session in
                        try await client.syncAniList(serverUrl: session.serverUrl, token: session.apiToken)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Sección 2: Fallos y Errores (Mangas y Fuentes)
    
    private var failuresAndErrorsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Fuentes Bloqueadas / Fallidas
            let blockedSources = store.sources.filter { $0.isFailed }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(
                        isEn ? "Blocked Sources (\(blockedSources.count))" : "Fuentes Bloqueadas (\(blockedSources.count))",
                        systemImage: "shield.lefthalf.filled.trianglebadge.exclamationmark"
                    )
                    .font(.headline)
                    .foregroundStyle(blockedSources.isEmpty ? .secondary : .red)
                    
                    Spacer()
                    
                    if !blockedSources.isEmpty {
                        Button {
                            Task { await store.reactivateAllFailedSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
                        } label: {
                            Text(isEn ? "Unblock All" : "Desbloquear Todas")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)
                
                if blockedSources.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(isEn ? "All scrapers operational. No blocked sources." : "Todos los scrapers están operativos. Sin bloqueos de red.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 6) {
                        ForEach(blockedSources) { src in
                            HStack {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Text(src.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Button(isEn ? "Reactivate" : "Reactivar") {
                                    Task { await store.toggleSource(source: src, apiClient: apiClient, session: appState.session) }
                                }
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.2), in: Capsule())
                                .foregroundStyle(.red)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Mangas y Capítulos Fallidos en Descarga
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(
                        isEn ? "Failed Downloads (\(store.failedJobs.count))" : "Descargas Fallidas (\(store.failedJobs.count))",
                        systemImage: "xmark.octagon.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(store.failedJobs.isEmpty ? .secondary : .orange)
                    
                    Spacer()
                    
                    if !store.failedJobs.isEmpty {
                        Button {
                            Task {
                                await store.executeAction(
                                    name: "retryAllFailed",
                                    apiClient: apiClient,
                                    session: appState.session,
                                    successText: isEn ? "All failed downloads sent to retry!" : "¡Reintentando todas las descargas fallidas!"
                                ) { client, session in
                                    try await client.retryAllFailedJobs(serverUrl: session.serverUrl, token: session.apiToken)
                                }
                                await store.loadFailedJobs(apiClient: apiClient, session: appState.session)
                            }
                        } label: {
                            Text(isEn ? "Retry All" : "Reintentar Todas")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange, in: Capsule())
                                .foregroundStyle(.black)
                        }
                    }
                }
                .padding(.horizontal)
                
                if store.isLoadingFailedJobs && store.failedJobs.isEmpty {
                    ProgressView().padding(.horizontal)
                } else if store.failedJobs.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(isEn ? "No failed chapter downloads." : "No hay descargas de capítulos fallidas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 8) {
                        ForEach(store.failedJobs) { job in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(job.mangaTitle)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text((isEn ? "Ch. " : "Cap. ") + String(format: "%g", job.chapterIndex))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.cyan)
                                }
                                
                                HStack(spacing: 8) {
                                    Text(job.source)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.08), in: Capsule())
                                    
                                    if job.isPaused {
                                        Text(isEn ? "Paused by Breaker" : "Pausado por Disyuntor")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.orange)
                                    }
                                    
                                    Spacer()
                                    
                                    Button {
                                        Task { await store.retryFailedJob(jobId: job.id, apiClient: apiClient, session: appState.session) }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "arrow.clockwise")
                                            Text(isEn ? "Retry" : "Reintentar")
                                        }
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.cyan.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.cyan)
                                    }
                                    
                                    Button {
                                        Task { await store.cancelFailedJob(jobId: job.id, apiClient: apiClient, session: appState.session) }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                                
                                if let reason = job.failedReason, !reason.isEmpty {
                                    Text(reason)
                                        .font(.caption2)
                                        .foregroundStyle(.red.opacity(0.8))
                                        .lineLimit(2)
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    // MARK: - Sección 3: Fuentes y Scrapers (Pestaña propia limpia)
    
    private var sourcesManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Acciones superiores de fuentes
            HStack {
                Button {
                    Task { await store.syncSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
                } label: {
                    HStack(spacing: 4) {
                        if store.activeAction == "syncSources" {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.down.doc.fill")
                        }
                        Text(isEn ? "Sync Sources" : "Sincronizar Fuentes")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.cyan, in: Capsule())
                }
                .disabled(store.activeAction != nil)
                
                Button {
                    Task { await store.reactivateAllFailedSources(apiClient: apiClient, session: appState.session, isEn: isEn) }
                } label: {
                    HStack(spacing: 4) {
                        if store.activeAction == "reactivateSources" {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(isEn ? "Reactivate Blocked" : "Reactivar Bloqueadas")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.85), in: Capsule())
                }
                .disabled(store.activeAction != nil)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Filtro por Estado y Buscador
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(isEn ? "Search sources..." : "Buscar fuente...", text: $store.sourceSearchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                
                Picker("Filtro", selection: $store.sourceFilter) {
                    ForEach(SourceFilter.allCases) { f in
                        Text(f.label(isEn: isEn)).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .tint(.cyan)
                .padding(.horizontal, 6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal)
            
            // Lista compacta y navegable
            if store.isLoadingSources && store.sources.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(.cyan)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if filteredSources.isEmpty {
                Text(isEn ? "No sources matching filter." : "No se encontraron fuentes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(filteredSources) { source in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(source.isActive ? Color.green : (source.isFailed ? Color.red : Color.gray))
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                
                                HStack(spacing: 6) {
                                    Text(source.isActive ? (isEn ? "Active" : "Activa") : (source.isFailed ? (isEn ? "Blocked / Failed" : "Bloqueada / Fallida") : (isEn ? "Disabled" : "Deshabilitada")))
                                        .font(.caption2)
                                        .foregroundStyle(source.isActive ? .green : (source.isFailed ? .red : .secondary))
                                    
                                    if let origin = source.origin {
                                        Text("• \(origin)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            if store.isTogglingSource == source.name {
                                ProgressView().scaleEffect(0.8)
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Sección 4: Colas BullMQ
    
    private var queuesAndMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEn ? "Queue Remote Controller (BullMQ)" : "Control Remoto de Colas (BullMQ)")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)
            
            if let summary = store.queuesResponse?.summary {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metricCard(title: isEn ? "Active Jobs" : "Trabajos Activos", value: "\(summary.totalActive)", icon: "play.circle.fill", color: .cyan)
                    metricCard(title: isEn ? "Waiting" : "En Espera", value: "\(summary.totalWaiting)", icon: "clock.fill", color: .blue)
                    metricCard(title: isEn ? "Delayed" : "Retrasados", value: "\(summary.totalDelayed)", icon: "hourglass", color: .orange)
                    metricCard(title: isEn ? "Failed" : "Fallidos", value: "\(summary.totalFailed)", icon: "xmark.octagon.fill", color: summary.totalFailed > 0 ? .red : .green)
                }
                .padding(.horizontal)
            }
            
            HStack(spacing: 8) {
                Button {
                    Task {
                        await store.executeAction(
                            name: "retryAllFailed",
                            apiClient: apiClient,
                            session: appState.session,
                            successText: isEn ? "All failed jobs sent to retry!" : "¡Reintento lanzado en trabajos fallidos!"
                        ) { client, session in
                            try await client.retryAllFailedJobs(serverUrl: session.serverUrl, token: session.apiToken)
                        }
                    }
                } label: {
                    HStack {
                        if store.activeAction == "retryAllFailed" {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                        }
                        Text(isEn ? "Retry All Failed" : "Reintentar Fallidos")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.red)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                .disabled(store.activeAction != nil)
                
                Button {
                    Task {
                        await store.executeAction(
                            name: "cleanCompleted",
                            apiClient: apiClient,
                            session: appState.session,
                            successText: isEn ? "Completed jobs cleaned!" : "¡Colas completadas limpiadas!"
                        ) { client, session in
                            try await client.cleanQueue(serverUrl: session.serverUrl, token: session.apiToken, type: "completed")
                        }
                    }
                } label: {
                    HStack {
                        if store.activeAction == "cleanCompleted" {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text(isEn ? "Clean Completed" : "Limpiar Completados")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .disabled(store.activeAction != nil)
            }
            .padding(.horizontal)
            
            if let queues = store.queuesResponse?.queues {
                VStack(spacing: 8) {
                    ForEach(queues) { queue in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(queue.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(queue.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            
                            HStack(spacing: 6) {
                                if queue.active > 0 {
                                    badge(count: queue.active, color: .cyan, label: "act")
                                }
                                if queue.waiting > 0 {
                                    badge(count: queue.waiting, color: .blue, label: isEn ? "wait" : "esp")
                                }
                                if queue.failed > 0 {
                                    badge(count: queue.failed, color: .red, label: isEn ? "fail" : "fall")
                                }
                                if queue.active == 0 && queue.waiting == 0 && queue.failed == 0 {
                                    Text(isEn ? "Idle" : "Inactiva")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        actionKey: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 38, height: 38)
                    if store.activeAction == actionKey {
                        ProgressView().tint(color).scaleEffect(0.8)
                    } else {
                        Image(systemName: icon)
                            .foregroundStyle(color)
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .disabled(store.activeAction != nil)
    }
    
    @ViewBuilder
    private func badge(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 2) {
            Text("\(count)")
                .fontWeight(.bold)
            Text(label)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.2), in: Capsule())
        .foregroundStyle(color)
    }
    
    @ViewBuilder
    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
