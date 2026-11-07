import SwiftUI

public enum ServerSection: String, CaseIterable, Identifiable {
    case status
    case queue
    case scrapers
    case requests
    case operations
    
    public var id: String { rawValue }
    
    public func title(isEn: Bool) -> String {
        switch self {
        case .status: return isEn ? "Status" : "Estado"
        case .queue: return isEn ? "Queue" : "Colas"
        case .scrapers: return isEn ? "Sources" : "Fuentes"
        case .requests: return isEn ? "Requests" : "Peticiones"
        case .operations: return isEn ? "Operations" : "Operaciones"
        }
    }
    
    public var icon: String {
        switch self {
        case .status: return "chart.bar.xaxis"
        case .queue: return "arrow.down.circle.fill"
        case .scrapers: return "globe.badge.chevron.backward"
        case .requests: return "tray.and.arrow.down.fill"
        case .operations: return "server.rack"
        }
    }
}

/// Centro de Control Remoto del Servidor Kaizen (Estación de trabajo en pantalla completa)
/// Diseñado para iPhone e iPad (horizontal y vertical) con submenú interactivo Liquid Glass.
public struct ServerHubView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var selectedSection: ServerSection = .status
    @State private var showAIStudio = false
    @State private var showAddMangaSheet = false
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    private var isPad: Bool { horizontalSizeClass == .regular }
    
    private func badge(for section: ServerSection) -> Int {
        switch section {
        case .queue:
            return appState.activeDownloadCount + appState.waitingDownloadCount
        default:
            return 0
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Submenú de cápsulas Liquid Glass
                submenuPillBar
                
                // Workstation en pantalla completa según sección seleccionada
                ZStack {
                    switch selectedSection {
                    case .status:
                        HomeDashboardView(apiClient: apiClient, isEmbedded: true)
                            .transition(.opacity)
                    case .queue:
                        LiveDownloadQueueSheet(apiClient: apiClient, isEmbedded: true)
                            .transition(.opacity)
                    case .scrapers:
                        AdminDashboardView(apiClient: apiClient, isEmbedded: true, defaultSection: .sources)
                            .transition(.opacity)
                    case .requests:
                        MangaRequestsView(apiClient: apiClient, isEmbedded: true)
                            .transition(.opacity)
                    case .operations:
                        AdminDashboardView(apiClient: apiClient, isEmbedded: true, defaultSection: .operations)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(isEn ? "Server Hub" : "Servidor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    InAppLanguageToggle(apiClient: apiClient)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button {
                            showAIStudio = true
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.purple)
                                .padding(6)
                                .background(Color.purple.opacity(0.18), in: Circle())
                        }
                        .accessibilityLabel("AI Studio")
                        
                        Button {
                            showAddMangaSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
                                .padding(6)
                                .background(Color(red: 0.2, green: 0.8, blue: 0.9).opacity(0.18), in: Circle())
                        }
                        .accessibilityLabel(isEn ? "Add Manga" : "Añadir Manga")
                    }
                }
            }
            .sheet(isPresented: $showAIStudio) {
                AIStudioView(apiClient: apiClient)
            }
            .sheet(isPresented: $showAddMangaSheet) {
                AddMangaRemoteSheet(apiClient: apiClient)
            }
            .task {
                await appState.refreshDownloadQueue(client: apiClient)
            }
        }
    }
    
    // MARK: - Submenú de Cápsulas Liquid Glass
    
    private var submenuPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ServerSection.allCases) { sec in
                    let isSelected = selectedSection == sec
                    let count = badge(for: sec)
                    
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedSection = sec
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: sec.icon)
                                .font(.caption.weight(.semibold))
                            Text(sec.title(isEn: isEn))
                                .font(.caption.weight(.semibold))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? Color.black.opacity(0.35) : Color(red: 0.2, green: 0.8, blue: 0.9), in: Capsule())
                                    .foregroundStyle(isSelected ? Color.white : Color.black)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? AnyShapeStyle(Color(red: 0.2, green: 0.8, blue: 0.9)) : AnyShapeStyle(.ultraThinMaterial),
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? Color.black : Color.white)
                        .overlay(
                            Capsule().stroke(isSelected ? Color.clear : Color.white.opacity(0.14), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: isPad ? .infinity : nil, alignment: isPad ? .center : .leading)
        }
        .background(Color.black.opacity(0.85))
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.08))
        }
    }
}
