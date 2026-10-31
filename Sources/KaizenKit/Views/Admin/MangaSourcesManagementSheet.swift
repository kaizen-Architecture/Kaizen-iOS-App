import SwiftUI

/// Hoja para administrar las fuentes y scrapers vinculados a un manga en Kaizen
public struct MangaSourcesManagementSheet: View {
    let manga: Manga
    let apiClient: KaizenAPIClient
    var onUpdate: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @State private var sources: [MangaConfiguredSource] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    
    // Añadir fuente modal
    @State private var showAddSourceSheet = false
    @State private var availableScrapers: [String] = []
    @State private var selectedScraper: String = ""
    @State private var searchKeyword: String = ""
    @State private var searchResults: [RemoteSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var isAdding: Bool = false
    @State private var addError: String?
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    public init(manga: Manga, apiClient: KaizenAPIClient, onUpdate: @escaping () -> Void = {}) {
        self.manga = manga
        self.apiClient = apiClient
        self.onUpdate = onUpdate
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(.cyan)
                        Text(isEn ? "Loading sources..." : "Cargando fuentes...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        Section {
                            if sources.isEmpty {
                                Text(isEn ? "No custom sources configured for this series." : "No hay fuentes secundarias configuradas para esta serie.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(sources) { src in
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Text(src.source)
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundStyle(.white)
                                                
                                                if src.priority == 0 {
                                                    Text(isEn ? "PRIMARY" : "PRINCIPAL")
                                                        .font(.system(size: 9, weight: .black))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.green.opacity(0.2), in: Capsule())
                                                        .foregroundStyle(.green)
                                                } else {
                                                    Text(isEn ? "Priority \(src.priority)" : "Prioridad \(src.priority)")
                                                        .font(.system(size: 9, weight: .semibold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.white.opacity(0.1), in: Capsule())
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            
                                            Text(src.title)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Menu {
                                            if src.priority != 0 {
                                                Button {
                                                    promoteToPrimary(src)
                                                } label: {
                                                    Label(isEn ? "Set as Primary" : "Convertir en principal", systemImage: "star.fill")
                                                }
                                            }
                                            
                                            Button(role: .destructive) {
                                                removeSource(src)
                                            } label: {
                                                Label(isEn ? "Remove Source" : "Eliminar fuente", systemImage: "trash")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .font(.title3)
                                                .foregroundStyle(.cyan)
                                                .padding(6)
                                        }
                                    }
                                    .listRowBackground(Color.white.opacity(0.04))
                                }
                            }
                        } header: {
                            Text(isEn ? "Configured Sources" : "Fuentes de Descarga")
                        } footer: {
                            Text(isEn ? "Kaizen downloads chapters in priority order. If a scraper fails or is blocked, alternative sources are used automatically." : "Kaizen descarga los capítulos en orden de prioridad. Si una fuente falla o sufre bloqueos, se recurre automáticamente a las siguientes.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(isEn ? "Manga Sources" : "Fuentes del Manga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Done" : "Listo") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        searchKeyword = manga.title
                        showAddSourceSheet = true
                    } label: {
                        Label(isEn ? "Add Source" : "Añadir Fuente", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .task {
                await loadSources()
            }
            .sheet(isPresented: $showAddSourceSheet) {
                addSourceModal
            }
        }
    }
    
    // MARK: - Modal para Buscar y Añadir Fuente
    
    private var addSourceModal: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Selector de Scraper
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isEn ? "Select Source Scraper" : "Seleccionar Fuente / Scraper")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        if availableScrapers.isEmpty {
                            ProgressView().tint(.cyan)
                        } else {
                            Picker("Scraper", selection: $selectedScraper) {
                                ForEach(availableScrapers, id: \.self) { scraper in
                                    Text(scraper).tag(scraper)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // Buscador
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField(isEn ? "Manga title to search..." : "Título del manga...", text: $searchKeyword)
                                .textFieldStyle(.plain)
                                .foregroundStyle(.white)
                                .onSubmit { Task { await executeSearch() } }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        
                        Button {
                            Task { await executeSearch() }
                        } label: {
                            if isSearching {
                                ProgressView().tint(.black)
                                    .padding(.horizontal, 8)
                            } else {
                                Text(isEn ? "Search" : "Buscar")
                                    .font(.subheadline.weight(.bold))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.black)
                        .disabled(isSearching || searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    
                    if let addError {
                        Text(addError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                    
                    // Resultados
                    if isSearching {
                        Spacer()
                        ProgressView(isEn ? "Searching source..." : "Buscando en la fuente...").tint(.cyan)
                        Spacer()
                    } else if searchResults.isEmpty {
                        Spacer()
                        Text(isEn ? "Search for this series on the chosen source" : "Busca la serie en el catálogo de la fuente elegida")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        List(searchResults) { result in
                            Button {
                                Task { await addSource(result) }
                            } label: {
                                HStack(spacing: 12) {
                                    if let cover = result.cover, let url = URL(string: cover) {
                                        RemoteImage(url: url, token: appState.session?.apiToken)
                                            .frame(width: 44, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.06))
                                            .frame(width: 44, height: 60)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        
                                        HStack(spacing: 6) {
                                            Text(result.source)
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.cyan)
                                            
                                            Text("•")
                                                .foregroundStyle(.secondary)
                                            
                                            Text("\(result.chapters) " + (isEn ? "chapters" : "capítulos"))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.cyan)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.white.opacity(0.04))
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(isEn ? "Add Source" : "Añadir Fuente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Cancel" : "Cancelar") { showAddSourceSheet = false }
                }
            }
            .task {
                await loadAvailableScrapers()
            }
        }
    }
    
    // MARK: - Acciones
    
    private func loadSources() async {
        guard let session = appState.session else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            sources = try await apiClient.fetchMangaSources(serverUrl: session.serverUrl, token: session.apiToken, mangaId: manga.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func loadAvailableScrapers() async {
        guard let session = appState.session else { return }
        do {
            let list = try await apiClient.fetchAvailableSources(serverUrl: session.serverUrl, token: session.apiToken)
            availableScrapers = list.sorted()
            if selectedScraper.isEmpty, let first = availableScrapers.first {
                selectedScraper = first
            }
        } catch {
            // Ignorar
        }
    }
    
    private func executeSearch() async {
        guard let session = appState.session, !searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty, !selectedScraper.isEmpty else { return }
        isSearching = true
        addError = nil
        defer { isSearching = false }
        do {
            searchResults = try await apiClient.searchMangaRemote(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                keyword: searchKeyword.trimmingCharacters(in: .whitespaces),
                source: selectedScraper
            )
        } catch {
            addError = error.localizedDescription
        }
    }
    
    private func addSource(_ result: RemoteSearchResult) async {
        guard let session = appState.session else { return }
        isAdding = true
        addError = nil
        defer { isAdding = false }
        do {
            try await apiClient.addMangaSource(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: manga.id,
                source: result.source,
                title: result.title
            )
            showAddSourceSheet = false
            await loadSources()
            onUpdate()
        } catch {
            addError = error.localizedDescription
        }
    }
    
    private func promoteToPrimary(_ src: MangaConfiguredSource) {
        guard let session = appState.session else { return }
        Task {
            do {
                try await apiClient.switchMangaPrimarySource(
                    serverUrl: session.serverUrl,
                    token: session.apiToken,
                    mangaId: manga.id,
                    newSource: src.source,
                    newSourceTitle: src.title
                )
                await loadSources()
                onUpdate()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func removeSource(_ src: MangaConfiguredSource) {
        guard let session = appState.session else { return }
        Task {
            do {
                try await apiClient.removeMangaSource(serverUrl: session.serverUrl, token: session.apiToken, sourceId: src.id)
                await loadSources()
                onUpdate()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
