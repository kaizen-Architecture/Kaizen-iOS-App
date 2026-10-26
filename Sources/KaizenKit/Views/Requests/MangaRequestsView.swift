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
    
    public func loadRequests(session: UserSession?) async {
        guard session != nil else { return }
        isLoading = true
        defer { isLoading = false }
        
        // Simulación inicial mientras conectamos el router de trpc.mangaRequest.list
        // Si hay peticiones reales se cargarán desde el endpoint tRPC
        if requests.isEmpty {
            requests = [
                MangaRequestItem(id: 1, title: "Solo Leveling", startChapter: 1, status: .approved, requestedBy: "Alex R."),
                MangaRequestItem(id: 2, title: "One Piece", startChapter: 1100, status: .downloading, requestedBy: "Maria L.", downloadProgress: 0.45),
                MangaRequestItem(id: 3, title: "Spy x Family", startChapter: 90, status: .available, requestedBy: "Kevin T.")
            ]
        }
    }
    
    public func submitRequest(session: UserSession?) async {
        guard let session, !titleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Introduce el título del manga"
            return
        }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        let newReq = MangaRequestItem(
            id: Int.random(in: 100...9999),
            title: titleInput.trimmingCharacters(in: .whitespacesAndNewlines),
            startChapter: startChapterInput,
            status: .pending,
            requestedBy: session.username
        )
        
        requests.insert(newReq, at: 0)
        titleInput = ""
        startChapterInput = 1
        successMessage = "¡Solicitud registrada correctamente!"
    }
}

public struct MangaRequestsView: View {
    @Environment(AppState.self) private var appState
    @State private var store = MangaRequestsStore()
    @State private var showCreateSheet: Bool = false
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
                        Text("Solicitar nueva serie")
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
                                Task { await store.submitRequest(session: appState.session) }
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
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Listado de peticiones
                    List {
                        Section("Peticiones en Curso") {
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
                                            Text("•")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(req.requestedBy)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
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
                }
            }
            .navigationTitle(String(localized: "tab_requests"))
            .task {
                await store.loadRequests(session: appState.session)
            }
        }
    }
    
    @ViewBuilder
    private func statusBadge(for status: RequestStatus) -> some View {
        switch status {
        case .pending:
            Text("Pendiente")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
        case .approved:
            Text("Aprobado")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2), in: Capsule())
                .foregroundStyle(.green)
        case .downloading:
            HStack(spacing: 4) {
                ProgressView().tint(.cyan).scaleEffect(0.7)
                Text("Descargando")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.cyan.opacity(0.2), in: Capsule())
            .foregroundStyle(.cyan)
        case .available:
            Text("Disponible")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2), in: Capsule())
                .foregroundStyle(.blue)
        case .rejected:
            Text("Rechazado")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.2), in: Capsule())
                .foregroundStyle(.red)
        }
    }
}
