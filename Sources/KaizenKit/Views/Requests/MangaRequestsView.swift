import SwiftUI

@MainActor
@Observable
public final class MangaRequestsStore {
    public var requests: [MangaRequestItem] = []
    public var titleInput: String = ""
    public var startChapterInput: Int = 1
    public var isSubmitting: Bool = false
    public var isLoading: Bool = false
    public var errorMessage: String?
    public var successMessage: String?
    
    public init() {}
    
    public func loadRequests(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            requests = try await apiClient.fetchRequests(serverUrl: session.serverUrl, token: session.apiToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func submitRequest(apiClient: KaizenAPIClient, session: UserSession?) async {
        let cleanTitle = titleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !cleanTitle.isEmpty else {
            errorMessage = "Introduce el título del manga"
            return
        }
        
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        
        do {
            try await apiClient.createRequest(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                title: cleanTitle,
                startChapter: startChapterInput
            )
            titleInput = ""
            startChapterInput = 1
            successMessage = "¡Solicitud registrada correctamente!"
            await loadRequests(apiClient: apiClient, session: session)
        } catch {
            errorMessage = "Error al registrar la solicitud: \(error.localizedDescription)"
        }
    }
}

public struct MangaRequestsView: View {
    @Environment(AppState.self) private var appState
    @State private var store = MangaRequestsStore()
    let apiClient: KaizenAPIClient
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Tarjeta superior para solicitar nueva serie
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Solicitar nueva serie a Kaizen")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        TextField("Título del manga (AniList / MangaDex)...", text: $store.titleInput)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        
                        HStack {
                            Text("Capítulo inicio:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Stepper("\(store.startChapterInput)", value: $store.startChapterInput, in: 1...2000)
                                .fixedSize()
                            
                            Spacer()
                            
                            Button {
                                Task { await store.submitRequest(apiClient: apiClient, session: appState.session) }
                            } label: {
                                if store.isSubmitting {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("Solicitar")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.cyan, in: Capsule())
                            .foregroundStyle(.black)
                            .disabled(store.titleInput.isEmpty || store.isSubmitting)
                        }
                        
                        if let error = store.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if let success = store.successMessage {
                            Text(success)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Listado de peticiones reales
                    if store.isLoading && store.requests.isEmpty {
                        Spacer()
                        ProgressView().tint(.cyan)
                        Spacer()
                    } else if store.requests.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "Sin peticiones registradas",
                            systemImage: "tray",
                            description: Text("Cuando solicites series o las soliciten otros usuarios en Kaizen, aparecerán aquí con su estado en vivo.")
                        )
                        Spacer()
                    } else {
                        List {
                            Section("Peticiones en Curso (\(store.requests.count))") {
                                ForEach(store.requests) { req in
                                    HStack(spacing: 12) {
                                        Image(systemName: "book.closed.fill")
                                            .font(.title2)
                                            .foregroundStyle(.cyan)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(req.title)
                                                .font(.headline)
                                                .foregroundStyle(.white)
                                            
                                            HStack(spacing: 6) {
                                                Text("Desde Cap. \(req.startChapter)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                if let username = req.username {
                                                    Text("•")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                    Text(username)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        statusBadge(for: req.status)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .refreshable {
                            await store.loadRequests(apiClient: apiClient, session: appState.session)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "tab_requests"))
            .task {
                await store.loadRequests(apiClient: apiClient, session: appState.session)
            }
        }
    }
    
    @ViewBuilder
    private func statusBadge(for status: String) -> some View {
        switch status.uppercased() {
        case "PENDING":
            Text("Pendiente")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
        case "APPROVED":
            Text("Aprobado")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2), in: Capsule())
                .foregroundStyle(.green)
        case "DOWNLOADING":
            HStack(spacing: 4) {
                ProgressView().tint(.cyan).scaleEffect(0.7)
                Text("Descargando")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.cyan.opacity(0.2), in: Capsule())
            .foregroundStyle(.cyan)
        case "AVAILABLE":
            Text("Disponible")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2), in: Capsule())
                .foregroundStyle(.blue)
        default:
            Text(status)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.2), in: Capsule())
                .foregroundStyle(.red)
        }
    }
}
