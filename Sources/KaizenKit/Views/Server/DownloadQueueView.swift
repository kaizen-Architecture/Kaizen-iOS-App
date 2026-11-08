import SwiftUI

/// Cola de Descargas del Servidor (`trpc/manga.downloadQueue`) con estética Cyberpunk Liquid Glass.
public struct LiveDownloadQueueSheet: View {
    public enum QueueFilter: String, CaseIterable, Identifiable {
        case all, active, waiting, failed
        public var id: String { rawValue }
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var jobs: [DownloadQueueJob] = []
    @State private var isLoading = false
    @State private var filter: QueueFilter
    @State private var isExecutingAction = false
    @State private var selectedMangaForSources: Manga? = nil
    @State private var selectedMangaForDetail: Manga? = nil
    public var isEmbedded: Bool = false
    
    public init(apiClient: KaizenAPIClient, isEmbedded: Bool = false, initialFilter: QueueFilter = .all) {
        self.apiClient = apiClient
        self.isEmbedded = isEmbedded
        self._filter = State(initialValue: initialFilter)
    }
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    private var isPad: Bool { sizeClass == .regular }
    
    /// Excluir los capítulos ya completados de la cola de descargas
    private var nonCompletedJobs: [DownloadQueueJob] {
        jobs.filter { $0.status != "completed" }
    }
    
    private var filteredJobs: [DownloadQueueJob] {
        switch filter {
        case .all:
            return nonCompletedJobs
        case .active:
            return nonCompletedJobs.filter { $0.status == "active" }
        case .waiting:
            return nonCompletedJobs.filter { $0.status == "waiting" || $0.status == "delayed" }
        case .failed:
            return nonCompletedJobs.filter { $0.status == "failed" }
        }
    }
    
    private var activeCount: Int { nonCompletedJobs.filter { $0.status == "active" }.count }
    private var waitingCount: Int { nonCompletedJobs.filter { $0.status == "waiting" || $0.status == "delayed" }.count }
    private var failedCount: Int { nonCompletedJobs.filter { $0.status == "failed" }.count }
    
    private func title(for filter: QueueFilter) -> String {
        switch filter {
        case .all: return isEn ? "All (\(nonCompletedJobs.count))" : "Todas (\(nonCompletedJobs.count))"
        case .active: return isEn ? "Active (\(activeCount))" : "Activas (\(activeCount))"
        case .waiting: return isEn ? "Queued (\(waitingCount))" : "En cola (\(waitingCount))"
        case .failed: return isEn ? "Failed (\(failedCount))" : "Fallidas (\(failedCount))"
        }
    }
    
    public var body: some View {
        if isEmbedded {
            queueMainContent
                .refreshable { await loadQueue() }
                .task {
                    await loadQueue()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(3.5))
                        guard !Task.isCancelled else { break }
                        await loadQueue(silent: true)
                    }
                }
        } else {
            NavigationStack {
                queueMainContent
                    .ambientGlowBackground()
                    .navigationTitle(isEn ? "Download Queue" : "Cola de Descargas")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(isEn ? "Done" : "Listo") { dismiss() }
                        }
                    }
                    .refreshable { await loadQueue() }
                    .task {
                        await loadQueue()
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(3.5))
                            guard !Task.isCancelled else { break }
                            await loadQueue(silent: true)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Vista Principal en Grid de Tarjetas Liquid Glass (Mockup 1)
    
    private var queueMainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerAndActionsSection
                filterPillsRow
                
