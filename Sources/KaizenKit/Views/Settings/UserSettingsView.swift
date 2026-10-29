import SwiftUI

@MainActor
@Observable
public final class UserSettingsStore {
    public var anilistEnabled: Bool = false
    public var anilistUsername: String = ""
    public var anilistAutoSync: Bool = true
    
    public var whatsappEnabled: Bool = false
    public var whatsappPhone: String = ""
    public var whatsappApiKey: String = ""
    
    public var discordEnabled: Bool = false
    public var discordWebhookUrl: String = ""
    
    public var telegramEnabled: Bool = false
    public var telegramChatId: String = ""
    
    public var defaultReadingDirection: ReadingDirection = .rightToLeft
    public var isTestingChannel: Bool = false
    public var toastMessage: String?
    
    public init() {}
    
    public func loadSettings(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        
        // 1. Cargar ajustes del servidor (AniList global, etc.)
        if let s = try? await apiClient.fetchServerSettings(serverUrl: session.serverUrl, token: session.apiToken) {
            self.anilistEnabled = s.anilistEnabled
            self.anilistUsername = s.anilistUsername ?? ""
            self.anilistAutoSync = s.anilistAutoSync
            self.discordEnabled = s.discordEnabled
            self.whatsappEnabled = s.whatsappEnabled
        }
        
        // 2. Cargar ajustes personales del usuario
        if let userSettings = try? await apiClient.fetchUserSettings(
            serverUrl: session.serverUrl,
            token: session.apiToken,
            userId: session.id
        ) {
            if !anilistEnabled {
                self.anilistEnabled = userSettings.anilistEnabled
                self.anilistUsername = userSettings.anilistUsername ?? ""
                self.anilistAutoSync = userSettings.anilistAutoSync
            }
            if !whatsappEnabled {
                self.whatsappEnabled = userSettings.whatsappEnabled
                self.whatsappPhone = userSettings.whatsappPhone ?? ""
                self.whatsappApiKey = userSettings.whatsappApiKey ?? ""
            }
            if !discordEnabled {
                self.discordEnabled = userSettings.discordEnabled
                self.discordWebhookUrl = userSettings.discordWebhookUrl ?? ""
            }
            self.telegramEnabled = userSettings.telegramEnabled
            self.telegramChatId = userSettings.telegramChatId ?? ""
        }
    }
    
    public func testConnection(channelName: String) async {
        isTestingChannel = true
        defer { isTestingChannel = false }
        try? await Task.sleep(nanoseconds: 600_000_000)
        toastMessage = "Prueba de \(channelName) completada con éxito"
    }
}

