import SwiftUI

/// Tarjeta visual reutilizable para portadas de Manga en cuadrículas
public struct MangaCardView: View {
    @Environment(AppState.self) private var appState
    public let manga: Manga
    
    public init(manga: Manga) {
        self.manga = manga
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // Portada con relación de aspecto 2:3 fija garantizada para todas las series
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay {
                        RemoteImage(
                            url: manga.coverUrl.flatMap { URL(string: $0) },
                            token: appState.session?.apiToken,
                            contentMode: .fill
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                .overlay(alignment: .bottom) {
                    if manga.safeReadingPercentage > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Color.black.opacity(0.6)
                                Color.cyan.frame(width: geo.size.width * CGFloat(min(max(manga.safeReadingPercentage / 100.0, 0), 1)))
                            }
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    }
                }
                
                // Badge de capítulos no leídos
                if manga.unreadCount > 0 {
                    Text("\(manga.unreadCount)")
                        .font(.caption2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(6)
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
            
            // Título en una línea (el diseño nativo deja el protagonismo a la portada)
            Text(manga.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
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
