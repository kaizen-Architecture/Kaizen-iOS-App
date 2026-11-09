import Foundation
import zlib

/// Extractor nativo ligero de archivos ZIP y CBZ (.cbz) sin dependencias externas.
/// Lee el Directorio Central del archivo ZIP y descomprime entradas almacenadas (Stored)
/// y comprimidas con Deflate estándar (RFC 1951) usando la librería nativa del sistema `zlib`.
public struct ZipArchiveExtractor: Sendable {
    public enum ZipError: Error, LocalizedError {
        case invalidArchive
        case decompressionFailed(String)
        case cannotCreateDestination
        
        public var errorDescription: String? {
            switch self {
            case .invalidArchive:
                return "El archivo no es un archivo ZIP o CBZ válido."
            case .decompressionFailed(let file):
                return "Error al descomprimir la entrada \(file)."
            case .cannotCreateDestination:
                return "No se pudo crear la carpeta de destino."
            }
        }
    }
    
    public struct ExtractedFile: Sendable {
        public let name: String
        public let size: Int64
    }
    
    private static let validImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "avif", "gif", "bmp"
    ]
    
    /// Descomprime todas las imágenes de un archivo ZIP/CBZ en el directorio de destino
    /// con nombres normalizados ordenados numéricamente (`page_001.jpg`, `page_002.png`...).
    @discardableResult
    public static func extract(archiveURL: URL, to destinationDir: URL) throws -> [ExtractedFile] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        // Mapear el archivo en memoria de forma eficiente sin volcarlo todo en la RAM física
        let data = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        let count = data.count
        guard count >= 22 else { throw ZipError.invalidArchive }
        
        // 1. Localizar el registro End of Central Directory (EOCD: 0x06054b50 -> [0x50, 0x4b, 0x05, 0x06])
        let maxSearch = min(count, 65535 + 22)
        let searchStart = count - maxSearch
        var eocdOffset: Int? = nil
        
        for i in stride(from: count - 22, through: searchStart, by: -1) {
            if data[i] == 0x50 && data[i + 1] == 0x4b && data[i + 2] == 0x05 && data[i + 3] == 0x06 {
                eocdOffset = i
                break
            }
        }
        guard let eocd = eocdOffset else { throw ZipError.invalidArchive }
        
        // 2. Extraer metadatos del Directorio Central desde el EOCD
        let totalEntries = Int(data.subdata(in: (eocd + 10)..<(eocd + 12)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let cdOffset = Int(data.subdata(in: (eocd + 16)..<(eocd + 20)).withUnsafeBytes { $0.load(as: UInt32.self) })
        guard cdOffset < count else { throw ZipError.invalidArchive }
        
        // 3. Recorrer las entradas del Directorio Central
        var currentCDOffset = cdOffset
        var rawEntries: [(originalName: String, data: Data)] = []
        
        for _ in 0..<totalEntries {
            guard currentCDOffset + 46 <= count else { break }
            // Comprobar firma Central Directory: 0x02014b50 -> [0x50, 0x4b, 0x01, 0x02]
            guard data[currentCDOffset] == 0x50,
                  data[currentCDOffset + 1] == 0x4b,
                  data[currentCDOffset + 2] == 0x01,
                  data[currentCDOffset + 3] == 0x02 else { break }
            
            let method = data.subdata(in: (currentCDOffset + 10)..<(currentCDOffset + 12)).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compSize = Int(data.subdata(in: (currentCDOffset + 20)..<(currentCDOffset + 24)).withUnsafeBytes { $0.load(as: UInt32.self) })
            let uncompSize = Int(data.subdata(in: (currentCDOffset + 24)..<(currentCDOffset + 28)).withUnsafeBytes { $0.load(as: UInt32.self) })
            let nameLen = Int(data.subdata(in: (currentCDOffset + 28)..<(currentCDOffset + 30)).withUnsafeBytes { $0.load(as: UInt16.self) })
            let extraLen = Int(data.subdata(in: (currentCDOffset + 30)..<(currentCDOffset + 32)).withUnsafeBytes { $0.load(as: UInt16.self) })
            let commentLen = Int(data.subdata(in: (currentCDOffset + 32)..<(currentCDOffset + 34)).withUnsafeBytes { $0.load(as: UInt16.self) })
            let localOffset = Int(data.subdata(in: (currentCDOffset + 42)..<(currentCDOffset + 46)).withUnsafeBytes { $0.load(as: UInt32.self) })
            
            let nameData = data.subdata(in: (currentCDOffset + 46)..<(currentCDOffset + 46 + nameLen))
            let fileName = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            
            currentCDOffset += 46 + nameLen + extraLen + commentLen
            
            // Descartar directorios, metadatos de macOS (__MACOSX) y archivos ocultos
            let baseName = (fileName as NSString).lastPathComponent
            if baseName.hasPrefix(".") || fileName.contains("__MACOSX") || fileName.hasSuffix("/") {
                continue
            }
            let ext = (fileName as NSString).pathExtension.lowercased()
            guard validImageExtensions.contains(ext) else { continue }
            
            // 4. Leer encabezado local para ubicar el inicio exacto del payload
            guard localOffset + 30 <= count else { continue }
            let localNameLen = Int(data.subdata(in: (localOffset + 26)..<(localOffset + 28)).withUnsafeBytes { $0.load(as: UInt16.self) })
            let localExtraLen = Int(data.subdata(in: (localOffset + 28)..<(localOffset + 30)).withUnsafeBytes { $0.load(as: UInt16.self) })
            let payloadStart = localOffset + 30 + localNameLen + localExtraLen
            guard payloadStart + compSize <= count else { continue }
            
            let payload = data.subdata(in: payloadStart..<(payloadStart + compSize))
            let uncompressedData: Data
            
            if method == 0 {
                // Stored: los datos no están comprimidos
                uncompressedData = payload
            } else if method == 8 {
                // Deflated: descomprimir usando zlib
                guard let decompressed = decompressDeflate(payload, expectedSize: uncompSize) else {
                    throw ZipError.decompressionFailed(fileName)
                }
                uncompressedData = decompressed
            } else {
                // Formato no soportado, omitir
                continue
            }
            
            rawEntries.append((originalName: fileName, data: uncompressedData))
        }
        
        guard !rawEntries.isEmpty else {
            throw ZipError.invalidArchive
        }
        
        // 5. Ordenar las páginas numéricamente igual que el servidor Kaizen
        rawEntries.sort {
            $0.originalName.localizedStandardCompare($1.originalName) == .orderedAscending
        }
        
        // 6. Escribir cada página con nombre canónico normalizado (page_001.ext)
        var result: [ExtractedFile] = []
        for (idx, entry) in rawEntries.enumerated() {
            let ext = (entry.originalName as NSString).pathExtension.lowercased()
            let normalizedName = String(format: "page_%03d.%@", idx + 1, ext.isEmpty ? "jpg" : ext)
            let destination = destinationDir.appendingPathComponent(normalizedName)
            try entry.data.write(to: destination, options: .atomic)
            result.append(ExtractedFile(name: normalizedName, size: Int64(entry.data.count)))
        }
        
        return result
    }
    
    /// Descomprime datos raw Deflate (RFC 1951) de un archivo ZIP usando zlib nativo.
    private static func decompressDeflate(_ compressed: Data, expectedSize: Int) -> Data? {
        guard !compressed.isEmpty else { return Data() }
        var stream = z_stream()
        
        // -MAX_WBITS (-15) le indica a zlib que el payload es raw Deflate sin encabezados zlib ni gzip
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }
        
        var destination = Data(count: expectedSize)
        let actualBytes: Int? = destination.withUnsafeMutableBytes { destBuffer in
            guard let destAddress = destBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return nil }
            return compressed.withUnsafeBytes { srcBuffer in
                guard let srcAddress = srcBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return nil }
                stream.next_in = UnsafeMutablePointer(mutating: srcAddress)
                stream.avail_in = uInt(compressed.count)
                stream.next_out = destAddress
                stream.avail_out = uInt(expectedSize)
                
                let status = inflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END || status == Z_OK else { return nil }
                return expectedSize - Int(stream.avail_out)
            }
        }
        
        guard let actualBytes else { return nil }
        return destination.prefix(actualBytes)
    }
}
