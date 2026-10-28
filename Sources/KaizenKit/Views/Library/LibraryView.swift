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
    @State private var selectedManga: Manga?
    @State private var showCreateLibraryAlert = false
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
                                    Button {
                                        selectedManga = manga
                                    } label: {
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
            .navigationTitle(String(localized: "tab_library"))
            .searchable(text: $searchText, prompt: isEn ? "Search your catalog..." : "Buscar en tu catálogo...")
            .task {
                if appState.mangas.isEmpty {
                    await appState.loadLibrary(client: apiClient, force: false)
                }
            }
            .sheet(item: $selectedManga) { manga in
                MangaDetailSheet(manga: manga, apiClient: apiClient)
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

/// Ficha completa e interactiva de Manga con listado de capítulos y lector real
public struct MangaDetailSheet: View {
    let manga: Manga
    let apiClient: KaizenAPIClient
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @State private var detailedManga: Manga?
    @State private var isLoadingChapters: Bool = false
    @State private var readingChapter: Chapter?
    @State private var errorMessage: String?
    @State private var showCreateShelfAlert: Bool = false
    @State private var newShelfName: String = ""
    
    public init(manga: Manga, apiClient: KaizenAPIClient) {
        self.manga = manga
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private var currentManga: Manga {
        detailedManga ?? manga
    }
    
    private var chapters: [Chapter] {
        detailedManga?.chapters ?? currentManga.chapters ?? []
    }
    
    private var isCaughtUp: Bool {
        if chapters.isEmpty { return false }
        return chapters.allSatisfy { $0.isRead } || currentManga.readingPercentage >= 100
    }
    
    private var nextUnreadChapter: Chapter? {
        chapters.sorted { $0.index < $1.index }.first { !$0.isRead }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Cabecera con portada e información básica
                        HStack(alignment: .top, spacing: 18) {
                            MangaCardView(manga: currentManga)
                                .frame(width: 140)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text(currentManga.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                
                                if let authors = currentManga.authors, !authors.isEmpty {
                                    Text(authors.joined(separator: ", "))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                // Estado de publicación
                                HStack(spacing: 8) {
                                    Text(currentManga.status == "COMPLETED" ? (isEn ? "Completed" : "Finalizado") : (isEn ? "Ongoing" : "En emisión"))
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(currentManga.status == "COMPLETED" ? Color.purple.opacity(0.2) : Color.green.opacity(0.2), in: Capsule())
                                        .foregroundStyle(currentManga.status == "COMPLETED" ? Color.purple : Color.green)
                                    
                                    if currentManga.readingPercentage >= 100 {
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
                                
                                // Botones de Favorito y Librerías de Lectura
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
                                            Text(isEn ? "Reading Library" : "Librería de lectura")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.1), in: Capsule())
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        
                        // Botón de acción principal: Continuar Lectura / Todo Leído
                        if isCaughtUp {
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.title3)
                                    Text(isEn ? "All Caught Up • Everything Read" : "¡Al día! Todo leído")
                                        .font(.headline.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.4), lineWidth: 1))
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
                                HStack {
                                    Image(systemName: "book.fill")
                                    let validPage = (next.lastReadPage > 0 && next.lastReadPage < 9000) ? next.lastReadPage : 1
                                    if validPage > 1 {
                                        Text(isEn ? "Continue Ch. \(next.index) (p. \(validPage))" : "Continuar Cap. \(next.index) (pág. \(validPage))")
                                    } else {
                                        Text(isEn ? "Read Ch. \(next.index)" : "Leer Cap. \(next.index)")
                                    }
                                }
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        // Sinopsis
                        if let synopsis = currentManga.synopsis, !synopsis.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(isEn ? "Synopsis" : "Sinopsis")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(synopsis)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(5)
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        // Listado de Capítulos
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text((isEn ? "Chapters (" : "Capítulos (") + "\(chapters.count))")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                
                                Spacer()
                                
                                if !chapters.isEmpty {
                                    Button(isEn ? "Mark all read" : "Marcar todo leído") {
                                        markAllAsRead()
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.cyan)
                                }
                            }
                            .padding(.horizontal, 16)
                            
                            if isLoadingChapters && chapters.isEmpty {
                                HStack {
                                    Spacer()
                                    ProgressView().tint(.cyan)
                                    Spacer()
                                }
                                .padding(.vertical, 30)
                            } else if chapters.isEmpty {
                                Text(isEn ? "No chapters available on the server" : "No hay capítulos disponibles en el servidor")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(chapters.sorted(by: { $0.index > $1.index })) { chapter in
                                        HStack {
                                            Button {
                                                readingChapter = chapter
                                            } label: {
                                                HStack(spacing: 12) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(chapter.isRead ? Color.cyan.opacity(0.15) : Color.white.opacity(0.08))
                                                            .frame(width: 36, height: 36)
                                                        Text("\(chapter.index)")
                                                            .font(.caption.weight(.bold))
                                                            .foregroundStyle(chapter.isRead ? Color.cyan : Color.white)
                                                    }
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(chapter.displayName)
                                                            .font(.subheadline.weight(.semibold))
                                                            .foregroundStyle(.white)
                                                        if chapter.lastReadPage > 0 && !chapter.isRead {
                                                            Text(isEn ? "Page \(chapter.lastReadPage)" : "Página \(chapter.lastReadPage)")
                                                                .font(.caption2)
                                                                .foregroundStyle(.cyan)
                                                        }
                                                    }
                                                    Spacer()
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            
                                            // Botón de marcar leído/no leído
                                            Button {
                                                toggleChapterRead(chapter)
                                            } label: {
                                                Image(systemName: chapter.isRead ? "checkmark.circle.fill" : "circle")
                                                    .font(.title3)
                                                    .foregroundStyle(chapter.isRead ? Color.cyan : Color.secondary)
                                                    .padding(8)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(currentManga.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Close" : "Cerrar") { dismiss() }
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
    }
    
    private func loadDetail() async {
        guard let session = appState.session else { return }
        isLoadingChapters = true
        defer { isLoadingChapters = false }
        do {
            let detail = try await apiClient.fetchMangaDetail(serverUrl: session.serverUrl, token: session.apiToken, mangaId: currentManga.id)
            self.detailedManga = detail
            appState.updateMangaInState(detail)
        } catch {
            errorMessage = error.localizedDescription
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
}
