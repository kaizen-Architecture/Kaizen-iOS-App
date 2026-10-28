import SwiftUI

@MainActor
@Observable
public final class AdminStore {
    public var queuesResponse: QueuesResponse?
    public var isLoading: Bool = false
    public var isSyncingAll: Bool = false
    public var errorMessage: String?
    public var successMessage: String?
    
    public init() {}
    
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
    
    public func syncAll(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        isSyncingAll = true
        errorMessage = nil
        successMessage = nil
        defer { isSyncingAll = false }
        
        do {
            try await apiClient.syncAllMangas(serverUrl: session.serverUrl, token: session.apiToken)
            successMessage = "¡Comprobación de capítulos lanzada en todas las series!"
            await loadMetrics(apiClient: apiClient, session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct AdminDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var store = AdminStore()
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header de Estado
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Servidor Kaizen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(appState.session?.serverUrl.host ?? "Conectado")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            Label("En línea", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        }
                        .padding(.horizontal)
                        
                        // Resumen de BullMQ
                        if let summary = store.queuesResponse?.summary {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                metricCard(title: "Trabajos Activos", value: "\(summary.totalActive)", icon: "play.circle.fill", color: .cyan)
                                metricCard(title: "En Espera", value: "\(summary.totalWaiting)", icon: "clock.fill", color: .blue)
                                metricCard(title: "Retrasados", value: "\(summary.totalDelayed)", icon: "hourglass", color: .orange)
                                metricCard(title: "Fallidos", value: "\(summary.totalFailed)", icon: "xmark.octagon.fill", color: summary.totalFailed > 0 ? .red : .green)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Acciones de administración
                        VStack(spacing: 10) {
                            Button {
                                Task { await store.syncAll(apiClient: apiClient, session: appState.session) }
                            } label: {
                                HStack {
                                    if store.isSyncingAll {
                                        ProgressView().tint(.black)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("Comprobar nuevos capítulos (Sync All)")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                            }
                            .disabled(store.isSyncingAll)
                            
                            if let success = store.successMessage {
                                Text(success)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if let error = store.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Detalle de las 10 colas BullMQ del servidor
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Colas de Trabajo del Sistema (BullMQ)")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal)
                            
                            if store.isLoading && store.queuesResponse == nil {
                                HStack {
                                    Spacer()
                                    ProgressView().tint(.cyan)
                                    Spacer()
                                }
                                .padding(.vertical, 20)
                            } else if let queues = store.queuesResponse?.queues {
                                VStack(spacing: 8) {
                                    ForEach(queues) { queue in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(queue.label)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                Text(queue.name)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            
                                            HStack(spacing: 8) {
                                                if queue.active > 0 {
                                                    badge(count: queue.active, color: .cyan, label: "act")
                                                }
                                                if queue.waiting > 0 {
                                                    badge(count: queue.waiting, color: .blue, label: "esp")
                                                }
                                                if queue.failed > 0 {
                                                    badge(count: queue.failed, color: .red, label: "fall")
                                                }
                                                if queue.active == 0 && queue.waiting == 0 && queue.failed == 0 {
                                                    Text("Inactiva")
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
                    .padding(.vertical, 16)
                }
                .refreshable {
                    await store.loadMetrics(apiClient: apiClient, session: appState.session)
                }
            }
            .navigationTitle(String(localized: "tab_admin"))
            .task {
                await store.loadMetrics(apiClient: apiClient, session: appState.session)
            }
        }
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
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
