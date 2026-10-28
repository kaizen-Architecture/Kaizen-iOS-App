import SwiftUI

/// Pantalla de acceso a Kaizen: servidor, usuario, contraseña y API Token.
///
/// El login (usuario + contraseña) identifica al usuario y su rol; el API Token es lo que
/// el servidor exige para la API REST (biblioteca, lector, progreso).
public struct LoginView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @AppStorage("kaizen.serverURL") private var serverUrlString: String = "http://192.168.20.28:3333"
    @AppStorage("kaizen_remember_login") private var rememberLogin: Bool = true
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var apiToken: String = ""
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String?
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        logo
                        formCard
                        languagePicker
                        
                        Label {
                            Text("login_keychain_secured")
                        } icon: {
                            Image(systemName: "checkmark.shield.fill")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        
                        Text("Kaizen iOS v1.1.0 (Build 2)")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .environment(\.locale, Locale(identifier: appState.currentLanguage))
    }
    
    // MARK: - Componentes
    
    /// Logo oficial (kaizen.png). Tiene fondo claro, así que se muestra como una insignia redondeada.
    private var logo: some View {
        Image("KaizenLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 168, height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .shadow(color: .cyan.opacity(0.25), radius: 24, y: 10)
            .accessibilityLabel("Kaizen")
    }
    
    private var formCard: some View {
        VStack(spacing: 16) {
            field("login_server_url", systemImage: "server.rack") {
                TextField("http://192.168.1.10:3333", text: $serverUrlString)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            
            field("login_username", systemImage: "person.fill") {
                TextField("admin", text: $username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            
            field("login_password", systemImage: "lock.fill") {
                SecureField("••••••••", text: $password)
            }
            
            field("login_api_token", systemImage: "key.fill", footnote: "login_api_token_hint") {
                SecureField("bc1400be…", text: $apiToken)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(loginAction)
            }
            
            Toggle(isOn: $rememberLogin) {
                Label {
                    Text(appState.currentLanguage == "en" ? "Remember login on this device" : "Recordar sesión en este dispositivo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(.cyan)
                }
            }
            .tint(.cyan)
            .padding(.vertical, 2)
            
            if let errorMessage {
                Label {
                    Text(errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            
            Button(action: loginAction) {
                HStack {
                    if isAuthenticating {
                        ProgressView().tint(.black)
                    } else {
                        Text("login_button")
                            .font(.headline.weight(.semibold))
                        Image(systemName: "arrow.right")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .foregroundStyle(.black)
            }
            .disabled(isAuthenticating || username.isEmpty || serverUrlString.isEmpty)
            .opacity(username.isEmpty || serverUrlString.isEmpty ? 0.5 : 1)
        }
        .padding(24)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
    
    /// Selector ES | EN dentro del contenido (no junto a la barra de estado del iPad).
    private var languagePicker: some View {
        HStack(spacing: 4) {
            languageButton("ES", code: "es")
            languageButton("EN", code: "en")
        }
        .padding(4)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
    
    private func languageButton(_ title: String, code: String) -> some View {
        let selected = appState.currentLanguage == code
        return Button {
            Task { await appState.switchLanguage(to: code, client: apiClient) }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(selected ? Color.cyan : Color.clear, in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white)
        }
    }
    
    private func field<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        footnote: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            
            content()
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Acción
    
    private func loginAction() {
        guard !isAuthenticating, !username.isEmpty else { return }
        
        guard let url = ServerURL.parse(serverUrlString) else {
            errorMessage = KaizenError.invalidServerURL.userMessage(language: appState.currentLanguage)
            return
        }
        
        isAuthenticating = true
        errorMessage = nil
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password
        
        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                let session = try await apiClient.login(serverUrl: url, username: user, password: pass, apiToken: token)
                appState.setSession(session, remember: rememberLogin)
            } catch let error as KaizenError {
                errorMessage = error.userMessage(language: appState.currentLanguage)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
