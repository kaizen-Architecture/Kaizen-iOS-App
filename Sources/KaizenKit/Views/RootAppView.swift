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
                    // iPadOS: Layout con barra lateral expansiva colapsable
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

// MARK: - Layout iPhone

struct iPhoneRootLayout: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    var body: some View {
        TabView {
            if appState.isManagement {
                HomeDashboardView(apiClient: apiClient)
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.xaxis")
                    }
                
                LibraryView(apiClient: apiClient, mode: .unifiedCatalog)
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
                
                AdminDashboardView(apiClient: apiClient)
                    .tabItem {
                        Label("Server Control", systemImage: "server.rack")
                    }
                
                AIStudioView(apiClient: apiClient)
                    .tabItem {
                        Label("AI Studio", systemImage: "sparkles")
                    }
                
                UserSettingsView(apiClient: apiClient)
                    .tabItem {
                        Label(isEn ? "Settings" : "Ajustes", systemImage: "gearshape.fill")
                    }
            } else {
                LibraryView(apiClient: apiClient, mode: .personalReading)
                    .tabItem {
                        Label(isEn ? "My Reading" : "Mi Lectura", systemImage: "book.pages.fill")
                    }
                
                LibraryView(apiClient: apiClient, mode: .discoverCatalog)
                    .tabItem {
                        Label(isEn ? "Discover" : "Discover", systemImage: "safari.fill")
                    }
                
                ReadingHistoryView(apiClient: apiClient)
                    .tabItem {
                        Label(isEn ? "History" : "Historial", systemImage: "clock.arrow.circlepath")
                    }
                
                MangaRequestsView(apiClient: apiClient)
                    .tabItem {
                        Label(isEn ? "Requests" : "Peticiones", systemImage: "hand.raised.fill")
                    }
                
                UserSettingsView(apiClient: apiClient)
                    .tabItem {
                        Label(isEn ? "Settings" : "Ajustes", systemImage: "gearshape.fill")
                    }
            }
        }
    }
}

// MARK: - Layout iPadOS

