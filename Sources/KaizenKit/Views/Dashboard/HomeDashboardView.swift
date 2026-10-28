import SwiftUI

/// Pantalla Principal (Home) con estanterías lógicas y lectura en curso
public struct HomeDashboardView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var selectedManga: Manga?
    @State private var showCreateShelfSheet = false
    @State private var newShelfName = ""
    @State private var newShelfIcon = "books.vertical.fill"
    
    // Secciones expandidas en modo cuadrícula adaptativa (recordadas en preferencias)
    @State private var expandedSections: Set<String> = {
        if let saved = UserDefaults.standard.stringArray(forKey: "kaizen_home_expanded_sections") {
            return Set(saved)
        }
        return []
    }()
    
    // Columnas adaptativas para el modo cuadrícula expandida (en iPad caben 5-6 columnas, ~15 mangas por pantalla)
    private let adaptiveGridColumns = [
        GridItem(.adaptive(minimum: 125, maximum: 175), spacing: 16)
    ]
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    // Mangas que se están leyendo actualmente (ordenados cronológicamente por el historial)
    private var inProgressMangas: [Manga] {
        let historyMangaIds = appState.history.map { $0.mangaId }
        var result: [Manga] = []
        for id in historyMangaIds {
            if let m = appState.mangas.first(where: { $0.id == id }), !result.contains(where: { $0.id == id }) {
                result.append(m)
            }
        }
        for m in appState.mangas where m.readingPercentage > 0 && m.readingPercentage < 100 {
            if !result.contains(where: { $0.id == m.id }) {
                result.append(m)
            }
        }
        return result
    }
    
    // Mangas favoritos
    private var favoriteMangas: [Manga] {
        appState.mangas.filter { $0.isFavorite }
    }
    
    // Recién añadidos (orden natural o mayor id)
    private var recentlyAddedMangas: [Manga] {
        Array(appState.mangas.suffix(10).reversed())
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if appState.isLoadingLibrary && appState.mangas.isEmpty {
                    ProgressView().tint(.cyan)
                } else if appState.mangas.isEmpty {
                    ContentUnavailableView(
                        isEn ? "Welcome to Kaizen" : "Bienvenido a Kaizen",
                        systemImage: "house",
                        description: Text(isEn ? "Your library is syncing with the server." : "Tu biblioteca aún se está sincronizando con el servidor.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            // SECCIÓN 1: Continuar Leyendo
                            if !inProgressMangas.isEmpty {
                                shelfSection(
                                    id: "continue_reading",
                                    title: isEn ? "Continue Reading" : "Continuar leyendo",
                                    icon: "play.circle.fill",
                                    iconColor: .cyan,
                                    mangas: inProgressMangas
                                )
                            }
                            
                            // SECCIÓN 2: Bibliotecas del Servidor (si existen y tienen mangas)
                            ForEach(appState.libraries) { lib in
                                let libMangas = appState.mangas.filter { $0.libraryId == lib.id }
                                if !libMangas.isEmpty {
                                    shelfSection(
                                        id: "server_lib_\(lib.id)",
                                        title: lib.displayTitle,
                                        icon: "books.vertical.fill",
                                        iconColor: .indigo,
                                        mangas: libMangas
                                    )
                                }
                            }
                            
                            // SECCIÓN 3: Estanterías Lógicas Personalizadas (Solo las creadas que tengan mangas)
                            ForEach(appState.shelves) { shelf in
                                let shelfMangas = appState.mangas.filter { shelf.mangaIds.contains($0.id) }
                                if !shelfMangas.isEmpty {
                                    shelfSection(
                                        id: "shelf_\(shelf.id.uuidString)",
                                        title: shelf.name,
                                        icon: shelf.icon,
                                        iconColor: .yellow,
                                        mangas: shelfMangas
                                    )
                                }
                            }
                            
                            // SECCIÓN 4: Favoritos
                            if !favoriteMangas.isEmpty {
                                shelfSection(
                                    id: "favorites",
                                    title: isEn ? "Your Favorites" : "Tus Favoritos",
                                    icon: "heart.fill",
                                    iconColor: .pink,
                                    mangas: favoriteMangas
                                )
                            }
                            
                            // SECCIÓN 5: Recién Añadidos
                            if !recentlyAddedMangas.isEmpty {
                                shelfSection(
                                    id: "recently_added",
                                    title: isEn ? "Recently Added" : "Recién añadidos",
                                    icon: "sparkles",
                                    iconColor: .purple,
                                    mangas: recentlyAddedMangas
                                )
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .refreshable {
                        await appState.loadLibrary(client: apiClient, force: true)
                    }
                }
            }
            .navigationTitle("Kaizen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newShelfName = ""
                        showCreateShelfSheet = true
                    } label: {
                        Label(isEn ? "New Shelf" : "Nueva Estantería", systemImage: "plus.rectangle.on.folder")
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .task {
                if appState.mangas.isEmpty {
                    await appState.loadLibrary(client: apiClient, force: false)
                }
            }
            .sheet(item: $selectedManga) { manga in
                MangaDetailSheet(manga: manga, apiClient: apiClient)
            }
            .alert(isEn ? "New Shelf" : "Nueva Estantería", isPresented: $showCreateShelfSheet) {
                TextField(isEn ? "e.g. Shonen, Top Picks, Re-reading..." : "Ej: Shonen, Selección, Para releer...", text: $newShelfName)
                Button(isEn ? "Create" : "Crear") {
                    appState.createShelf(name: newShelfName)
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            } message: {
                Text(isEn ? "Organize your mangas into custom shelves." : "Organiza tus mangas a tu gusto con tus propias estanterías personales.")
            }
        }
    }
    
    private func toggleSection(_ id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            if expandedSections.contains(id) {
                expandedSections.remove(id)
            } else {
                expandedSections.insert(id)
            }
            UserDefaults.standard.set(Array(expandedSections), forKey: "kaizen_home_expanded_sections")
        }
    }
    
    @ViewBuilder
    private func shelfSection(id: String, title: String, icon: String, iconColor: Color, mangas: [Manga]) -> some View {
        let isExpanded = expandedSections.contains(id)
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("(\(mangas.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Botón Expandir / Contraer a la derecha
                Button {
                    toggleSection(id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                            .font(.caption2.weight(.bold))
                        Text(isExpanded ? (isEn ? "Collapse" : "Contraer") : (isEn ? "Expand" : "Expandir"))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(isExpanded ? Color.cyan : Color.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isExpanded ? Color.cyan.opacity(0.18) : Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isExpanded ? Color.cyan.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            
            if isExpanded {
                // Modo Cuadrícula Adaptativa (en iPad muestra ~15 mangas de un vistazo con scroll vertical)
                LazyVGrid(columns: adaptiveGridColumns, spacing: 16) {
                    ForEach(mangas) { manga in
                        Button {
                            selectedManga = manga
                        } label: {
                            MangaCardView(manga: manga)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Modo Horizontal de una sola línea
                horizontalMangaList(mangas: mangas)
            }
        }
    }
    
    @ViewBuilder
    private func horizontalMangaList(mangas: [Manga]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(mangas) { manga in
                    Button {
                        selectedManga = manga
                    } label: {
                        MangaCardView(manga: manga)
                            .frame(width: 130)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
