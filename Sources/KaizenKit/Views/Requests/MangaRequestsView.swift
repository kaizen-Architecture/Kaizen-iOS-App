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
    
    public func submitRequest(apiClient: KaizenAPIClient, session: UserSession?, isEn: Bool) async {
        let cleanTitle = titleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !cleanTitle.isEmpty else {
            errorMessage = isEn ? "Please enter manga title" : "Introduce el título del manga"
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
            successMessage = isEn ? "Request registered successfully!" : "¡Solicitud registrada correctamente!"
            await loadRequests(apiClient: apiClient, session: session)
        } catch {
            errorMessage = isEn ? "Error registering request: \(error.localizedDescription)" : "Error al registrar la solicitud: \(error.localizedDescription)"
        }
    }
    
    public func updateStatus(apiClient: KaizenAPIClient, session: UserSession?, requestId: Int, status: String) async {
        guard let session else { return }
        do {
            try await apiClient.updateRequestStatus(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                requestId: requestId,
                status: status
            )
            await loadRequests(apiClient: apiClient, session: session)
        } catch {
            errorMessage = error.localizedDescription
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
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Tarjeta superior para solicitar nueva serie
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isEn ? "Request New Series to Kaizen" : "Solicitar nueva serie a Kaizen")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        TextField(isEn ? "Manga title (AniList / MangaDex)..." : "Título del manga (AniList / MangaDex)...", text: $store.titleInput)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        
                        HStack {
                            Text(isEn ? "Start Chapter:" : "Capítulo inicio:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Stepper("\(store.startChapterInput)", value: $store.startChapterInput, in: 1...2000)
                                .fixedSize()
                            
                            Spacer()
                            
                            Button {
                                Task { await store.submitRequest(apiClient: apiClient, session: appState.session, isEn: isEn) }
                            } label: {
                                if store.isSubmitting {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(isEn ? "Request" : "Solicitar")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(.black)
                                }
                            }
                            .disabled(store.isSubmitting || store.titleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        
                        if let error = store.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let success = store.successMessage {
                            Text(success)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    
                    // Lista de peticiones
                    if store.isLoading && store.requests.isEmpty {
                        Spacer()
                        ProgressView().tint(.cyan)
                        Spacer()
                    } else if store.requests.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            isEn ? "No Requests Found" : "Sin peticiones registradas",
                            systemImage: "tray",
                            description: Text(isEn ? "When you or other readers request manga, they will appear here with live status." : "Cuando solicites series o las soliciten otros usuarios en Kaizen, aparecerán aquí con su estado en vivo.")
                        )
                        Spacer()
                    } else {
                        List {
                            Section(isEn ? "Pending & Active Requests (\(store.requests.count))" : "Peticiones en Curso (\(store.requests.count))") {
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
                                                Text((isEn ? "From Ch. " : "Desde Cap. ") + "\(req.startChapter)")
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
                                    .contextMenu {
                                        if appState.isManagement {
                                            Button {
                                                Task { await store.updateStatus(apiClient: apiClient, session: appState.session, requestId: req.id, status: "APPROVED") }
                                            } label: {
                                                Label(isEn ? "Approve Request" : "Aprobar Solicitud", systemImage: "checkmark.circle.fill")
                                            }
                                            
                                            Button {
                                                Task { await store.updateStatus(apiClient: apiClient, session: appState.session, requestId: req.id, status: "DOWNLOADING") }
                                            } label: {
                                                Label(isEn ? "Mark as Downloading" : "Poner a Descargar", systemImage: "arrow.down.circle.fill")
                                            }
                                            
                                            Button(role: .destructive) {
                                                Task { await store.updateStatus(apiClient: apiClient, session: appState.session, requestId: req.id, status: "REJECTED") }
                                            } label: {
                                                Label(isEn ? "Reject Request" : "Rechazar Solicitud", systemImage: "xmark.circle.fill")
                                            }
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        if appState.isManagement {
                                            Button {
                                                Task { await store.updateStatus(apiClient: apiClient, session: appState.session, requestId: req.id, status: "APPROVED") }
                                            } label: {
                                                Label(isEn ? "Approve" : "Aprobar", systemImage: "checkmark")
                                            }
                                            .tint(.green)
                                            
                                            Button {
                                                Task { await store.updateStatus(apiClient: apiClient, session: appState.session, requestId: req.id, status: "REJECTED") }
                                            } label: {
                                                Label(isEn ? "Reject" : "Rechazar", systemImage: "xmark")
                                            }
                                            .tint(.red)
                                        }
                                    }
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
            .navigationTitle(isEn ? "Requests" : "Peticiones")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    InAppLanguageToggle(apiClient: apiClient)
                }
            }
            .task {
                await store.loadRequests(apiClient: apiClient, session: appState.session)
            }
        }
    }
    
    @ViewBuilder
    private func statusBadge(for status: String) -> some View {
        switch status.uppercased() {
        case "PENDING":
            Text(isEn ? "Pending" : "Pendiente")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
        case "APPROVED":
            Text(isEn ? "Approved" : "Aprobado")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2), in: Capsule())
                .foregroundStyle(.green)
        case "DOWNLOADING":
            HStack(spacing: 4) {
                ProgressView().tint(.cyan).scaleEffect(0.7)
                Text(isEn ? "Downloading" : "Descargando")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.cyan.opacity(0.2), in: Capsule())
            .foregroundStyle(.cyan)
        case "AVAILABLE":
            Text(isEn ? "Available" : "Disponible")
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
