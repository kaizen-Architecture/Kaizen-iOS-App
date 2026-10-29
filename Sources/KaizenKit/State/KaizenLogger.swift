import Foundation
import os
import SwiftUI

/// Niveles de severidad para el sistema de diagnóstico y logs de Kaizen
public enum LogLevel: String, Codable, Sendable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    
    public var icon: String {
        switch self {
        case .debug: return "ant.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .cyan
        case .warning: return .orange
        case .error: return .red
        }
    }
}

/// Entrada individual de log registrada en la app
public struct LogEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String
    public let details: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: String,
        message: String,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.details = details
    }
    
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    public var plainTextLine: String {
        let det = details.map { " | \($0)" } ?? ""
        return "[\(formattedTimestamp)] [\(level.rawValue)] [\(category)] \(message)\(det)"
    }
}

/// Gestor central de diagnóstico y logs persistentes en Kaizen iOS
@MainActor
@Observable
public final class KaizenLogger {
    public static let shared = KaizenLogger()
    
    public private(set) var entries: [LogEntry] = []
    private let maxEntriesInMemory = 400
    private let osLog = Logger(subsystem: "moe.kaizen.KaizenApp", category: "App")
    
    public var logFileURL: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("kaizen_app.log")
    }
    
    private init() {
        loadRecentFileLogs()
        log(level: .info, category: "System", message: "Kaizen Logger inicializado con éxito")
    }
    
    public func log(
        level: LogLevel,
        category: String,
        message: String,
        details: String? = nil
    ) {
        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            details: details
        )
        
        // 1. Buffer en memoria observable
        entries.append(entry)
        if entries.count > maxEntriesInMemory {
            entries.removeFirst(entries.count - maxEntriesInMemory)
        }
        
        // 2. Sistema nativo os.Logger de Apple
        switch level {
        case .debug:
            osLog.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .info:
            osLog.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warning:
            osLog.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error:
            osLog.error("[\(category, privacy: .public)] \(message, privacy: .public) \(details ?? "", privacy: .public)")
        }
        
        // 3. Persistir en archivo de texto plano local
        appendToFile(entry: entry)
    }
    
    public func debug(_ category: String, _ message: String, details: String? = nil) {
        log(level: .debug, category: category, message: message, details: details)
    }
    
    public func info(_ category: String, _ message: String, details: String? = nil) {
        log(level: .info, category: category, message: message, details: details)
    }
    
    public func warning(_ category: String, _ message: String, details: String? = nil) {
        log(level: .warning, category: category, message: message, details: details)
    }
    
    public func error(_ category: String, _ message: String, details: String? = nil) {
        log(level: .error, category: category, message: message, details: details)
    }
    
    public func exportPlainText() -> String {
        entries.map(\.plainTextLine).joined(separator: "\n")
    }
    
    public func clear() {
        entries.removeAll()
        if let url = logFileURL {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        log(level: .info, category: "System", message: "Registros limpiados por el usuario")
    }
    
    private func appendToFile(entry: LogEntry) {
        guard let url = logFileURL else { return }
        let line = entry.plainTextLine + "\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let fileHandle = try? FileHandle(forWritingTo: url) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
    
    private func loadRecentFileLogs() {
        guard let url = logFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Cargar hasta las últimas 50 líneas previas
        let recentLines = lines.suffix(50)
        for line in recentLines {
            let entry = LogEntry(
                level: line.contains("[ERROR]") ? .error : (line.contains("[WARN]") ? .warning : .info),
                category: "Restored",
                message: line
            )
            entries.append(entry)
        }
    }
}
