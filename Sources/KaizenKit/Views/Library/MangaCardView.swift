import SwiftUI

/// Tarjeta visual reutilizable para portadas de Manga en cuadrículas
public struct MangaCardView: View {
    @Environment(AppState.self) private var appState
    public let manga: Manga
    
    public init(manga: Manga) {
        self.manga = manga
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Portada con relación de aspecto 2:3 fija garantizada para todas las series
                CoverView(
                    url: manga.coverUrl,
                    token: appState.session?.apiToken,
                    width: nil,
                    height: nil,
                    cornerRadius: 16
                )
                .aspectRatio(2/3, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if manga.safeReadingPercentage > 0 {
                        ProgressBarGlow(progress: min(max(manga.safeReadingPercentage / 100.0, 0), 1), color: Color(red: 0.2, green: 0.8, blue: 0.9), height: 4)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                    }
                }
                
                // Badge de capítulos no leídos
                if manga.unreadCount > 0 {
                    Text("\(manga.unreadCount)")
                        .font(.caption2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.2, green: 0.8, blue: 0.9), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(8)
                }
                
                // Indicador de favorito
                if manga.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                        .padding(6)
                        .background(Color.black.opacity(0.6), in: Circle())
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            
            // Título
            Text(manga.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private var placeholderCover: some View {
        ZStack {
            Color.white.opacity(0.06)
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