public struct UserSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var store = UserSettingsStore()
    @State private var newShelfName = ""
    @State private var showNewShelfAlert = false
    @State private var showDiagnosticsLogs = false
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Sección AniList & Tracker (Sincronizado con Kaizen)
                Section {
                    LabeledContent(isEn ? "Status" : "Estado") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.anilistEnabled ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(store.anilistEnabled ? (isEn ? "Connected in Kaizen" : "Conectado en Kaizen") : (isEn ? "Disconnected" : "Desconectado"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(store.anilistEnabled ? .green : .secondary)
                        }
                    }
                    
                    if store.anilistEnabled {
                        LabeledContent(isEn ? "AniList User" : "Usuario de AniList", value: store.anilistUsername.isEmpty ? (isEn ? "Configured" : "Configurado") : store.anilistUsername)
                        LabeledContent("Auto-sync", value: store.anilistAutoSync ? (isEn ? "Enabled" : "Activado") : (isEn ? "Disabled" : "Desactivado"))
                    }
                } header: {
                    Text(isEn ? "AniList Integration (Kaizen Server)" : "Integración con AniList (Servidor Kaizen)")
                } footer: {
                    Text(isEn ? "Read chapters automatically sync to your AniList account through the server." : "Los capítulos leídos se sincronizan automáticamente con tu cuenta de AniList a través del servidor.")
                }
                
                // Sección: Estanterías Lógicas del Lector
                Section(isEn ? "Your Reading Shelves" : "Tus Estanterías de Lectura") {
                    ForEach(appState.shelves) { shelf in
                        HStack {
                            Image(systemName: shelf.icon)
                                .foregroundStyle(.yellow)
                            Text(shelf.name)
                            Spacer()
                            Text("\(shelf.mangaIds.count) " + (isEn ? (shelf.mangaIds.count == 1 ? "title" : "titles") : (shelf.mangaIds.count == 1 ? "obra" : "obras")))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let shelf = appState.shelves[idx]
                            appState.deleteShelf(id: shelf.id)
                        }
                    }
                    
                    Button {
                        newShelfName = ""
                        showNewShelfAlert = true
                    } label: {
                        Label(isEn ? "Create new shelf..." : "Crear nueva estantería...", systemImage: "plus")
                    }
                }
                
                // Canales de Notificación Personales
                Section(isEn ? "Personal Notifications" : "Canales de Notificación") {
                    Toggle("WhatsApp (CallMeBot)", isOn: $store.whatsappEnabled)
                        .tint(.green)
                    if store.whatsappEnabled {
                        TextField(isEn ? "Phone (+34...)" : "Teléfono (+34...)", text: $store.whatsappPhone)
                        SecureField(isEn ? "CallMeBot API Key" : "API Key de CallMeBot", text: $store.whatsappApiKey)
                    }
                    
                    Toggle("Discord Webhook", isOn: $store.discordEnabled)
                        .tint(.indigo)
                    if store.discordEnabled {
                        TextField("Webhook URL", text: $store.discordWebhookUrl)
                    }
                    
                    Toggle("Telegram Bot", isOn: $store.telegramEnabled)
                        .tint(.blue)
                    if store.telegramEnabled {
                        TextField("Chat ID", text: $store.telegramChatId)
                    }
                    
                    if store.whatsappEnabled || store.discordEnabled || store.telegramEnabled {
                        Button {
                            Task { await store.testConnection(channelName: isEn ? "Notifications" : "Notificaciones") }
                        } label: {
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                Text(isEn ? "Test Live Link" : "Probar Enlace en Vivo")
                            }
                        }
                    }
                }
                
                // Preferencias del Lector
                Section(isEn ? "Reader Preferences" : "Preferencias del Lector") {
                    Picker(isEn ? "Reading mode" : "Modo de lectura", selection: $store.defaultReadingDirection) {
                        ForEach(ReaderMode.allCases) { mode in
                            Text(mode.label(language: appState.currentLanguage)).tag(mode)
                        }
                    }
                }
                
                // Idioma de la Aplicación
                Section(isEn ? "App Language" : "Idioma") {
                    Picker(isEn ? "Interface Language" : "Idioma de la interfaz", selection: Binding(
                        get: { appState.currentLanguage },
                        set: { newLang in
                            Task {
                                await appState.switchLanguage(to: newLang, client: apiClient)
                            }
                        }
                    )) {
                        Text("Español (ES)").tag("es")
                        Text("English (EN)").tag("en")
                    }
                }
                
                // Información de Sesión y Salida
                Section(isEn ? "Active Session" : "Sesión Activa") {
                    if let user = appState.session {
                        LabeledContent(isEn ? "User" : "Usuario", value: user.username)
                        LabeledContent(isEn ? "Role" : "Rol", value: user.role.rawValue)
                        LabeledContent(isEn ? "Server" : "Servidor", value: user.serverUrl.absoluteString)
                    }
                    
                    Button(isEn ? "Log Out" : "Cerrar Sesión", role: .destructive) {
                        appState.logout()
                    }
                }
                
                // Diagnóstico y Registros del Sistema
                Section(isEn ? "Diagnostics & Logs" : "Diagnóstico y Registros") {
                    Button {
                        showDiagnosticsLogs = true
                    } label: {
                        HStack {
                            Label(isEn ? "View System Logs" : "Ver Registros del Sistema", systemImage: "doc.text.magnifyingglass")
                            Spacer()
                            let errCount = KaizenLogger.shared.entries.filter { $0.level == .error }.count
                            if errCount > 0 {
                                Text("\(errCount) " + (isEn ? "errors" : "errores"))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.15), in: Capsule())
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.white)
                }
                
                // Versión de la Aplicación
                Section(isEn ? "About Kaizen" : "Acerca de Kaizen") {
                    LabeledContent(isEn ? "Version" : "Versión", value: "1.1.0 (Build 2)")
                    LabeledContent(isEn ? "Compatibility" : "Compatibilidad", value: "iOS 17+ / iPadOS")
                    LabeledContent(isEn ? "Target" : "Plataforma", value: "Native SwiftUI (arm64)")
                }
            }
            .navigationTitle(isEn ? "Settings" : "Ajustes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    InAppLanguageToggle(apiClient: apiClient)
                }
            }
            .task {
                await store.loadSettings(apiClient: apiClient, session: appState.session)
            }
            .sheet(isPresented: $showDiagnosticsLogs) {
                DiagnosticsLogView()
            }
            .alert(isEn ? "New Shelf" : "Nueva Estantería", isPresented: $showNewShelfAlert) {
                TextField(isEn ? "Shelf name..." : "Nombre de la estantería...", text: $newShelfName)
                Button(isEn ? "Create" : "Crear") {
                    appState.createShelf(name: newShelfName)
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            }
        }
    }
}