                if filteredJobs.isEmpty {
                    if isLoading && jobs.isEmpty {
                        HStack { Spacer(); ProgressView().tint(.cyan); Spacer() }
                            .padding(.vertical, 60)
                    } else {
                        ContentUnavailableView(
                            isEn ? "Queue is empty" : "Cola vacía",
                            systemImage: "arrow.down.circle",
                            description: Text(isEn ? "No downloads in this state." : "No hay descargas en este estado.")
                        )
                        .padding(.vertical, 48)
                    }
                } else {
                    let columns = isPad
                        ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                        : [GridItem(.flexible(), spacing: 14)]
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredJobs) { job in
                            jobGlassCard(job)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .sheet(item: $selectedMangaForSources) { manga in
            MangaSourcesManagementSheet(manga: manga, apiClient: apiClient) {
                Task {
                    await loadQueue()
                }
            }
        }
        .sheet(item: $selectedMangaForDetail) { manga in
            NavigationStack {
                MangaDetailView(manga: manga, apiClient: apiClient)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(isEn ? "Done" : "Listo") {
                                selectedMangaForDetail = nil
                            }
                        }
                    }
            }
        }
    }
    
    // MARK: - Cabecera con Contador y Botones Neon
    
    @ViewBuilder
    private var headerAndActionsSection: some View {
        if isPad {
            HStack(alignment: .center, spacing: 16) {
                headerTitleBlock
                Spacer()
                actionButtonsBlock
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                headerTitleBlock
                actionButtonsBlock
            }
        }
    }
    
    private var headerTitleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isEn ? "Download Queue" : "Cola de Descargas")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            
            Text(
                isEn
                    ? "\(activeCount) active · \(waitingCount) queued · \(failedCount) failed"
                    : "\(activeCount) activas · \(waitingCount) en espera · \(failedCount) fallidas"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
    
    private var actionButtonsBlock: some View {
        HStack(spacing: 10) {
            Button {
                perform { session in
                    try await apiClient.cleanQueue(serverUrl: session.serverUrl, token: session.apiToken, type: "completed")
                }
            } label: {
                Label(isEn ? "Clear completed" : "Limpiar completadas", systemImage: "trash")
                    .font(.footnote.weight(.semibold))
            }
            .kaizenGlassButton(prominent: false)
            .disabled(isExecutingAction)
            
            Button {
                perform { session in
                    try await apiClient.retryAllFailedJobs(serverUrl: session.serverUrl, token: session.apiToken)
                }
            } label: {
                Label(isEn ? "Retry failed" : "Reintentar fallidos", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.bold))
            }
            .kaizenGlassButton(prominent: true)
            .disabled(isExecutingAction)
        }
    }
    
    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QueueFilter.allCases) { f in
                    let isSelected = (filter == f)
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            filter = f
                        }
                    } label: {
                        Text(title(for: f))
                            .font(.caption.weight(isSelected ? .bold : .semibold))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? Color.black : Color.white)
                            .kaizenGlass(interactive: false, tint: isSelected ? .cyan : nil, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                }
            }
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - Tarjeta Cyberpunk Liquid Glass con Portada y Barra Neón
    
    private func jobGlassCard(_ job: DownloadQueueJob) -> some View {
        let matchedManga = appState.mangas.first(where: { $0.id == job.mangaId })
        let coverURL = matchedManga?.coverUrl.flatMap { URL(string: $0) }
        
        return HStack(alignment: .center, spacing: 14) {
            // Portada 2:3 a la izquierda
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                
                if let coverURL {
                    RemoteImage(
                        url: coverURL,
                        token: appState.session?.apiToken,
                        contentMode: .fill
                    )
                } else {
                    Image(systemName: icon(for: job.status))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(color(for: job.status))
                }
            }
            .frame(width: 72, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
            
            // Columna de información, barra neón y controles
            VStack(alignment: .leading, spacing: 7) {
                Text(job.mangaTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text((isEn ? "Ch. " : "Cap. ") + String(format: "%g", job.chapterIndex) + " · " + job.source)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                
                if job.status == "active" || job.progress > 0 {
                    HStack(spacing: 10) {
                        GeometryReader { geo in
                            let pct = CGFloat(min(max(job.progress, 6), 100)) / 100.0
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(height: 8)
                                
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.30, green: 0.96, blue: 1.0), Color.cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(geo.size.width * pct, 12), height: 8)
                                    .shadow(color: Color.cyan.opacity(0.85), radius: 6, x: 0, y: 0)
                            }
                        }
                        .frame(height: 8)
                        
                        Text("\(max(job.progress, 1))%")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 2)
                }
                
                Spacer(minLength: 0)
                
                // Fila inferior: Píldora de estado neón + botones de acción circulares
                HStack(spacing: 8) {
                    statusPill(for: job)
                    
                    Spacer(minLength: 0)
                    
                    if job.status == "failed" {
                        Button {
                            perform { session in
                                try await apiClient.retryJob(serverUrl: session.serverUrl, token: session.apiToken, jobId: job.id)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .kaizenGlass(interactive: true, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if let matchedManga {
                        Button {
                            selectedMangaForSources = matchedManga
                        } label: {
                            Image(systemName: "network")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.cyan)
                                .frame(width: 32, height: 32)
                                .kaizenGlass(interactive: true, in: Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            selectedMangaForDetail = matchedManga
                        } label: {
                            Image(systemName: "book.pages")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 32, height: 32)
                                .kaizenGlass(interactive: true, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(minHeight: 132)
        .background {
            if let coverURL {
                RemoteImage(url: coverURL, token: appState.session?.apiToken, contentMode: .fill)
                    .blur(radius: 38)
                    .opacity(0.22)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            if job.status == "failed" {
                Button {
                    perform { session in
                        try await apiClient.retryJob(serverUrl: session.serverUrl, token: session.apiToken, jobId: job.id)
                    }
                } label: {
                    Label(isEn ? "Retry download" : "Reintentar descarga", systemImage: "arrow.clockwise")
                }
            }
            if let matchedManga {
                Button {
                    selectedMangaForSources = matchedManga
                } label: {
                    Label(isEn ? "Change / Add Source" : "Cambiar / Añadir fuente", systemImage: "network")
                }
                Button {
                    selectedMangaForDetail = matchedManga
                } label: {
                    Label(isEn ? "Open Series" : "Abrir serie", systemImage: "books.vertical")
                }
            }
        }
    }
    
    @ViewBuilder
    private func statusPill(for job: DownloadQueueJob) -> some View {
        switch job.status {
        case "active":
            Text(isEn ? "Downloading" : "Descargando")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(red: 0.25, green: 0.98, blue: 0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(Color.green.opacity(0.55), lineWidth: 1))
                .shadow(color: Color.green.opacity(0.35), radius: 6)
        case "failed":
            let errText = (job.failedReason?.isEmpty == false)
                ? job.failedReason!
                : (isEn ? "Download failed" : "Error de descarga")
            Text(errText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(Color.red.opacity(0.55), lineWidth: 1))
                .shadow(color: Color.red.opacity(0.35), radius: 6)
        case "completed":
            Text(isEn ? "Completed" : "Completado")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(Color.cyan.opacity(0.45), lineWidth: 1))
        default:
            Text(isEn ? "Queued" : "En cola")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1))
        }
    }
    
    private func color(for status: String) -> Color {
        switch status {
        case "active": return .cyan
        case "waiting": return .indigo
        case "failed": return .red
        case "completed": return .green
        default: return .gray
        }
    }
    
    private func icon(for status: String) -> String {
        switch status {
        case "active": return "arrow.down"
        case "waiting": return "clock"
        case "failed": return "exclamationmark"
        case "completed": return "checkmark"
        default: return "questionmark"
        }
    }
    
    // MARK: - Datos
    
    private func perform(_ action: @escaping (UserSession) async throws -> Void) {
        guard let session = appState.session else { return }
        Task {
            isExecutingAction = true
            defer { isExecutingAction = false }
            try? await action(session)
            await loadQueue()
        }
    }
    
    private func loadQueue(silent: Bool = false) async {
        guard let session = appState.session else { return }
        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }
        if let fetched = try? await apiClient.fetchDownloadQueue(serverUrl: session.serverUrl, token: session.apiToken) {
            jobs = fetched
            appState.downloadQueueJobs = fetched
        }
    }
}
