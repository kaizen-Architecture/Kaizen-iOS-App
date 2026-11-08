import SwiftUI

/// Pestaña "Leyendo": continuar último capítulo, series en curso y novedades descargadas.
/// El avatar abre un menú con Historial, Peticiones, Ajustes y cambio de vista Admin/Lector.
public struct ReadingHomeView: View {
    private enum ProfileSheet: String, Identifiable {
        case history, requests, settings
        var id: String { rawValue }
    }
    
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    let apiClient: KaizenAPIClient
    
    @State private var sheet: ProfileSheet?
    @State private var resumeEntry: ReadingHistoryEntry?
    @State private var recentDownloads: [KaizenServerRecentDownload] = []
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    private var isPad: Bool { sizeClass == .regular }
    
    private var lastEntry: ReadingHistoryEntry? {
        appState.history.max(by: { $0.updatedAt < $1.updatedAt })
    }
    
    private var inProgress: [Manga] {
        appState.mangas
            .filter { manga in
                let inHistory = appState.history.contains { $0.mangaId == manga.id }
                let hasStarted = (manga.totalChapters > manga.unreadCount && manga.totalChapters > 0)
                    || (manga.safeReadingPercentage > 0 && manga.safeReadingPercentage < 100)
                    || inHistory
                let hasUnread = manga.unreadCount > 0 || manga.safeReadingPercentage < 100
                return hasStarted && hasUnread
            }
            .prefix(16)
            .map { $0 }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let entry = lastEntry {
                        heroCard(entry)
                    }
                    
                    if !inProgress.isEmpty {
                        inProgressSection
                    }
                    
                    if !recentDownloads.isEmpty {
                        recentSection
                    }
                    
                    if lastEntry == nil && inProgress.isEmpty && recentDownloads.isEmpty {
                        ContentUnavailableView(
                            isEn ? "Nothing to read yet" : "Aún no hay lecturas",
                            systemImage: "book.pages",
                            description: Text(isEn ? "Open a series from the Library to start." : "Abre una serie desde la Biblioteca para empezar.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .ambientGlowBackground()
            .overlay(alignment: .top) {
                SyncProgressBanner()
            }
            .navigationTitle(isEn ? "Reading" : "Leyendo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    InAppLanguageToggle(apiClient: apiClient)
                }
                ToolbarItem(placement: .topBarTrailing) { profileMenu }
            }
            .navigationDestination(for: Manga.self) { manga in
                MangaDetailView(manga: manga, apiClient: apiClient)
            }
            .task {
                await appState.loadLibrary(client: apiClient, force: false)
                await loadRecent()
            }
            .refreshable {
                await appState.checkForNewChapters(client: apiClient)
                await loadRecent()
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .history: ReadingHistoryView(apiClient: apiClient)
                case .requests: MangaRequestsView(apiClient: apiClient)
                case .settings: UserSettingsView(apiClient: apiClient)
                }
            }
            .fullScreenCover(item: $resumeEntry) { entry in
                ReaderView(
                    mangaId: entry.mangaId,
                    chapterId: entry.chapterId,
                    chapterIndex: entry.chapterIndex,
                    initialPage: max(entry.pageIndex + 1, 1),
                    apiClient: apiClient
                )
            }
        }
    }
    
    // MARK: - Perfil
    
