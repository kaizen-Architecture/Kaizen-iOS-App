import SwiftUI
import UIKit
import CryptoKit

/// Descarga imágenes del servidor Kaizen enviando el API Token con caché de doble capa (memoria + disco).
actor ImageLoader {
    static let shared = ImageLoader()
    private let memoryCache = NSCache<NSURL, UIImage>()
    private let diskCacheDir: URL
    
    init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 150 * 1024 * 1024 // 150 MB
        
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheDir = caches.appendingPathComponent("KaizenImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }
    
    private func diskPath(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDir.appendingPathComponent(filename)
    }
    
    func cachedImage(for url: URL) -> UIImage? {
        if let mem = memoryCache.object(forKey: url as NSURL) {
            return mem
        }
        let file = diskPath(for: url)
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memoryCache.setObject(img, forKey: url as NSURL, cost: data.count)
            return img
        }
        return nil
    }
    
    func image(for url: URL, token: String?) async -> UIImage? {
        if let cached = cachedImage(for: url) {
            return cached
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        
        memoryCache.setObject(image, forKey: url as NSURL, cost: data.count)
        let file = diskPath(for: url)
        try? data.write(to: file, options: .atomic)
        
        return image
    }
}

/// Imagen remota autenticada con soporte de caché persistente y visualización fluida
public struct RemoteImage: View {
    public let url: URL?
    public let token: String?
    public var contentMode: ContentMode = .fill
    
    @State private var uiImage: UIImage?
    @State private var failed = false
    
    public init(url: URL?, token: String?, contentMode: ContentMode = .fill) {
        self.url = url
        self.token = token
        self.contentMode = contentMode
    }
    
    public var body: some View {
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
        guard let url else {
            failed = true
            return
        }
        // Intentar leer caché inmediatamente
        if let cached = await ImageLoader.shared.cachedImage(for: url) {
            uiImage = cached
            return
        }
        
        failed = false
        if let image = await ImageLoader.shared.image(for: url, token: token) {
            uiImage = image
        } else {
            failed = true
        }
    }
}
