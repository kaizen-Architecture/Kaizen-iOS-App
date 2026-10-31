import SwiftUI
import Charts

/// Hoja / Drawer en vivo con la Cola de Descargas de Kaizen (`trpc/manga.downloadQueue`)
public struct LiveDownloadQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var jobs: [DownloadQueueJob] = []
    @State private var isLoading: Bool = false
    @State private var selectedFilter: String = "all" // "all", "active", "waiting", "failed", "completed"
    @State private var isExecutingAction: Bool = false
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private var filteredJobs: [DownloadQueueJob] {
        if selectedFilter == "all" { return jobs }
        return jobs.filter { $0.status == selectedFilter }
    }
    
    private var activeCount: Int { jobs.filter { $0.status == "active" }.count }
    private var waitingCount: Int { jobs.filter { $0.status == "waiting" }.count }
    private var failedCount: Int { jobs.filter { $0.status == "failed" }.count }
    private var completedCount: Int { jobs.filter { $0.status == "completed" }.count }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    filterPillsRow
                    
                    if isLoading && jobs.isEmpty {
                        Spacer()
                        ProgressView().tint(.cyan)
                        Spacer()
                    } else if filteredJobs.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            isEn ? "Download Queue Empty" : "Cola de descargas vacía",
                            systemImage: "arrow.down.circle",
                            description: Text(isEn ? "No chapter downloads matching the current filter." : "No hay descargas de capítulos en este estado ahora mismo.")
                        )
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredJobs) { job in
                                    queueJobCard(job)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .refreshable {
                            await loadQueue()
                        }
                    }
                    
                    bottomActionsBar
                }
                .padding(.top, 8)
            }
            .navigationTitle(isEn ? "Live Download Queue" : "Cola de Descargas en Vivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await loadQueue() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.cyan)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEn ? "Close" : "Cerrar") {
                        dismiss()
                    }
                    .foregroundStyle(.cyan)
                }
            }
            .task {
                await loadQueue()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    guard !Task.isCancelled else { break }
                    await loadQueue(silent: true)
                }
            }
        }
    }
    
    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(id: "all", title: isEn ? "All (\(jobs.count))" : "Todas (\(jobs.count))", tint: .cyan)
                filterPill(id: "active", title: isEn ? "Downloading (\(activeCount))" : "Descargando (\(activeCount))", tint: .cyan)
                filterPill(id: "waiting", title: isEn ? "Queued (\(waitingCount))" : "En cola (\(waitingCount))", tint: .indigo)
                filterPill(id: "failed", title: isEn ? "Failed (\(failedCount))" : "Fallidas (\(failedCount))", tint: .red)
                filterPill(id: "completed", title: isEn ? "Completed (\(completedCount))" : "Completadas (\(completedCount))", tint: .green)
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func filterPill(id: String, title: String, tint: Color) -> some View {
        let isSelected = selectedFilter == id
        return Button {
            selectedFilter = id
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? tint : Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(isSelected ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }
    
    private func queueJobCard(_ job: DownloadQueueJob) -> some View {
        let statusColor = colorForStatus(job.status)
        let chapterStr = String(format: "%g", job.chapterIndex)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.mangaTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text((isEn ? "Ch. " : "Cap. ") + chapterStr)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.cyan)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(job.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Text(labelForStatus(job))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            
            if job.status == "active" {
                ProgressView(value: Double(max(min(job.progress, 100), 5)) / 100.0)
                    .tint(.cyan)
            }
            
            if let reason = job.failedReason, !reason.isEmpty, job.status == "failed" {
                HStack {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        Task {
                            guard let session = appState.session else { return }
                            try? await apiClient.retryJob(serverUrl: session.serverUrl, token: session.apiToken, jobId: job.id)
                            await loadQueue()
                        }
                    } label: {
                        Text(isEn ? "Retry" : "Reintentar")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.2), in: Capsule())
                            .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(job.status == "active" ? Color.cyan.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var bottomActionsBar: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    guard let session = appState.session else { return }
                    isExecutingAction = true
                    defer { isExecutingAction = false }
                    try? await apiClient.retryAllFailedJobs(serverUrl: session.serverUrl, token: session.apiToken)
                    await loadQueue()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text(isEn ? "Retry Failed" : "Reintentar Fallidas")
                }
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .disabled(isExecutingAction || failedCount == 0)
            
            Button {
                Task {
                    guard let session = appState.session else { return }
                    isExecutingAction = true
                    defer { isExecutingAction = false }
                    try? await apiClient.cleanQueue(serverUrl: session.serverUrl, token: session.apiToken, type: "completed")
                    await loadQueue()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                    Text(isEn ? "Clean Completed" : "Limpiar Completadas")
                }
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isExecutingAction)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "active": return .cyan
        case "waiting": return .indigo
        case "failed": return .red
        case "completed": return .green
        default: return .secondary
        }
    }
    
    private func labelForStatus(_ job: DownloadQueueJob) -> String {
        switch job.status {
        case "active":
            return job.progress > 0 ? "\(job.progress)%" : (isEn ? "Downloading" : "Descargando")
        case "waiting":
            return isEn ? "Queued" : "En cola"
        case "failed":
            return isEn ? "Failed" : "Fallido"
        case "completed":
            return isEn ? "Completed" : "Completado"
        default:
            return job.status.capitalized
        }
    }
    
    private func loadQueue(silent: Bool = false) async {
        guard let session = appState.session else { return }
        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }
        if let fetched = try? await apiClient.fetchDownloadQueue(serverUrl: session.serverUrl, token: session.apiToken) {
            self.jobs = fetched
            appState.downloadQueueJobs = fetched
        }
    }
}

