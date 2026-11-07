import SwiftUI

/// Pestaña "Leyendo": continuar último capítulo, series en curso y novedades descargadas.
/// El avatar abre un menú con Historial, Peticiones, Ajustes y cambio de vista Admin/Lector.
public struct ReadingHomeView: View {
    private enum ProfileSheet: String, Identifiable {
        case history, requests, settings
        var id: String { rawValue }
    }
    
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var sheet: ProfileSheet?
    @State private var resumeEntry: ReadingHistoryEntry?
    @State private var recentDownloads: [KaizenServerRecentDownload] = []
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool { appState.currentLanguage == "en" }
    
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
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .accessibilityLabel(isEn ? "Profile" : "Perfil")
    }
    
    // MARK: - Hero
    
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
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(isEn ? "CONTINUE READING" : "CONTINUAR LEYENDO")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.cyan)
                
                Text(entry.mangaTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                
                ProgressView(value: progressVal, total: 100)
                    .tint(.cyan)
                    .padding(.vertical, 2)
                
                Button {
                    resumeEntry = entry
                } label: {
                    Label(isEn ? "Continue" : "Continuar", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .padding(.top, 2)
            }
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(height: 160)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.black
                RemoteImage(url: coverURL, token: appState.session?.apiToken, contentMode: .fill)
                    .frame(height: 160)
                    .clipped()
                    .blur(radius: 35)
                    .scaleEffect(1.25)
                    .overlay(Color.black.opacity(0.65))
            }
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            Text(isEn ? "In progress" : "En curso")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(inProgress) { manga in
                        NavigationLink(value: manga) {
                            MangaCardView(manga: manga)
                                .frame(width: 112)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
    
    // MARK: - Novedades
    
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEn ? "New chapters" : "Nuevos capítulos")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            
            VStack(spacing: 0) {
                ForEach(Array(recentDownloads.prefix(5).enumerated()), id: \.element.id) { offset, item in
                    let matchedManga = appState.mangas.first(where: { $0.id == item.mangaId })
                    Group {
                        if let matchedManga {
                            NavigationLink(value: matchedManga) {
                                recentDownloadRow(item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            recentDownloadRow(item)
                        }
                    }
                    
                    if offset < min(recentDownloads.count, 5) - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
    
    private func recentDownloadRow(_ item: KaizenServerRecentDownload) -> some View {
        HStack(spacing: 12) {
            RemoteImage(
                url: item.coverUrl.flatMap { URL(string: $0) },
                token: appState.session?.apiToken,
                contentMode: .fill
            )
            .frame(width: 40, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.mangaTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text((isEn ? "Chapter " : "Capítulo ") + String(format: "%g", item.index))
                    .font(.footnote)
                    .foregroundStyle(.cyan)
            }
            Spacer()
            if let size = item.formattedSize {
                Text(size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(12)
    }
    
    private func loadRecent() async {
        guard let session = appState.session else { return }
        if let items = try? await apiClient.fetchRecentServerDownloads(serverUrl: session.serverUrl, token: session.apiToken) {
            recentDownloads = items
        }
    }
}
