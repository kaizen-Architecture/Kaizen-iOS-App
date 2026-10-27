import SwiftUI
import UIKit

/// Descarga imágenes del servidor Kaizen enviando el API Token (AsyncImage no permite cabeceras).
actor ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, NSData>()

    func data(for url: URL, token: String?) async -> Data? {
        if let cached = cache.object(forKey: url as NSURL) { return cached as Data }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        cache.setObject(data as NSData, forKey: url as NSURL)
        return data
    }
}

/// Imagen remota autenticada con indicador de carga y marcador si falla.
struct RemoteImage: View {
    let url: URL?
    let token: String?
    var contentMode: ContentMode = .fill

    @State private var uiImage: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    Color.white.opacity(0.05)
                    ProgressView().tint(.cyan)
                }
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        uiImage = nil
        failed = false
        guard let url else { failed = true; return }
        if let data = await ImageLoader.shared.data(for: url, token: token),
           let image = UIImage(data: data) {
            uiImage = image
        } else {
            failed = true
        }
    }
}
