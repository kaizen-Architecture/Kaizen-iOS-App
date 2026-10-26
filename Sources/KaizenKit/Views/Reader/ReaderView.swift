import SwiftUI

public enum ReadingDirection: String, CaseIterable, Identifiable {
    case rightToLeft = "Manga (RTL)"
    case leftToRight = "Comic (LTR)"
    case verticalCascade = "Cascada Webtoon"
    
    public var id: String { rawValue }
}

@MainActor
@Observable
public final class ReaderStore {
    public let mangaId: String
    public let chapterId: String
    public var pages: [String] = []
    public var currentPage: Int = 1
    public var readingDirection: ReadingDirection = .rightToLeft
    public var isHUDVisible: Bool = true
    public var isLoading: Bool = false
    public var errorMessage: String?
    
    public init(mangaId: String, chapterId: String) {
        self.mangaId = mangaId
        self.chapterId = chapterId
    }
    
    public func loadPages(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            pages = try await apiClient.fetchChapterPages(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: mangaId,
                chapterId: chapterId
            )
        } catch {
            errorMessage = "Error cargando páginas: \(error.localizedDescription)"
        }
    }
    
    public func saveProgress(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        try? await apiClient.updateReadingProgress(
            serverUrl: session.serverUrl,
            token: session.apiToken,
            mangaId: mangaId,
            chapterId: chapterId,
            page: currentPage
        )
    }
}

/// Lector Inmersivo Nativo de Kaizen
public struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var store: ReaderStore
    let apiClient: KaizenAPIClient
    
    public init(mangaId: String, chapterId: String, apiClient: KaizenAPIClient) {
        _store = State(initialValue: ReaderStore(mangaId: mangaId, chapterId: chapterId))
        self.apiClient = apiClient
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Área de visualización de páginas
            Group {
                if store.isLoading && store.pages.isEmpty {
                    ProgressView().tint(.cyan)
                } else if store.pages.isEmpty {
                    ContentUnavailableView(
                        "No se encontraron páginas",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("No se han podido extraer las páginas de este capítulo.")
                    )
                } else {
                    switch store.readingDirection {
                    case .rightToLeft, .leftToRight:
                        TabView(selection: $store.currentPage) {
                            ForEach(Array(store.pages.enumerated()), id: \.offset) { index, urlString in
                                AsyncImage(url: URL(string: urlString)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .tag(index + 1)
                                    case .failure:
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.largeTitle)
                                            .foregroundStyle(.secondary)
                                    case .empty:
                                        ProgressView().tint(.cyan)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .environment(\.layoutDirection, store.readingDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                        
                    case .verticalCascade:
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(store.pages, id: \.self) { urlString in
                                    AsyncImage(url: URL(string: urlString)) { image in
                                        image
                                            .resizable()
                                            .scaledToFit()
                                    } placeholder: {
                                        ProgressView().frame(height: 300)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.isHUDVisible.toggle()
                }
            }
            
            // Controles flotantes HUD en Liquid Glass
            if store.isHUDVisible {
                VStack {
                    // Barra Superior Flotante
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.12), in: Circle())
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text("Capítulo")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Pág. \(store.currentPage) / \(max(store.pages.count, 1))")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        
                        Spacer()
                        
                        Menu {
                            Picker("Dirección", selection: $store.readingDirection) {
                                ForEach(ReadingDirection.allCases) { dir in
                                    Text(dir.rawValue).tag(dir)
                                }
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.12), in: Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    Spacer()
                    
                    // Barra Inferior con Slider de Páginas
                    if !store.pages.isEmpty {
                        HStack(spacing: 16) {
                            Text("\(store.currentPage)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 30, alignment: .trailing)
                            
                            Slider(
                                value: Binding(
                                    get: { Double(store.currentPage) },
                                    set: { store.currentPage = Int($0) }
                                ),
                                in: 1...Double(max(store.pages.count, 1)),
                                step: 1
                            )
                            .tint(.cyan)
                            
                            Text("\(store.pages.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 30, alignment: .leading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.65), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!store.isHUDVisible)
        .task {
            await store.loadPages(apiClient: apiClient, session: appState.session)
        }
        .onChange(of: store.currentPage) { _, _ in
            Task {
                await store.saveProgress(apiClient: apiClient, session: appState.session)
            }
        }
    }
}
