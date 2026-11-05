import SwiftUI

/// Hoja nativa con la cola de descargas del servidor (`trpc/manga.downloadQueue`).
public struct LiveDownloadQueueSheet: View {
    private enum QueueFilter: String, CaseIterable, Identifiable {
        case all, active, waiting, failed
        var id: String { rawValue }
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var jobs: [DownloadQueueJob] = []
    @State private var isLoading = false
    @State private var filter: QueueFilter = .all
    @State private var isExecutingAction = false
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
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
        NavigationStack {
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
            .navigationTitle(isEn ? "Download queue" : "Cola de descargas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEn ? "Done" : "Listo") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
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
    
    // MARK: - Fila
    
    private func jobRow(_ job: DownloadQueueJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Button {
                    perform { session in
                        try await apiClient.retryJob(serverUrl: session.serverUrl, token: session.apiToken, jobId: job.id)
                    }
                } label: {
                    Label(isEn ? "Retry" : "Reintentar", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.vertical, 4)
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
