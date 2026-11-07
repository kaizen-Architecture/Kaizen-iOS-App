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
    
    public var isEmbedded: Bool = false
    
    public init(apiClient: KaizenAPIClient, isEmbedded: Bool = false) {
        self.apiClient = apiClient
        self.isEmbedded = isEmbedded
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
        if isEmbedded {
            dashboardScrollContent
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
        } else {
            NavigationStack {
                dashboardScrollContent
                    .navigationTitle(isEn ? "Statistics" : "Estadísticas")
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
                        LiveDownloadQueueSheet(apiClient: apiClient, initialFilter: queueInitialFilter)
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
        }
    }
    
    private var dashboardScrollContent: some View {
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
        }
    }
    
    // MARK: - 1. Cinco Tarjetas KPI (trpc/manga.activity)
    
    private var kpiCardsGrid: some View {
        let columns = isPad
            ? Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        
        return LazyVGrid(columns: columns, spacing: 10) {
            Button {
                queueInitialFilter = .active
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
                queueInitialFilter = .waiting
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
                queueInitialFilter = .failed
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
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        recentDownloadItemView(item)
                    }
                }
            }
        }
        .padding(15)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
