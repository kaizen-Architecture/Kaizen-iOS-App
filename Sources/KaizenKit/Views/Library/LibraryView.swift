import SwiftUI

public enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case reading = "Leyendo"
    case caughtUp = "Al día"
    case favorites = "Favoritos"
    
    public var id: String { rawValue }
    
    public func label(language: String) -> String {
        switch self {
        case .all: return language == "en" ? "All" : "Todos"
        case .reading: return language == "en" ? "Reading" : "Leyendo"
        case .caughtUp: return language == "en" ? "Caught Up" : "Al día"
        case .favorites: return language == "en" ? "Favorites" : "Favoritos"
        }
    }
}

public struct LibraryView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var selectedFilter: LibraryFilter = .all
    @State private var selectedLibraryId: Int? = nil
    @State private var selectedStatus: String? = nil
    @State private var selectedGenre: String? = nil
    @State private var searchText: String = ""
    @State private var showCreateLibraryAlert = false
    @State private var showAddMangaSheet = false
    @State private var newLibraryPath = ""
    @State private var creationError: String?
    
    private let columns = [
        GridItem(.adaptive(minimum: 125, maximum: 180), spacing: 16)
    ]
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private var availableGenres: [String] {
        let all = appState.mangas.compactMap(\.genres).flatMap { $0 }
        let cleaned = all.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    private var availableStatuses: [String] {
        let all = appState.mangas.compactMap(\.status)
        let cleaned = all.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty }
        let set = Set(cleaned)
        if set.isEmpty {
            return ["ONGOING", "COMPLETED"]
        }
        return Array(set).sorted()
    }
    
    private func localizedStatus(_ status: String) -> String {
        switch status.uppercased() {
        case "ONGOING":
            return isEn ? "Ongoing" : "En emisión"
        case "COMPLETED":
            return isEn ? "Completed" : "Finalizado"
        case "HIATUS":
            return isEn ? "Hiatus" : "En pausa"
        case "CANCELLED", "CANCELED":
            return isEn ? "Cancelled" : "Cancelado"
        default:
            return status.capitalized
        }
    }
    
    private var hasActiveFilters: Bool {
        selectedFilter != .all || selectedLibraryId != nil || selectedStatus != nil || selectedGenre != nil || !searchText.isEmpty
    }
    
    private func resetFilters() {
        selectedFilter = .all
        selectedLibraryId = nil
        selectedStatus = nil
        selectedGenre = nil
        searchText = ""
    }
    
    private var filteredMangas: [Manga] {
        appState.mangas.filter { manga in
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let titleMatch = manga.title.localizedCaseInsensitiveContains(text)
                let authorMatch = manga.authors?.contains { $0.localizedCaseInsensitiveContains(text) } ?? false
                let altMatch = manga.altTitles?.contains { $0.localizedCaseInsensitiveContains(text) } ?? false
                let genreMatch = manga.genres?.contains { $0.localizedCaseInsensitiveContains(text) } ?? false
                matchesSearch = titleMatch || authorMatch || altMatch || genreMatch
            }
            
            let matchesLibrary = selectedLibraryId == nil || manga.libraryId == selectedLibraryId
            
            let matchesStatus: Bool
            if let selectedStatus {
                matchesStatus = manga.status?.uppercased() == selectedStatus.uppercased()
            } else {
                matchesStatus = true
            }
            
            let matchesGenre: Bool
            if let selectedGenre {
                matchesGenre = manga.genres?.contains { $0.caseInsensitiveCompare(selectedGenre) == .orderedSame } ?? false
            } else {
                matchesGenre = true
            }
            
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .reading:
                matchesFilter = manga.readingPercentage > 0 && manga.readingPercentage < 100
            case .caughtUp:
                matchesFilter = manga.readingPercentage >= 100
            case .favorites:
                matchesFilter = manga.isFavorite
            }
            
            return matchesSearch && matchesLibrary && matchesStatus && matchesGenre && matchesFilter
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Barra superior con filtros y selector de biblioteca
                    VStack(spacing: 8) {
                        // Fila 1: Filtros de lectura y biblioteca remota del servidor
                        HStack {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(LibraryFilter.allCases) { filter in
                                        Button(filter.label(language: appState.currentLanguage)) {
                                            selectedFilter = filter
                                        }
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            selectedFilter == filter ?
                                            Color.cyan : Color.white.opacity(0.08),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(
                                            selectedFilter == filter ? Color.black : Color.white
                                        )
                                    }
                                }
                            }
                            
                            // Menú de Bibliotecas de Kaizen
                            if !appState.libraries.isEmpty {
                                Menu {
                                    Button(isEn ? "All Server Libraries" : "Todas las bibliotecas") {
                                        selectedLibraryId = nil
                                    }
                                    Divider()
                                    ForEach(appState.libraries) { lib in
                                        Button(lib.displayTitle) {
                                            selectedLibraryId = lib.id
                                        }
                                    }
                                    Divider()
                                    Button(isEn ? "Add Library..." : "Añadir biblioteca...") {
                                        newLibraryPath = ""
                                        creationError = nil
                                        showCreateLibraryAlert = true
                                    }
                                } label: {
                                    Image(systemName: selectedLibraryId != nil ? "folder.fill.badge.gearshape" : "folder.badge.gearshape")
                                        .font(.headline)
                                        .foregroundStyle(selectedLibraryId != nil ? Color.black : Color.cyan)
                                        .padding(8)
                                        .background(selectedLibraryId != nil ? Color.cyan : Color.white.opacity(0.08), in: Circle())
                                }
                            }
                        }
                        
                        // Fila 2: Filtros por Tipo (Estado) y Género
                        HStack(spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    // Selector de Tipo / Estado
                                    Menu {
                                        Button(isEn ? "All Types" : "Todos los tipos") {
                                            selectedStatus = nil
                                        }
                                        Divider()
                                        ForEach(availableStatuses, id: \.self) { status in
                                            Button(localizedStatus(status)) {
                                                selectedStatus = status
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "line.3.horizontal.decrease.circle")
                                            Text(selectedStatus == nil ? (isEn ? "Type: All" : "Tipo: Todos") : localizedStatus(selectedStatus!))
                                                .fontWeight(.medium)
                                            Image(systemName: "chevron.down")
                                                .font(.caption2)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            selectedStatus != nil ? Color.cyan : Color.white.opacity(0.07),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(selectedStatus != nil ? Color.black : Color.white)
                                    }
                                    
                                    // Selector de Género
                                    if !availableGenres.isEmpty {
                                        Menu {
                                            Button(isEn ? "All Genres" : "Todos los géneros") {
                                                selectedGenre = nil
                                            }
                                            Divider()
                                            ForEach(availableGenres, id: \.self) { genre in
                                                Button(genre) {
                                                    selectedGenre = genre
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: "tag")
                                                Text(selectedGenre == nil ? (isEn ? "Genre: All" : "Género: Todos") : selectedGenre!)
                                                    .fontWeight(.medium)
                                                Image(systemName: "chevron.down")
                                                    .font(.caption2)
                                            }
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                selectedGenre != nil ? Color.cyan : Color.white.opacity(0.07),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(selectedGenre != nil ? Color.black : Color.white)
                                        }
                                    }
                                    
                                    // Botón para resetear filtros si hay alguno activo
                                    if hasActiveFilters {
                                        Button(action: resetFilters) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "xmark.circle.fill")
                                                Text(isEn ? "Clear" : "Limpiar")
                                            }
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    // Contenido
                    if appState.isLoadingLibrary && appState.mangas.isEmpty {
                        Spacer()
                        ProgressView().tint(.cyan)
                        Spacer()
                    } else if filteredMangas.isEmpty {
                        Spacer()
                        if let error = appState.libraryErrorMessage {
                            VStack(spacing: 14) {
                                ContentUnavailableView(
                                    isEn ? "Failed to load library" : "No se pudo cargar la biblioteca",
                                    systemImage: "exclamationmark.triangle",
                                    description: Text(error)
                                )
                                Button(isEn ? "Retry" : "Reintentar") {
                                    Task {
                                        await appState.loadLibrary(client: apiClient, force: true)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            VStack(spacing: 16) {
                                ContentUnavailableView(
                                    isEn ? "No manga found" : "No hay mangas",
                                    systemImage: "books.vertical",
                                    description: Text(hasActiveFilters ? (isEn ? "No manga match the selected filters or search." : "Ningún manga coincide con los filtros o la búsqueda.") : (isEn ? "Your library is empty" : "Tu biblioteca está vacía"))
                                )
                                if hasActiveFilters {
                                    Button(isEn ? "Reset Filters" : "Restablecer filtros") {
                                        resetFilters()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.cyan)
                                }
                            }
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(filteredMangas) { manga in
                                    NavigationLink(value: manga) {
                                        MangaCardView(manga: manga)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            Task { await appState.toggleFavorite(mangaId: manga.id, client: apiClient) }
                                        } label: {
                                            Label(
                                                manga.isFavorite ? (isEn ? "Remove from favorites" : "Quitar de favoritos") : (isEn ? "Add to favorites" : "Añadir a favoritos"),
                                                systemImage: manga.isFavorite ? "heart.slash" : "heart.fill"
                                            )
                                        }
                                        
                                        if !appState.shelves.isEmpty {
                                            Menu(isEn ? "Shelves" : "Estanterías") {
                                                ForEach(appState.shelves) { shelf in
                                                    Button {
                                                        appState.toggleMangaInShelf(shelfId: shelf.id, mangaId: manga.id)
                                                    } label: {
                                                        let inShelf = appState.isMangaInShelf(shelfId: shelf.id, mangaId: manga.id)
                                                        Label(shelf.name, systemImage: inShelf ? "checkmark.circle.fill" : "circle")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                        .refreshable {
                            await appState.loadLibrary(client: apiClient, force: true)
                        }
                    }
                }
            }
            .navigationTitle(isEn ? "Library" : "Biblioteca")
            .searchable(text: $searchText, prompt: isEn ? "Search your catalog..." : "Buscar en tu catálogo...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await appState.loadLibrary(client: apiClient, force: true)
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(appState.isLoadingLibrary ? .cyan : .secondary)
                        }
                        .disabled(appState.isLoadingLibrary)
                        
                        if appState.isManagement {
                            Button {
                                showAddMangaSheet = true
                            } label: {
                                Label(isEn ? "Add Manga" : "Añadir Manga", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                }
            }
            .task {
                await appState.loadLibrary(client: apiClient, force: false)
            }
            .navigationDestination(for: Manga.self) { manga in
                MangaDetailView(manga: manga, apiClient: apiClient)
            }
            .sheet(isPresented: $showAddMangaSheet) {
                AddMangaRemoteSheet(apiClient: apiClient) {
                    Task { await appState.loadLibrary(client: apiClient, force: true) }
                }
            }
            .alert(isEn ? "New Server Library" : "Nueva Biblioteca", isPresented: $showCreateLibraryAlert) {
                TextField(isEn ? "Server path (e.g. /manga/manhwa)" : "Ruta en servidor (ej: /manga/manhwa)", text: $newLibraryPath)
                Button(isEn ? "Create" : "Crear") {
                    guard let session = appState.session, !newLibraryPath.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task {
                        do {
                            let newLib = try await apiClient.createLibrary(serverUrl: session.serverUrl, token: session.apiToken, path: newLibraryPath.trimmingCharacters(in: .whitespaces))
                            appState.libraries.append(newLib)
                        } catch {
                            creationError = error.localizedDescription
                        }
                    }
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            } message: {
                Text(isEn ? "Enter the absolute path on the server disk where manga will be stored." : "Introduce la ruta absoluta en el disco del servidor donde se alojarán los mangas.")
            }
        }
    }
}

/// Ficha completa e interactiva de Manga adaptada a iPad y iPhone, con control de Admin
public struct MangaDetailView: View {
    let manga: Manga
    let apiClient: KaizenAPIClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppState.self) private var appState
    
    @State private var detailedManga: Manga?
    @State private var isLoadingChapters: Bool = false
    @State private var readingChapter: Chapter?
    @State private var errorMessage: String?
    @State private var showCreateShelfAlert: Bool = false
    @State private var newShelfName: String = ""
    @State private var isCheckingNewChapters: Bool = false
    @State private var checkChaptersFeedback: (isSuccess: Bool, message: String)?
    
    // Búsqueda y ordenación de capítulos
    @State private var chapterSearchText: String = ""
    @State private var sortNewestFirst: Bool = true
    
    // Herramientas de Administrador y Control de Servidor
    @State private var configuredSources: [MangaConfiguredSource] = []
    @State private var isLoadingSources: Bool = false
    @State private var showSourcesSheet: Bool = false
    @State private var showRedownloadRangeAlert: Bool = false
    @State private var rangeStartChapter: String = "1"
    @State private var rangeEndChapter: String = "10"
    @State private var showDeleteMangaAlert: Bool = false
    @State private var alsoDeleteFiles: Bool = true
    @State private var chapterToDelete: Chapter?
    @State private var showDeleteChapterAlert: Bool = false
    @State private var adminActionToast: String?
    
    public init(manga: Manga, apiClient: KaizenAPIClient) {
        self.manga = manga
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private var isPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var currentManga: Manga {
        detailedManga ?? manga
    }
    
    private var chapters: [Chapter] {
        detailedManga?.chapters ?? currentManga.chapters ?? []
    }
    
    private var filteredChapters: [Chapter] {
        let base: [Chapter]
        if chapterSearchText.trimmingCharacters(in: .whitespaces).isEmpty {
            base = chapters
        } else {
            let query = chapterSearchText.trimmingCharacters(in: .whitespaces).lowercased()
            base = chapters.filter { ch in
                "\(ch.index)".contains(query) ||
                (ch.fileName?.localizedCaseInsensitiveContains(query) ?? false) ||
                ch.displayName.localizedCaseInsensitiveContains(query)
            }
        }
        return base.sorted {
            sortNewestFirst ? ($0.index > $1.index) : ($0.index < $1.index)
        }
    }
    
    private var isCaughtUp: Bool {
        if chapters.isEmpty { return false }
        return chapters.allSatisfy { $0.isRead } || currentManga.safeReadingPercentage >= 100
    }
    
    private var nextUnreadChapter: Chapter? {
        chapters.sorted { $0.index < $1.index }.first { !$0.isRead }
    }
    
    // Columnas adaptativas para iPad: 2-3 columnas de capítulos cómodos
    private let padGridColumns = [
        GridItem(.adaptive(minimum: 280, maximum: 440), spacing: 12)
    ]
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isPad {
                // Modo Dividido en iPad: Izquierda Manga & Metadata (y opciones admin si es admin), Derecha Capítulos
                HStack(alignment: .top, spacing: 0) {
                    // Columna Izquierda: Portada, Metadata, Sinopsis y Admin si aplica
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            headerHeroSection
                            feedbackBanners
                            primaryActionButton
                            
                            if let synopsis = currentManga.synopsis, !synopsis.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(isEn ? "Synopsis" : "Sinopsis")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(synopsis)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(14)
                                }
                            }
                            
                            // Opciones de Administrador y Servidor (visibles únicamente si es Admin)
                            if appState.isManagement {
                                serverControlSection
                                sourcesInlineSection
                            }
                        }
                        .padding(20)
                        .padding(.bottom, 30)
                    }
                    .frame(width: 440)
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                        .ignoresSafeArea()
                    
                    // Columna Derecha: Listado completo de Capítulos con buscador y ordenación
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            chaptersSection
                        }
                        .padding(20)
                        .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                // Modo Vertical en iPhone
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerHeroSection
                        feedbackBanners
                        primaryActionButton
                        
                        if let synopsis = currentManga.synopsis, !synopsis.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(isEn ? "Synopsis" : "Sinopsis")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(synopsis)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(6)
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        // Opciones de Administrador y Servidor (visibles únicamente si es Admin)
                        if appState.isManagement {
                            serverControlSection
                            sourcesInlineSection
                        }
                        
                        // Listado de Capítulos
                        chaptersSection
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(currentManga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    // Menú de Herramientas de Administrador
                    if appState.isManagement {
                        Menu {
                            Section(isEn ? "Server Control" : "Control de Servidor") {
                                Button {
                                    showSourcesSheet = true
                                } label: {
                                    Label(isEn ? "Manga Sources..." : "Gestionar Fuentes...", systemImage: "antenna.radiowaves.left.and.right")
                                }
                                
                                Button {
                                    rangeStartChapter = "1"
                                    rangeEndChapter = "\(max(chapters.count, 10))"
                                    showRedownloadRangeAlert = true
                                } label: {
                                    Label(isEn ? "Redownload Chapter Range..." : "Redescargar Rango...", systemImage: "arrow.triangle.2.circlepath")
                                }
                                
                                Button {
                                    auditMangaIntegrity()
                                } label: {
                                    Label(isEn ? "Audit Files Integrity" : "Auditar Integridad", systemImage: "checkmark.shield")
                                }
                                
                                Button {
                                    toggleMangaLock()
                                } label: {
                                    Label(
                                        currentManga.isLocked ? (isEn ? "Unlock Manga Updates" : "Desbloquear Actualizaciones") : (isEn ? "Lock Manga Updates" : "Bloquear Actualizaciones"),
                                        systemImage: currentManga.isLocked ? "lock.open" : "lock"
                                    )
                                }
                            }
                            
                            Divider()
                            
                            Section {
                                Button(role: .destructive) {
                                    showDeleteMangaAlert = true
                                } label: {
                                    Label(isEn ? "Delete Manga from Server..." : "Eliminar Manga del Servidor...", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.subheadline)
                                .foregroundStyle(.cyan)
                                .padding(8)
                                .background(Color.cyan.opacity(0.15), in: Circle())
                        }
                    }
                }
            }
        }
        .task {
            await loadDetail()
        }
        .fullScreenCover(item: $readingChapter) { chapter in
            let safePage = (chapter.lastReadPage > 0 && chapter.lastReadPage < 9000) ? chapter.lastReadPage : 1
            ReaderView(
                manga: currentManga,
                mangaId: currentManga.id,
                chapterId: chapter.id,
                chapterIndex: chapter.index,
                initialPage: safePage,
                allChapters: detailedManga?.chapters ?? [],
                apiClient: apiClient
            )
            .onDisappear {
                Task { await loadDetail() }
            }
        }
        .sheet(isPresented: $showSourcesSheet) {
            MangaSourcesManagementSheet(manga: currentManga, apiClient: apiClient) {
                Task { await loadDetail() }
            }
        }
        .alert(isEn ? "Redownload Chapter Range" : "Redescargar Rango de Capítulos", isPresented: $showRedownloadRangeAlert) {
            TextField(isEn ? "Start Chapter (e.g. 1)" : "Capítulo Inicio (ej: 1)", text: $rangeStartChapter)
            TextField(isEn ? "End Chapter (e.g. 20)" : "Capítulo Fin (ej: 20)", text: $rangeEndChapter)
            Button(isEn ? "Redownload" : "Redescargar") {
                executeRedownloadRange()
            }
            Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
        } message: {
            Text(isEn ? "Re-queues all chapters in this range for redownload on Kaizen server." : "Encola la redescarga completa de los capítulos seleccionados en el servidor Kaizen.")
        }
        .alert(isEn ? "Delete Chapter" : "Eliminar Capítulo", isPresented: $showDeleteChapterAlert) {
            Button(isEn ? "Delete File & Chapter" : "Eliminar Capítulo y Archivo", role: .destructive) {
                if let ch = chapterToDelete {
                    executeDeleteChapter(ch)
                }
            }
            Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
        } message: {
            if let ch = chapterToDelete {
                Text(isEn ? "Are you sure you want to delete \(ch.displayName)? The physical file on the server will be deleted." : "¿Seguro que quieres borrar el \(ch.displayName)? El archivo se borrará permanentemente del servidor.")
            }
        }
        .alert(isEn ? "Delete Series from Kaizen" : "Eliminar Manga de Kaizen", isPresented: $showDeleteMangaAlert) {
            Button(isEn ? "Delete from Server & Disk" : "Eliminar de Servidor y Disco", role: .destructive) {
                executeDeleteManga(deleteFiles: true)
            }
            Button(isEn ? "Unlink Only (Keep Files)" : "Solo Desvincular (Conservar Archivos)") {
                executeDeleteManga(deleteFiles: false)
            }
            Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
        } message: {
            Text(isEn ? "This will remove the series from your Kaizen library." : "Esto eliminará la serie de tu catálogo de Kaizen.")
        }
        .alert(isEn ? "New Reading Library" : "Nueva Librería de Lectura", isPresented: $showCreateShelfAlert) {
            TextField(isEn ? "e.g. Masterpieces, Re-read, Top Tier..." : "Ej: Obras maestras, Relecturas, Favoritos...", text: $newShelfName)
            Button(isEn ? "Create & Add" : "Crear y Añadir") {
                let name = newShelfName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    let newShelf = UserShelf(name: name, icon: "books.vertical.fill", mangaIds: [currentManga.id])
                    appState.shelves.append(newShelf)
                    appState.saveShelves()
                }
            }
            Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
        } message: {
            Text(isEn ? "Create a custom reading library and automatically add this manga to it." : "Crea una librería de lectura y asigna este manga inmediatamente.")
        }
    }
    
    // MARK: - Cabecera Hero Adaptativa
    
    private var headerHeroSection: some View {
        HStack(alignment: .top, spacing: isPad ? 24 : 16) {
            // Portada con tamaño ampliado en iPad
            MangaCardView(manga: currentManga)
                .frame(width: isPad ? 210 : 135)
                .shadow(color: Color.cyan.opacity(0.2), radius: 12, y: 6)
            
            VStack(alignment: .leading, spacing: isPad ? 12 : 8) {
                Text(currentManga.title)
                    .font(isPad ? .title.weight(.bold) : .title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                
                if let authors = currentManga.authors, !authors.isEmpty {
                    Text(authors.joined(separator: ", "))
                        .font(isPad ? .headline : .subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Badges de Estado y Bloqueo
                HStack(spacing: 8) {
                    Text(currentManga.status == "COMPLETED" ? (isEn ? "Completed" : "Finalizado") : (isEn ? "Ongoing" : "En emisión"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(currentManga.status == "COMPLETED" ? Color.purple.opacity(0.2) : Color.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(currentManga.status == "COMPLETED" ? Color.purple : Color.green)
                    
                    if currentManga.isLocked {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text(isEn ? "Locked" : "Bloqueado")
                        }
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                    }
                    
                    if isCaughtUp {
                        Text(isEn ? "Caught Up" : "Al día")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.2), in: Capsule())
                            .foregroundStyle(.cyan)
                    }
                }
                
                // Porcentaje de lectura
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(isEn ? "Progress: \(Int(currentManga.readingPercentage))%" : "Progreso: \(Int(currentManga.readingPercentage))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(currentManga.totalChapters - currentManga.unreadCount)/\(currentManga.totalChapters) " + (isEn ? "ch." : "cap."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max(currentManga.readingPercentage / 100.0, 0), 1))
                        .tint(.cyan)
                }
                
                // Botones Rápidos: Favorito, Librerías, Comprobar
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await appState.toggleFavorite(mangaId: currentManga.id, client: apiClient)
                            detailedManga?.isFavorite.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: currentManga.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(currentManga.isFavorite ? .pink : .white)
                            Text(isEn ? "Favorite" : "Favorito")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    Menu {
                        ForEach(appState.shelves) { shelf in
                            Button {
                                appState.toggleMangaInShelf(shelfId: shelf.id, mangaId: currentManga.id)
                            } label: {
                                let inShelf = appState.isMangaInShelf(shelfId: shelf.id, mangaId: currentManga.id)
                                Label(shelf.name, systemImage: inShelf ? "checkmark.circle.fill" : "circle")
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            newShelfName = ""
                            showCreateShelfAlert = true
                        } label: {
                            Label(isEn ? "+ New Reading Library..." : "+ Nueva librería de lectura...", systemImage: "plus")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "books.vertical.fill")
                                .foregroundStyle(.yellow)
                            Text(isEn ? "Libraries" : "Librerías")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        Task { await checkForNewChapters() }
                    } label: {
                        HStack(spacing: 6) {
                            if isCheckingNewChapters {
                                ProgressView().scaleEffect(0.65).tint(.cyan)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(isEn ? "Check" : "Comprobar")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                        .foregroundStyle(Color.cyan)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingNewChapters)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    
    // MARK: - Botón Principal de Continuación
    
    @ViewBuilder
    private var primaryActionButton: some View {
        if isCaughtUp {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                    Text(isEn ? "All Caught Up • Everything Read" : "¡Al día! Todo leído")
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.4), lineWidth: 1))
                .foregroundStyle(Color.green)
                
                if let firstCh = chapters.sorted(by: { $0.index < $1.index }).first {
                    Button {
                        readingChapter = firstCh
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text(isEn ? "Re-read from Chapter 1" : "Volver a leer desde el inicio")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 16)
        } else if let next = nextUnreadChapter {
            Button {
                readingChapter = next
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.fill")
                        .font(.headline)
                    let validPage = (next.lastReadPage > 0 && next.lastReadPage < 9000) ? next.lastReadPage : 1
                    if validPage > 1 {
                        Text(isEn ? "Continue Ch. \(next.index) (p. \(validPage))" : "Continuar Cap. \(next.index) (pág. \(validPage))")
                    } else {
                        Text(isEn ? "Read Chapter \(next.index)" : "Leer Capítulo \(next.index)")
                    }
                }
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.black)
                .shadow(color: Color.cyan.opacity(0.35), radius: 8, y: 4)
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Banners de Notificaciones y Feedback
    
    @ViewBuilder
    private var feedbackBanners: some View {
        if let feedback = checkChaptersFeedback {
            HStack(spacing: 8) {
                Image(systemName: feedback.isSuccess ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.subheadline)
                Text(feedback.message)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(feedback.isSuccess ? Color.green : Color.cyan)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((feedback.isSuccess ? Color.green : Color.cyan).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke((feedback.isSuccess ? Color.green : Color.cyan).opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        
        if let toast = adminActionToast {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.subheadline)
                Text(toast)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.cyan)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
            .padding(.horizontal, 16)
        }
        
        if let errorMsg = errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                Text(isEn ? "Error: \(errorMsg)" : "Error: \(errorMsg)")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Sección de Control de Servidor Kaizen (Paridad Web)
    
    private var serverControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(isEn ? "Server Administration" : "Control del Servidor", systemImage: "server.rack")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.cyan)
                
                Spacer()
                
                if currentManga.isLocked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text(isEn ? "Updates Locked" : "Actualizaciones Bloqueadas")
                    }
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
                }
            }
            
            // Botones de acción rápida en fila desplazable
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // 1. Redescargar Rango
                    Button {
                        rangeStartChapter = "1"
                        rangeEndChapter = "\(max(chapters.count, 10))"
                        showRedownloadRangeAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(isEn ? "Redownload Range" : "Redescargar Rango...")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    
                    // 2. Auditar Integridad de Archivos
                    Button {
                        auditMangaIntegrity()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield")
                            Text(isEn ? "Audit Files" : "Auditar Integridad")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    
                    // 3. Bloquear / Desbloquear Actualizaciones
                    Button {
                        toggleMangaLock()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: currentManga.isLocked ? "lock.open" : "lock")
                            Text(currentManga.isLocked ? (isEn ? "Unlock Updates" : "Desbloquear") : (isEn ? "Lock Updates" : "Bloquear"))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(currentManga.isLocked ? .orange : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background((currentManga.isLocked ? Color.orange : Color.white).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke((currentManga.isLocked ? Color.orange : Color.white).opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    
                    // 4. Eliminar Manga del Servidor
                    Button {
                        showDeleteMangaAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text(isEn ? "Delete Manga..." : "Eliminar del Servidor...")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Sección de Fuentes (MangaSources - Paridad Web)
    
    private var sourcesHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.purple)
                Text(isEn ? "Configured Sources (\(max(configuredSources.count, 1)))" : "Fuentes de la Serie (\(max(configuredSources.count, 1)))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            Button {
                showSourcesSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text(isEn ? "Add Source" : "Añadir Fuente")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
    
    private var sourcesEmptyPlaceholder: some View {
        HStack(spacing: 10) {
            // Badge fuente inicial
            Text(currentManga.source ?? "Default")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.25), in: Capsule())
                .foregroundStyle(Color.purple)
            
            Text(isEn ? "Default Primary Source" : "Fuente Principal de la Serie")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                showSourcesSheet = true
            } label: {
                Text(isEn ? "Configure" : "Configurar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func sourceRowItem(index: Int, src: MangaConfiguredSource) -> some View {
        HStack(spacing: 10) {
            // Badge de Scraper
            Text(src.source)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(index == 0 ? Color.cyan.opacity(0.25) : Color.purple.opacity(0.25), in: Capsule())
                .foregroundStyle(index == 0 ? Color.cyan : Color.purple)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(src.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if index == 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                        Text(isEn ? "Primary" : "Principal")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.yellow)
                    }
                }
            }
            
            Spacer()
            
            if index != 0 {
                Button {
                    promoteToPrimarySource(src)
                } label: {
                    Text(isEn ? "Set Primary" : "Hacer Principal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.cyan.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            
            Button {
                deleteSource(src)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.75))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var sourcesInlineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourcesHeader
            
            if configuredSources.isEmpty {
                sourcesEmptyPlaceholder
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(configuredSources.enumerated()), id: \.element.id) { index, src in
                        sourceRowItem(index: index, src: src)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Sección de Capítulos con Búsqueda y Grid Adaptativo para iPad
    
    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Barra de Título, Filtro y Ordenación
            HStack(spacing: 12) {
                Text((isEn ? "Chapters (" : "Capítulos (") + "\(filteredChapters.count)/\(chapters.count))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                // Botón de Ordenación Ascendente / Descendente
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sortNewestFirst.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortNewestFirst ? "arrow.down" : "arrow.up")
                        Text(sortNewestFirst ? (isEn ? "Newest" : "Recientes") : (isEn ? "Oldest" : "Primeros"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                
                if !chapters.isEmpty {
                    Button(isEn ? "Mark all read" : "Marcar todo leído") {
                        markAllAsRead()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                }
            }
            .padding(.horizontal, 16)
            
            // Buscador rápido de capítulo si la serie tiene más de 10 capítulos
            if chapters.count > 10 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(isEn ? "Filter by chapter # (e.g. 45)..." : "Filtrar por número (ej: 45)...", text: $chapterSearchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    if !chapterSearchText.isEmpty {
                        Button {
                            chapterSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
            }
            
            // Contenido de Capítulos
            if isLoadingChapters && chapters.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(.cyan)
                    Spacer()
                }
                .padding(.vertical, 30)
            } else if filteredChapters.isEmpty {
                Text(isEn ? "No matching chapters found" : "No se encontraron capítulos coincidentes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            } else {
                if isPad {
                    // Modo Cuadrícula Adaptativa en iPad (2-3 columnas para aprovechar la pantalla completa)
                    LazyVGrid(columns: padGridColumns, spacing: 12) {
                        ForEach(filteredChapters, id: \.uniqueKey) { chapter in
                            chapterCardRow(chapter)
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    // Modo Lista en iPhone
                    LazyVStack(spacing: 8) {
                        ForEach(filteredChapters, id: \.uniqueKey) { chapter in
                            chapterCardRow(chapter)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    // MARK: - Tarjeta de Fila de Capítulo
    
    @ViewBuilder
    private func chapterCardRow(_ chapter: Chapter) -> some View {
        HStack(spacing: 12) {
            Button {
                readingChapter = chapter
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(chapter.isRead ? Color.cyan.opacity(0.18) : Color.white.opacity(0.08))
                            .frame(width: 42, height: 42)
                        Text("\(chapter.index)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(chapter.isRead ? Color.cyan : Color.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chapter.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            if chapter.lastReadPage > 0 && !chapter.isRead {
                                Text(isEn ? "Page \(chapter.lastReadPage)" : "Pág. \(chapter.lastReadPage)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.cyan)
                            }
                            
                            if let formattedSize = chapter.formattedSize {
                                Text(formattedSize)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            // Acciones por capítulo
            HStack(spacing: 8) {
                // Si es admin: botón directo de redescargar
                if appState.isManagement {
                    Button {
                        redownloadSingleChapter(chapter)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.cyan)
                            .padding(7)
                            .background(Color.cyan.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isEn ? "Redownload chapter on server" : "Redescargar capítulo en el servidor")
                }
                
                // Botón de marcar leído/no leído (disponible para todos)
                Button {
                    toggleChapterRead(chapter)
                } label: {
                    Image(systemName: chapter.isRead ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(chapter.isRead ? Color.cyan : Color.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                
                // Si es admin: botón directo de eliminar capítulo y archivo de disco
                if appState.isManagement {
                    Button {
                        chapterToDelete = chapter
                        showDeleteChapterAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .padding(7)
                            .background(Color.red.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isEn ? "Delete chapter and file from server" : "Eliminar capítulo y archivo del servidor")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(chapter.isRead ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .contextMenu {
            if appState.isManagement {
                Button {
                    redownloadSingleChapter(chapter)
                } label: {
                    Label(isEn ? "Redownload Chapter" : "Redescargar capítulo", systemImage: "arrow.triangle.2.circlepath")
                }
                
                Button {
                    reportChapterCorrupt(chapter)
                } label: {
                    Label(isEn ? "Report Corrupt" : "Reportar corrupto", systemImage: "flag")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    chapterToDelete = chapter
                    showDeleteChapterAlert = true
                } label: {
                    Label(isEn ? "Delete Chapter from Server" : "Eliminar del servidor", systemImage: "trash")
                }
            } else {
                Button {
                    toggleChapterRead(chapter)
                } label: {
                    Label(chapter.isRead ? (isEn ? "Mark as unread" : "Marcar como no leído") : (isEn ? "Mark as read" : "Marcar como leído"), systemImage: chapter.isRead ? "circle" : "checkmark.circle")
                }
            }
        }
    }
    
    // MARK: - Métodos de Carga y Sincronización
    
    private func loadDetail() async {
        guard let session = appState.session else { return }
        KaizenLogger.shared.info("MangaDetail", "Cargando ficha de '\(currentManga.title)' (ID: \(currentManga.id))")
        isLoadingChapters = true
        defer { isLoadingChapters = false }
        do {
            let detail = try await apiClient.fetchMangaDetail(serverUrl: session.serverUrl, token: session.apiToken, mangaId: currentManga.id)
            self.detailedManga = detail
            appState.updateMangaInState(detail)
            errorMessage = nil
            KaizenLogger.shared.info("MangaDetail", "Ficha actualizada con éxito: '\(detail.title)' con \(detail.chapters?.count ?? 0) capítulos")
        } catch {
            errorMessage = error.localizedDescription
            KaizenLogger.shared.error("MangaDetail", "Error al cargar capítulos de '\(currentManga.title)' (ID: \(currentManga.id))", details: error.localizedDescription)
        }
        
        if appState.isManagement {
            do {
                let srcs = try await apiClient.fetchMangaSources(serverUrl: session.serverUrl, token: session.apiToken, mangaId: currentManga.id)
                self.configuredSources = srcs
            } catch {
                // Mantener estado previo si falla la llamada
            }
        }
    }
    
    private func promoteToPrimarySource(_ src: MangaConfiguredSource) {
        guard let session = appState.session else { return }
        Task {
            do {
                try await apiClient.switchMangaPrimarySource(
                    serverUrl: session.serverUrl,
                    token: session.apiToken,
                    mangaId: currentManga.id,
                    newSource: src.source,
                    newSourceTitle: src.title
                )
                adminActionToast = isEn ? "Primary source switched to \(src.source)" : "Fuente principal cambiada a \(src.source)"
                await loadDetail()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func deleteSource(_ src: MangaConfiguredSource) {
        guard let session = appState.session else { return }
        Task {
            do {
                try await apiClient.removeMangaSource(
                    serverUrl: session.serverUrl,
                    token: session.apiToken,
                    sourceId: src.id
                )
                adminActionToast = isEn ? "Source removed" : "Fuente eliminada"
                await loadDetail()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func checkForNewChapters() async {
        guard let session = appState.session else { return }
        isCheckingNewChapters = true
        checkChaptersFeedback = nil
        defer { isCheckingNewChapters = false }
        
        let initialCount = currentManga.totalChapters
        
        do {
            try await apiClient.syncManga(serverUrl: session.serverUrl, token: session.apiToken, mangaId: currentManga.id)
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            let updated = try await apiClient.fetchMangaDetail(serverUrl: session.serverUrl, token: session.apiToken, mangaId: currentManga.id)
            self.detailedManga = updated
            appState.updateMangaInState(updated)
            
            let diff = updated.totalChapters - initialCount
            if diff > 0 {
                checkChaptersFeedback = (
                    isSuccess: true,
                    message: isEn
                        ? "🎉 Found \(diff) new chapter(s)! Queued and downloading on Kaizen server."
                        : "🎉 ¡Se han encontrado \(diff) capítulo(s) nuevo(s)! Están encolados y descargándose en el servidor."
                )
            } else {
                checkChaptersFeedback = (
                    isSuccess: true,
                    message: isEn
                        ? "You're all caught up! No new chapters found right now."
                        : "¡Estás al día! No hay capítulos nuevos disponibles en este momento."
                )
            }
        } catch {
            checkChaptersFeedback = (isSuccess: false, message: error.localizedDescription)
        }
    }
    
    private func toggleChapterRead(_ chapter: Chapter) {
        guard let session = appState.session else { return }
        let newRead = !chapter.isRead
        if let idx = detailedManga?.chapters?.firstIndex(where: { $0.id == chapter.id }) {
            detailedManga?.chapters?[idx].isRead = newRead
        }
        Task {
            try? await apiClient.toggleChapterRead(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: currentManga.id,
                chapterId: chapter.id,
                isRead: newRead
            )
            await loadDetail()
        }
    }
    
    private func markAllAsRead() {
        guard let session = appState.session else { return }
        detailedManga?.chapters = detailedManga?.chapters?.map {
            var ch = $0
            ch.isRead = true
            return ch
        }
        Task {
            try? await apiClient.markAllChaptersRead(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: currentManga.id,
                isRead: true
            )
            await loadDetail()
        }
    }
    
    // MARK: - Acciones de Administrador
    
    private func redownloadSingleChapter(_ chapter: Chapter) {
        guard let session = appState.session else { return }
        Task {
            do {
                try await apiClient.redownloadChapter(serverUrl: session.serverUrl, token: session.apiToken, chapterId: chapter.id)
                adminActionToast = isEn ? "Chapter \(chapter.index) queued for redownload." : "Capítulo \(chapter.index) encolado para redescarga."
                await loadDetail()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func reportChapterCorrupt(_ chapter: Chapter) {
        guard let session = appState.session else { return }
        Task {
            do {
                try await apiClient.reportCorruptChapter(serverUrl: session.serverUrl, token: session.apiToken, chapterId: chapter.id)
                adminActionToast = isEn ? "Chapter \(chapter.index) reported corrupt. Audit scheduled." : "Capítulo \(chapter.index) reportado. Auditoría programada."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func executeDeleteChapter(_ chapter: Chapter) {
        guard let session = appState.session else { return }
        Task {
            do {
                try await apiClient.deleteChapter(serverUrl: session.serverUrl, token: session.apiToken, chapterId: chapter.id)
                adminActionToast = isEn ? "Chapter \(chapter.index) deleted from server." : "Capítulo \(chapter.index) eliminado del servidor."
                await loadDetail()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func executeRedownloadRange() {
        guard let session = appState.session,
              let start = Int(rangeStartChapter.trimmingCharacters(in: .whitespaces)),
              let end = Int(rangeEndChapter.trimmingCharacters(in: .whitespaces)) else { return }
        Task {
            do {
                try await apiClient.redownloadChapterRange(
                    serverUrl: session.serverUrl,
                    token: session.apiToken,
                    mangaId: currentManga.id,
                    startChapter: start,
                    endChapter: end
                )
                adminActionToast = isEn ? "Range \(start)-\(end) queued for redownload." : "Rango \(start)-\(end) encolado para redescarga."
                await loadDetail()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func auditMangaIntegrity() {
        guard let session = appState.session else { return }
        Task {
            do {
                try await apiClient.auditMangaIntegrity(serverUrl: session.serverUrl, token: session.apiToken, mangaId: currentManga.id)
                adminActionToast = isEn ? "Integrity audit started for this series." : "Auditoría de integridad iniciada para esta serie."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func toggleMangaLock() {
        guard let session = appState.session else { return }
        let newLocked = !currentManga.isLocked
        Task {
            do {
                try await apiClient.toggleMangaLock(serverUrl: session.serverUrl, token: session.apiToken, mangaId: currentManga.id, isLocked: newLocked)
                adminActionToast = newLocked
                    ? (isEn ? "Manga updates locked." : "Actualizaciones automáticas bloqueadas.")
                    : (isEn ? "Manga updates unlocked." : "Actualizaciones automáticas desbloqueadas.")
                await loadDetail()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func executeDeleteManga(deleteFiles: Bool) {
        guard let session = appState.session else { return }
        Task {
            do {
                try await apiClient.deleteManga(serverUrl: session.serverUrl, token: session.apiToken, mangaId: currentManga.id, shouldRemoveFiles: deleteFiles)
                appState.mangas.removeAll { $0.id == currentManga.id }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Compatibilidad con código existente
public typealias MangaDetailSheet = MangaDetailView

