import SwiftUI
import UIKit

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
    public var isBufferingChapter: Bool = true
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
        
        isBufferingChapter = true
        errorMessage = nil
        
        // 1. Comprobar si las páginas ya fueron precargadas en segundo plano
        if let cached = await ChapterPrefetchManager.shared.cachedPages(for: currentChapterId), !cached.isEmpty {
            self.pages = cached
            self.isLoading = false
            self.errorMessage = nil
            if currentPage > pages.count && !pages.isEmpty {
                currentPage = 1
            }
            
            // Comprobar si la página inicial ya está en caché de disco o memoria
            let targetPage = max(min(currentPage, cached.count), 1)
            let initialUrlStr = cached[targetPage - 1]
            if let initialUrl = URL(string: initialUrlStr),
               await ImageLoader.shared.cachedImage(for: initialUrl) != nil {
                // Página ya disponible de inmediato: abrir sin demora
                withAnimation(.easeOut(duration: 0.25)) {
                    self.isBufferingChapter = false
                }
            } else {
                // Descarga prioritaria de la primera página
                if let initialUrl = URL(string: initialUrlStr) {
                    _ = await ImageLoader.shared.image(for: initialUrl, token: session.apiToken)
                }
                withAnimation(.easeOut(duration: 0.3)) {
                    self.isBufferingChapter = false
                }
            }
            
            triggerDelayedPrefetch(apiClient: apiClient, session: session)
            return
        }
        
        isLoading = true
        
        do {
            let fetchedPages = try await apiClient.fetchChapterPages(
                serverUrl: session.serverUrl,
                token: session.apiToken,
                mangaId: mangaId,
                chapterId: currentChapterId
            )
            self.pages = fetchedPages
            await ChapterPrefetchManager.shared.storePages(fetchedPages, for: currentChapterId)
            
            if currentPage > pages.count && !pages.isEmpty {
                currentPage = 1
            }
            
            // BUFFER PRIORITARIO: Descargar inmediatamente la página actual con máxima prioridad
            // Al dedicar todo el ancho de banda exclusivamente a la página 1, tarda solo ~200-400ms
            let targetPage = max(min(currentPage, fetchedPages.count), 1)
            if !fetchedPages.isEmpty, let firstUrl = URL(string: fetchedPages[targetPage - 1]) {
                _ = await ImageLoader.shared.image(for: firstUrl, token: session.apiToken)
            }
            
            // Desvanecer la pantalla de preparación para mostrar el lector con la página 1 ya lista
            withAnimation(.easeOut(duration: 0.35)) {
                self.isLoading = false
                self.isBufferingChapter = false
            }
            
            // Pre-cargar la página siguiente en segundo plano para scroll instantáneo
            if targetPage < fetchedPages.count, let secondUrl = URL(string: fetchedPages[targetPage]) {
                Task(priority: .userInitiated) {
                    _ = await ImageLoader.shared.image(for: secondUrl, token: session.apiToken)
                }
            }
            
            triggerDelayedPrefetch(apiClient: apiClient, session: session)
        } catch {
            withAnimation {
                self.isLoading = false
                self.isBufferingChapter = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    public func triggerDelayedPrefetch(apiClient: KaizenAPIClient, session: UserSession?) {
        guard let next = nextChapter else { return }
        Task(priority: .utility) {
            // Esperar 3 segundos para no competir con las primeras páginas del capítulo en curso
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            await ChapterPrefetchManager.shared.prefetchNextChapter(
                mangaId: mangaId,
                nextChapter: next,
                apiClient: apiClient,
                session: session
            )
        }
    }
    
    public func prefetchUpcomingPages(from pageIndex: Int, session: UserSession?) {
        guard let session, !pages.isEmpty else { return }
        let startIndex = pageIndex
        let endIndex = min(startIndex + 3, pages.count)
        guard startIndex < endIndex else { return }
        
        let token = session.apiToken
        let upcomingUrls = Array(pages[startIndex..<endIndex])
        Task(priority: .utility) {
            for urlStr in upcomingUrls {
                guard let url = URL(string: urlStr) else { continue }
                _ = await ImageLoader.shared.image(for: url, token: token)
            }
        }
    }
    
    public func goToNextChapter(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let next = nextChapter else { return }
        currentChapterId = next.id
        currentChapterIndex = next.index
        currentPage = 1
        pages = []
        isBufferingChapter = true
        await loadPages(apiClient: apiClient, session: session)
    }
    
    public func goToPreviousChapter(apiClient: KaizenAPIClient, session: UserSession?) async {
        guard let prev = previousChapter else { return }
        currentChapterId = prev.id
        currentChapterIndex = prev.index
        currentPage = 1
        pages = []
        isBufferingChapter = true
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
    
    @State private var isTransitioningChapter: Bool = false
    @State private var topPullOffset: CGFloat = 0
    
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
            readerContentLayer
            hudOverlayLayer
            bufferingOverlayLayer
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
        .onChange(of: store.currentPage) { _, newPage in
            recordHistory()
            Task {
                await store.saveProgress(apiClient: apiClient, session: appState.session)
            }
            store.prefetchUpcomingPages(from: newPage, session: appState.session)
        }
    }

    // MARK: - Subvistas del Lector para aligerar el chequeo de tipos del compilador

    @ViewBuilder
    private var readerContentLayer: some View {
        Group {
            if store.pages.isEmpty && !store.isBufferingChapter {
                ContentUnavailableView(
                    isEn ? "No pages found" : "No se encontraron páginas",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text(store.errorMessage ?? (isEn ? "Could not load pages for this chapter." : "No se han podido cargar las páginas de este capítulo."))
                )
            } else {
                switch store.readerMode {
                case .webtoon:
                    webtoonScrollView
                case .horizontalLTR, .horizontalRTL:
                    horizontalTabView
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                store.isHUDVisible.toggle()
            }
        }
    }

    @ViewBuilder
    private var webtoonScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if store.hasPreviousChapter {
                        previousChapterPullIndicator
                    }
                    
                    GeometryReader { g in
                        let minY = g.frame(in: .named("webtoonReaderScroll")).minY
                        Color.clear.preference(key: ReaderTopOffsetKey.self, value: minY)
                    }
                    .frame(height: 0)
                    
                    ForEach(Array(store.pages.enumerated()), id: \.offset) { index, urlString in
                        ReaderPageView(
                            pageIndex: index + 1,
                            totalPages: store.pages.count,
                            url: URL(string: urlString),
                            token: appState.session?.apiToken,
                            isEn: isEn,
                            readerTheme: store.readerTheme
                        )
                        .id(index + 1)
                    }
                    
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
                        triggerAutoNextChapter()
                    }
                    
                    if store.hasNextChapter {
                        VStack(spacing: 10) {
                            ProgressView().tint(Color(red: 0.2, green: 0.8, blue: 0.9))
                            Text(isEn ? "Scrolling to next chapter..." : "Deslizando al siguiente capítulo...")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
                            if let next = store.nextChapter {
                                Text(next.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 100)
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            triggerAutoNextChapter()
                        }
                        
                        Spacer().frame(height: 120)
                    } else {
                        Spacer().frame(height: 160)
                    }
                }
            }
            .coordinateSpace(name: "webtoonReaderScroll")
            .onPreferenceChange(ReaderTopOffsetKey.self) { minY in
                topPullOffset = minY
                if minY > 85 {
                    triggerAutoPreviousChapter()
                }
            }
            .onChange(of: store.currentPage) { _, newPage in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newPage, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var horizontalTabView: some View {
        TabView(selection: $store.currentPage) {
            ForEach(Array(store.pages.enumerated()), id: \.offset) { index, urlString in
                ReaderPageView(
                    pageIndex: index + 1,
                    totalPages: store.pages.count,
                    url: URL(string: urlString),
                    token: appState.session?.apiToken,
                    isEn: isEn,
                    readerTheme: store.readerTheme
                )
                .tag(index + 1)
            }
            
            EndOfChapterSlide(
                currentChapterIndex: store.currentChapterIndex,
                hasNextChapter: store.hasNextChapter,
                nextChapterName: store.nextChapter?.fileName ?? ((isEn ? "Chapter " : "Capítulo ") + "\(store.currentChapterIndex + 1)"),
                isEn: isEn,
                onNext: {
                    triggerAutoNextChapter()
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
        .simultaneousGesture(
            DragGesture()
                .onEnded { value in
                    if store.currentPage == 1 && value.translation.width > 80 && store.hasPreviousChapter {
                        triggerAutoPreviousChapter()
                    }
                    if store.currentPage == (store.pages.count + 1) && value.translation.width < -80 && store.hasNextChapter {
                        triggerAutoNextChapter()
                    }
                }
        )
    }

    @ViewBuilder
    private var previousChapterPullIndicator: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title3)
                .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
                .rotationEffect(.degrees(topPullOffset > 70 ? 180 : 0))
                .animation(.spring(response: 0.3), value: topPullOffset > 70)
            Text(topPullOffset > 70
                ? (isEn ? "Release to load previous chapter" : "Suelta para ir al capítulo anterior")
                : (isEn ? "Pull down for previous chapter" : "Desliza hacia abajo para ir al capítulo anterior"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let prev = store.previousChapter {
                Text(prev.displayName)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
            }
        }
        .frame(height: 75)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var hudOverlayLayer: some View {
        if store.isHUDVisible && !store.isBufferingChapter {
            VStack {
                topHUDBar
                Spacer()
                bottomHUDBar
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var topHUDBar: some View {
        GlassCard {
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                
                VStack(spacing: 2) {
                    Text(store.manga?.title ?? (isEn ? "Reader" : "Lector"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text((isEn ? "Chapter " : "Capítulo ") + "\(store.currentChapterIndex)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
                }
                .frame(maxWidth: .infinity)
                
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
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bottomHUDBar: some View {
        if !store.pages.isEmpty {
            GlassCard {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await store.goToPreviousChapter(apiClient: apiClient, session: appState.session)
                                recordHistory()
                            }
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.subheadline)
                                .foregroundStyle(store.hasPreviousChapter ? .white : .white.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.hasPreviousChapter)

                        Text("\(store.currentPage)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { Double(store.currentPage) },
                                set: { store.currentPage = Int($0) }
                            ),
                            in: 1...Double(max(store.pages.count, 1)),
                            step: 1
                        )
                        .tint(Color(red: 0.2, green: 0.8, blue: 0.9))

                        Text("\(store.pages.count)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 28, alignment: .leading)

                        Button {
                            Task {
                                await store.goToNextChapter(apiClient: apiClient, session: appState.session)
                                recordHistory()
                            }
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.subheadline)
                                .foregroundStyle(store.hasNextChapter ? .white : .white.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.hasNextChapter)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 20)
            .safeAreaPadding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var bufferingOverlayLayer: some View {
        if store.isBufferingChapter {
            ChapterLoadingOverlayView(
                mangaTitle: store.manga?.title ?? (isEn ? "Manga" : "Manga"),
                chapterName: store.currentChapter.displayName,
                chapterIndex: store.currentChapterIndex,
                totalPages: store.pages.count,
                isEn: isEn,
                onDismiss: {
                    dismiss()
                }
            )
            .zIndex(100)
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
    
    private func triggerAutoNextChapter() {
        guard !isTransitioningChapter, store.hasNextChapter else { return }
        isTransitioningChapter = true
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()
        impact.impactOccurred()
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await store.goToNextChapter(apiClient: apiClient, session: appState.session)
            recordHistory()
            try? await Task.sleep(nanoseconds: 500_000_000)
            isTransitioningChapter = false
        }
    }
    
    private func triggerAutoPreviousChapter() {
        guard !isTransitioningChapter, store.hasPreviousChapter else { return }
        isTransitioningChapter = true
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()
        impact.impactOccurred()
        Task {
            await store.goToPreviousChapter(apiClient: apiClient, session: appState.session)
            recordHistory()
            try? await Task.sleep(nanoseconds: 500_000_000)
            isTransitioningChapter = false
        }
    }
}

private struct ReaderTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Página de Manga inmersiva con proporciones reales, carga asíncrona optimizada,
/// placeholder elegante con número de página y soporte completo para Pinch-to-Zoom y Doble Tap.
private struct ReaderPageView: View {
    let pageIndex: Int
    let totalPages: Int
    let url: URL?
    let token: String?
    let isEn: Bool
    let readerTheme: ReaderTheme
    
    @State private var uiImage: UIImage?
    @State private var isLoading: Bool = false
    @State private var hasFailed: Bool = false
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
                    .transition(.opacity)
            } else {
                // Placeholder con proporción realista de manga (1 : 1.42) para que LazyVStack
                // no colapse a 20pt y nunca muestre 50 spinners en columna.
                MangaPagePlaceholderView(
                    pageIndex: pageIndex,
                    totalPages: totalPages,
                    isEn: isEn,
                    hasFailed: hasFailed,
                    onRetry: {
                        Task { await loadPage() }
                    }
                )
            }
        }
        .task(id: url) {
            await loadPage()
        }
    }
    
    private func loadPage() async {
        guard let url else {
            hasFailed = true
            return
        }
        
        // 1. Revisar caché inmediata en memoria o disco
        if let cached = await ImageLoader.shared.cachedImage(for: url) {
            self.uiImage = cached
            self.hasFailed = false
            return
        }
        
        isLoading = true
        hasFailed = false
        
        if let img = await ImageLoader.shared.image(for: url, token: token) {
            withAnimation(.easeIn(duration: 0.2)) {
                self.uiImage = img
            }
        } else {
            self.hasFailed = true
        }
        isLoading = false
    }
}

/// Placeholder con altura real y diseño elegante para páginas pendientes de descarga
private struct MangaPagePlaceholderView: View {
    let pageIndex: Int
    let totalPages: Int
    let isEn: Bool
    let hasFailed: Bool
    let onRetry: () -> Void
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            
            VStack(spacing: 14) {
                if hasFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    
                    Text(isEn ? "Failed to load page \(pageIndex)" : "Error al cargar la página \(pageIndex)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    
                    Button(action: onRetry) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text(isEn ? "Retry" : "Reintentar")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.2, green: 0.8, blue: 0.9), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().tint(Color(red: 0.2, green: 0.8, blue: 0.9))
                            .controlSize(.small)
                        Text(totalPages > 0
                            ? (isEn ? "Page \(pageIndex) of \(totalPages)" : "Página \(pageIndex) de \(totalPages)")
                            : (isEn ? "Page \(pageIndex)" : "Página \(pageIndex)"))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }
            .padding(24)
        }
        .aspectRatio(1 / 1.42, contentMode: .fit)
        .frame(minHeight: 480, maxHeight: 850)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

/// Pantalla inmersiva de transición y preparación del capítulo
private struct ChapterLoadingOverlayView: View {
    let mangaTitle: String
    let chapterName: String
    let chapterIndex: Int
    let totalPages: Int
    let isEn: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            RadialGradient(
                colors: [Color(red: 0.2, green: 0.8, blue: 0.9).opacity(0.14), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.8, blue: 0.9).opacity(0.12))
                        .frame(width: 88, height: 88)
                    
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
                }
                
                VStack(spacing: 8) {
                    Text(mangaTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    Text(chapterName.isEmpty ? ((isEn ? "Chapter " : "Capítulo ") + "\(chapterIndex)") : chapterName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Color(red: 0.2, green: 0.8, blue: 0.9))
                        .controlSize(.regular)
                    
                    Text(totalPages > 0
                        ? (isEn ? "Preparing \(totalPages) pages..." : "Preparando \(totalPages) páginas...")
                        : (isEn ? "Loading chapter..." : "Cargando capítulo..."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Text(isEn ? "Cancel" : "Cancelar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .transition(.opacity)
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
                .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
            
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
                    .background(Color(red: 0.2, green: 0.8, blue: 0.9), in: Capsule())
                    .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.9).opacity(0.35), radius: 10, y: 4)
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
                    .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
                
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
                        .background(Color(red: 0.2, green: 0.8, blue: 0.9), in: Capsule())
                        .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.9).opacity(0.4), radius: 10, y: 5)
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
