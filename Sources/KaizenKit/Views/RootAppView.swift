import SwiftUI

/// Vista raíz adaptativa para iPhone y iPad conectando todas las pantallas reales con soporte i18n reactivo
public struct RootAppView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        Group {
            if !appState.isAuthenticated {
                LoginView(apiClient: apiClient)
            } else {
                // iPhone: barra flotante · iPadOS: barra lateral colapsable (sidebarAdaptable)
                MainTabsView(apiClient: apiClient)
            }
        }
        .environment(\.locale, Locale(identifier: appState.currentLanguage))
    }
}

// MARK: - Componente Compartido: Conmutador de Idioma In-App

public struct InAppLanguageToggle: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        HStack(spacing: 2) {
            Button("ES") {
                Task { await appState.switchLanguage(to: "es", client: apiClient) }
            }
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(appState.currentLanguage == "es" ? Color.cyan : Color.clear, in: Capsule())
            .foregroundStyle(appState.currentLanguage == "es" ? Color.black : Color.white.opacity(0.8))
            
            Button("EN") {
                Task { await appState.switchLanguage(to: "en", client: apiClient) }
            }
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(appState.currentLanguage == "en" ? Color.cyan : Color.clear, in: Capsule())
            .foregroundStyle(appState.currentLanguage == "en" ? Color.black : Color.white.opacity(0.8))
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Componente Compartido: Switch instantáneo Admin ↔ Reader

public struct AdminReaderModeSwitch: View {
    @Environment(AppState.self) private var appState
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    public init() {}
    
    public var body: some View {
        if appState.isActualAdmin {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        appState.simulateReaderMode = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.caption2)
                        Text("Admin")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(!appState.simulateReaderMode ? Color.cyan : Color.clear, in: Capsule())
                    .foregroundStyle(!appState.simulateReaderMode ? Color.black : Color.secondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        appState.simulateReaderMode = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book.pages.fill")
                            .font(.caption2)
                        Text("Reader")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(appState.simulateReaderMode ? Color.green : Color.clear, in: Capsule())
                    .foregroundStyle(appState.simulateReaderMode ? Color.black : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(3)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
    }
}


// MARK: - Navegación principal adaptativa (iPhone: barra flotante · iPad: barra lateral)

struct MainTabsView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private var availableTabs: [String] {
        appState.isManagement
            ? ["reading", "library", "explore", "server"]
            : ["reading", "library", "explore"]
    }
    
    var body: some View {
        TabView(selection: Binding(
            get: { appState.selectedMainTab },
            set: { appState.selectedMainTab = $0 }
        )) {
            ReadingHomeView(apiClient: apiClient)
                .tabItem {
                    Label(isEn ? "Reading" : "Leyendo", systemImage: "book.pages.fill")
                }
                .tag("reading")
            
            LibraryView(apiClient: apiClient, mode: .personalReading)
                .tabItem {
                    Label(isEn ? "Library" : "Biblioteca", systemImage: "books.vertical.fill")
                }
                .tag("library")
            
            LibraryView(apiClient: apiClient, mode: appState.isManagement ? .unifiedCatalog : .discoverCatalog)
                .tabItem {
                    Label(isEn ? "Explore" : "Explorar", systemImage: "safari.fill")
                }
                .tag("explore")
            
            if appState.isManagement {
                ServerHubView(apiClient: apiClient)
                    .tabItem {
                        Label(isEn ? "Server" : "Servidor", systemImage: "server.rack")
                    }
                    .tag("server")
                    .badge(appState.activeDownloadCount)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 35)
                .onEnded { value in
                    handleMainTabSwipe(value: value)
                }
        )
        .onChange(of: appState.isManagement) { _, isManagement in
            if !isManagement && appState.selectedMainTab == "server" {
                appState.selectedMainTab = "reading"
            }
        }
        .task {
            await appState.refreshDownloadQueue(client: apiClient)
        }
    }
    
    // MARK: - Desplazamiento Horizontal entre Pestañas Principales (Swipe Paging)
    
    private func handleMainTabSwipe(value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height
        
        // Si estamos en server, ServerHubView gestiona su propio submenú interno
        guard appState.selectedMainTab != "server" else { return }
        
        // Reservar el borde izquierdo (< 30 pt) para el gesto nativo de navegación hacia atrás en NavigationStack
        guard value.startLocation.x > 30 else { return }
        
        // Intención clara horizontal (> 35 pt y componente horizontal mayor que vertical)
        guard abs(horizontal) > 35, abs(horizontal) > abs(vertical) * 1.2 else { return }
        
        let tabs = availableTabs
        guard let currentIndex = tabs.firstIndex(of: appState.selectedMainTab) else { return }
        
        if horizontal < 0 {
            // Deslizar hacia la izquierda -> avanzar a la siguiente pestaña (Reading -> Library -> Explore -> Server)
            let nextIndex = min(currentIndex + 1, tabs.count - 1)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                appState.selectedMainTab = tabs[nextIndex]
            }
        } else {
            // Deslizar hacia la derecha -> retroceder a la pestaña previa (Server -> Explore -> Library -> Reading)
            let prevIndex = max(currentIndex - 1, 0)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                appState.selectedMainTab = tabs[prevIndex]
            }
        }
    }
}