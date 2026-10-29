import SwiftUI

/// Pantalla Principal (Home) con estanterías lógicas y lectura en curso
public struct HomeDashboardView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var selectedManga: Manga?
    @State private var showCreateShelfSheet = false
    @State private var newShelfName = ""
    @State private var newShelfIcon = "books.vertical.fill"
    
    // Gestión y edición de librerías de lectura (shelves)
    @State private var shelfToRename: UserShelf?
    @State private var renameText: String = ""
    @State private var showRenameAlert = false
    @State private var shelfToDelete: UserShelf?
    @State private var showDeleteAlert = false
    
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
                            
                            // SECCIÓN 2: Librerías de Lectura Personalizadas (un manga puede estar en varias)
                            ForEach(appState.shelves) { shelf in
                                let shelfMangas = appState.mangas.filter { shelf.mangaIds.contains($0.id) }
                                if !shelfMangas.isEmpty {
                                    shelfSection(
                                        id: "shelf_\(shelf.id.uuidString)",
                                        title: shelf.name,
                                        icon: shelf.icon,
                                        iconColor: .yellow,
                                        mangas: shelfMangas,
                                        shelf: shelf
                                    )
                                }
                            }
                            
                            // SECCIÓN 3: Favoritos
                            if !favoriteMangas.isEmpty {
                                shelfSection(
                                    id: "favorites",
                                    title: isEn ? "Your Favorites" : "Tus Favoritos",
                                    icon: "heart.fill",
                                    iconColor: .pink,
                                    mangas: favoriteMangas
                                )
                            }
                            
                            // SECCIÓN 4: Recién Añadidos
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
                        
                        Button {
                            newShelfName = ""
                            showCreateShelfSheet = true
                        } label: {
                            Label(isEn ? "New Library" : "Nueva Librería", systemImage: "plus.rectangle.on.folder")
                                .foregroundStyle(.cyan)
                        }
                    }
                }
            }
            .task {
                await appState.loadLibrary(client: apiClient, force: false)
            }
            .sheet(item: $selectedManga) { manga in
                MangaDetailSheet(manga: manga, apiClient: apiClient)
            }
            .alert(isEn ? "New Reading Library" : "Nueva Librería de Lectura", isPresented: $showCreateShelfSheet) {
                TextField(isEn ? "e.g. Manhwa Top, Re-reading, Favorites..." : "Ej: Manhwa Top, Para releer, Favoritos...", text: $newShelfName)
                Button(isEn ? "Create" : "Crear") {
                    appState.createShelf(name: newShelfName)
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            } message: {
                Text(isEn ? "Create a reading library to organize your series. A manga can be in multiple libraries." : "Crea una librería para organizar tus series. Un manga puede estar en varias librerías a la vez.")
            }
            .alert(isEn ? "Rename Library" : "Renombrar Librería", isPresented: $showRenameAlert) {
                TextField(isEn ? "Library name" : "Nombre de la librería", text: $renameText)
                Button(isEn ? "Save" : "Guardar") {
                    if let s = shelfToRename {
                        appState.renameShelf(id: s.id, newName: renameText)
                    }
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            }
            .alert(isEn ? "Delete Library" : "Borrar Librería", isPresented: $showDeleteAlert) {
                Button(isEn ? "Delete" : "Borrar", role: .destructive) {
                    if let s = shelfToDelete {
                        appState.deleteShelf(id: s.id)
                    }
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            } message: {
                Text(isEn ? "Are you sure you want to delete this reading library? Your mangas won't be deleted." : "¿Seguro que quieres borrar esta librería de lectura? Tus mangas no se eliminarán de Kaizen.")
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
    private func shelfSection(
        id: String,
        title: String,
        icon: String,
        iconColor: Color,
        mangas: [Manga],
        shelf: UserShelf? = nil
    ) -> some View {
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
                
                // Si es una librería personalizable, menú con opciones para renombrar o borrar
                if let shelf {
                    Menu {
                        Button {
                            shelfToRename = shelf
                            renameText = shelf.name
                            showRenameAlert = true
                        } label: {
                            Label(isEn ? "Rename Library" : "Renombrar librería", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            shelfToDelete = shelf
                            showDeleteAlert = true
                        } label: {
                            Label(isEn ? "Delete Library" : "Borrar librería", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
                
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
