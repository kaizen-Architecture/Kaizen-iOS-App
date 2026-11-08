import SwiftUI

public enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case reading = "Leyendo"
    case caughtUp = "Al día"
    case completed = "Completadas"
    case favorites = "Favoritos"
    
    public var id: String { rawValue }
    
    public func label(language: String) -> String {
        switch self {
        case .all: return language == "en" ? "All" : "Todos"
        case .reading: return language == "en" ? "Reading" : "Leyendo"
        case .caughtUp: return language == "en" ? "Caught Up" : "Al día"
        case .completed: return language == "en" ? "Completed" : "Completadas"
        case .favorites: return language == "en" ? "Favorites" : "Favoritos"
        }
    }
}

public enum CaughtUpSubFilter: String, CaseIterable, Identifiable {
    case all, ongoing, completed, hiatus
    public var id: String { rawValue }
    
    public func label(language: String) -> String {
        let isEn = language == "en"
        switch self {
        case .all: return isEn ? "All" : "Todas"
        case .ongoing: return isEn ? "Publishing" : "En emisión"
        case .completed: return isEn ? "Completed" : "Finalizadas"
        case .hiatus: return isEn ? "Hiatus" : "En pausa"
        }
    }
}

public enum LibraryDisplayMode: String, Sendable {
    /// Vista unificada (Catálogo completo + Leyendo + Favoritos + Estanterías propias)
    case unifiedCatalog
    /// Espacio personal del lector (Leyendo ahora + Favoritos + Estanterías digitales propias)
    case personalReading
    /// Catálogo general del servidor para explorar (Discover para el Reader)
    case discoverCatalog
}

