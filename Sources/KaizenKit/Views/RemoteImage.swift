import SwiftUI
import UIKit
import CryptoKit

/// Descarga imágenes del servidor Kaizen enviando el API Token con caché de doble capa (memoria + disco)
/// y deduplicación de tareas en vuelo para no saturar la red ni el servidor.
actor ImageLoader {
    static let shared = ImageLoader()
    private let memoryCache = NSCache<NSURL, UIImage>()
    private let diskCacheDir: URL
    private var inFlightTasks: [URL: Task<UIImage?, Never>] = [:]
    
    init() {
        memoryCache.countLimit = 250
        memoryCache.totalCostLimit = 200 * 1024 * 1024 // 200 MB
        
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
        // Carga inmediata para archivos locales en disco (Modo Offline)
        if url.isFileURL {
            if let image = UIImage(contentsOfFile: url.path) {
                return image
            }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                return image
            }
            return nil
        }
        
        if let cached = cachedImage(for: url) {
            return cached
        }
        
        // Evitar duplicar descargas simultáneas de la misma URL
        if let existing = inFlightTasks[url] {
            return await existing.value
        }
        
        let diskFile = diskPath(for: url)
        let memCache = memoryCache
        let cacheKey = url as NSURL
        
        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .returnCacheDataElseLoad
            if let token, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return nil }
            
            memCache.setObject(image, forKey: cacheKey, cost: data.count)
            try? data.write(to: diskFile, options: .atomic)
            return image
        }
        
        inFlightTasks[url] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: url)
        return result
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
                    .transition(.opacity)
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
            withAnimation(.easeIn(duration: 0.2)) {
                uiImage = image
            }
        } else {
            failed = true
        }
    }
}
