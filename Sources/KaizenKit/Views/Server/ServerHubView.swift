import SwiftUI

/// Pestaña "Servidor" (solo gestión): estado resumido y accesos al resto de herramientas de administración.
public struct ServerHubView: View {
    private enum Destination: String, Identifiable {
        case dashboard, operations, queue, requests, aiStudio
        var id: String { rawValue }
    }
    
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var destination: Destination?
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        summaryCard(
                            title: isEn ? "Downloading" : "Descargando",
                            value: "\(appState.activeDownloadCount)",
                            caption: "\(appState.waitingDownloadCount) " + (isEn ? "queued" : "en cola"),
                            tint: .cyan
                        )
                        summaryCard(
                            title: isEn ? "Series" : "Series",
                            value: "\(appState.mangas.count)",
                            caption: isEn ? "in library" : "en biblioteca",
                            tint: .white
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text((appState.session?.serverUrl.host() ?? "Kaizen") + " · " + (isEn ? "Online" : "En línea"))
                    }
                    .textCase(nil)
                    .font(.footnote.weight(.semibold))
                }
                
                Section(isEn ? "Monitor" : "Monitorizar") {
                    row(.queue, icon: "arrow.down.circle.fill", tint: .cyan,
                        title: isEn ? "Live download queue" : "Cola de descargas",
                        subtitle: isEn ? "Active, queued and failed jobs" : "Activas, en cola y fallidas")
                    row(.dashboard, icon: "chart.bar.xaxis", tint: .indigo,
                        title: isEn ? "Statistics" : "Estadísticas",
                        subtitle: isEn ? "14-day activity and storage" : "Actividad 14 días y espacio")
                }
                
                Section(isEn ? "Manage" : "Gestionar") {
                    row(.operations, icon: "server.rack", tint: .teal,
                        title: isEn ? "Operations & sources" : "Operaciones y fuentes",
                        subtitle: isEn ? "Sync, scrapers, failures" : "Sincronizar, scrapers, fallos")
                    row(.requests, icon: "tray.and.arrow.down.fill", tint: .orange,
                        title: isEn ? "Requests" : "Peticiones",
                        subtitle: isEn ? "Approve or reject user requests" : "Aprobar o rechazar peticiones")
                    row(.aiStudio, icon: "sparkles", tint: .purple,
                        title: "AI Studio",
                        subtitle: isEn ? "Assistant tools" : "Herramientas del asistente")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(isEn ? "Server" : "Servidor")
            .task { await appState.refreshDownloadQueue(client: apiClient) }
            .refreshable { await appState.refreshDownloadQueue(client: apiClient) }
            .sheet(item: $destination) { item in
                switch item {
                case .dashboard: HomeDashboardView(apiClient: apiClient)
                case .operations: AdminDashboardView(apiClient: apiClient)
                case .queue: LiveDownloadQueueSheet(apiClient: apiClient)
                case .requests: MangaRequestsView(apiClient: apiClient)
                case .aiStudio: AIStudioView(apiClient: apiClient)
                }
            }
        }
    }
    
    private func summaryCard(title: String, value: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    private func row(_ target: Destination, icon: String, tint: Color, title: String, subtitle: String) -> some View {
        Button {
            destination = target
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.white)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
