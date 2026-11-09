import SwiftUI

/// Tarjeta visual reutilizable con acabado Cyberpunk Liquid Glass para cuadrículas y carruseles
public struct MangaCardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    public let manga: Manga
    
    public init(manga: Manga) {
        self.manga = manga
    }
    
    private var isPad: Bool {
        horizontalSizeClass == .regular
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: isPad ? 8 : 6) {
            ZStack(alignment: .topTrailing) {
                // Portada con relación de aspecto 2:3 fija garantizada
                RoundedRectangle(cornerRadius: isPad ? 12 : 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay {
                        RemoteImage(
                            url: manga.coverUrl.flatMap { URL(string: $0) },
                            token: appState.session?.apiToken,
                            contentMode: .fill
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: isPad ? 12 : 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: isPad ? 12 : 10, style: .continuous)
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
                        .padding(.horizontal, isPad ? 7 : 5)
                        .padding(.vertical, isPad ? 3 : 2)
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
                        .padding(isPad ? 6 : 5)
                }
                
                // Indicador de favorito
                if manga.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                        .padding(isPad ? 6 : 5)
                        .background(Color.black.opacity(0.65), in: Circle())
                        .overlay(Circle().stroke(Color.pink.opacity(0.45), lineWidth: 1))
                        .padding(isPad ? 6 : 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                
                // Badge sutil de lectura sin conexión (Offline)
                if OfflineStorageManager.shared.offlineMangas.contains(where: { $0.id == manga.id }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: isPad ? 11 : 9, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(isPad ? 4 : 3)
                    .background(Color(red: 0.35, green: 0.98, blue: 0.70), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 0.8))
                    .shadow(color: Color.green.opacity(0.45), radius: 4)
                    .padding(isPad ? 6 : 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            
            // Título con tipografía limpia sobre el marco de cristal
            Text(manga.title)
                .font(isPad ? .footnote.weight(.bold) : .caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
        }
        .padding(isPad ? 8 : 5)
        .frame(maxHeight: .infinity, alignment: .top)
        .kaizenGlass(in: RoundedRectangle(cornerRadius: isPad ? 18 : 14, style: .continuous))
    }
}
