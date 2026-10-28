import SwiftUI

/// Pantalla Principal (Home) con estanterías lógicas y lectura en curso
public struct HomeDashboardView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var selectedManga: Manga?
    @State private var showCreateShelfSheet = false
    @State private var newShelfName = ""
    @State private var newShelfIcon = "books.vertical.fill"
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    // Mangas que se están leyendo actualmente
    private var inProgressMangas: [Manga] {
        appState.mangas.filter { $0.readingPercentage > 0 && $0.readingPercentage < 100 }
    }
    
    // Mangas favoritos
    private var favoriteMangas: [Manga] {
        appState.mangas.filter { $0.isFavorite }
    }
    
    // Recién añadidos (orden natural o mayor id)
    private var recentlyAddedMangas: [Manga] {
        Array(appState.mangas.suffix(10).reversed())
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if appState.isLoadingLibrary && appState.mangas.isEmpty {
                    ProgressView().tint(.cyan)
                } else if appState.mangas.isEmpty {
                    ContentUnavailableView(
                        "Bienvenido a Kaizen",
                        systemImage: "house",
                        description: Text("Tu biblioteca aún se está sincronizando con el servidor.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            // SECCIÓN 1: Continuar Leyendo
                            if !inProgressMangas.isEmpty {
                                shelfSection(
                                    title: "Continuar leyendo",
                                    icon: "play.circle.fill",
                                    iconColor: .cyan,
                                    mangas: inProgressMangas
                                )
                            }
                            
                            // SECCIÓN 2: Estanterías Lógicas Personalizadas del Usuario
                            ForEach(appState.shelves) { shelf in
                                let shelfMangas = appState.mangas.filter { shelf.mangaIds.contains($0.id) }
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: shelf.icon)
                                            .foregroundStyle(.yellow)
                                        Text(shelf.name)
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(.white)
                                        Text("(\(shelfMangas.count))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    
                                    if shelfMangas.isEmpty {
                                        Text("Estantería vacía. Añade obras desde la ficha de cualquier manga.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    } else {
                                        horizontalMangaList(mangas: shelfMangas)
                                    }
                                }
                            }
                            
                            // SECCIÓN 3: Favoritos
                            if !favoriteMangas.isEmpty {
                                shelfSection(
                                    title: "Tus Favoritos",
                                    icon: "heart.fill",
                                    iconColor: .pink,
                                    mangas: favoriteMangas
                                )
                            }
                            
                            // SECCIÓN 4: Recién Añadidos
                            if !recentlyAddedMangas.isEmpty {
                                shelfSection(
                                    title: "Recién añadidos",
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
                        Label("Nueva Estantería", systemImage: "plus.rectangle.on.folder")
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
            .alert("Nueva Estantería Lógica", isPresented: $showCreateShelfSheet) {
                TextField("Ej: Joyas de la corona, Volver a leer...", text: $newShelfName)
                Button("Crear") {
                    appState.createShelf(name: newShelfName)
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Organiza tus mangas a tu gusto con tus propias estanterías personales.")
            }
        }
    }
    
    @ViewBuilder
    private func shelfSection(title: String, icon: String, iconColor: Color, mangas: [Manga]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
            }
            .padding(.horizontal, 16)
            
            horizontalMangaList(mangas: mangas)
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
