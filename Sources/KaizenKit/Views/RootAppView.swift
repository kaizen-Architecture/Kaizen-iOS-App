import SwiftUI

/// Vista raíz adaptativa para iPhone y iPad conectando todas las pantallas reales con soporte i18n reactivo
public struct RootAppView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                if horizontalSizeClass == .regular {
                    // iPadOS: Layout con barra lateral expansiva
                    iPadRootLayout(apiClient: apiClient)
                } else {
                    // iPhone: Layout compacto con TabView
                    iPhoneRootLayout(apiClient: apiClient)
                }
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

// MARK: - Layout iPhone

struct iPhoneRootLayout: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    var body: some View {
        TabView {
            HomeDashboardView(apiClient: apiClient)
                .tabItem {
                    Label(isEn ? "Home" : "Inicio", systemImage: "house.fill")
                }
            
            LibraryView(apiClient: apiClient)
                .tabItem {
                    Label(isEn ? "Library" : "Biblioteca", systemImage: "books.vertical.fill")
                }
            
            ReadingHistoryView(apiClient: apiClient)
                .tabItem {
                    Label(isEn ? "History" : "Historial", systemImage: "clock.arrow.circlepath")
                }
            
            MangaRequestsView(apiClient: apiClient)
                .tabItem {
                    Label(isEn ? "Requests" : "Peticiones", systemImage: "tray.and.arrow.down.fill")
                }
            
            if appState.isManagement {
                AdminDashboardView(apiClient: apiClient)
                    .tabItem {
                        Label(isEn ? "Control" : "Administración", systemImage: "server.rack")
                    }
                
                AIStudioView(apiClient: apiClient)
                    .tabItem {
                        Label("AI Studio", systemImage: "sparkles")
                    }
            }
            
            UserSettingsView(apiClient: apiClient)
                .tabItem {
                    Label(isEn ? "Settings" : "Ajustes", systemImage: "gearshape.fill")
                }
        }
    }
}

// MARK: - Layout iPadOS

struct iPadRootLayout: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    @State private var selectedTab: String? = "home"
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    Label(isEn ? "Home" : "Inicio", systemImage: "house.fill").tag("home")
                    Label(isEn ? "Library" : "Biblioteca", systemImage: "books.vertical.fill").tag("library")
                    Label(isEn ? "History" : "Historial", systemImage: "clock.arrow.circlepath").tag("history")
                    Label(isEn ? "Requests" : "Peticiones", systemImage: "tray.and.arrow.down.fill").tag("requests")
                }
                
                if appState.isManagement {
                    Section(isEn ? "Administration" : "Administración") {
                        Label(isEn ? "Server Control" : "Control Remoto", systemImage: "server.rack").tag("admin")
                        Label("AI Studio", systemImage: "sparkles").tag("ai_studio")
                    }
                }
                
                Section {
                    Label(isEn ? "Settings" : "Ajustes", systemImage: "gearshape.fill").tag("settings")
                }
            }
            .navigationTitle("Kaizen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    InAppLanguageToggle(apiClient: apiClient)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    if let user = appState.session {
                        HStack(spacing: 10) {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.username)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(user.role.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            
                            Button(action: { appState.logout() }) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        } detail: {
            switch selectedTab {
            case "home":
                HomeDashboardView(apiClient: apiClient)
            case "library":
                LibraryView(apiClient: apiClient)
            case "history":
                ReadingHistoryView(apiClient: apiClient)
            case "requests":
                MangaRequestsView(apiClient: apiClient)
            case "admin":
                if appState.isManagement {
                    AdminDashboardView(apiClient: apiClient)
                } else {
                    HomeDashboardView(apiClient: apiClient)
                }
            case "ai_studio":
                if appState.isManagement {
                    AIStudioView(apiClient: apiClient)
                } else {
                    HomeDashboardView(apiClient: apiClient)
                }
            case "settings":
                UserSettingsView(apiClient: apiClient)
            default:
                HomeDashboardView(apiClient: apiClient)
            }
        }
    }
}
