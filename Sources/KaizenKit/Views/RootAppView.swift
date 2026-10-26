import SwiftUI

/// Vista raíz adaptativa para iPhone y iPad conectando todas las pantallas reales
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

// MARK: - Layout iPhone

struct iPhoneRootLayout: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    var body: some View {
        TabView {
            Tab(String(localized: "tab_home"), systemImage: "house.fill") {
                LibraryView(apiClient: apiClient)
            }
            
            Tab(String(localized: "tab_library"), systemImage: "books.vertical.fill") {
                LibraryView(apiClient: apiClient)
            }
            
            Tab(String(localized: "tab_requests"), systemImage: "tray.and.arrow.down.fill") {
                MangaRequestsView(apiClient: apiClient)
            }
            
            // Pestañas exclusivas de Administrador / Manager
            if appState.isManagement {
                Tab(String(localized: "tab_admin"), systemImage: "server.rack") {
                    AdminDashboardView(apiClient: apiClient)
                }
                
                Tab(String(localized: "tab_ai_studio"), systemImage: "sparkles") {
                    AIStudioView(apiClient: apiClient)
                }
            }
            
            Tab(String(localized: "tab_settings"), systemImage: "gearshape.fill") {
                UserSettingsView(apiClient: apiClient)
            }
        }
    }
}

// MARK: - Layout iPadOS

struct iPadRootLayout: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    @State private var selectedTab: String? = "library"
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    Label(String(localized: "tab_home"), systemImage: "house.fill").tag("home")
                    Label(String(localized: "tab_library"), systemImage: "books.vertical.fill").tag("library")
                    Label(String(localized: "tab_requests"), systemImage: "tray.and.arrow.down.fill").tag("requests")
                }
                
                if appState.isManagement {
                    Section(String(localized: "tab_admin")) {
                        Label(String(localized: "tab_admin"), systemImage: "server.rack").tag("admin")
                        Label(String(localized: "tab_ai_studio"), systemImage: "sparkles").tag("ai_studio")
                    }
                }
                
                Section {
                    Label(String(localized: "tab_settings"), systemImage: "gearshape.fill").tag("settings")
                }
            }
            .navigationTitle("Kaizen")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    if let user = appState.session {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.username)
                                    .font(.caption.weight(.semibold))
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
            case "library", "home":
                LibraryView(apiClient: apiClient)
            case "requests":
                MangaRequestsView(apiClient: apiClient)
            case "admin":
                AdminDashboardView(apiClient: apiClient)
            case "ai_studio":
                AIStudioView(apiClient: apiClient)
            case "settings":
                UserSettingsView(apiClient: apiClient)
            default:
                LibraryView(apiClient: apiClient)
            }
        }
    }
}
