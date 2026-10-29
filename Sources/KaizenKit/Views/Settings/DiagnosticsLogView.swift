import SwiftUI

/// Visor interactivo y completo de registros del sistema para diagnóstico y depuración
public struct DiagnosticsLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @State private var filterLevel: LogLevelFilter = .all
    @State private var searchText: String = ""
    @State private var showCopiedAlert: Bool = false
    @State private var showClearConfirm: Bool = false
    
    public init() {}
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private enum LogLevelFilter: String, CaseIterable, Identifiable {
        case all = "Todos"
        case errors = "Errores"
        case warnings = "Avisos"
        case network = "Red"
        
        var id: String { rawValue }
        
        func label(isEn: Bool) -> String {
            switch self {
            case .all: return isEn ? "All" : "Todos"
            case .errors: return isEn ? "Errors" : "Errores"
            case .warnings: return isEn ? "Warnings" : "Avisos"
            case .network: return isEn ? "Network" : "Red"
            }
        }
    }
    
    private var filteredEntries: [LogEntry] {
        let entries = KaizenLogger.shared.entries
        return entries.filter { entry in
            // Filtro por nivel / categoría
            let levelMatch: Bool
            switch filterLevel {
            case .all:
                levelMatch = true
            case .errors:
                levelMatch = entry.level == .error
            case .warnings:
                levelMatch = entry.level == .warning || entry.level == .error
            case .network:
                levelMatch = entry.category == "Network" || entry.category == "APIClient"
            }
            
            guard levelMatch else { return false }
            
            // Filtro por búsqueda de texto
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }
            let query = searchText.lowercased()
            return entry.message.lowercased().contains(query)
                || entry.category.lowercased().contains(query)
                || (entry.details?.lowercased().contains(query) ?? false)
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Barra de filtros y selector
                    VStack(spacing: 10) {
                        Picker("Filtro", selection: $filterLevel) {
                            ForEach(LogLevelFilter.allCases) { filter in
                                Text(filter.label(isEn: isEn)).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.04))
                    
                    if filteredEntries.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "text.document")
                                .font(.system(size: 42))
                                .foregroundStyle(.secondary)
                            Text(isEn ? "No logs recorded matching filter" : "No hay registros que coincidan con el filtro")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(filteredEntries) { entry in
                                        logEntryRow(entry)
                                            .id(entry.id)
                                    }
                                }
                                .padding(12)
                            }
                        }
                    }
                    
                    // Barra inferior de acciones
                    HStack(spacing: 12) {
                        // Botón Copiar al Portapapeles
                        Button {
                            let text = KaizenLogger.shared.exportPlainText()
                            UIPasteboard.general.string = text
                            showCopiedAlert = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                Text(isEn ? "Copy All" : "Copiar todo")
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                        }
                        
                        // Botón Compartir archivo
                        if let fileURL = KaizenLogger.shared.logFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                            ShareLink(item: fileURL) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(isEn ? "Share .log" : "Compartir .log")
                                }
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.cyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.cyan)
                            }
                        }
                        
                        // Botón Limpiar
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text(isEn ? "Clear" : "Limpiar")
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.04))
                }
            }
            .navigationTitle(isEn ? "System Diagnostics" : "Diagnóstico y Logs")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: isEn ? "Search logs..." : "Buscar en registros...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEn ? "Close" : "Cerrar") { dismiss() }
                }
            }
            .alert(isEn ? "Logs Copied" : "Registros Copiados", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(isEn ? "All logs have been copied to your clipboard." : "Se han copiado todos los registros al portapapeles.")
            }
            .alert(isEn ? "Clear Logs?" : "¿Limpiar Registros?", isPresented: $showClearConfirm) {
                Button(isEn ? "Clear" : "Limpiar", role: .destructive) {
                    KaizenLogger.shared.clear()
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            } message: {
                Text(isEn ? "This will erase in-memory and local disk logs." : "Esto borrará los registros en memoria y en el archivo local.")
            }
        }
    }
    
    @ViewBuilder
    private func logEntryRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: entry.level.icon)
                    .font(.caption2)
                    .foregroundStyle(entry.level.color)
                
                Text(entry.level.rawValue)
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(entry.level.color)
                
                Text("[\(entry.category)]")
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(entry.formattedTimestamp)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            
            Text(entry.message)
                .font(.system(size: 12).monospaced())
                .foregroundStyle(.white)
                .textSelection(.enabled)
            
            if let details = entry.details, !details.isEmpty {
                Text(details)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(entry.level == .error ? Color.red.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
