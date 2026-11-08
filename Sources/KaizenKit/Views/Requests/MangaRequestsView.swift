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

private enum RequestFilter: String, CaseIterable, Identifiable {
    case pending, approved, rejected
    var id: String { rawValue }
}

public struct MangaRequestsView: View {
    @Environment(AppState.self) private var appState
    @State private var store = MangaRequestsStore()
    @State private var filter: RequestFilter = .pending
    @State private var showNewRequest = false
    let apiClient: KaizenAPIClient
    public var isEmbedded: Bool = false
    
    public init(apiClient: KaizenAPIClient, isEmbedded: Bool = false) {
        self.apiClient = apiClient
        self.isEmbedded = isEmbedded
    }
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    
    private func bucket(_ status: String) -> RequestFilter {
        switch status.uppercased() {
        case "PENDING": return .pending
        case "APPROVED", "DOWNLOADING", "AVAILABLE": return .approved
        default: return .rejected
        }
    }
    
    private var pendingCount: Int {
        store.requests.filter { bucket($0.status) == .pending }.count
    }
    
    private var visibleRequests: [MangaRequestItem] {
        store.requests.filter { bucket($0.status) == filter }
    }
    
    private func title(for filter: RequestFilter) -> String {
        switch filter {
        case .pending: return isEn ? "Pending" : "Pendientes"
        case .approved: return isEn ? "Approved" : "Aprobadas"
        case .rejected: return isEn ? "Rejected" : "Rechazadas"
        }
    }
    
    public var body: some View {
        if isEmbedded {
            requestsListContent
                .refreshable {
                    await store.loadRequests(apiClient: apiClient, session: appState.session)
                }
                .task {
                    await store.loadRequests(apiClient: apiClient, session: appState.session)
                }
                .sheet(isPresented: $showNewRequest) {
                    newRequestSheet
                }
        } else {
            NavigationStack {
                requestsListContent
                    .navigationTitle(isEn ? "Requests" : "Peticiones")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showNewRequest = true } label: { Image(systemName: "plus") }
                                .accessibilityLabel(isEn ? "New request" : "Nueva petición")
                        }
                    }
                    .refreshable {
                        await store.loadRequests(apiClient: apiClient, session: appState.session)
                    }
                    .task {
                        await store.loadRequests(apiClient: apiClient, session: appState.session)
                    }
                    .sheet(isPresented: $showNewRequest) {
                        newRequestSheet
                    }
            }
        }
    }
    
    private var requestsListContent: some View {
        List {
            Section {
                Picker("", selection: $filter) {
                    ForEach(RequestFilter.allCases) { f in
                        Text(title(for: f)).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            
            if isEmbedded {
                Section {
                    Button {
                        showNewRequest = true
                    } label: {
                        Label(isEn ? "Request New Manga" : "Solicitar Nuevo Manga", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .kaizenGlassButton(prominent: false)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }
            
            if store.isLoading && store.requests.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if visibleRequests.isEmpty {
                ContentUnavailableView(
                    isEn ? "No requests" : "Sin peticiones",
                    systemImage: "tray",
                    description: Text(isEn ? "Nothing here yet." : "Aquí no hay nada todavía.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(visibleRequests) { req in
                        requestCard(req)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background((isEmbedded ? Color.clear : Color.black).ignoresSafeArea())
    }
    
    // MARK: - Tarjeta
    
    private func requestCard(_ req: MangaRequestItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(String(req.title.prefix(1)).uppercased())
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 62)
                    .background(
                        LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(req.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        if let username = req.username {
                            Text("@\(username)")
                        }
                        Text("· " + (isEn ? "from Ch. " : "desde cap. ") + "\(req.startChapter)")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if bucket(req.status) != .pending {
                    statusBadge(for: req.status)
                }
            }
            
            if appState.isManagement && bucket(req.status) == .pending {
                HStack(spacing: 10) {
                    Button {
                        Task { await store.updateStatus(apiClient: apiClient, session: appState.session, requestId: req.id, status: "APPROVED") }
                    } label: {
                        Label(isEn ? "Approve" : "Aprobar", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .kaizenGlassButton(prominent: true)
                    .tint(.cyan)
                    
                    Button {
                        Task { await store.updateStatus(apiClient: apiClient, session: appState.session, requestId: req.id, status: "REJECTED") }
                    } label: {
                        Label(isEn ? "Reject" : "Rechazar", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .kaizenGlassButton(prominent: false)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            if appState.isManagement {
                Button {
                    Task { await store.updateStatus(apiClient: apiClient, session: appState.session, requestId: req.id, status: "DOWNLOADING") }
                } label: {
                    Label(isEn ? "Mark as downloading" : "Poner a descargar", systemImage: "arrow.down.circle")
                }
            }
        }
    }
    
    // MARK: - Nueva petición
    
    private var newRequestSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isEn ? "Manga title" : "Título del manga", text: $store.titleInput)
                    Stepper(
                        (isEn ? "Start chapter: " : "Capítulo inicio: ") + "\(store.startChapterInput)",
                        value: $store.startChapterInput,
                        in: 1...2000
                    )
                } footer: {
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(.red)
                    } else if let success = store.successMessage {
                        Text(success).foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(isEn ? "New request" : "Nueva petición")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Cancel" : "Cancelar") { showNewRequest = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEn ? "Request" : "Solicitar") {
                        Task {
                            await store.submitRequest(apiClient: apiClient, session: appState.session, isEn: isEn)
                            if store.errorMessage == nil { showNewRequest = false }
                        }
                    }
                    .disabled(store.isSubmitting || store.titleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Estado
    
    @ViewBuilder
    private func statusBadge(for status: String) -> some View {
        let (text, color): (String, Color) = {
            switch status.uppercased() {
            case "APPROVED": return (isEn ? "Approved" : "Aprobada", .green)
            case "DOWNLOADING": return (isEn ? "Downloading" : "Descargando", .cyan)
            case "AVAILABLE": return (isEn ? "Available" : "Disponible", .blue)
            default: return (isEn ? "Rejected" : "Rechazada", .red)
            }
        }()
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}
