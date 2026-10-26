import SwiftUI

/// Vista de Login y Conexión para Kaizen con soporte bilingüe y diseño Liquid Glass
public struct LoginView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var serverUrlString: String = "http://192.168.20.28:3333"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String?
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        ZStack {
            // Fondo oscuro refinado
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Selector de Idioma en esquina superior
                HStack {
                    Spacer()
                    Button {
                        let nextLang = appState.currentLanguage == "es" ? "en" : "es"
                        Task {
                            await appState.switchLanguage(to: nextLang, client: apiClient)
                        }
                    } label: {
                        Text(appState.currentLanguage == "es" ? "🇪🇸 ES | EN" : "🇬🇧 EN | ES")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                
                Spacer()
                
                // Emblema Oficial Kaizen
                VStack(spacing: 12) {
                    // Logo emblemático (si está disponible en bundle o fallback visual)
                    Image(systemName: "magazine.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .cyan.opacity(0.4), radius: 16, y: 8)
                    
                    Text("KAIZEN")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(3)
                    
                    Text("MANGA DOWNLOADER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.cyan.opacity(0.9))
                        .tracking(4)
                }
                
                // Tarjeta Frosted Liquid Glass
                VStack(spacing: 16) {
                    // Campo URL del Servidor
                    VStack(alignment: .leading, spacing: 6) {
                        Label(String(localized: "login_server_url"), systemImage: "server.rack")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        TextField("http://...", text: $serverUrlString)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                    
                    // Campo Usuario
                    VStack(alignment: .leading, spacing: 6) {
                        Label(String(localized: "login_username"), systemImage: "person.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        TextField("admin", text: $username)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    
                    // Campo Contraseña
                    VStack(alignment: .leading, spacing: 6) {
                        Label(String(localized: "login_password"), systemImage: "lock.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        SecureField("••••••••", text: $password)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Botón Iniciar Sesión
                    Button {
                        loginAction()
                    } label: {
                        HStack {
                            if isAuthenticating {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text(String(localized: "login_button"))
                                    .font(.headline.weight(.semibold))
                                Image(systemName: "arrow.right")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .foregroundStyle(.black)
                    }
                    .disabled(isAuthenticating || username.isEmpty || serverUrlString.isEmpty)
                    
                    // Opción QR
                    Button(String(localized: "login_qr_option")) {
                        // Scanner QR
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .padding(24)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Indicador de seguridad Keychain
                Label(String(localized: "login_keychain_secured"), systemImage: "checkmark.shield.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .environment(\.locale, Locale(identifier: appState.currentLanguage))
    }
    
    private func loginAction() {
        guard let url = URL(string: serverUrlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "URL de servidor inválida"
            return
        }
        
        isAuthenticating = true
        errorMessage = nil
        
        Task {
            do {
                let session = try await apiClient.login(
                    serverUrl: url,
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                await MainActor.run {
                    appState.setSession(session)
                    isAuthenticating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error de autenticación: \(error.localizedDescription)"
                    isAuthenticating = false
                }
            }
        }
    }
}
