import SwiftUI

/// Vista completa de mangas descargados en el dispositivo para lectura 100% offline.
/// Sigue exactamente el diseño compacto y las proporciones 2:3 del resto de la app (6 columnas en iPad y 3 en iPhone).
public struct OfflineDownloadsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let apiClient: KaizenAPIClient
    
    @State private var offlineManager = OfflineStorageManager.shared
    @State private var selectedMangaToDelete: OfflineMangaMetadata? = nil
    @State private var showDeleteAllAlert: Bool = false
    @State private var readingChapterInfo: (manga: Manga, chapter: Chapter)? = nil
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private var isPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var columns: [GridItem] {
        if isPad {
            return [GridItem(.adaptive(minimum: 125, maximum: 180), spacing: 16, alignment: .top)]
        } else {
            return [GridItem(.adaptive(minimum: 96, maximum: 125), spacing: 10, alignment: .top)]
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                storageSummaryBanner
                
                if offlineManager.offlineMangas.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: isPad ? 20 : 12) {
                            ForEach(offlineManager.offlineMangas) { manga in
                                offlineMangaCard(manga)
                            }
                        }
                        .padding(.horizontal, isPad ? 16 : 12)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                }
            }
            .ambientGlowBackground()
            .navigationTitle(isEn ? "Offline Downloads" : "Descargas Sin Conexión")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    InAppLanguageToggle(apiClient: apiClient)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if !offlineManager.offlineMangas.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                offlineManager.deleteAllReadChapters()
                            } label: {
                                Label(isEn ? "Clean read chapters" : "Limpiar capítulos leídos", systemImage: "trash")
                            }
                            
                            Button(role: .destructive) {
                                showDeleteAllAlert = true
                            } label: {
                                Label(isEn ? "Delete all downloads" : "Borrar todas las descargas", systemImage: "xmark.bin.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .alert(isEn ? "Delete All Local Downloads?" : "¿Eliminar todas las descargas locales?", isPresented: $showDeleteAllAlert) {
                Button(isEn ? "Delete All" : "Borrar Todo", role: .destructive) {
                    for m in offlineManager.offlineMangas {
                        offlineManager.deleteManga(mangaId: m.id)
                    }
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            } message: {
                Text(isEn ? "This will free all local space. Your series will remain safe on Kaizen server." : "Se liberará todo el espacio en este dispositivo. Tus mangas seguirán a salvo en el servidor Kaizen.")
            }
            .fullScreenCover(item: Binding(
                get: { readingChapterInfo.map { IdentifiableChapterWrapper(manga: $0.manga, chapter: $0.chapter) } },
                set: { if $0 == nil { readingChapterInfo = nil } }
            )) { wrapper in
                ReaderView(
                    manga: wrapper.manga,
                    mangaId: wrapper.manga.id,
                    chapterId: wrapper.chapter.id,
                    chapterIndex: wrapper.chapter.index,
                    initialPage: wrapper.chapter.lastReadPage > 0 ? wrapper.chapter.lastReadPage : 1,
                    allChapters: wrapper.manga.chapters ?? [],
                    apiClient: apiClient
                )
            }
        }
    }
    
    // MARK: - Banner de Almacenamiento Superior
    
    private var storageSummaryBanner: some View {
        let totalMangas = offlineManager.offlineMangas.count
        let totalChapters = offlineManager.offlineMangas.reduce(0) { $0 + $1.chapters.count }
        let storageStr = offlineManager.formattedTotalStorage
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive.fill")
                        .font(.headline)
                        .foregroundStyle(.cyan)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isEn ? "\(storageStr) used locally" : "\(storageStr) ocupados en local")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        
                        Text(isEn ? "\(totalMangas) mangas · \(totalChapters) chapters ready offline" : "\(totalMangas) mangas · \(totalChapters) capítulos listos sin conexión")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    offlineManager.deleteAllReadChapters()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text(isEn ? "Clean read" : "Limpiar leídos")
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                    .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, isPad ? 16 : 12)
        .padding(.top, 6)
    }
    
    // MARK: - Tarjeta de Manga Offline (Formato idéntico a MangaCardView)
    
    private func offlineMangaCard(_ item: OfflineMangaMetadata) -> some View {
        VStack(alignment: .leading, spacing: isPad ? 8 : 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: isPad ? 12 : 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay {
                        if let localCover = offlineManager.coverLocalURL(mangaId: item.id),
                           let uiImg = UIImage(contentsOfFile: localCover.path) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if let remoteStr = item.coverRemoteUrl, let url = URL(string: remoteStr) {
                            RemoteImage(url: url, token: appState.session?.apiToken, contentMode: .fill)
                        } else {
                            ZStack {
                                Color.white.opacity(0.05)
                                Image(systemName: "book.closed.fill")
                                    .font(.title)
                                    .foregroundStyle(.cyan.opacity(0.8))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: isPad ? 12 : 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: isPad ? 12 : 10, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                
                // Insignia Verde Neón de Offline
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .black))
                    Text("\(item.chapters.count) " + (isEn ? "ch." : "caps."))
                        .font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.35, green: 0.98, blue: 0.70), Color.green],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 0.8))
                .shadow(color: Color.green.opacity(0.55), radius: 4)
                .padding(isPad ? 6 : 5)
            }
            
            // Título
            Text(item.title)
                .font(isPad ? .footnote.weight(.bold) : .caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 2)
            
            // Subtítulo con peso en disco
            Text(item.formattedSize)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
        .padding(isPad ? 8 : 5)
        .frame(maxHeight: .infinity, alignment: .top)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: isPad ? 18 : 14, style: .continuous))
        .onTapGesture {
            // Abrir directamente el primer capítulo no leído o el primero descargado
            if let firstCh = item.chapters.first(where: { !$0.isRead }) ?? item.chapters.first {
                let mangaModel = Manga(
                    id: item.id,
                    title: item.title,
                    coverUrl: item.coverRemoteUrl,
                    synopsis: item.synopsis,
                    authors: item.authors,
                    genres: item.genres,
                    status: item.status,
                    totalChapters: item.chapters.count,
                    chapters: item.chapters.map { Chapter(id: $0.id, mangaId: $0.mangaId, index: $0.index, fileName: $0.title, lastReadPage: $0.lastReadPage) }
                )
                let chModel = Chapter(id: firstCh.id, mangaId: firstCh.mangaId, index: firstCh.index, fileName: firstCh.title, lastReadPage: firstCh.lastReadPage)
                readingChapterInfo = (manga: mangaModel, chapter: chModel)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                offlineManager.deleteManga(mangaId: item.id)
            } label: {
                Label(isEn ? "Delete Offline Manga (\(item.formattedSize))" : "Eliminar manga local (\(item.formattedSize))", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Estado Vacío
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 54))
                .foregroundStyle(.cyan.opacity(0.8))
            
            Text(isEn ? "No offline downloads yet" : "No tienes descargas sin conexión")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            
            Text(isEn ? "Download your favorite series from Library or Explore to read seamlessly during flights or trips with no internet connection." : "Descarga tus series desde la Biblioteca o Explorar para leer sin conexión durante tus viajes o en modo avión.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
        }
    }
}

private struct IdentifiableChapterWrapper: Identifiable {
    var id: String { "\(manga.id)_\(chapter.id)" }
    let manga: Manga
    let chapter: Chapter
}
