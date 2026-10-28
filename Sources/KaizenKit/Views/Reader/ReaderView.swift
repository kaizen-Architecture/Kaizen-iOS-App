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
    public let mangaId: Int
    public let chapterId: Int
    public let chapterIndex: Int
    public var pages: [String] = []
    public var currentPage: Int = 1
    public var readingDirection: ReadingDirection = .verticalCascade
    public var isHUDVisible: Bool = true
    public var isLoading: Bool = false
    public var errorMessage: String?
    
    public init(mangaId: Int, chapterId: Int, chapterIndex: Int = 1, initialPage: Int = 1) {
        self.mangaId = mangaId
        self.chapterId = chapterId
        self.chapterIndex = chapterIndex
        self.currentPage = max(initialPage, 1)
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
            if currentPage > pages.count && !pages.isEmpty {
                currentPage = 1
            }
        } catch {
            errorMessage = "Error cargando páginas: \(error.localizedDescription)"
        }
    }
    
    public func saveProgress(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session, !pages.isEmpty else { return }
        let isFullyRead = currentPage >= pages.count
        try? await apiClient.updateReadingProgress(
            serverUrl: session.serverUrl,
            token: session.apiToken,
            mangaId: mangaId,
            chapterId: chapterId,
            page: currentPage,
            isRead: isFullyRead ? true : nil
        )
    }
}

/// Lector Inmersivo Nativo de Kaizen
public struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var store: ReaderStore
    let apiClient: KaizenAPIClient
    
    public init(mangaId: Int, chapterId: Int, chapterIndex: Int = 1, initialPage: Int = 1, apiClient: KaizenAPIClient) {
        _store = State(initialValue: ReaderStore(mangaId: mangaId, chapterId: chapterId, chapterIndex: chapterIndex, initialPage: initialPage))
        self.apiClient = apiClient
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Área de visualización de páginas
            Group {
                if store.isLoading && store.pages.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(.cyan)
                        Text("Extrayendo páginas del servidor...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if store.pages.isEmpty {
                    ContentUnavailableView(
                        "No se encontraron páginas",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text(store.errorMessage ?? "No se han podido extraer las páginas de este capítulo.")
                    )
                } else {
                    switch store.readingDirection {
                    case .rightToLeft, .leftToRight:
                        TabView(selection: $store.currentPage) {
                            ForEach(Array(store.pages.enumerated()), id: \.offset) { index, urlString in
                                RemoteImage(
                                    url: URL(string: urlString),
                                    token: appState.session?.apiToken,
                                    contentMode: .fit
                                )
                                .tag(index + 1)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .environment(\.layoutDirection, store.readingDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                        
                    case .verticalCascade:
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(store.pages.enumerated()), id: \.offset) { index, urlString in
                                    RemoteImage(
                                        url: URL(string: urlString),
                                        token: appState.session?.apiToken,
                                        contentMode: .fit
                                    )
                                    .id(index + 1)
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
                            Text("Capítulo \(store.chapterIndex)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Pág. \(store.currentPage) / \(max(store.pages.count, 1))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Menu {
                            Picker("Dirección", selection: $store.readingDirection) {
                                ForEach(ReadingDirection.allCases) { dir in
                                    Text(dir.rawValue).tag(dir)
                                }
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.12), in: Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75), in: Capsule())
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
                        .background(Color.black.opacity(0.75), in: Capsule())
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
