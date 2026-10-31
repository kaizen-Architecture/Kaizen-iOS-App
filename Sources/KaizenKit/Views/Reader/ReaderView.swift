import SwiftUI

/// Lector Inmersivo de Kaizen (Inspirado en Paperback: Zoom, Scrubber reactivo, HUD Glassmorphism, Bilingüe)
@MainActor
@Observable
public final class ReaderStore {
    public let manga: Manga?
    public let mangaId: Int
    public var currentChapterId: Int
    public var currentChapterIndex: Int
    public var allChapters: [Chapter]
    
    public var pages: [String] = []
    public var currentPage: Int = 1
    public var readerMode: ReaderMode = .webtoon
    public var readerTheme: ReaderTheme = .black
    public var isHUDVisible: Bool = true
    public var isLoading: Bool = false
    public var errorMessage: String?
    
    public init(
        manga: Manga? = nil,
        mangaId: Int,
        chapterId: Int,
        chapterIndex: Int = 1,
        initialPage: Int = 1,
        allChapters: [Chapter] = [],
        initialMode: ReaderMode = .webtoon,
        initialTheme: ReaderTheme = .black
    ) {
        self.manga = manga
        self.mangaId = mangaId
        self.currentChapterId = chapterId
        self.currentChapterIndex = chapterIndex
        let safeInitial = (initialPage > 0 && initialPage < 9000) ? initialPage : 1
        self.currentPage = safeInitial
        self.allChapters = allChapters.sorted { $0.index < $1.index }
        self.readerMode = initialMode
        self.readerTheme = initialTheme
    }
    
    public var currentChapter: Chapter {
        allChapters.first(where: { $0.id == currentChapterId }) ??
            Chapter(id: currentChapterId, index: currentChapterIndex, fileName: "Capítulo \(currentChapterIndex)")
    }
    
    public var currentChapterPosition: Int? {
        allChapters.firstIndex(where: { $0.id == currentChapterId })
    }
    
    public var hasPreviousChapter: Bool {
        guard let pos = currentChapterPosition else { return false }
        return pos > 0
    }
    
    public var hasNextChapter: Bool {
        guard let pos = currentChapterPosition else { return false }
        return pos < (allChapters.count - 1)
    }
    
    public var nextChapter: Chapter? {
        guard let pos = currentChapterPosition, hasNextChapter else { return nil }
        return allChapters[pos + 1]
    }
    
    public var previousChapter: Chapter? {
        guard let pos = currentChapterPosition, hasPreviousChapter else { return nil }
        return allChapters[pos - 1]
    }
    
    public var reportMessage: String?
    public var isReportingCorrupt: Bool = false
    
