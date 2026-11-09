import SwiftUI
import UIKit
import ImageIO
import CryptoKit

/// Descarga imágenes del servidor Kaizen enviando el API Token con caché de doble capa (memoria síncrona + disco)
///, downsampling en segundo plano para miniaturas y deduplicación de tareas en vuelo.
actor ImageLoader {
    static let shared = ImageLoader()
    
    /// Caché en memoria thread-safe accesible de forma síncrona (`0ms`, sin salto de actor)
    /// para evitar parpadeos y tirones al hacer scroll rápido en `LazyVGrid`.
    nonisolated(unsafe) private static let fastMemoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 450
        cache.totalCostLimit = 180 * 1024 * 1024 // 180 MB
        return cache
    }()
    
    private let diskCacheDir: URL
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]
    
    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheDir = caches.appendingPathComponent("KaizenImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }
    
    nonisolated static func cacheKey(for url: URL, maxPixelSize: CGFloat? = nil) -> NSString {
        if let maxPixelSize {
            return "\(url.absoluteString)#\(Int(maxPixelSize))" as NSString
        }
        return url.absoluteString as NSString
    }
    
    /// Lectura síncrona inmediata desde RAM para usar directamente en `RemoteImage.init` / `body`.
    nonisolated static func memoryCachedImage(for url: URL, maxPixelSize: CGFloat? = nil) -> UIImage? {
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let hit = fastMemoryCache.object(forKey: key) {
            return hit
        }
        if maxPixelSize != nil, let fullHit = fastMemoryCache.object(forKey: url.absoluteString as NSString) {
            return fullHit
        }
        return nil
    }
    
    nonisolated private static func decodeImage(from data: Data, maxPixelSize: CGFloat?) -> UIImage? {
        if let maxPixelSize, maxPixelSize > 0 {
            let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
            if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) {
                let downsampleOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
                ]
                if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) {
                    return UIImage(cgImage: cgImage)
                }
            }
        }
        guard let rawImage = UIImage(data: data) else { return nil }
        return rawImage.byPreparingForDisplay() ?? rawImage
    }
    
    nonisolated private static func imageCost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1024 * 100 }
        return cg.bytesPerRow * cg.height
    }
    
    private func diskPath(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDir.appendingPathComponent(filename)
    }
    
    func cachedImage(for url: URL, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        let memKey = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let mem = Self.fastMemoryCache.object(forKey: memKey) {
            return mem
        }
        let file = diskPath(for: url)
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: file),
                  let img = Self.decodeImage(from: data, maxPixelSize: maxPixelSize) else {
                return nil
            }
            Self.fastMemoryCache.setObject(img, forKey: memKey, cost: Self.imageCost(img))
            return img
        }.value
    }
    
    func image(for url: URL, token: String?, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        if let cached = await cachedImage(for: url, maxPixelSize: maxPixelSize) {
            return cached
        }
        
        let taskKey = Self.cacheKey(for: url, maxPixelSize: maxPixelSize) as String
        if let existing = inFlightTasks[taskKey] {
            return await existing.value
        }
        
        let diskFile = diskPath(for: url)
        let memKey = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .returnCacheDataElseLoad
            if let token, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = Self.decodeImage(from: data, maxPixelSize: maxPixelSize) else {
                return nil
            }
            
            Self.fastMemoryCache.setObject(image, forKey: memKey, cost: Self.imageCost(image))
            try? data.write(to: diskFile, options: .atomic)
            return image
        }
        
        inFlightTasks[taskKey] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: taskKey)
        return result
    }
}

/// Imagen remota autenticada con lectura síncrona desde memoria (`0ms`) y downsampling fuera del hilo principal
public struct RemoteImage: View {
    public let url: URL?
    public let token: String?
    public var contentMode: ContentMode = .fill
    public var maxPixelSize: CGFloat? = 440
    
    @State private var uiImage: UIImage?
    @State private var loadedURL: URL?
    @State private var failed = false
    
    public init(url: URL?, token: String?, contentMode: ContentMode = .fill, maxPixelSize: CGFloat? = 440) {
        self.url = url
        self.token = token
        self.contentMode = contentMode
        self.maxPixelSize = maxPixelSize
        if let url, let mem = ImageLoader.memoryCachedImage(for: url, maxPixelSize: maxPixelSize) {
            _uiImage = State(initialValue: mem)
            _loadedURL = State(initialValue: url)
        }
    }
    
    private var resolvedImage: UIImage? {
        if let uiImage, loadedURL == url {
            return uiImage
        }
        if let url {
            return ImageLoader.memoryCachedImage(for: url, maxPixelSize: maxPixelSize)
        }
        return nil
    }
    
    public var body: some View {
        ZStack {
            if let img = resolvedImage {
                Image(uiImage: img)
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
                Color.white.opacity(0.05)
            }
        }
        .task(id: url) { await load() }
    }
    
    private func load() async {
        guard let url else {
            failed = true
            return
        }
        if let mem = ImageLoader.memoryCachedImage(for: url, maxPixelSize: maxPixelSize) {
            uiImage = mem
            loadedURL = url
            failed = false
            return
        }
        if let cached = await ImageLoader.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            uiImage = cached
            loadedURL = url
            failed = false
            return
        }
        
        failed = false
        if let image = await ImageLoader.shared.image(for: url, token: token, maxPixelSize: maxPixelSize) {
            uiImage = image
            loadedURL = url
        } else {
            failed = true
        }
    }
}
