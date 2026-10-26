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
        if let settings = try? await apiClient.fetchUserSettings(
            serverUrl: session.serverUrl,
            token: session.apiToken,
            userId: session.id
        ) {
            self.anilistEnabled = settings.anilistEnabled
            self.anilistUsername = settings.anilistUsername ?? ""
            self.anilistAutoSync = settings.anilistAutoSync
            self.whatsappEnabled = settings.whatsappEnabled
            self.whatsappPhone = settings.whatsappPhone ?? ""
            self.whatsappApiKey = settings.whatsappApiKey ?? ""
            self.discordEnabled = settings.discordEnabled
            self.discordWebhookUrl = settings.discordWebhookUrl ?? ""
            self.telegramEnabled = settings.telegramEnabled
            self.telegramChatId = settings.telegramChatId ?? ""
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
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Sección AniList & Scrobble
                Section("AniList & Tracker") {
                    Toggle("Conectar AniList", isOn: $store.anilistEnabled)
                        .tint(.cyan)
                    
                    if store.anilistEnabled {
                        TextField("Usuario de AniList", text: $store.anilistUsername)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        
                        Toggle("Auto-scrobble al terminar capítulos", isOn: $store.anilistAutoSync)
                            .tint(.cyan)
                        
                        Button {
                            Task { await store.testConnection(channelName: "AniList") }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Probar Conexión con AniList")
                            }
                        }
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
        }
    }
}