public struct LibraryView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    let mode: LibraryDisplayMode
    
    @State private var selectedFilter: LibraryFilter
    @State private var caughtUpSubFilter: CaughtUpSubFilter = .all
    @State private var selectedShelfId: UUID? = nil
    @State private var selectedLibraryId: Int? = nil
    @State private var selectedStatus: String? = nil
    @State private var selectedGenre: String? = nil
    @State private var searchText: String = ""
    
    @State private var showCreateLibraryAlert = false
    @State private var showAddMangaSheet = false
    @State private var showQueueSheet = false
    @State private var newLibraryPath = ""
    @State private var creationError: String?
    
    // Gestión de estanterías personalizadas (unificadas aquí)
    @State private var showCreateShelfAlert = false
    @State private var newShelfName = ""
    @State private var shelfToRename: UserShelf? = nil
    @State private var renameShelfText = ""
    @State private var showRenameShelfAlert = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 125, maximum: 180), spacing: 16, alignment: .top)
    ]
    
    public init(apiClient: KaizenAPIClient, mode: LibraryDisplayMode = .unifiedCatalog) {
        self.apiClient = apiClient
        self.mode = mode
        self._selectedFilter = State(initialValue: mode == .personalReading ? .reading : .all)
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private var navigationTitleText: String {
        switch mode {
        case .unifiedCatalog:
            return isEn ? "Library" : "Biblioteca"
        case .personalReading:
            return isEn ? "Library" : "Biblioteca"
        case .discoverCatalog:
            return isEn ? "Explore" : "Explorar"
        }
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
        let defaultFilter: LibraryFilter = mode == .personalReading ? .reading : .all
        return selectedFilter != defaultFilter || selectedShelfId != nil || selectedLibraryId != nil || selectedStatus != nil || selectedGenre != nil || !searchText.isEmpty
    }
    
    private func resetFilters() {
        selectedFilter = mode == .personalReading ? .reading : .all
        selectedShelfId = nil
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
            
            let matchesFilterOrShelf: Bool
            if let shelfId = selectedShelfId,
               let shelf = appState.shelves.first(where: { $0.id == shelfId }) {
                matchesFilterOrShelf = shelf.mangaIds.contains(manga.id)
            } else {
                switch selectedFilter {
                case .all:
                    if mode == .personalReading {
                        let inAnyShelf = appState.shelves.contains { $0.mangaIds.contains(manga.id) }
                        matchesFilterOrShelf = manga.isFavorite || manga.readingPercentage > 0 || inAnyShelf
                    } else {
                        matchesFilterOrShelf = true
                    }
                case .reading:
                    let inHistory = appState.history.contains { $0.mangaId == manga.id }
                    let hasStarted = (manga.totalChapters > manga.unreadCount && manga.totalChapters > 0)
                        || (manga.readingPercentage > 0 && manga.readingPercentage < 100)
                        || inHistory
                    let hasUnread = manga.unreadCount > 0 || manga.readingPercentage < 100
                    matchesFilterOrShelf = hasStarted && hasUnread
                case .caughtUp:
                    let inHistory = appState.history.contains { $0.mangaId == manga.id }
                    let hasStarted = (manga.totalChapters > 0 && manga.totalChapters > manga.unreadCount)
                        || manga.readingPercentage > 0
                        || inHistory
                    let noUnread = manga.unreadCount == 0 && manga.totalChapters > 0
                    let isCaughtUpBase = (hasStarted && noUnread) || (manga.readingPercentage >= 100 && manga.unreadCount == 0)
                    
                    if !isCaughtUpBase {
                        matchesFilterOrShelf = false
                    } else {
                        switch caughtUpSubFilter {
                        case .all:
                            matchesFilterOrShelf = true
                        case .ongoing:
                            matchesFilterOrShelf = manga.isOngoing
                        case .completed:
                            matchesFilterOrShelf = manga.isCompleted
                        case .hiatus:
                            matchesFilterOrShelf = manga.isHiatus
                        }
                    }
                case .completed:
                    let inHistory = appState.history.contains { $0.mangaId == manga.id }
                    let hasRead = manga.readingPercentage >= 100 || (manga.totalChapters > 0 && manga.unreadCount == 0) || inHistory
                    matchesFilterOrShelf = manga.isCompleted && hasRead
                case .favorites:
                    matchesFilterOrShelf = manga.isFavorite
                }
            }
            
            return matchesSearch && matchesLibrary && matchesStatus && matchesGenre && matchesFilterOrShelf
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topFilterBars
                mainCatalogContent
            }
            .ambientGlowBackground()
            .overlay(alignment: .top) {
                SyncProgressBanner()
            }
            .navigationTitle(navigationTitleText)
            .searchable(text: $searchText, prompt: isEn ? "Search title, author, genre..." : "Buscar título, autor, género...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    InAppLanguageToggle(apiClient: apiClient)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarTrailingButtons
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
            .sheet(isPresented: $showQueueSheet) {
                LiveDownloadQueueSheet(apiClient: apiClient)
            }
            .alert(isEn ? "New Reading Shelf" : "Nueva Estantería", isPresented: $showCreateShelfAlert) {
                TextField(isEn ? "e.g. Manhwa Top, To Re-read..." : "Ej: Manhwa Top, Para releer...", text: $newShelfName)
                Button(isEn ? "Create" : "Crear") {
                    appState.createShelf(name: newShelfName)
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            } message: {
                Text(isEn ? "Organize your series into custom shelves. A manga can belong to multiple shelves." : "Organiza tus series en estanterías personalizadas. Un manga puede estar en varias a la vez.")
            }
            .alert(isEn ? "Rename Shelf" : "Renombrar Estantería", isPresented: $showRenameShelfAlert) {
                TextField(isEn ? "Shelf name" : "Nombre de la estantería", text: $renameShelfText)
                Button(isEn ? "Save" : "Guardar") {
                    if let s = shelfToRename {
                        appState.renameShelf(id: s.id, newName: renameShelfText)
                    }
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
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
    
    // MARK: - Subvistas de Filtros y Cabecera de Biblioteca
    
    private var topFilterBars: some View {
        VStack(spacing: 8) {
            if mode != .discoverCatalog {
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LibraryFilter.allCases) { filter in
                                if !(mode == .personalReading && filter == .all) {
                                    let isSelected = (selectedShelfId == nil && selectedFilter == filter)
                                    Button {
                                        selectedShelfId = nil
                                        selectedFilter = filter
                                    } label: {
                                        HStack(spacing: 5) {
                                            if filter == .favorites {
                                                Image(systemName: "heart.fill")
                                                    .font(.caption2)
                                            } else if filter == .reading {
                                                Image(systemName: "play.fill")
                                                    .font(.caption2)
                                            } else if filter == .caughtUp {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption2)
                                            } else if filter == .completed {
                                                Image(systemName: "flag.checkered")
                                                    .font(.caption2)
                                            }
                                            Text(filter.label(language: appState.currentLanguage))
                                        }
                                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(isSelected ? Color.black : Color.white)
                                        .kaizenGlass(interactive: true, tint: isSelected ? .cyan : nil, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            // Píldoras de Estanterías Personalizadas del Usuario
                            ForEach(appState.shelves) { shelf in
                                let isShelfSelected = (selectedShelfId == shelf.id)
                                HStack(spacing: 4) {
                                    Button {
                                        selectedShelfId = shelf.id
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "folder.fill")
                                                .font(.caption2)
                                            Text(shelf.name)
                                            Text("(\(shelf.mangaIds.count))")
                                                .font(.caption2)
                                                .opacity(0.75)
                                        }
                                        .font(.subheadline.weight(isShelfSelected ? .bold : .medium))
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(isShelfSelected ? Color.black : Color.white)
                                        .kaizenGlass(interactive: true, tint: isShelfSelected ? .cyan : nil, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if isShelfSelected {
                                        Menu {
                                            Button {
                                                shelfToRename = shelf
                                                renameShelfText = shelf.name
                                                showRenameShelfAlert = true
                                            } label: {
                                                Label(isEn ? "Rename Shelf" : "Renombrar estantería", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                selectedShelfId = nil
                                                appState.deleteShelf(id: shelf.id)
                                            } label: {
                                                Label(isEn ? "Delete Shelf" : "Borrar estantería", systemImage: "trash")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle.fill")
                                                .foregroundStyle(.cyan)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    
                }
            }
            
            if mode != .discoverCatalog && selectedShelfId == nil && selectedFilter == .caughtUp {
                caughtUpSubFilterBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    private var caughtUpSubFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CaughtUpSubFilter.allCases) { sub in
                    let isSelected = (caughtUpSubFilter == sub)
                    let count = countForCaughtUp(sub: sub)
                    
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            caughtUpSubFilter = sub
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(sub.label(language: appState.currentLanguage))
                            Text("(\(count))")
                                .font(.caption2.weight(.bold))
                                .opacity(0.8)
                        }
                        .font(.caption.weight(isSelected ? .bold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.black : Color.white)
                        .kaizenGlass(interactive: true, tint: isSelected ? .cyan : nil, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }
    
    private func countForCaughtUp(sub: CaughtUpSubFilter) -> Int {
        appState.mangas.filter { manga in
            let inHistory = appState.history.contains { $0.mangaId == manga.id }
            let hasStarted = (manga.totalChapters > 0 && manga.totalChapters > manga.unreadCount)
                || manga.readingPercentage > 0
                || inHistory
            let noUnread = manga.unreadCount == 0 && manga.totalChapters > 0
            let isCaughtUpBase = (hasStarted && noUnread) || (manga.readingPercentage >= 100 && manga.unreadCount == 0)
            guard isCaughtUpBase else { return false }
            
            switch sub {
            case .all: return true
            case .ongoing: return manga.isOngoing
            case .completed: return manga.isCompleted
            case .hiatus: return manga.isHiatus
            }
        }.count
    }
    
    @ViewBuilder
    private var mainCatalogContent: some View {
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
                await appState.checkForNewChapters(client: apiClient)
            }
        }
    }
    
    private var toolbarTrailingButtons: some View {
        HStack(spacing: 4) {
            Menu {
                Picker(isEn ? "Status" : "Estado", selection: $selectedStatus) {
                    Text(isEn ? "All" : "Todos").tag(String?.none)
                    ForEach(availableStatuses, id: \.self) { status in
                        Text(localizedStatus(status)).tag(String?.some(status))
                    }
                }
                .pickerStyle(.menu)
                
                if !availableGenres.isEmpty {
                    Picker(isEn ? "Genre" : "Género", selection: $selectedGenre) {
                        Text(isEn ? "All" : "Todos").tag(String?.none)
                        ForEach(availableGenres, id: \.self) { genre in
                            Text(genre).tag(String?.some(genre))
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                if appState.isManagement && !appState.libraries.isEmpty {
                    Picker(isEn ? "Server library" : "Biblioteca del servidor", selection: $selectedLibraryId) {
                        Text(isEn ? "All" : "Todas").tag(Int?.none)
                        ForEach(appState.libraries) { lib in
                            Text(lib.displayTitle).tag(Int?.some(lib.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                if hasActiveFilters {
                    Button(role: .destructive, action: resetFilters) {
                        Label(isEn ? "Clear filters" : "Quitar filtros", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel(isEn ? "Filters" : "Filtros")
            
            Menu {
                if mode != .discoverCatalog {
                    Button {
                        newShelfName = ""
                        showCreateShelfAlert = true
                    } label: {
                        Label(isEn ? "New Shelf" : "Nueva Estantería", systemImage: "folder.badge.plus")
                    }
                }
                
                if appState.isManagement {
                    Button {
                        showAddMangaSheet = true
                    } label: {
                        Label(isEn ? "Add Manga" : "Añadir Manga", systemImage: "plus.circle")
                    }
                    Button {
                        newLibraryPath = ""
                        creationError = nil
                        showCreateLibraryAlert = true
                    } label: {
                        Label(isEn ? "Add Library..." : "Añadir biblioteca...", systemImage: "folder.badge.gearshape")
                    }
                }
                
                Button {
                    Task { await appState.loadLibrary(client: apiClient, force: true) }
                } label: {
                    Label(isEn ? "Refresh" : "Actualizar", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(appState.isLoadingLibrary)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(isEn ? "Add" : "Añadir")
        }
    }
}
/// Ficha completa e interactiva de Manga adaptada a iPad (Panel Ocultable/Ampliable y Admin Plegado) y iPhone
public struct MangaDetailView: View {
    private enum PadPanelMode {
        case hidden
        case split
        case expanded
    }
    
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
    
    // Estado del panel izquierdo en iPad y acordeones plegables (folded por defecto)
    @State private var padPanelMode: PadPanelMode = .split
    @State private var isSourcesFolded: Bool = true
    @State private var isServerAdminFolded: Bool = true
    @State private var isSynopsisExpanded: Bool = false
    
    // Búsqueda y ordenación de capítulos
    @State private var chapterSearchText: String = ""
    @State private var sortNewestFirst: Bool = true
    
    // Herramientas de Administrador y Control de Servidor
    @State private var configuredSources: [MangaConfiguredSource] = []
    @State private var isLoadingSources: Bool = false
    @State private var showSourcesSheet: Bool = false
    @State private var showAdminSheet: Bool = false
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
        if nextUnreadChapter != nil { return false }
        return chapters.allSatisfy { $0.isRead } || currentManga.safeReadingPercentage >= 100
    }
    
    private var nextUnreadChapter: Chapter? {
        let sorted = chapters.sorted { $0.index < $1.index }
        // 1. Priorizar el progreso real registrado en el historial del usuario
        if let historyEntry = appState.history.first(where: { $0.mangaId == currentManga.id }),
           let histCh = sorted.first(where: { $0.id == historyEntry.chapterId }) {
            // Si el usuario estaba a mitad de este capítulo, continuar en él
            if historyEntry.pageIndex < max(historyEntry.totalPages, 1) {
                return histCh
            }
            // Si ya lo completó, el candidato natural es el siguiente capítulo por número
            if let next = sorted.first(where: { $0.index > histCh.index }) {
                return next
            }
        }
        // 2. Si no hay entrada de historial o ya se completó la serie, primer capítulo no leído
        return sorted.first { !$0.isRead }
    }
    
    // MARK: - Fondo atmosférico (portada desenfocada) y hoja de administración
    
    private var detailBackdrop: some View {
        ZStack(alignment: .top) {
            Color.black
            ZStack {
                RemoteImage(
                    url: currentManga.coverUrl.flatMap { URL(string: $0) },
                    token: appState.session?.apiToken,
                    contentMode: .fill
                )
                .blur(radius: 50)
                .opacity(0.55)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 440)
            .clipped()
        }
        .ignoresSafeArea()
    }
    
    private var adminSheetButton: some View {
        Button {
            showAdminSheet = true
        } label: {
            HStack {
                Label(isEn ? "Sources & administration" : "Fuentes y administración", systemImage: "server.rack")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .kaizenGlass(interactive: true, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private var adminSheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    sourcesInlineSection
                    serverControlSection
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(isEn ? "Server" : "Servidor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEn ? "Done" : "Listo") { showAdminSheet = false }
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
        // Columnas de capítulos cuando el panel izquierdo está oculto (100% pantalla para capítulos)
    private let fullWidthChapterColumns = [
        GridItem(.adaptive(minimum: 320, maximum: 540), spacing: 12)
    ]
    
    private var leftPanelWidth: CGFloat {
        switch padPanelMode {
        case .hidden:
            return 68
        case .split:
            return 390
        case .expanded:
            return 560
        }
    }
    
    private func togglePadExpand() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            padPanelMode = (padPanelMode == .expanded) ? .split : .expanded
        }
    }
    
    private func togglePadHidden() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            padPanelMode = (padPanelMode == .hidden) ? .split : .hidden
        }
    }
    
    public var body: some View {
        ZStack {
            detailBackdrop
            
            if isPad {
                HStack(alignment: .top, spacing: 0) {
                    if padPanelMode == .hidden {
                        collapsedLeftDock
                            .frame(width: 68)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                headerHeroSection
                                feedbackBanners
                                primaryActionButton
                                quickActionsRow
                                synopsisCardSection
                                
                                if appState.isManagement {
                                    adminSheetButton
                                }
                            }
                            .padding(18)
                            .padding(.bottom, 30)
                        }
                        .frame(width: leftPanelWidth)
                    }
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                        .ignoresSafeArea()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            chaptersSection
                        }
                        .padding(18)
                        .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                // Modo Vertical en iPhone
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerHeroSection
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        feedbackBanners
                        primaryActionButton
                            .padding(.horizontal, 16)
                        quickActionsRow
                            .padding(.horizontal, 16)
                        synopsisCardSection
                            .padding(.horizontal, 16)
                        
                        if appState.isManagement {
                            adminSheetButton
                                .padding(.horizontal, 16)
                        }
                        
                        chaptersSection
                            .padding(.horizontal, 16)
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
                    if isPad {
                        Button {
                            togglePadHidden()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sidebar.left")
                                Text(padPanelMode == .hidden ? (isEn ? "Show Info" : "Mostrar Ficha") : (isEn ? "Hide Info" : "Ocultar Ficha"))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        
                        if padPanelMode != .hidden {
                            Button {
                                togglePadExpand()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: padPanelMode == .expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    Text(padPanelMode == .expanded ? (isEn ? "Reduce" : "Reducir") : (isEn ? "Expand" : "Agrandar"))
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.cyan.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if appState.isManagement {
                        adminToolbarMenu
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
        .sheet(isPresented: $showAdminSheet) {
            adminSheetContent
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
    
    // MARK: - Menú Toolbar de Administrador
    
    private var adminToolbarMenu: some View {
        Button {
            showAdminSheet = true
        } label: {
            Image(systemName: "wrench.and.screwdriver")
        }
        .accessibilityLabel(isEn ? "Server tools" : "Herramientas de servidor")
    }
        // MARK: - Mini-Dock Lateral cuando la Ficha está Oculta en iPad
    
    private var collapsedLeftDock: some View {
        VStack(spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    padPanelMode = .split
                }
            } label: {
                VStack(spacing: 6) {
                    coverThumbnail(width: 44, height: 66, cornerRadius: 8)
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }
            }
            .buttonStyle(.plain)
            .help(isEn ? "Show Manga Info" : "Mostrar ficha del manga")
            
            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.horizontal, 12)
            
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    padPanelMode = .expanded
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            
            Button {
                Task {
                    await appState.toggleFavorite(mangaId: currentManga.id, client: apiClient)
                    detailedManga?.isFavorite.toggle()
                }
            } label: {
                Image(systemName: currentManga.isFavorite ? "heart.fill" : "heart")
                    .font(.subheadline)
                    .foregroundStyle(currentManga.isFavorite ? .pink : .white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            
            Button {
                Task { await checkForNewChapters() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(.cyan)
                    .frame(width: 38, height: 38)
                    .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isCheckingNewChapters)
            
            Spacer()
        }
        .padding(.top, 18)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.02))
    }
    
    // MARK: - Portada Limpia (Sin duplicar título debajo)
    
    private func coverThumbnail(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: width, height: height)
            .overlay {
                RemoteImage(
                    url: currentManga.coverUrl.flatMap { URL(string: $0) },
                    token: appState.session?.apiToken,
                    contentMode: .fill
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.cyan.opacity(0.18), radius: 10, y: 4)
    }
    
    // MARK: - Cabecera Hero Rediseñada (Sin Textos Partidos ni Duplicados)
    
    private var headerHeroSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroTopRow
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            heroProgressRow
        }
        .padding(16)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    private var heroTopRow: some View {
        HStack(alignment: .top, spacing: 16) {
            // Portada limpia (al pulsar en iPad agranda/reduce el panel)
            Button {
                if isPad { togglePadExpand() }
            } label: {
                coverThumbnail(width: isPad ? 112 : 100, height: isPad ? 168 : 150, cornerRadius: 14)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(currentManga.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(padPanelMode == .expanded ? 5 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture {
                            if isPad { togglePadExpand() }
                        }
                    
                    Spacer(minLength: 0)
                    
                    if isPad {
                        Button {
                            togglePadExpand()
                        } label: {
                            Image(systemName: padPanelMode == .expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.cyan)
                                .padding(7)
                                .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help(padPanelMode == .expanded ? (isEn ? "Reduce panel" : "Reducir ficha") : (isEn ? "Expand panel" : "Agrandar ficha"))
                    }
                }
                
                if let authors = currentManga.authors, !authors.isEmpty {
                    Text(authors.joined(separator: ", "))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                // Badges con fixedSize horizontal para no partir palabras en sílabas
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        statusBadge
                        if isCaughtUp {
                            caughtUpBadge
                        }
                    }
                    if currentManga.isLocked {
                        lockedBadge
                    }
                }
                .padding(.top, 2)
            }
        }
    }
    
    private var heroProgressRow: some View {
        let readCount = max(currentManga.totalChapters - currentManga.unreadCount, 0)
        let pct = Int(currentManga.safeReadingPercentage)
        let progressText = "\(pct)% (\(readCount)/\(currentManga.totalChapters) " + (isEn ? "ch.)" : "cap.)")
        let progressFraction = min(max(currentManga.safeReadingPercentage / 100.0, 0), 1)
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isEn ? "Reading progress" : "Progreso de lectura")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(progressText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
            }
            ProgressView(value: progressFraction)
                .tint(.cyan)
        }
    }
    
    private var statusBadge: some View {
        let isCompleted = currentManga.status == "COMPLETED"
        return HStack(spacing: 4) {
            Circle()
                .fill(isCompleted ? Color.purple : Color.green)
                .frame(width: 6, height: 6)
            Text(isCompleted ? (isEn ? "Completed" : "Finalizado") : (isEn ? "Ongoing" : "En emisión"))
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background((isCompleted ? Color.purple : Color.green).opacity(0.18), in: Capsule())
        .foregroundStyle(isCompleted ? Color.purple : Color.green)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var lockedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
            Text(isEn ? "Updates Locked" : "Bloqueado")
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.18), in: Capsule())
        .foregroundStyle(.orange)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var caughtUpBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text(isEn ? "Caught Up" : "Al día")
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.cyan.opacity(0.18), in: Capsule())
        .foregroundStyle(.cyan)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - Botón Principal y Fila de 3 Acciones Rápidas Equilibradas
    
    @ViewBuilder
    private var primaryActionButton: some View {
        if isCaughtUp {
            if let firstCh = chapters.sorted(by: { $0.index < $1.index }).first {
                Button {
                    readingChapter = firstCh
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                        Text(isEn ? "Re-read from Chapter 1" : "Releer desde el Capítulo 1")
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        } else if let next = nextUnreadChapter {
            Button {
                readingChapter = next
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.fill")
                    let validPage = (next.lastReadPage > 0 && next.lastReadPage < 9000) ? next.lastReadPage : 1
                    if validPage > 1 {
                        Text(isEn ? "Continue Ch. \(next.index) (p. \(validPage))" : "Continuar Cap. \(next.index) (pág. \(validPage))")
                    } else {
                        Text(isEn ? "Read Chapter \(next.index)" : "Leer Capítulo \(next.index)")
                    }
                }
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundStyle(.black)
                .shadow(color: Color.cyan.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var quickActionsRow: some View {
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
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isCheckingNewChapters)
        }
    }
    
    // MARK: - Tarjeta de Sinopsis Expandible
    
    @ViewBuilder
    private var synopsisCardSection: some View {
        if let synopsis = currentManga.synopsis, !synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isEn ? "SYNOPSIS" : "SINOPSIS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let source = currentManga.source {
                        Text(source)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(synopsis)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineSpacing(3)
                    .lineLimit(isSynopsisExpanded || padPanelMode == .expanded ? nil : 5)
                
                if synopsis.count > 180 && padPanelMode != .expanded {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSynopsisExpanded.toggle()
                        }
                    } label: {
                        Text(isSynopsisExpanded ? (isEn ? "Show less" : "Mostrar menos") : (isEn ? "Read more..." : "Leer más..."))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
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
        }
        
        if let errorMsg = errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                Text("Error: \(errorMsg)")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Acordeón 1: Fuentes de la Serie (Folded por defecto)
    
    private var sourcesSummarySubtitle: String {
        if configuredSources.isEmpty {
            return currentManga.source ?? (isEn ? "Default source" : "Fuente principal")
        }
        return configuredSources.map(\.source).joined(separator: " • ")
    }
    
    private var sourcesFoldHeader: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                isSourcesFolded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.purple)
                    .frame(width: 34, height: 34)
                    .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isEn ? "Configured Sources" : "Fuentes de la Serie")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("\(max(configuredSources.count, 1))")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.25), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                    Text(sourcesSummarySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text(isSourcesFolded ? (isEn ? "Show" : "Mostrar") : (isEn ? "Hide" : "Plegar"))
                    Image(systemName: isSourcesFolded ? "chevron.down" : "chevron.up")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var sourcesEmptyPlaceholder: some View {
        HStack(spacing: 10) {
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(src.source)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(index == 0 ? Color.cyan.opacity(0.22) : Color.purple.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(index == 0 ? Color.cyan : Color.purple)
                
                if index == 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text(isEn ? "Primary" : "Principal")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.yellow)
                }
                
                Spacer()
                
                if index != 0 {
                    Button {
                        promoteToPrimarySource(src)
                    } label: {
                        Text(isEn ? "Set Primary" : "Hacer Principal")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    deleteSource(src)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.85))
                        .padding(5)
                }
                .buttonStyle(.plain)
            }
            
            Text(src.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(index == 0 ? Color.cyan.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var sourcesInlineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourcesFoldHeader
            
            if !isSourcesFolded {
                Divider()
                    .background(Color.white.opacity(0.08))
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(isEn ? "Linked server scrapers" : "Scrapers vinculados en el servidor")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showSourcesSheet = true
                        } label: {
                            HStack(spacing: 4) {
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
            }
        }
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.22), lineWidth: 1))
    }
    
    // MARK: - Acordeón 2: Opciones de Servidor Admin (Folded por defecto)
    
    private var serverFoldHeader: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                isServerAdminFolded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.cyan)
                    .frame(width: 34, height: 34)
                    .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEn ? "Server Options (Admin)" : "Opciones de Servidor (Admin)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(isEn ? "Redownload range, file audit, lock & delete" : "Redescargar rango, auditar archivos, bloqueo y borrado")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text(isServerAdminFolded ? (isEn ? "Show" : "Mostrar") : (isEn ? "Hide" : "Plegar"))
                    Image(systemName: isServerAdminFolded ? "chevron.down" : "chevron.up")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var serverControlSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            serverFoldHeader
            
            if !isServerAdminFolded {
                Divider()
                    .background(Color.white.opacity(0.08))
                
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    Button {
                        rangeStartChapter = "1"
                        rangeEndChapter = "\(max(chapters.count, 10))"
                        showRedownloadRangeAlert = true
                    } label: {
                        serverActionTile(
                            icon: "arrow.triangle.2.circlepath",
                            title: isEn ? "Redownload Range" : "Redescargar Rango",
                            subtitle: isEn ? "Batch chapters" : "Capítulos por lote",
                            tint: .cyan
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        auditMangaIntegrity()
                    } label: {
                        serverActionTile(
                            icon: "checkmark.shield",
                            title: isEn ? "Audit Files" : "Auditar Archivos",
                            subtitle: isEn ? "Verify CBZ integrity" : "Verificar CBZ",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        toggleMangaLock()
                    } label: {
                        serverActionTile(
                            icon: currentManga.isLocked ? "lock.open" : "lock",
                            title: currentManga.isLocked ? (isEn ? "Unlock Series" : "Desbloquear Serie") : (isEn ? "Lock Series" : "Bloquear Serie"),
                            subtitle: currentManga.isLocked ? (isEn ? "Enable auto-updates" : "Activar descargas") : (isEn ? "Pause auto-updates" : "Pausar descargas"),
                            tint: .orange
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showDeleteMangaAlert = true
                    } label: {
                        serverActionTile(
                            icon: "trash",
                            title: isEn ? "Delete Manga" : "Eliminar Manga",
                            subtitle: isEn ? "Remove from server" : "Borrar del servidor",
                            tint: .red
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
        }
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.22), lineWidth: 1))
    }
    
    private func serverActionTile(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.2), lineWidth: 1))
    }
    
    // MARK: - Sección de Capítulos Sin Redundancia
    
    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(isEn ? "Chapters" : "Capítulos")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text("\(filteredChapters.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                        .foregroundStyle(.cyan)
                }
                
                Spacer()
                
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                
                if !chapters.isEmpty {
                    Button {
                        markAllAsRead()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                            Text(isEn ? "Mark all" : "Marcar todo")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if chapters.count > 6 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(isEn ? "Go to chapter #..." : "Ir al capítulo #...", text: $chapterSearchText)
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
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            
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
                    .padding(.vertical, 20)
            } else if isPad && padPanelMode == .hidden {
                // Cuando la ficha está oculta, mostramos 2 columnas amplias
                LazyVGrid(columns: fullWidthChapterColumns, spacing: 10) {
                    ForEach(filteredChapters, id: \.uniqueKey) { chapter in
                        chapterCardRow(chapter)
                    }
                }
            } else {
                // En vista dividida o iPhone: 1 columna limpia con ancho completo para cada fila
                LazyVStack(spacing: 8) {
                    ForEach(filteredChapters, id: \.uniqueKey) { chapter in
                        chapterCardRow(chapter)
                    }
                }
            }
        }
    }
    
    // MARK: - Fila de Capítulo Sin Repetir Número + Menú Contextual Limpio
    
    private func chapterCardRow(_ chapter: Chapter) -> some View {
        HStack(spacing: 12) {
            Button {
                readingChapter = chapter
            } label: {
                HStack(spacing: 12) {
                    chapterNumberBadge(chapter)
                    chapterStatusMetadata(chapter)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            chapterTrailingActions(chapter)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(chapter.isRead ? Color.cyan.opacity(0.14) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            chapterContextMenuItems(chapter)
        }
    }
    
    private func chapterNumberBadge(_ chapter: Chapter) -> some View {
        HStack(spacing: 4) {
            Text(isEn ? "Ch." : "Cap.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(chapter.isRead ? Color.cyan.opacity(0.8) : Color.secondary)
            Text("\(chapter.index)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(chapter.isRead ? Color.cyan : Color.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            chapter.isRead ? Color.cyan.opacity(0.15) : Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(chapter.isRead ? Color.cyan.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private func chapterStatusMetadata(_ chapter: Chapter) -> some View {
        HStack(spacing: 8) {
            if let formattedSize = chapter.formattedSize {
                Text(formattedSize)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            if !chapter.isRead && chapter.lastReadPage > 0 {
                Text(isEn ? "Page \(chapter.lastReadPage)" : "Pág. \(chapter.lastReadPage)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.16), in: Capsule())
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
    
    private func chapterTrailingActions(_ chapter: Chapter) -> some View {
        HStack(spacing: 6) {
            Button {
                toggleChapterRead(chapter)
            } label: {
                Image(systemName: chapter.isRead ? "checkmark" : "circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(chapter.isRead ? Color.cyan : Color.secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        chapter.isRead ? Color.cyan.opacity(0.14) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .buttonStyle(.plain)
            
            if appState.isManagement {
                Menu {
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
                        Label(isEn ? "Delete from Server" : "Eliminar del servidor", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private func chapterContextMenuItems(_ chapter: Chapter) -> some View {
        Button {
            toggleChapterRead(chapter)
        } label: {
            Label(
                chapter.isRead ? (isEn ? "Mark as unread" : "Marcar como no leído") : (isEn ? "Mark as read" : "Marcar como leído"),
                systemImage: chapter.isRead ? "circle" : "checkmark.circle"
            )
        }
        
        if appState.isManagement {
            Divider()
            
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
