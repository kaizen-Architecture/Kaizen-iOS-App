import SwiftUI

/// Hoja nativa con la cola de descargas del servidor (`trpc/manga.downloadQueue`).
public struct LiveDownloadQueueSheet: View {
    public enum QueueFilter: String, CaseIterable, Identifiable {
        case all, active, waiting, failed
        public var id: String { rawValue }
    }
    
    @Environment(\.dismiss) private var dismiss
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
    
    private var filteredJobs: [DownloadQueueJob] {
        filter == .all ? jobs : jobs.filter { $0.status == filter.rawValue }
    }
    
    private var failedCount: Int { jobs.filter { $0.status == "failed" }.count }
    
    private func title(for filter: QueueFilter) -> String {
        switch filter {
        case .all: return isEn ? "All" : "Todas"
        case .active: return isEn ? "Active" : "Activas"
        case .waiting: return isEn ? "Queued" : "En cola"
        case .failed: return isEn ? "Failed" : "Fallidas"
        }
    }
    
    public var body: some View {
        if isEmbedded {
            queueList
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
                queueList
                    .navigationTitle(isEn ? "Download queue" : "Cola de descargas")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(isEn ? "Done" : "Listo") { dismiss() }
                        }
                        ToolbarItemGroup(placement: .bottomBar) {
                            queueActionButtons
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
    
    @ViewBuilder
    private var queueActionButtons: some View {
        Button {
            perform { session in
                try await apiClient.retryAllFailedJobs(serverUrl: session.serverUrl, token: session.apiToken)
            }
        } label: {
            Label(isEn ? "Retry failed" : "Reintentar fallidas", systemImage: "arrow.clockwise")
        }
        .disabled(isExecutingAction || failedCount == 0)
        
        Spacer()
        
        Button {
            perform { session in
                try await apiClient.cleanQueue(serverUrl: session.serverUrl, token: session.apiToken, type: "completed")
            }
        } label: {
            Label(isEn ? "Clear completed" : "Limpiar completadas", systemImage: "trash")
        }
        .disabled(isExecutingAction)
    }
    
    private var queueList: some View {
        List {
            Section {
                Picker("", selection: $filter) {
                    ForEach(QueueFilter.allCases) { f in
                        Text(title(for: f)).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            
            if isEmbedded {
                Section {
                    HStack(spacing: 12) {
                        Button {
                            perform { session in
                                try await apiClient.retryAllFailedJobs(serverUrl: session.serverUrl, token: session.apiToken)
                            }
                        } label: {
                            Label(isEn ? "Retry failed" : "Reintentar fallidas", systemImage: "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.glass)
                        .disabled(isExecutingAction || failedCount == 0)
                        
                        Button {
                            perform { session in
                                try await apiClient.cleanQueue(serverUrl: session.serverUrl, token: session.apiToken, type: "completed")
                            }
                        } label: {
                            Label(isEn ? "Clear completed" : "Limpiar completadas", systemImage: "trash")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.glass)
                        .disabled(isExecutingAction)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }
            
            if filteredJobs.isEmpty {
                if isLoading && jobs.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView(
                        isEn ? "Queue is empty" : "Cola vacía",
                        systemImage: "arrow.down.circle",
                        description: Text(isEn ? "No downloads in this state." : "No hay descargas en este estado.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(filteredJobs) { job in
                        jobRow(job)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
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
    
    // MARK: - Fila
    
    private func jobRow(_ job: DownloadQueueJob) -> some View {
        let matchedManga = appState.mangas.first(where: { $0.id == job.mangaId })
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon(for: job.status))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(color(for: job.status).gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.mangaTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text((isEn ? "Ch. " : "Cap. ") + String(format: "%g", job.chapterIndex) + " · " + job.source)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(label(for: job))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color(for: job.status))
            }
            
            if job.status == "active" {
                ProgressView(value: Double(min(max(job.progress, 3), 100)), total: 100)
                    .tint(.cyan)
            }
            
            if job.status == "failed" {
                if let reason = job.failedReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    Button {
                        perform { session in
                            try await apiClient.retryJob(serverUrl: session.serverUrl, token: session.apiToken, jobId: job.id)
                        }
                    } label: {
                        Label(isEn ? "Retry" : "Reintentar", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    
                    if let matchedManga {
                        Button {
                            selectedMangaForSources = matchedManga
                        } label: {
                            Label(isEn ? "Sources" : "Fuentes", systemImage: "network")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        
                        Button {
                            selectedMangaForDetail = matchedManga
                        } label: {
                            Label(isEn ? "Series" : "Serie", systemImage: "book.pages")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
    
    private func label(for job: DownloadQueueJob) -> String {
        switch job.status {
        case "active": return job.progress > 0 ? "\(job.progress)%" : (isEn ? "Downloading" : "Descargando")
        case "waiting": return isEn ? "Queued" : "En cola"
        case "failed": return isEn ? "Failed" : "Fallido"
        case "completed": return isEn ? "Done" : "Completado"
        default: return job.status.capitalized
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
