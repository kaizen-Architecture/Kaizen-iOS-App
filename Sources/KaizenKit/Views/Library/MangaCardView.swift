import SwiftUI

/// Tarjeta visual reutilizable para portadas de Manga en cuadrículas
public struct MangaCardView: View {
    public let manga: Manga
    
    public init(manga: Manga) {
        self.manga = manga
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // Portada
                Group {
                    if let urlStr = manga.coverUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                placeholderCover
                            case .empty:
                                ZStack {
                                    Color.white.opacity(0.05)
                                    ProgressView().tint(.cyan)
                                }
                            @unknown default:
                                placeholderCover
                            }
                        }
                    } else {
                        placeholderCover
                    }
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                
                // Badge de capítulos no leídos
                if manga.unreadCount > 0 {
                    Text("\(manga.unreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [Color.red, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .padding(8)
                }
            }
            
            // Título
            Text(manga.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Subtítulo con capítulos
            Text("\(manga.totalChapters) capítulos")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