struct iPadRootLayout: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    @State private var selectedTab: String? = "dashboard"
    @State private var showLiveQueueSheet = false
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                if appState.isActualAdmin {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(isEn ? "View Mode" : "Modo de Vista")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if appState.simulateReaderMode {
                                    Text(isEn ? "Inspecting Reader" : "Probando Reader")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.green)
                                }
                            }
                            AdminReaderModeSwitch()
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                if appState.isManagement {
                    Section(isEn ? "Kaizen Remote" : "Kaizen Remoto") {
                        Label(isEn ? "Kaizen Dashboard" : "Dashboard Kaizen", systemImage: "chart.bar.xaxis")
                            .tag("dashboard")
                        Label(isEn ? "Library" : "Biblioteca", systemImage: "books.vertical.fill")
                            .tag("library")
                        Label(isEn ? "History" : "Historial", systemImage: "clock.arrow.circlepath")
                            .tag("history")
                        Label(isEn ? "Requests" : "Peticiones", systemImage: "tray.and.arrow.down.fill")
                            .tag("requests")
                    }
                    
                    Section(isEn ? "Administration" : "Administración") {
                        Label("Server Control", systemImage: "server.rack")
                            .tag("admin")
                        Label("AI Studio", systemImage: "sparkles")
                            .tag("ai_studio")
                    }
                } else {
                    Section(isEn ? "Reading & Catalog" : "Lectura y Catálogo") {
                        Label(isEn ? "My Reading" : "Mi Lectura", systemImage: "book.pages.fill")
                            .tag("reading")
                        Label("Discover", systemImage: "safari.fill")
                            .tag("discover")
                        Label(isEn ? "History" : "Historial", systemImage: "clock.arrow.circlepath")
                            .tag("history")
                        Label(isEn ? "Requests" : "Peticiones", systemImage: "hand.raised.fill")
                            .tag("requests")
                    }
                }
                
                Section(isEn ? "Downloads" : "Descargas") {
                    Button {
                        showLiveQueueSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: appState.activeDownloadCount > 0 ? "arrow.down.circle.dotted" : "arrow.down.circle")
                                .foregroundStyle(appState.activeDownloadCount > 0 ? .cyan : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isEn ? "Download Queue" : "Cola de Descarga")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                Text(
                                    appState.activeDownloadCount > 0 || appState.waitingDownloadCount > 0
                                    ? "\(appState.activeDownloadCount) act · \(appState.waitingDownloadCount) " + (isEn ? "queued" : "en cola")
                                    : (isEn ? "View live status" : "Ver estado en vivo")
                                )
                                .font(.caption2)
                                .foregroundStyle(appState.activeDownloadCount > 0 ? .cyan : .secondary)
                            }
                            Spacer()
                            if appState.activeDownloadCount > 0 {
                                Text("\(appState.activeDownloadCount)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                }
                
                Section(isEn ? "User & Settings" : "Usuario y Ajustes") {
                    Label(isEn ? "User Settings" : "Ajustes de Usuario", systemImage: "gearshape.fill")
                        .tag("settings")
                }
            }
            .navigationTitle("Kaizen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("KaizenLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    InAppLanguageToggle(apiClient: apiClient)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    if let user = appState.session {
                        HStack(spacing: 10) {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .foregroundStyle(appState.simulateReaderMode ? .green : .cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.username)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(appState.simulateReaderMode ? "\(user.role.rawValue) (Reader UI)" : user.role.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(appState.simulateReaderMode ? .green : .secondary)
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
            case "dashboard":
                if appState.isManagement {
                    HomeDashboardView(apiClient: apiClient)
                } else {
                    LibraryView(apiClient: apiClient, mode: .personalReading)
                }
            case "library":
                if appState.isManagement {
                    LibraryView(apiClient: apiClient, mode: .unifiedCatalog)
                } else {
                    LibraryView(apiClient: apiClient, mode: .personalReading)
                }
            case "reading":
                LibraryView(apiClient: apiClient, mode: .personalReading)
            case "discover":
                LibraryView(apiClient: apiClient, mode: .discoverCatalog)
            case "history":
                ReadingHistoryView(apiClient: apiClient)
            case "requests":
                MangaRequestsView(apiClient: apiClient)
            case "admin":
                if appState.isManagement {
                    AdminDashboardView(apiClient: apiClient)
                } else {
                    LibraryView(apiClient: apiClient, mode: .personalReading)
                }
            case "ai_studio":
                if appState.isManagement {
                    AIStudioView(apiClient: apiClient)
                } else {
                    LibraryView(apiClient: apiClient, mode: .personalReading)
                }
            case "settings":
                UserSettingsView(apiClient: apiClient)
            default:
                if appState.isManagement {
                    HomeDashboardView(apiClient: apiClient)
                } else {
                    LibraryView(apiClient: apiClient, mode: .personalReading)
                }
            }
        }
        .onAppear {
            syncDefaultTabForMode(isManagement: appState.isManagement)
        }
        .onChange(of: appState.isManagement) { _, newValue in
            syncDefaultTabForMode(isManagement: newValue)
        }
        .task {
            await appState.refreshDownloadQueue(client: apiClient)
        }
        .sheet(isPresented: $showLiveQueueSheet) {
            LiveDownloadQueueSheet(apiClient: apiClient)
        }
    }
    
    private func syncDefaultTabForMode(isManagement: Bool) {
        if isManagement {
            if selectedTab == nil || selectedTab == "reading" || selectedTab == "discover" {
                selectedTab = "dashboard"
            }
        } else {
            if selectedTab == nil || selectedTab == "dashboard" || selectedTab == "library" || selectedTab == "admin" || selectedTab == "ai_studio" {
                selectedTab = "reading"
            }
        }
    }
}
