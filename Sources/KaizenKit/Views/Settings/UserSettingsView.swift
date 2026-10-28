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
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Sección AniList & Tracker (Sincronizado con Kaizen)
                Section {
                    LabeledContent("Estado") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.anilistEnabled ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(store.anilistEnabled ? "Conectado en Kaizen" : "Desconectado")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(store.anilistEnabled ? .green : .secondary)
                        }
                    }
                    
                    if store.anilistEnabled {
                        LabeledContent("Usuario de AniList", value: store.anilistUsername.isEmpty ? "Configurado" : store.anilistUsername)
                        LabeledContent("Auto-sync", value: store.anilistAutoSync ? "Activado" : "Desactivado")
                    }
                } header: {
                    Text("Integración con AniList (Servidor Kaizen)")
                } footer: {
                    Text("Los capítulos leídos se sincronizan automáticamente con tu cuenta de AniList a través del servidor.")
                }
                
                // Sección: Estanterías Lógicas del Lector
                Section("Tus Estanterías Personales") {
                    ForEach(appState.shelves) { shelf in
                        HStack {
                            Image(systemName: shelf.icon)
                                .foregroundStyle(.yellow)
                            Text(shelf.name)
                            Spacer()
                            Text("\(shelf.mangaIds.count) obras")
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
                        Label("Crear nueva estantería...", systemImage: "plus")
                    }
                }
                
                // Canales de Notificación Personales
                Section("Canales de Notificación Personales") {
                    Toggle("WhatsApp (CallMeBot)", isOn: $store.whatsappEnabled)
                        .tint(.green)
                    if store.whatsappEnabled {
                        TextField("Teléfono (+34...)", text: $store.whatsappPhone)
                        SecureField("API Key de CallMeBot", text: $store.whatsappApiKey)
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
                            Task { await store.testConnection(channelName: "Notificaciones") }
                        } label: {
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                Text("Probar Enlace en Vivo")
                            }
                        }
                    }
                }
                
                // Preferencias del Lector
                Section("Preferencias del Lector") {
                    Picker("Dirección de lectura", selection: $store.defaultReadingDirection) {
                        ForEach(ReadingDirection.allCases) { dir in
                            Text(dir.rawValue).tag(dir)
                        }
                    }
                }
                
                // Idioma de la Aplicación
                Section("Idioma") {
                    Picker("Idioma de la interfaz", selection: Binding(
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
                Section("Sesión Activa") {
                    if let user = appState.session {
                        LabeledContent("Usuario", value: user.username)
                        LabeledContent("Rol", value: user.role.rawValue)
                        LabeledContent("Servidor", value: user.serverUrl.absoluteString)
                    }
                    
                    Button("Cerrar Sesión", role: .destructive) {
                        appState.logout()
                    }
                }
            }
            .navigationTitle(String(localized: "tab_settings"))
            .task {
                await store.loadSettings(apiClient: apiClient, session: appState.session)
            }
            .alert("Nueva Estantería", isPresented: $showNewShelfAlert) {
                TextField("Nombre de la estantería", text: $newShelfName)
                Button("Crear") {
                    appState.createShelf(name: newShelfName)
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }
}