    private var profileMenu: some View {
        Menu {
            if let user = appState.session {
                Section("\(user.username) · \(user.role.rawValue)") {
                    Button { sheet = .history } label: {
                        Label(isEn ? "History" : "Historial", systemImage: "clock.arrow.circlepath")
                    }
                    if !appState.isManagement {
                        Button { sheet = .requests } label: {
                            Label(isEn ? "Requests" : "Peticiones", systemImage: "hand.raised.fill")
                        }
                    }
                    Button { sheet = .settings } label: {
                        Label(isEn ? "Settings" : "Ajustes", systemImage: "gearshape.fill")
                    }
                }
            }
            if appState.isActualAdmin {
                Button {
                    appState.toggleAdminReaderPreview()
                } label: {
                    Label(
                        appState.simulateReaderMode
                            ? (isEn ? "Back to Admin view" : "Volver a vista Admin")
                            : (isEn ? "Preview as Reader" : "Probar como Lector"),
                        systemImage: appState.simulateReaderMode ? "shield.lefthalf.filled" : "book.pages"
                    )
                }
            }
            Button(role: .destructive) {
                appState.logout()
            } label: {
                Label(isEn ? "Log Out" : "Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Text(String((appState.session?.username ?? "K").prefix(2)).uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
                .frame(width: 32, height: 32)
                .kaizenGlass(interactive: true, in: Circle())
        }
        .accessibilityLabel(isEn ? "Profile" : "Perfil")
    }
    
    // MARK: - Hero (Tarjeta Cyberpunk Liquid Glass con Portada y Barra Neón)
    
    private func heroCard(_ entry: ReadingHistoryEntry) -> some View {
        let coverURL = entry.coverUrl.flatMap { URL(string: $0) }
        let manga = appState.mangas.first(where: { $0.id == entry.mangaId })
        let progressVal: Double = entry.progressPercentage
        let chapterIdxText = "\(entry.chapterIndex)"
        let pagesText = "\(entry.pageIndex + 1)/\(entry.totalPages)"
        let subtitle = (isEn ? "Chapter " : "Capítulo ") + chapterIdxText + " · " + (isEn ? "p. " : "pág. ") + pagesText
        
        return HStack(spacing: 16) {
            RemoteImage(url: coverURL, token: appState.session?.apiToken, contentMode: .fill)
                .frame(width: 88, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 8, y: 4)
            
            VStack(alignment: .leading, spacing: 7) {
                Text(isEn ? "CONTINUE READING" : "CONTINUAR LEYENDO")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.cyan)
                    .shadow(color: Color.cyan.opacity(0.45), radius: 4)
                
                Text(entry.mangaTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                
                GeometryReader { geo in
                    let pct = CGFloat(min(max(progressVal, 4), 100)) / 100.0
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .frame(height: 6)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.35, green: 0.98, blue: 1.0), Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geo.size.width * pct, 10), height: 6)
                            .shadow(color: Color.cyan.opacity(0.85), radius: 5)
                    }
                }
                .frame(height: 6)
                .padding(.vertical, 2)
                
                Button {
                    resumeEntry = entry
                } label: {
                    Label(isEn ? "Continue" : "Continuar", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 6)
                }
                .kaizenGlassButton(prominent: true)
                .padding(.top, 2)
            }
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(height: 164)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if let coverURL {
                RemoteImage(url: coverURL, token: appState.session?.apiToken, contentMode: .fill)
                    .frame(height: 164)
                    .blur(radius: 36)
                    .opacity(0.32)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contextMenu {
            if let manga {
                NavigationLink(value: manga) {
                    Label(isEn ? "Open series" : "Abrir serie", systemImage: "books.vertical")
                }
            }
        }
    }
    
    // MARK: - En curso
    
    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEn ? "In progress" : "En curso")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(inProgress) { manga in
                        NavigationLink(value: manga) {
                            MangaCardView(manga: manga)
                                .frame(width: 132)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
    }
    
    // MARK: - Novedades en Grid de Tarjetas Cyberpunk Liquid Glass
    
    private var recentSection: some View {
        let items = Array(recentDownloads.prefix(6))
        let columns = isPad
            ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
            : [GridItem(.flexible(), spacing: 12)]
        
        return VStack(alignment: .leading, spacing: 14) {
            Text(isEn ? "New chapters" : "Nuevos capítulos")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    recentItemCell(item: item)
                }
            }
        }
    }
    
    @ViewBuilder
    private func recentItemCell(item: KaizenServerRecentDownload) -> some View {
        let matched = appState.mangas.first(where: {
            if let mid = item.mangaId, $0.id == mid { return true }
            return $0.title.localizedCaseInsensitiveCompare(item.mangaTitle) == .orderedSame
        })
        if let matched {
            NavigationLink(value: matched) {
                recentDownloadRow(item)
            }
            .buttonStyle(.plain)
        } else {
            recentDownloadRow(item)
        }
    }
    
    private func recentDownloadRow(_ item: KaizenServerRecentDownload) -> some View {
        let coverURL = item.coverUrl.flatMap { URL(string: $0) }
        
        return HStack(spacing: 12) {
            RemoteImage(
                url: coverURL,
                token: appState.session?.apiToken,
                contentMode: .fill
            )
            .frame(width: 48, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(item.mangaTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text((isEn ? "Ch. " : "Cap. ") + String(format: "%g", item.index))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.16), in: Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.45), lineWidth: 1))
                    
                    if let size = item.formattedSize {
                        Text(size)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan.opacity(0.75))
        }
        .padding(12)
        .background {
            if let coverURL {
                RemoteImage(url: coverURL, token: appState.session?.apiToken, contentMode: .fill)
                    .blur(radius: 30)
                    .opacity(0.18)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    private func loadRecent() async {
        guard let session = appState.session else { return }
        if let items = try? await apiClient.fetchRecentServerDownloads(serverUrl: session.serverUrl, token: session.apiToken) {
            recentDownloads = items
        }
    }
}
