import SwiftUI

/// Vista de Historial de Lectura cronológico (inspirado en Paperback, bilingüe)
public struct ReadingHistoryView: View {
    @Environment(AppState.self) private var appState
    let apiClient: KaizenAPIClient
    
    @State private var searchText = ""
    @State private var showClearConfirmation = false
    @State private var selectedHistoryEntry: ReadingHistoryEntry?
    
    public init(apiClient: KaizenAPIClient) {
        self.apiClient = apiClient
    }
    
    private var isEn: Bool {
        appState.currentLanguage == "en"
    }
    
    private var filteredSections: [(title: String, entries: [ReadingHistoryEntry])] {
        let baseSections = appState.historyGroupedByDate(language: appState.currentLanguage)
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return baseSections
        }
        let query = searchText.localizedLowercase
        return baseSections.compactMap { section in
            let filtered = section.entries.filter {
                $0.mangaTitle.localizedLowercase.contains(query) ||
                $0.chapterFileName.localizedLowercase.contains(query)
            }
            return filtered.isEmpty ? nil : (title: section.title, entries: filtered)
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if appState.history.isEmpty {
                    ContentUnavailableView(
                        isEn ? "No Recent Reads" : "Sin lecturas recientes",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(isEn ? "Manga you start reading will appear here to resume anytime." : "Los mangas que comiences a leer se guardarán aquí para continuar al instante donde los dejaste.")
                    )
                } else if filteredSections.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredSections, id: \.title) { section in
                            Section {
                                ForEach(section.entries) { entry in
                                    HistoryCardRow(entry: entry, isEn: isEn) {
                                        selectedHistoryEntry = entry
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation {
                                                appState.deleteHistoryEntry(id: entry.id)
                                            }
                                        } label: {
                                            Label(isEn ? "Delete" : "Eliminar", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                Text(section.title)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.cyan)
                                    .textCase(nil)
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(isEn ? "History" : "Historial")
            .searchable(text: $searchText, prompt: isEn ? "Search history..." : "Buscar en el historial...")
            .toolbar {
                if !appState.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showClearConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .confirmationDialog(
                isEn ? "Clear all reading history?" : "¿Borrar todo el historial?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(isEn ? "Clear All History" : "Borrar todo el historial", role: .destructive) {
                    withAnimation {
                        appState.clearHistory()
                    }
                }
                Button(isEn ? "Cancel" : "Cancelar", role: .cancel) {}
            } message: {
                Text(isEn ? "This action cannot be undone." : "Esta acción no se puede deshacer.")
            }
            .fullScreenCover(item: $selectedHistoryEntry) { entry in
                ReaderView(
                    mangaId: entry.mangaId,
                    chapterId: entry.chapterId,
                    chapterIndex: entry.chapterIndex,
                    initialPage: max(entry.pageIndex + 1, 1),
                    apiClient: apiClient
                )
            }
        }
    }
}

private struct HistoryCardRow: View {
    @Environment(AppState.self) private var appState
    let entry: ReadingHistoryEntry
    let isEn: Bool
    let onContinue: () -> Void
    
    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: entry.updatedAt, relativeTo: Date())
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Portada con doble caché
            RemoteImage(
                url: entry.coverUrl.flatMap { URL(string: $0) },
                token: appState.session?.apiToken,
                contentMode: .fill
            )
            .frame(width: 60, height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            // Información y barra de progreso
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.mangaTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text((isEn ? "Chapter " : "Capítulo ") + "\(entry.chapterIndex)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text((isEn ? "p. " : "Pág. ") + "\(entry.pageIndex + 1)/\(entry.totalPages)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // Barra de progreso de lectura
                ProgressView(value: entry.progressPercentage, total: 100)
                    .tint(.cyan)
                    .scaleEffect(y: 0.8, anchor: .center)
            }
            
            Spacer()
            
            // Botón Continuar
            Button(action: onContinue) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                    Text(isEn ? "Continue" : "Continuar")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.cyan, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
    }
}