    public func loadPages(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session else { return }
        
        // 1. Comprobar si las páginas ya fueron precargadas en segundo plano
        if let cached = await ChapterPrefetchManager.shared.cachedPages(for: currentChapterId), !cached.isEmpty {
            self.pages = cached
            self.isLoading = false
            self.errorMessage = nil
            if currentPage > pages.count && !pages.isEmpty {
                currentPage = 1
            }
            // Disparar precarga del siguiente capítulo si existe
            if let next = nextChapter {
                Task {
                    await ChapterPrefetchManager.shared.prefetchNextChapter(
                        mangaId: mangaId,
                        nextChapter: next,
                        apiClient: apiClient,
                        session: session
                    )
                }
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            pages = try await apiClient.fetchChapterPages(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: mangaId,
                chapterId: currentChapterId
            )
            await ChapterPrefetchManager.shared.storePages(pages, for: currentChapterId)
            if currentPage > pages.count && !pages.isEmpty {
                currentPage = 1
            }
            
            // Disparar precarga del siguiente capítulo
            if let next = nextChapter {
                Task {
                    await ChapterPrefetchManager.shared.prefetchNextChapter(
                        mangaId: mangaId,
                        nextChapter: next,
                        apiClient: apiClient,
                        session: session
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func goToNextChapter(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let next = nextChapter else { return }
        currentChapterId = next.id
        currentChapterIndex = next.index
        currentPage = 1
        pages = []
        await loadPages(apiClient: apiClient, session: session)
    }
    
    public func goToPreviousChapter(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let prev = previousChapter else { return }
        currentChapterId = prev.id
        currentChapterIndex = prev.index
        currentPage = 1
        pages = []
        await loadPages(apiClient: apiClient, session: session)
    }
    
    public func saveProgress(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let session, !pages.isEmpty else { return }
        let isFullyRead = currentPage >= pages.count
        try? await apiClient.updateReadingProgress(
            serverUrl: session.serverUrl,
            token: session.apiToken,
            mangaId: mangaId,
            chapterId: currentChapterId,
            page: currentPage,
            isRead: isFullyRead ? true : nil
        )
    }
    
    public func reportCorruptChapter(apiClient: KaizenAPIClient, session: UserSession?, isEn: Bool) async {
        guard let session else { return }
        isReportingCorrupt = true
        defer { isReportingCorrupt = false }
        do {
            try await apiClient.reportCorruptChapter(serverUrl: session.serverUrl, token: session.apiToken, chapterId: currentChapterId)
            reportMessage = isEn ? "Chapter reported corrupt. Server is auditing files." : "Capítulo reportado como corrupto. El servidor está auditando los archivos."
        } catch {
            reportMessage = error.localizedDescription
        }
    }
}

public struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var store: ReaderStore
    let apiClient: KaizenAPIClient
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    public init(
        manga: Manga? = nil,
        mangaId: Int,
        chapterId: Int,
        chapterIndex: Int = 1,
        initialPage: Int = 1,
        allChapters: [Chapter] = [],
        apiClient: KaizenAPIClient
    ) {
        _store = State(initialValue: ReaderStore(
            manga: manga,
            mangaId: mangaId,
            chapterId: chapterId,
            chapterIndex: chapterIndex,
            initialPage: initialPage,
            allChapters: allChapters
        ))
        self.apiClient = apiClient
    }
    
    private var backgroundColor: Color {
        switch store.readerTheme {
        case .black: return .black
        case .darkGray: return Color(white: 0.12)
        case .light: return .white
        }
    }
    
    public var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            // Área de Páginas con zoom interactivo
            Group {
                if store.isLoading && store.pages.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView().tint(.cyan)
                        Text(isEn ? "Loading pages from server..." : "Cargando páginas del servidor...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if store.pages.isEmpty {
                    ContentUnavailableView(
                        isEn ? "No pages found" : "No se encontraron páginas",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text(store.errorMessage ?? (isEn ? "Could not load pages for this chapter." : "No se han podido cargar las páginas de este capítulo."))
                    )
                } else {
                    switch store.readerMode {
                    case .webtoon:
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(store.pages.enumerated()), id: \.offset) { index, urlString in
                                        ZoomablePageView(
                                            url: URL(string: urlString),
                                            token: appState.session?.apiToken
                                        )
                                        .id(index + 1)
                                    }
                                    
                                    // Tarjeta de fin de capítulo
                                    EndOfChapterCard(
                                        currentChapterIndex: store.currentChapterIndex,
                                        hasNextChapter: store.hasNextChapter,
                                        nextChapterName: store.nextChapter?.fileName ?? ((isEn ? "Chapter " : "Capítulo ") + "\(store.currentChapterIndex + 1)"),
                                        isEn: isEn,
                                        onReportCorrupt: {
                                            Task {
                                                await store.reportCorruptChapter(apiClient: apiClient, session: appState.session, isEn: isEn)
                                            }
                                        }
                                    ) {
                                        Task {
                                            await store.goToNextChapter(apiClient: apiClient, session: appState.session)
                                            recordHistory()
                                        }
                                    }
                                    
                                    // Espacio generoso inferior para que en iPad nunca quede cortado ni solapado por el HUD
                                    Spacer().frame(height: 160)
                                }
                            }
                            .onChange(of: store.currentPage) { _, newPage in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(newPage, anchor: .top)
                                }
                            }
                        }
                        
                    case .horizontalLTR, .horizontalRTL:
                        TabView(selection: $store.currentPage) {
                            ForEach(Array(store.pages.enumerated()), id: \.offset) { index, urlString in
                                ZoomablePageView(
                                    url: URL(string: urlString),
                                    token: appState.session?.apiToken
                                )
                                .tag(index + 1)
                            }
                            
                            // Diapositiva final de capítulo en modo horizontal
                            EndOfChapterSlide(
                                currentChapterIndex: store.currentChapterIndex,
                                hasNextChapter: store.hasNextChapter,
                                nextChapterName: store.nextChapter?.fileName ?? ((isEn ? "Chapter " : "Capítulo ") + "\(store.currentChapterIndex + 1)"),
                                isEn: isEn,
                                onNext: {
                                    Task {
                                        await store.goToNextChapter(apiClient: apiClient, session: appState.session)
                                        recordHistory()
                                    }
                                },
                                onPrev: {
                                    if !store.pages.isEmpty {
                                        store.currentPage = store.pages.count
                                    }
                                }
                            )
                            .tag(store.pages.count + 1)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .environment(\.layoutDirection, store.readerMode == .horizontalRTL ? .rightToLeft : .leftToRight)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.isHUDVisible.toggle()
                }
            }
            
            // HUD Flotante (Glassmorphism estilo Paperback)
            if store.isHUDVisible {
                VStack {
                    // Barra Superior Flotante
                    HStack(spacing: 14) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.14), in: Circle())
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.manga?.title ?? (isEn ? "Reader" : "Lector"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            Text((isEn ? "Chapter " : "Capítulo ") + "\(store.currentChapterIndex)")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                        }
                        
                        Spacer()
                        
                        // Menú de Ajustes del Lector
                        Menu {
                            Section(isEn ? "Reading Mode" : "Modo de Lectura") {
                                ForEach(ReaderMode.allCases) { mode in
                                    Button {
                                        store.readerMode = mode
                                        appState.updateReaderMode(mode)
                                    } label: {
                                        Label(mode.rawValue, systemImage: mode.iconName)
                                    }
                                }
                            }
                            
                            Section(isEn ? "Theme" : "Tema de Fondo") {
                                ForEach(ReaderTheme.allCases) { theme in
                                    Button {
                                        store.readerTheme = theme
                                        appState.updateReaderTheme(theme)
                                    } label: {
                                        Text(theme.rawValue)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.14), in: Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    
                    Spacer()
                    
                    // Barra Inferior Flotante (Scrubber & Controles de Capítulos)
                    if !store.pages.isEmpty {
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                // Capítulo Anterior
                                Button {
                                    Task {
                                        await store.goToPreviousChapter(apiClient: apiClient, session: appState.session)
                                        recordHistory()
                                    }
                                } label: {
                                    Image(systemName: "backward.end.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(store.hasPreviousChapter ? .white : .white.opacity(0.25))
                                        .padding(8)
                                }
                                .disabled(!store.hasPreviousChapter)
                                
                                Text("\(store.currentPage)")
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, alignment: .trailing)
                                
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
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, alignment: .leading)
                                
                                // Capítulo Siguiente
                                Button {
                                    Task {
                                        await store.goToNextChapter(apiClient: apiClient, session: appState.session)
                                        recordHistory()
                                    }
                                } label: {
                                    Image(systemName: "forward.end.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(store.hasNextChapter ? .white : .white.opacity(0.25))
                                        .padding(8)
                                }
                                .disabled(!store.hasNextChapter)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .padding(.horizontal, 24)
                        .safeAreaPadding(.bottom, 16)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .alert(isEn ? "Chapter Status" : "Estado del Capítulo", isPresented: Binding(
            get: { store.reportMessage != nil },
            set: { if !$0 { store.reportMessage = nil } }
        )) {
            Button(isEn ? "OK" : "Aceptar", role: .cancel) { store.reportMessage = nil }
        } message: {
            if let msg = store.reportMessage {
                Text(msg)
            }
        }
        .statusBarHidden(!store.isHUDVisible)
        .task {
            store.readerMode = appState.preferredReaderMode
            store.readerTheme = appState.preferredReaderTheme
            await store.loadPages(apiClient: apiClient, session: appState.session)
            recordHistory()
        }
        .onChange(of: store.currentPage) { _, _ in
            recordHistory()
            Task {
                await store.saveProgress(apiClient: apiClient, session: appState.session)
            }
        }
    }
    
    private func recordHistory() {
        guard let targetManga = store.manga ?? appState.mangas.first(where: { $0.id == store.mangaId }) else { return }
        appState.recordHistory(
            manga: targetManga,
            chapter: store.currentChapter,
            pageIndex: max(store.currentPage - 1, 0),
            totalPages: max(store.pages.count, 1)
        )
    }
}

/// Página de Manga con soporte completo para Pinch-to-Zoom y Doble Tap
private struct ZoomablePageView: View {
    let url: URL?
    let token: String?
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        RemoteImage(
            url: url,
            token: token,
            contentMode: .fit
        )
        .scaleEffect(scale)
        .offset(offset)
        .gesture(
            MagnificationGesture()
                .onChanged { delta in
                    let newScale = lastScale * delta
                    scale = max(1.0, min(newScale, 4.0))
                }
                .onEnded { _ in
                    if scale < 1.05 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                    lastScale = scale
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if scale > 1.05 {
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                }
                .onEnded { _ in
                    if scale <= 1.05 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            offset = .zero
                            lastOffset = .zero
                        }
                    } else {
                        lastOffset = offset
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if scale > 1.2 {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                } else {
                    scale = 2.5
                    lastScale = 2.5
                }
            }
        }
    }
}

/// Tarjeta al final del capítulo optimizada para iPad y iPhone
private struct EndOfChapterCard: View {
    let currentChapterIndex: Int
    let hasNextChapter: Bool
    let nextChapterName: String
    let isEn: Bool
    let onReportCorrupt: (() -> Void)?
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 46))
                .foregroundStyle(.cyan)
            
            VStack(spacing: 4) {
                Text((isEn ? "Finished Chapter " : "Fin del Capítulo ") + "\(currentChapterIndex)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(isEn ? "Ready for the next step" : "Listo para continuar la historia")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if hasNextChapter {
                Button(action: onNext) {
                    HStack(spacing: 12) {
                        Image(systemName: "forward.fill")
                            .font(.headline)
                        Text((isEn ? "Read Next: " : "Leer siguiente: ") + nextChapterName)
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: 440)
                    .frame(height: 56)
                    .background(Color.cyan, in: Capsule())
                    .shadow(color: Color.cyan.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 6)
            } else {
                Text(isEn ? "🎉 You're all caught up with the latest chapter!" : "🎉 ¡Estás al día! Has completado el último capítulo disponible.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            if let onReportCorrupt {
                Button(action: onReportCorrupt) {
                    HStack(spacing: 6) {
                        Image(systemName: "flag")
                        Text(isEn ? "Report corrupted images" : "Reportar páginas dañadas / corruptas")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 20)
    }
}

/// Slide a pantalla completa para el final de capítulo en modo horizontal
private struct EndOfChapterSlide: View {
    let currentChapterIndex: Int
    let hasNextChapter: Bool
    let nextChapterName: String
    let isEn: Bool
    let onNext: () -> Void
    let onPrev: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.cyan)
                
                VStack(spacing: 8) {
                    Text((isEn ? "Completed Chapter " : "Capítulo Finalizado: ") + "\(currentChapterIndex)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text(isEn ? "Swipe back to review or continue to the next chapter" : "Desliza para releer o pulsa para avanzar al siguiente capítulo")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                
                if hasNextChapter {
                    Button(action: onNext) {
                        HStack(spacing: 12) {
                            Image(systemName: "forward.fill")
                            Text((isEn ? "Next: " : "Siguiente: ") + nextChapterName)
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: 380)
                        .frame(height: 56)
                        .background(Color.cyan, in: Capsule())
                        .shadow(color: Color.cyan.opacity(0.4), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
                
                Button(action: onPrev) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.backward")
                        Text(isEn ? "Return to last page" : "Volver a la última página")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}