/// Dashboard nativo de Kaizen para el Administrador (KPIs en vivo, Gráfica 14 días, GB por Fuente, Cola en vivo y Últimas Descargas)
public struct HomeDashboardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var activityStats = KaizenActivityStats()
    @State private var activityHistory: [KaizenActivityHistoryItem] = []
    @State private var sourceStats: [KaizenSourceStatItem] = []
    @State private var recentDownloads: [KaizenServerRecentDownload] = []
    @State private var queueJobs: [DownloadQueueJob] = []
    
    @State private var isLoading: Bool = false
    @State private var showQueueSheet: Bool = false
    @State private var showAddMangaSheet: Bool = false
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private var isPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var activeAndWaitingJobs: [DownloadQueueJob] {
        queueJobs.filter { $0.status == "active" || $0.status == "waiting" }
    }
    
    private var totalStorageBytes: Int64 {
        sourceStats.reduce(0) { $0 + $1.totalSize }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        kpiCardsGrid
                        
                        if isPad {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(spacing: 16) {
                                    downloads14DaysChartCard
                                    sourceStorageCard
                                }
                                .frame(maxWidth: .infinity)
                                
                                VStack(spacing: 16) {
                                    liveDownloadQueueCard
                                    recentServerDownloadsCard
                                }
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                            VStack(spacing: 16) {
                                liveDownloadQueueCard
                                downloads14DaysChartCard
                                sourceStorageCard
                                recentServerDownloadsCard
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await loadDashboardData()
                }
            }
            .navigationTitle(isEn ? "Kaizen Dashboard" : "Dashboard Kaizen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button {
                            showQueueSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("\(activityStats.active + activityStats.queued)")
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.cyan.opacity(0.16), in: Capsule())
                            .foregroundStyle(.cyan)
                        }
                        
                        if appState.isManagement {
                            Button {
                                showAddMangaSheet = true
                            } label: {
                                Label(isEn ? "Add Manga" : "Añadir Manga", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showQueueSheet) {
                LiveDownloadQueueSheet(apiClient: apiClient)
            }
            .sheet(isPresented: $showAddMangaSheet) {
                AddMangaRemoteSheet(apiClient: apiClient) {
                    Task {
                        await appState.loadLibrary(client: apiClient, force: true)
                        await loadDashboardData()
                    }
                }
            }
            .task {
                await loadDashboardData()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { break }
                    await refreshLiveQueueOnly()
                }
            }
        }
    }
    
    // MARK: - 1. Cinco Tarjetas KPI (trpc/manga.activity)
    
    private var kpiCardsGrid: some View {
        let columns = isPad
            ? Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        
        return LazyVGrid(columns: columns, spacing: 10) {
            Button {
                showQueueSheet = true
            } label: {
                kpiStatBox(
                    title: isEn ? "DOWNLOADING" : "DESCARGANDO",
                    value: "\(activityStats.active)",
                    subtitle: isEn ? "View live queue →" : "Ver cola en vivo →",
                    icon: "arrow.down.circle.fill",
                    color: .cyan
                )
            }
            .buttonStyle(.plain)
            
            Button {
                showQueueSheet = true
            } label: {
                kpiStatBox(
                    title: isEn ? "QUEUED" : "EN COLA",
                    value: "\(activityStats.queued)",
                    subtitle: isEn ? "Waiting turn" : "Esperando turno",
                    icon: "clock.fill",
                    color: .indigo
                )
            }
            .buttonStyle(.plain)
            
            kpiStatBox(
                title: isEn ? "SCHEDULED" : "PROGRAMADOS",
                value: "\(activityStats.scheduled)",
                subtitle: isEn ? "Active scheduler" : "Planificador activo",
                icon: "calendar.badge.clock",
                color: .purple
            )
            
            Button {
                showQueueSheet = true
            } label: {
                kpiStatBox(
                    title: isEn ? "FAILED" : "FALLIDOS",
                    value: "\(activityStats.failed)",
                    subtitle: activityStats.failed > 0 ? (isEn ? "Tap to inspect" : "Pulsar para revisar") : (isEn ? "All healthy" : "Sin fallos"),
                    icon: "exclamationmark.triangle.fill",
                    color: activityStats.failed > 0 ? .red : .green
                )
            }
            .buttonStyle(.plain)
            
            kpiStatBox(
                title: isEn ? "COMPLETED" : "COMPLETADOS",
                value: "\(activityStats.completed)",
                subtitle: isEn ? "Verified CBZ" : "CBZ verificados",
                icon: "checkmark.seal.fill",
                color: .green
            )
        }
    }
    
    private func kpiStatBox(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }
    
    // MARK: - 2. Gráfica de Descargas — Últimos 14 Días (Swift Charts)
    
    private var downloads14DaysChartCard: some View {
        let total14d = activityHistory.reduce(0) { $0 + $1.count }
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    isEn ? "Downloads — Last 14 Days" : "Descargas — Últimos 14 Días",
                    systemImage: "chart.bar.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                
                Spacer()
                
                Text("\(total14d) " + (isEn ? "ch." : "caps."))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
            }
            
            if activityHistory.isEmpty {
                Text(isEn ? "No download activity in the last 14 days." : "Sin actividad de descargas en los últimos 14 días.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(activityHistory) { item in
                    BarMark(
                        x: .value("Day", item.label),
                        y: .value("Chapters", item.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .indigo],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(4)
                }
                .frame(height: 165)
            }
        }
        .padding(15)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - 3. Series y Almacenamiento por Fuente (trpc/manga.sourceStats)
    
    private var sourceStorageCard: some View {
        let totalFormatted = ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
        let maxSourceBytes = max(sourceStats.first?.totalSize ?? 1, 1)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    isEn ? "Series & Storage by Source" : "Series y Espacio por Fuente",
                    systemImage: "externaldrive.fill.badge.timemachine"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                
                Spacer()
                
                Text("Total: \(totalFormatted)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            
            if sourceStats.isEmpty {
                Text(isEn ? "No source statistics available." : "No hay estadísticas de fuentes disponibles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(sourceStats.prefix(8)) { stat in
                        let ratio = Double(stat.totalSize) / Double(maxSourceBytes)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(stat.source) (\(stat.mangaCount) " + (isEn ? "series)" : "series)"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(stat.formattedSize)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.cyan)
                            }
                            ProgressView(value: min(max(ratio, 0.04), 1.0))
                                .tint(.cyan)
                        }
                    }
                }
            }
        }
        .padding(15)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - 4. Cola de Descargas en Vivo (trpc/manga.downloadQueue)
    
    private var liveDownloadQueueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    isEn ? "Live Download Queue" : "Cola de Descargas en Vivo",
                    systemImage: "arrow.down.circle.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                
                Spacer()
                
                Button {
                    showQueueSheet = true
                } label: {
                    Text(isEn ? "Full Queue (\(queueJobs.count)) →" : "Ver todas (\(queueJobs.count)) →")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }
            
            if activeAndWaitingJobs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(isEn ? "No active downloads right now. Tap 'Full Queue' for history." : "No hay descargas en curso ahora mismo. Pulsa 'Ver todas' para el historial.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    ForEach(activeAndWaitingJobs.prefix(5)) { job in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.mangaTitle)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text((isEn ? "Ch. " : "Cap. ") + String(format: "%g", job.chapterIndex) + " • \(job.source)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(job.status == "active" ? "\(max(job.progress, 1))%" : (isEn ? "Queued" : "En cola"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((job.status == "active" ? Color.cyan : Color.indigo).opacity(0.18), in: Capsule())
                                .foregroundStyle(job.status == "active" ? Color.cyan : Color.indigo)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(15)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.22), lineWidth: 1))
    }
    
    // MARK: - 5. Últimas Descargas del Servidor (trpc/manga.history)
    
    private var recentServerDownloadsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                isEn ? "Recent Server Downloads" : "Últimas Descargas en el Servidor",
                systemImage: "clock.arrow.circlepath"
            )
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            
            if recentDownloads.isEmpty {
                Text(isEn ? "No recent chapters downloaded." : "No hay capítulos descargados recientemente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentDownloads.prefix(6)) { item in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 34, height: 48)
                                .overlay {
                                    RemoteImage(
                                        url: item.coverUrl.flatMap { URL(string: $0) },
                                        token: appState.session?.apiToken,
                                        contentMode: .fill
                                    )
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.mangaTitle)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                
                                HStack(spacing: 6) {
                                    Text((isEn ? "Chapter " : "Capítulo ") + String(format: "%g", item.index))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.cyan)
                                    if let sz = item.formattedSize {
                                        Text("• \(sz)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(15)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - Carga de Datos del Dashboard
    
    private func loadDashboardData() async {
        guard let session = appState.session else { return }
        isLoading = true
        defer { isLoading = false }
        
        async let statsTask = apiClient.fetchActivityStats(serverUrl: session.serverUrl, token: session.apiToken)
        async let historyTask = apiClient.fetchActivityHistory(serverUrl: session.serverUrl, token: session.apiToken)
        async let sourcesTask = apiClient.fetchSourceStats(serverUrl: session.serverUrl, token: session.apiToken)
        async let recentTask = apiClient.fetchRecentServerDownloads(serverUrl: session.serverUrl, token: session.apiToken)
        async let queueTask = apiClient.fetchDownloadQueue(serverUrl: session.serverUrl, token: session.apiToken)
        
        if let st = try? await statsTask { self.activityStats = st }
        if let hi = try? await historyTask { self.activityHistory = hi }
        if let so = try? await sourcesTask { self.sourceStats = so }
        if let re = try? await recentTask { self.recentDownloads = re }
        if let qu = try? await queueTask {
            self.queueJobs = qu
            appState.downloadQueueJobs = qu
        }
    }
    
    private func refreshLiveQueueOnly() async {
        guard let session = appState.session else { return }
        if let st = try? await apiClient.fetchActivityStats(serverUrl: session.serverUrl, token: session.apiToken) {
            self.activityStats = st
        }
        if let qu = try? await apiClient.fetchDownloadQueue(serverUrl: session.serverUrl, token: session.apiToken) {
            self.queueJobs = qu
            appState.downloadQueueJobs = qu
        }
    }
}
