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
/// Diseñado para iPhone e iPad (horizontal y vertical) con submenú interactivo Liquid Glass
/// y navegación por gestos de deslizamiento horizontal (Swipe paging).
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
                // Submenú de cápsulas Liquid Glass sincronizado con el scroll horizontal
                submenuPillBar
                
                // Workstation en pantalla completa con soporte de deslizamiento táctil horizontal (Swipe)
                ZStack {
                    switch selectedSection {
                    case .status:
                        HomeDashboardView(apiClient: apiClient, isEmbedded: true)
                    case .queue:
                        LiveDownloadQueueSheet(apiClient: apiClient, isEmbedded: true)
                    case .scrapers:
                        AdminDashboardView(apiClient: apiClient, isEmbedded: true, defaultSection: .sources)
                    case .requests:
                        MangaRequestsView(apiClient: apiClient, isEmbedded: true)
                    case .operations:
                        AdminDashboardView(apiClient: apiClient, isEmbedded: true, defaultSection: .operations)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            handleSwipe(translation: value.translation)
                        }
                )
            }
            .ambientGlowBackground()
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
                                .foregroundStyle(.cyan)
                                .padding(6)
                                .background(Color.cyan.opacity(0.18), in: Circle())
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
            .navigationDestination(for: Manga.self) { manga in
                MangaDetailView(manga: manga, apiClient: apiClient)
            }
            .task {
                await appState.refreshDownloadQueue(client: apiClient)
            }
        }
    }
    
    // MARK: - Gestos de Deslizamiento Horizontal (Swipe Paging)
    
    private func handleSwipe(translation: CGSize) {
        let horizontal = translation.width
        let vertical = translation.height
        
        // Intención clara horizontal (> 35 pt y componente horizontal mayor que vertical)
        guard abs(horizontal) > 35, abs(horizontal) > abs(vertical) * 1.2 else { return }
        
        let all = ServerSection.allCases
        guard let currentIndex = all.firstIndex(of: selectedSection) else { return }
        
        if horizontal < 0 {
            // Deslizar hacia la izquierda -> avanzar sección
            let nextIndex = min(currentIndex + 1, all.count - 1)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedSection = all[nextIndex]
            }
        } else {
            // Deslizar hacia la derecha -> retroceder sección
            let prevIndex = max(currentIndex - 1, 0)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedSection = all[prevIndex]
            }
        }
    }
    
    // MARK: - Submenú de Cápsulas Liquid Glass con Auto-Scroll
    
    private var submenuPillBar: some View {
        ScrollViewReader { proxy in
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
                                        .background(isSelected ? Color.black.opacity(0.35) : Color.cyan, in: Capsule())
                                        .foregroundStyle(isSelected ? Color.white : Color.black)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.black : Color.white)
                            .overlay(
                                Capsule().stroke(
                                    LinearGradient(
                                        colors: isSelected
                                            ? [Color.white.opacity(0.55), Color.clear]
                                            : [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .id(sec)
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
            .onChange(of: selectedSection) { _, newSec in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newSec, anchor: .center)
                }
            }
        }
    }
}
