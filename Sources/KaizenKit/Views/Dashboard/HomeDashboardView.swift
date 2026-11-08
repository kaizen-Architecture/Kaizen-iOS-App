import SwiftUI
import Charts

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
    @State private var queueInitialFilter: LiveDownloadQueueSheet.QueueFilter = .all
    @State private var showAddMangaSheet: Bool = false
    
    // Hojas interactivas para las burbujas KPI (Scheduled, Failed, Completed)
    @State private var showSchedulerSheet: Bool = false
    @State private var showFailedSheet: Bool = false
    @State private var showCompletedSheet: Bool = false
    
    public var isEmbedded: Bool = false
    public var onNavigateToQueue: ((LiveDownloadQueueSheet.QueueFilter) -> Void)?
    
    public init(
        apiClient: KaizenAPIClient,
        isEmbedded: Bool = false,
        onNavigateToQueue: ((LiveDownloadQueueSheet.QueueFilter) -> Void)? = nil
    ) {
        self.apiClient = apiClient
        self.isEmbedded = isEmbedded
        self.onNavigateToQueue = onNavigateToQueue
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
    
    private var nonCompletedQueueJobs: [DownloadQueueJob] {
        queueJobs.filter { $0.status != "completed" }
    }
    
    private var totalStorageBytes: Int64 {
        sourceStats.reduce(0) { $0 + $1.totalSize }
    }
    
    private func openQueue(filter: LiveDownloadQueueSheet.QueueFilter) {
        queueInitialFilter = filter
        if let onNavigateToQueue {
            onNavigateToQueue(filter)
        } else {
            showQueueSheet = true
        }
    }
    
    public var body: some View {
        if isEmbedded {
            dashboardWithSheets
        } else {
            NavigationStack {
                dashboardWithSheets
                    .navigationTitle(isEn ? "Statistics" : "Estadísticas")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(spacing: 10) {
                                Button {
                                    openQueue(filter: .all)
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
            }
        }
    }
    
    private var dashboardWithSheets: some View {
        dashboardScrollContent
            .sheet(isPresented: $showQueueSheet) {
                LiveDownloadQueueSheet(apiClient: apiClient, initialFilter: queueInitialFilter)
            }
            .sheet(isPresented: $showSchedulerSheet) {
                SchedulerSheetView(apiClient: apiClient)
            }
            .sheet(isPresented: $showFailedSheet) {
                FailedJobsInspectorSheet(
                    apiClient: apiClient,
                    onJumpToQueue: {
                        showFailedSheet = false
                        openQueue(filter: .failed)
                    },
                    onChanged: {
                        Task { await loadDashboardData() }
                    }
                )
            }
            .sheet(isPresented: $showCompletedSheet) {
                CompletedDownloadsSheet(apiClient: apiClient)
            }
            .sheet(isPresented: $showAddMangaSheet) {
                AddMangaRemoteSheet(apiClient: apiClient) {
                    Task {
                        await appState.loadLibrary(client: apiClient, force: true)
                        await loadDashboardData()
                    }
                }
            }
            .refreshable {
                await loadDashboardData()
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
    
    private var dashboardScrollContent: some View {
        ZStack {
            if !isEmbedded {
                Color.clear.ambientGlowBackground()
            }
            
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
        }
    }
    
    // MARK: - 1. Cinco Burbujas KPI Interactivas (`trpc/manga.activity`)
    
    private var kpiCardsGrid: some View {
        let columns = isPad
            ? Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        
        return LazyVGrid(columns: columns, spacing: 10) {
            // 1. DOWNLOADING -> Va a la Cola (Activas)
            Button {
                openQueue(filter: .active)
            } label: {
                kpiStatBox(
                    title: isEn ? "DOWNLOADING" : "DESCARGANDO",
                    value: "\(activityStats.active)",
                    subtitle: isEn ? "View live queue →" : "Ver cola activa →",
                    icon: "arrow.down.circle.fill",
                    color: .cyan
                )
            }
            .buttonStyle(.plain)
            
            // 2. QUEUED -> Va a la Cola (En espera)
            Button {
                openQueue(filter: .waiting)
            } label: {
                kpiStatBox(
                    title: isEn ? "QUEUED" : "EN COLA",
                    value: "\(activityStats.queued)",
                    subtitle: isEn ? "Waiting turn →" : "Esperando turno →",
                    icon: "clock.fill",
                    color: .indigo
                )
            }
            .buttonStyle(.plain)
            
            // 3. SCHEDULED -> Abre el Planificador Activo (/scheduler en Kaizen Web)
            Button {
                showSchedulerSheet = true
            } label: {
                kpiStatBox(
                    title: isEn ? "SCHEDULED" : "PROGRAMADOS",
                    value: "\(activityStats.scheduled)",
                    subtitle: isEn ? "Open scheduler →" : "Ver planificador →",
                    icon: "calendar.badge.clock",
                    color: .purple
                )
            }
            .buttonStyle(.plain)
            
            // 4. FAILED -> Abre el Inspector de Fallos y Cambio de Fuente (FailedJobsModal en Kaizen Web)
            Button {
                showFailedSheet = true
            } label: {
                kpiStatBox(
                    title: isEn ? "FAILED" : "FALLIDOS",
                    value: "\(activityStats.failed)",
                    subtitle: activityStats.failed > 0 ? (isEn ? "Tap to recover →" : "Pulsar para recuperar →") : (isEn ? "All healthy →" : "Sin fallos →"),
                    icon: "exclamationmark.triangle.fill",
                    color: activityStats.failed > 0 ? .red : .green
                )
            }
            .buttonStyle(.plain)
            
            // 5. COMPLETED -> Abre el Historial de Capítulos CBZ Completados
            Button {
                showCompletedSheet = true
            } label: {
                kpiStatBox(
                    title: isEn ? "COMPLETED" : "COMPLETADOS",
                    value: "\(activityStats.completed)",
                    subtitle: isEn ? "Verified CBZ →" : "Ver CBZ verificados →",
                    icon: "checkmark.seal.fill",
                    color: .green
                )
            }
            .buttonStyle(.plain)
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
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .kaizenGlass(interactive: true, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    // MARK: - 3. Series y Almacenamiento por Fuente (`trpc/manga.sourceStats`)
    
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
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    // MARK: - 4. Cola de Descargas en Vivo (`trpc/manga.downloadQueue`)
    
    private var liveDownloadQueueCard: some View {
        let pendingOrFailedCount = nonCompletedQueueJobs.count
        let targetFilter: LiveDownloadQueueSheet.QueueFilter = activeAndWaitingJobs.isEmpty && activityStats.failed > 0 ? .failed : .all
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    isEn ? "Live Download Queue" : "Cola de Descargas en Vivo",
                    systemImage: "arrow.down.circle.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                
                Spacer()
                
                Button {
                    openQueue(filter: targetFilter)
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            isEn
                                ? "Open Queue (\(pendingOrFailedCount))"
                                : "Abrir Cola (\(pendingOrFailedCount))"
                        )
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.cyan.opacity(0.15), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            if activeAndWaitingJobs.isEmpty {
                Button {
                    openQueue(filter: targetFilter)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: activityStats.failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(activityStats.failed > 0 ? .orange : .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                activityStats.failed > 0
                                    ? (isEn
                                        ? "No active downloads · \(activityStats.failed) failed job(s) waiting for review"
                                        : "Sin descargas en curso · \(activityStats.failed) trabajo(s) fallido(s) por revisar")
                                    : (isEn
                                        ? "No active downloads right now. Tap to open Queue."
                                        : "No hay descargas en curso ahora mismo. Pulsa para abrir la Cola.")
                            )
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    ForEach(activeAndWaitingJobs.prefix(5)) { job in
                        Button {
                            openQueue(filter: job.status == "active" ? .active : .waiting)
                        } label: {
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
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(15)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    // MARK: - 5. Últimas Descargas del Servidor (`trpc/manga.history`)
    
    private var recentServerDownloadsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    isEn ? "Recent Server Downloads" : "Últimas Descargas en el Servidor",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                
                Spacer()
                
                Button {
                    showCompletedSheet = true
                } label: {
                    Text(isEn ? "View all →" : "Ver historial →")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }
            
            if recentDownloads.isEmpty {
                Text(isEn ? "No recent chapters downloaded." : "No hay capítulos descargados recientemente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentDownloads.prefix(6)) { item in
                        recentDownloadItemView(item)
                    }
                }
            }
        }
        .padding(15)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    @ViewBuilder
    private func recentDownloadItemView(_ item: KaizenServerRecentDownload) -> some View {
        let matched = appState.mangas.first(where: {
            if let mid = item.mangaId, $0.id == mid { return true }
            return $0.title.localizedCaseInsensitiveCompare(item.mangaTitle) == .orderedSame
        })
        if let matched {
            NavigationLink(value: matched) {
                recentServerDownloadRow(item)
            }
            .buttonStyle(.plain)
        } else {
            recentServerDownloadRow(item)
        }
    }
    
    private func recentServerDownloadRow(_ item: KaizenServerRecentDownload) -> some View {
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
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(8)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
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

// MARK: - Hoja 1: Planificador Activo (`SCHEDULED` KPI Bubble -> `/scheduler` en Kaizen Web)

public struct SchedulerSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let apiClient: KaizenAPIClient
    
    private enum ScheduleTab: String, CaseIterable, Identifiable {
        case ongoing, completed, locked, all
        var id: String { rawValue }
    }
    
    @State private var schedules: [KaizenScheduledManga] = []
    @State private var selectedTab: ScheduleTab = .ongoing
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    @State private var isStaggering: Bool = false
    @State private var statusBanner: String?
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    
    private var filteredSchedules: [KaizenScheduledManga] {
        schedules.filter { item in
            if !searchText.isEmpty && !item.title.localizedCaseInsensitiveContains(searchText) && !item.source.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            let st = (item.status ?? "").uppercased()
            switch selectedTab {
            case .ongoing:
                return st == "ONGOING" || st == "RELEASING" || st == "UNKNOWN" || st.isEmpty
            case .completed:
                return st == "FINISHED" || st == "COMPLETED"
            case .locked:
                return item.isLocked
            case .all:
                return true
            }
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.ambientGlowBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Tarjeta de Auto-Stagger (Optimización nocturna de Kaizen Web)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(
                                    isEn ? "Nightly Auto-Stagger (00:00 – 05:00)" : "Escalonado Nocturno Inteligente (00:00 – 05:00)",
                                    systemImage: "sparkles"
                                )
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                
                                Text(
                                    isEn
                                        ? "Distributes unlocked series checks across night hours to prevent scraper rate-limits."
                                        : "Distribuye las comprobaciones de series sin candado en la madrugada para evitar bloqueos."
                                )
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))
                            }
                            Spacer()
                            Button {
                                Task { await runAutoStagger() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isStaggering {
                                        ProgressView().tint(.black).scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                    }
                                    Text(isEn ? "Optimize" : "Optimizar")
                                }
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .contentShape(Capsule())
                            }
                            .kaizenGlassButton(prominent: true)
                            .disabled(isStaggering)
                        }
                        .padding(16)
                        .kaizenGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        
                        if let banner = statusBanner {
                            Text(banner)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.cyan)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        
                        // Píldoras de filtro
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ScheduleTab.allCases) { tab in
                                    let isSel = selectedTab == tab
                                    Button {
                                        selectedTab = tab
                                    } label: {
                                        Text(tabTitle(tab))
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .foregroundStyle(isSel ? Color.black : Color.white)
                                            .background(isSel ? Color.cyan : Color.white.opacity(0.08), in: Capsule())
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        if isLoading && schedules.isEmpty {
                            HStack { Spacer(); ProgressView().tint(.cyan).padding(.vertical, 40); Spacer() }
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredSchedules) { item in
                                    scheduleRow(item)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .searchable(text: $searchText, prompt: isEn ? "Search scheduled series..." : "Buscar serie programada...")
            .navigationTitle(isEn ? "Active Scheduler (\(schedules.count))" : "Planificador (\(schedules.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Close" : "Cerrar") { dismiss() }
                }
            }
            .task {
                await loadSchedules()
            }
        }
    }
    
    private func tabTitle(_ tab: ScheduleTab) -> String {
        switch tab {
        case .ongoing: return isEn ? "Ongoing" : "En emisión"
        case .completed: return isEn ? "Completed" : "Finalizadas"
        case .locked: return isEn ? "Locked" : "Con candado"
        case .all: return isEn ? "All (\(schedules.count))" : "Todas (\(schedules.count))"
        }
    }
    
    private func scheduleRow(_ item: KaizenScheduledManga) -> some View {
        HStack(spacing: 12) {
            RemoteImage(
                url: item.coverUrl.flatMap { URL(string: $0) },
                token: appState.session?.apiToken,
                contentMode: .fill
            )
            .frame(width: 44, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(item.source)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                    
                    Label(item.interval, systemImage: "clock")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            
            Spacer()
            
            Button {
                Task { await toggleLock(for: item) }
            } label: {
                Image(systemName: item.isLocked ? "lock.fill" : "lock.open")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(item.isLocked ? .orange : .white.opacity(0.65))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            
            Button {
                Task {
                    guard let session = appState.session else { return }
                    try? await apiClient.syncManga(serverUrl: session.serverUrl, token: session.apiToken, mangaId: item.id)
                    statusBanner = isEn ? "Queued check for '\(item.title)'" : "Comprobación encolada para '\(item.title)'"
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.cyan)
                    .frame(width: 36, height: 36)
                    .background(Color.cyan.opacity(0.15), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func loadSchedules() async {
        guard let session = appState.session else { return }
        isLoading = true
        defer { isLoading = false }
        if let list = try? await apiClient.fetchSchedules(serverUrl: session.serverUrl, token: session.apiToken) {
            self.schedules = list
        }
    }
    
    private func toggleLock(for item: KaizenScheduledManga) async {
        guard let session = appState.session else { return }
        let newLock = !item.isLocked
        try? await apiClient.toggleMangaLock(serverUrl: session.serverUrl, token: session.apiToken, mangaId: item.id, isLocked: newLock)
        if let idx = schedules.firstIndex(where: { $0.id == item.id }) {
            schedules[idx].isLocked = newLock
        }
    }
    
    private func runAutoStagger() async {
        guard let session = appState.session else { return }
        isStaggering = true
        defer { isStaggering = false }
        if let count = try? await apiClient.autoStaggerSchedules(serverUrl: session.serverUrl, token: session.apiToken) {
            statusBanner = isEn ? "Optimized \(count) series schedules!" : "¡Optimizados los horarios de \(count) series!"
            await loadSchedules()
        }
    }
}

// MARK: - Hoja 2: Inspector de Trabajos Fallidos y Cambio de Fuente (`FAILED` KPI Bubble -> `FailedJobsModal` en Kaizen Web)

public struct FailedJobsInspectorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let apiClient: KaizenAPIClient
    var onJumpToQueue: (() -> Void)?
    var onChanged: (() -> Void)?
    
    @State private var failedJobs: [FailedDownloadJob] = []
    @State private var availableSources: [String] = []
    @State private var selectedAlternativeByJob: [String: String] = [:]
    @State private var isLoading: Bool = false
    @State private var workingJobIds: Set<String> = []
    @State private var statusBanner: String?
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.ambientGlowBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    guard let session = appState.session else { return }
                                    try? await apiClient.retryAllFailedJobs(serverUrl: session.serverUrl, token: session.apiToken)
                                    await loadFailed()
                                    onChanged?()
                                }
                            } label: {
                                Label(isEn ? "Retry All Failed" : "Reintentar Todos", systemImage: "arrow.clockwise")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .contentShape(Capsule())
                            }
                            .kaizenGlassButton(prominent: true)
                            
                            if let onJumpToQueue {
                                Button {
                                    onJumpToQueue()
                                } label: {
                                    Label(isEn ? "View in Queue" : "Ver en Cola", systemImage: "list.bullet.rectangle")
                                        .font(.caption.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .contentShape(Capsule())
                                }
                                .kaizenGlassButton(prominent: false)
                            }
                        }
                        
                        if let banner = statusBanner {
                            Text(banner)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.cyan)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        
                        if isLoading && failedJobs.isEmpty {
                            HStack { Spacer(); ProgressView().tint(.cyan).padding(.vertical, 40); Spacer() }
                        } else if failedJobs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.green)
                                Text(isEn ? "Zero failed download jobs!" : "¡No hay descargas fallidas!")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            .padding(.vertical, 44)
                            .frame(maxWidth: .infinity)
                            .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        } else {
                            ForEach(failedJobs) { job in
                                failedJobCard(job)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isEn ? "Failed Downloads (\(failedJobs.count))" : "Fallos y Recuperación (\(failedJobs.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Close" : "Cerrar") { dismiss() }
                }
            }
            .task {
                await loadFailed()
            }
        }
    }
    
    private func failedJobCard(_ job: FailedDownloadJob) -> some View {
        let baseStr = appState.session?.serverUrl.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let coverURL = URL(string: "\(baseStr)/api/v1/mangas/\(job.mangaId)/cover")
        let altSources = availableSources.filter { $0 != job.source }
        let selectedAlt = selectedAlternativeByJob[job.id] ?? altSources.first ?? ""
        let isWorking = workingJobIds.contains(job.id)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: coverURL, token: appState.session?.apiToken, contentMode: .fill)
                    .frame(width: 56, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.mangaTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text((isEn ? "Chapter " : "Capítulo ") + String(format: "%g", job.chapterIndex) + " • \(job.source)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                    
                    Text(job.failedReason ?? (isEn ? "Download error" : "Error de descarga"))
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
            }
            
            // Selector de fuente alternativa (igual que RecoveryOptionsModal en Kaizen Web)
            if !altSources.isEmpty {
                HStack(spacing: 8) {
                    Text(isEn ? "Alternative source:" : "Fuente alternativa:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    
                    Picker("", selection: Binding(
                        get: { selectedAlt },
                        set: { selectedAlternativeByJob[job.id] = $0 }
                    )) {
                        ForEach(altSources, id: \.self) { src in
                            Text(src).tag(src)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.cyan)
                    
                    Spacer()
                }
            }
            
            HStack(spacing: 8) {
                Button {
                    Task {
                        guard let session = appState.session else { return }
                        workingJobIds.insert(job.id)
                        defer { workingJobIds.remove(job.id) }
                        try? await apiClient.retryJob(serverUrl: session.serverUrl, token: session.apiToken, jobId: job.id)
                        await loadFailed()
                        onChanged?()
                    }
                } label: {
                    Label(isEn ? "Retry" : "Reintentar", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                }
                .kaizenGlassButton(prominent: false)
                .disabled(isWorking)
                
                if !selectedAlt.isEmpty {
                    Button {
                        Task {
                            guard let session = appState.session else { return }
                            workingJobIds.insert(job.id)
                            defer { workingJobIds.remove(job.id) }
                            try? await apiClient.downloadChapterFromAlternativeSource(
                                serverUrl: session.serverUrl,
                                token: session.apiToken,
                                jobId: job.id,
                                mangaId: job.mangaId,
                                chapterIndex: job.chapterIndex,
                                newSource: selectedAlt
                            )
                            statusBanner = isEn
                                ? "Queued Ch. \(String(format: "%g", job.chapterIndex)) on \(selectedAlt)"
                                : "Cap. \(String(format: "%g", job.chapterIndex)) encolado desde \(selectedAlt)"
                            await loadFailed()
                            onChanged?()
                        }
                    } label: {
                        Label(
                            isEn ? "Download via \(selectedAlt)" : "Descargar en \(selectedAlt)",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                    }
                    .kaizenGlassButton(prominent: true)
                    .disabled(isWorking)
                }
                
                Button {
                    Task {
                        guard let session = appState.session else { return }
                        workingJobIds.insert(job.id)
                        defer { workingJobIds.remove(job.id) }
                        try? await apiClient.cancelJob(serverUrl: session.serverUrl, token: session.apiToken, jobId: job.id)
                        await loadFailed()
                        onChanged?()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                }
                .kaizenGlassButton(prominent: false)
                .disabled(isWorking)
            }
        }
        .padding(14)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private func loadFailed() async {
        guard let session = appState.session else { return }
        isLoading = true
        defer { isLoading = false }
        async let jobsTask = apiClient.fetchFailedJobs(serverUrl: session.serverUrl, token: session.apiToken)
        async let sourcesTask = apiClient.fetchAvailableSources(serverUrl: session.serverUrl, token: session.apiToken)
        if let jobs = try? await jobsTask { self.failedJobs = jobs }
        if let srcs = try? await sourcesTask { self.availableSources = srcs }
    }
}

// MARK: - Hoja 3: Historial de Capítulos CBZ Completados (`COMPLETED` KPI Bubble)

public struct CompletedDownloadsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let apiClient: KaizenAPIClient
    
    @State private var items: [KaizenServerRecentDownload] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    
    private var filteredItems: [KaizenServerRecentDownload] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.mangaTitle.localizedCaseInsensitiveContains(searchText) }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.ambientGlowBackground()
                
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if isLoading && items.isEmpty {
                            ProgressView().tint(.cyan).padding(.vertical, 40)
                        } else {
                            ForEach(filteredItems) { item in
                                HStack(spacing: 12) {
                                    RemoteImage(
                                        url: item.coverUrl.flatMap { URL(string: $0) },
                                        token: appState.session?.apiToken,
                                        contentMode: .fill
                                    )
                                    .frame(width: 44, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.mangaTitle)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        
                                        HStack(spacing: 6) {
                                            Text((isEn ? "Chapter " : "Capítulo ") + String(format: "%g", item.index))
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.cyan)
                                            if let sz = item.formattedSize {
                                                Text("• \(sz)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                }
                                .padding(12)
                                .kaizenGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .searchable(text: $searchText, prompt: isEn ? "Search downloaded chapters..." : "Buscar capítulos descargados...")
            .navigationTitle(isEn ? "Verified CBZ Downloads" : "Capítulos CBZ Verificados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Close" : "Cerrar") { dismiss() }
                }
            }
            .task {
                guard let session = appState.session else { return }
                isLoading = true
                defer { isLoading = false }
                if let list = try? await apiClient.fetchRecentServerDownloads(serverUrl: session.serverUrl, token: session.apiToken, limit: 60) {
                    self.items = list
                }
            }
        }
    }
}
