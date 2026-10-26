import SwiftUI

public enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case reading = "Leyendo"
    case completed = "Completados"
    case favorites = "Favoritos"
    
    public var id: String { rawValue }
}

@MainActor
@Observable
public final class LibraryStore {
    public var mangas: [Manga] = []
    public var selectedFilter: LibraryFilter = .all
    public var searchText: String = ""
    public var isLoading: Bool = false
    public var errorMessage: String?
    
    public init() {}
    
    public var filteredMangas: [Manga] {
        mangas.filter { manga in
            let matchesSearch = searchText.isEmpty ||
                manga.title.localizedCaseInsensitiveContains(searchText)
            
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .reading:
                matchesFilter = manga.readingPercentage > 0 && manga.readingPercentage < 100
            case .completed:
                matchesFilter = manga.readingPercentage >= 100
            case .favorites:
                matchesFilter = manga.isFavorite
            }
            
            return matchesSearch && matchesFilter
        }
    }
    
    public func loadLibrary(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            mangas = try await apiClient.fetchLibrary(
                serverUrl: session.serverUrl,
                token: session.apiToken
            )
        } catch {
            errorMessage = "Error cargando la biblioteca: \(error.localizedDescription)"
        }
    }
}

public struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var store = LibraryStore()
    @State private var selectedManga: Manga?
    let apiClient: KaizenAPIClient
    
    // Grid adaptativo para iPhone (2-3 columnas) y iPad (4-6 columnas)
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 16)
    ]
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Barra de Filtros horizontales
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LibraryFilter.allCases) { filter in
                                Button(filter.rawValue) {
                                    store.selectedFilter = filter
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    store.selectedFilter == filter ?
                                    Color.cyan : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    store.selectedFilter == filter ? Color.black : Color.white
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    
                    // Contenido: Grid de mangas o estado vacío
                    if store.isLoading && store.mangas.isEmpty {
                        Spacer()
                        ProgressView().tint(.cyan)
                        Spacer()
                    } else if store.filteredMangas.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "No hay mangas",
                            systemImage: "books.vertical",
                            description: Text(store.searchText.isEmpty ? "Tu biblioteca está vacía" : "Ningún título coincide con la búsqueda")
                        )
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(store.filteredMangas) { manga in
                                    Button {
                                        selectedManga = manga
                                    } label: {
                                        MangaCardView(manga: manga)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                        .refreshable {
                            await store.loadLibrary(apiClient: apiClient, session: appState.session)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "tab_library"))
            .searchable(text: $store.searchText, prompt: "Buscar en tu catálogo")
            .task {
                if store.mangas.isEmpty {
                    await store.loadLibrary(apiClient: apiClient, session: appState.session)
                }
            }
            .sheet(item: $selectedManga) { manga in
                MangaDetailSheet(manga: manga, apiClient: apiClient)
            }
        }
    }
}

/// Ficha rápida de Manga
public struct MangaDetailSheet: View {
    let manga: Manga
    let apiClient: KaizenAPIClient
    @Environment(\.dismiss) private var dismiss
    
    public init(manga: Manga, apiClient: KaizenAPIClient) {
        self.manga = manga
        self.apiClient = apiClient
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        MangaCardView(manga: manga)
                            .frame(width: 140)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(manga.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                            
                            if let authors = manga.authors, !authors.isEmpty {
                                Text(authors.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let genres = manga.genres, !genres.isEmpty {
                                FlowLayout(spacing: 4) {
                                    ForEach(genres, id: \.self) { genre in
                                        Text(genre)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.white.opacity(0.1), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    
                    if let synopsis = manga.synopsis {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sinopsis")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(synopsis)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle(manga.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

/// Helper para tags
struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        return CGSize(width: proposal.width ?? 0, height: 40)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: .unspecified)
            x += size.width + spacing
        }
    }
}
