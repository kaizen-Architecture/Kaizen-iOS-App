import SwiftUI

/// Modal para que el Administrador busque y dé de alta mangas en el servidor Kaizen de forma remota
public struct AddMangaRemoteSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let apiClient: KaizenAPIClient
    var onAdded: (() -> Void)?
    
    @State private var availableSources: [String] = []
    @State private var selectedSource: String = "all"
    @State private var searchText: String = ""
    @State private var searchResults: [RemoteSearchResult] = []
    
    @State private var isLoadingSources = false
    @State private var isSearching = false
    @State private var selectedResult: RemoteSearchResult?
    
    // Configuración de la serie al darla de alta
    @State private var intervalChoice: String = "0 * * * *"
    @State private var minChapters: Int = 0
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    public init(apiClient: KaizenAPIClient, onAdded: (() -> Void)? = nil) {
        self.apiClient = apiClient
        self.onAdded = onAdded
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Barra superior de búsqueda y fuente
                    searchHeaderView
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12))
                    }
                    
                    if let success = successMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(success)
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.green)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.12))
                    }
                    
                    // Contenido: Lista de resultados o configuración del manga seleccionado
                    if isSearching {
                        Spacer()
                        ProgressView(
                            selectedSource == "all"
                                ? (isEn ? "Searching all sources on Kaizen..." : "Buscando en todas las fuentes de Kaizen...")
                                : (isEn ? "Searching on \(selectedSource.capitalized)..." : "Buscando en \(selectedSource.capitalized)...")
                        )
                        .tint(.cyan)
                        .foregroundStyle(.secondary)
                        Spacer()
                    } else if let result = selectedResult {
                        configuredMangaView(result: result)
                    } else if searchResults.isEmpty {
                        emptyStateView
                    } else {
                        resultsListView
                    }
                }
            }
            .navigationTitle(isEn ? "Add Manga Remotely" : "Añadir Manga Remoto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Close" : "Cerrar") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSources()
            }
        }
    }
    
    // MARK: - Subcomponentes
    
    private var searchHeaderView: some View {
        VStack(spacing: 10) {
            // Selector de fuente
            HStack(spacing: 8) {
                Label(isEn ? "Source:" : "Fuente:", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                
                if isLoadingSources {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Picker(isEn ? "Source" : "Fuente", selection: $selectedSource) {
                        Text(isEn ? "🌐 All Sources (Global)" : "🌐 Todas las fuentes (Global)")
                            .tag("all")
                        
                        Divider()
                        
                        ForEach(availableSources, id: \.self) { src in
                            Text(src.capitalized).tag(src)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.cyan)
                }
                Spacer()
            }
            
            // Campo de búsqueda con botón de acción
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(isEn ? "Manga title or keywords..." : "Título del manga o palabras clave...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            Task { await executeSearch() }
                        }
                }
                .padding(10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                
                Button {
                    Task { await executeSearch() }
                } label: {
                    Text(isEn ? "Search" : "Buscar")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.black)
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedSource.isEmpty || isSearching)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: selectedSource == "all" ? "globe.americas.fill" : "books.vertical.circle")
                .font(.system(size: 48))
                .foregroundStyle(.cyan.opacity(0.7))
            Text(isEn ? "Search and Add New Series" : "Buscar y Añadir Nueva Serie")
                .font(.headline)
                .foregroundStyle(.white)
            Text(
                selectedSource == "all"
                    ? (isEn ? "Global Search: queries all available scrapers on Kaizen simultaneously." : "Búsqueda Global: consulta todos los scrapers disponibles en Kaizen simultáneamente.")
                    : (isEn ? "Searching in \(selectedSource.capitalized). You can also switch to 'All Sources (Global)'." : "Buscando en \(selectedSource.capitalized). También puedes cambiar a 'Todas las fuentes (Global)'.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
        }
    }
    
    private var resultsListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(searchResults) { result in
                    Button {
                        selectedResult = result
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(
                                url: result.cover.flatMap { URL(string: $0) },
                                token: appState.session?.apiToken,
                                contentMode: .fill
                            )
                            .frame(width: 50, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                HStack(spacing: 8) {
                                    Text(result.source)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.cyan)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.cyan.opacity(0.15), in: Capsule())
                                    
                                    if result.chapters > 0 {
                                        Text("\(result.chapters) " + (isEn ? "chapters" : "capítulos"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.cyan)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    private func configuredMangaView(result: RemoteSearchResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Ficha del manga elegido
                HStack(spacing: 16) {
                    RemoteImage(
                        url: result.cover.flatMap { URL(string: $0) },
                        token: appState.session?.apiToken,
                        contentMode: .fill
                    )
                    .frame(width: 70, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        Text((isEn ? "Source: " : "Fuente: ") + result.source)
                            .font(.caption)
                            .foregroundStyle(.cyan)
                        
                        if result.chapters > 0 {
                            Text((isEn ? "Available chapters: " : "Capítulos disponibles: ") + "\(result.chapters)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button {
                            selectedResult = nil
                        } label: {
                            Text(isEn ? "← Change selection" : "← Elegir otro")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                
                // Formulario de configuración de descarga automática
                VStack(alignment: .leading, spacing: 14) {
                    Text(isEn ? "Download & Check Schedule" : "Planificación de Comprobación y Descargas")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    
                    Picker(isEn ? "Frequency" : "Frecuencia", selection: $intervalChoice) {
                        Text(isEn ? "Hourly" : "Cada hora").tag("0 * * * *")
                        Text(isEn ? "Every 6 Hours" : "Cada 6 horas").tag("0 */6 * * *")
                        Text(isEn ? "Daily at 4 AM" : "Diario a las 4 AM").tag("0 4 * * *")
                        Text(isEn ? "Weekly" : "Semanal").tag("0 4 * * 1")
                    }
                    .pickerStyle(.segmented)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isEn ? "Minimum chapters to start downloading:" : "Mínimo de capítulos para iniciar descarga:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Stepper("\(minChapters) " + (isEn ? "chapters" : "capítulos"), value: $minChapters, in: 0...50)
                            .padding(10)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Button {
                        Task { await submitAddManga(result: result) }
                    } label: {
                        HStack {
                            if isAdding {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                Text(isEn ? "Add to Kaizen Library" : "Añadir a la Biblioteca de Kaizen")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                    }
                    .disabled(isAdding)
                }
                .padding(16)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Acciones
    
    private func loadSources() async {
        guard let session = appState.session else { return }
        isLoadingSources = true
        defer { isLoadingSources = false }
        do {
            let sources = try await apiClient.fetchAvailableSources(serverUrl: session.serverUrl, token: session.apiToken)
            self.availableSources = sources
            if self.selectedSource.isEmpty {
                self.selectedSource = "all"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func executeSearch() async {
        guard let session = appState.session, !selectedSource.isEmpty else { return }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        successMessage = nil
        selectedResult = nil
        defer { isSearching = false }
        
        do {
            let results = try await apiClient.searchMangaRemote(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                keyword: q,
                source: selectedSource
            )
            self.searchResults = results
            if results.isEmpty {
                errorMessage = isEn ? "No series found with this keyword." : "No se encontraron series para esta búsqueda."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func submitAddManga(result: RemoteSearchResult) async {
        guard let session = appState.session else { return }
        isAdding = true
        errorMessage = nil
        successMessage = nil
        defer { isAdding = false }
        
        do {
            try await apiClient.addMangaRemote(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                source: result.source,
                title: result.title,
                interval: intervalChoice,
                minChapters: minChapters
            )
            successMessage = isEn ? "Series successfully added to Kaizen!" : "¡Serie añadida con éxito a Kaizen!"
            // Refrescar biblioteca local
            await appState.loadLibrary(client: apiClient, force: true)
            onAdded?()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
