import SwiftUI

/// Tarjeta visual reutilizable con acabado Cyberpunk Liquid Glass para cuadrículas y carruseles
public struct MangaCardView: View {
    @Environment(AppState.self) private var appState
    public let manga: Manga
    
    public init(manga: Manga) {
        self.manga = manga
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Portada con relación de aspecto 2:3 fija garantizada
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay {
                        RemoteImage(
                            url: manga.coverUrl.flatMap { URL(string: $0) },
                            token: appState.session?.apiToken,
                            contentMode: .fill
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                    .overlay(alignment: .bottom) {
                        if manga.safeReadingPercentage > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.black.opacity(0.65))
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(red: 0.35, green: 0.98, blue: 1.0), Color.cyan],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * CGFloat(min(max(manga.safeReadingPercentage / 100.0, 0), 1)))
                                        .shadow(color: Color.cyan.opacity(0.85), radius: 4)
                                }
                            }
                            .frame(height: 4)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                        }
                    }
                
                // Badge Neón de capítulos no leídos
                if manga.unreadCount > 0 {
                    Text("\(manga.unreadCount)")
                        .font(.caption2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.98, blue: 1.0), Color.cyan],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.75), lineWidth: 1))
                        .shadow(color: Color.cyan.opacity(0.65), radius: 6)
                        .padding(6)
                }
                
                // Indicador de favorito
                if manga.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                        .padding(6)
                        .background(Color.black.opacity(0.65), in: Circle())
                        .overlay(Circle().stroke(Color.pink.opacity(0.45), lineWidth: 1))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            
            // Título con tipografía limpia sobre el marco de cristal
            Text(manga.title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
