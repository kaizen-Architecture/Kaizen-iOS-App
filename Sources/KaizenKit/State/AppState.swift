import Foundation
import SwiftUI

/// Estado global de la aplicación Kaizen, reactivo con @Observable (Swift 6)
@MainActor
@Observable
public final class AppState {
    public var session: UserSession?
    public var currentLanguage: String = "es"
    public var isConnecting: Bool = false
    public var errorMessage: String?
    
    // Caché en memoria para evitar recargas al cambiar de pestaña
    public var mangas: [Manga] = []
    public var libraries: [KaizenLibrary] = []
    public var serverSettings: KaizenServerSettings?
    public var isLoadingLibrary: Bool = false
    public var libraryErrorMessage: String?
    public private(set) var lastLibrarySyncTime: Date?
    
    // Estanterías y colecciones lógicas del lector
    public var shelves: [UserShelf] = []
    
    // Historial de lectura (inspirado en Paperback)
    public var history: [ReadingHistoryEntry] = []
    
    // Preferencias del lector
    public var preferredReaderMode: ReaderMode = .webtoon
    public var preferredReaderTheme: ReaderTheme = .black
    
    public var isAuthenticated: Bool {
        session != nil
    }
    
    public var isManagement: Bool {
        session?.role.isManagement ?? false
    }
    
    public init() {
        // Cargar idioma guardado explícitamente por el usuario
        if let savedLang = UserDefaults.standard.string(forKey: "kaizen_user_language") {
            self.currentLanguage = savedLang
        }
        // Intentar restaurar sesión guardada de forma segura en Keychain si no se desactivó 'recordar'
        let rememberDisabled = UserDefaults.standard.bool(forKey: "kaizen_remember_login_disabled")
        if !rememberDisabled, let savedSession = try? KeychainService.shared.loadSession() {
            self.session = savedSession
            if UserDefaults.standard.string(forKey: "kaizen_user_language") == nil {
                self.currentLanguage = savedSession.language
            }
        }
        loadShelves()
        loadHistory()
        loadReaderPreferences()
    }
    
    public func setSession(_ session: UserSession, remember: Bool = true) {
        var mutableSession = session
        if let chosenLang = UserDefaults.standard.string(forKey: "kaizen_user_language") {
            self.currentLanguage = chosenLang
            mutableSession.language = chosenLang
        } else {
            self.currentLanguage = session.language
        }
        self.session = mutableSession
        if remember {
            UserDefaults.standard.set(false, forKey: "kaizen_remember_login_disabled")
            try? KeychainService.shared.saveSession(mutableSession)
        } else {
            UserDefaults.standard.set(true, forKey: "kaizen_remember_login_disabled")
            KeychainService.shared.clearSession()
        }
        loadShelves()
        loadHistory()
        loadReaderPreferences()
    }
    
    public func logout() {
        self.session = nil
        self.mangas = []
        self.libraries = []
        self.serverSettings = nil
        self.history = []
        KeychainService.shared.clearSession()
        Task { await ChapterPrefetchManager.shared.clear() }
    }
    
    // MARK: - Gestión de Estanterías Lógicas
    
    private var shelvesStorageKey: String {
        let uid = session?.id ?? 0
        return "kaizen_user_shelves_\(uid)"
    }
    
    public func loadShelves() {
        if let data = UserDefaults.standard.data(forKey: shelvesStorageKey),
           let saved = try? JSONDecoder().decode([UserShelf].self, from: data) {
            // Filtrar estanterías sugeridas de prueba anteriores si están vacías
            let defaultNames = ["Joyas de la corona", "Volver a leer", "Pendientes prioritarios"]
            self.shelves = saved.filter { !(defaultNames.contains($0.name) && $0.mangaIds.isEmpty) }
        } else {
            self.shelves = []
        }
    }
    
    public func saveShelves() {
        if let data = try? JSONEncoder().encode(shelves) {
            UserDefaults.standard.set(data, forKey: shelvesStorageKey)
        }
    }
    
    public func createShelf(name: String, icon: String = "books.vertical.fill") {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let newShelf = UserShelf(name: cleanName, icon: icon)
        shelves.append(newShelf)
        saveShelves()
    }
    
    public func deleteShelf(id: UUID) {
        shelves.removeAll { $0.id == id }
        saveShelves()
    }
    
    public func renameShelf(id: UUID, newName: String, newIcon: String? = nil) {
        guard let idx = shelves.firstIndex(where: { $0.id == id }) else { return }
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        shelves[idx].name = clean
        if let newIcon {
            shelves[idx].icon = newIcon
        }
        saveShelves()
    }
    
    public func toggleMangaInShelf(shelfId: UUID, mangaId: Int) {
        guard let idx = shelves.firstIndex(where: { $0.id == shelfId }) else { return }
        if shelves[idx].mangaIds.contains(mangaId) {
            shelves[idx].mangaIds.removeAll { $0 == mangaId }
        } else {
            shelves[idx].mangaIds.append(mangaId)
        }
        saveShelves()
    }
    
    public func isMangaInShelf(shelfId: UUID, mangaId: Int) -> Bool {
        shelves.first(where: { $0.id == shelfId })?.mangaIds.contains(mangaId) ?? false
    }
    
    // MARK: - Gestión de Historial de Lectura (Inspirado en Paperback)
    
    private var historyStorageKey: String {
        let uid = session?.id ?? 0
        return "kaizen_reading_history_\(uid)"
    }
    
    public func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyStorageKey),
           let saved = try? JSONDecoder().decode([ReadingHistoryEntry].self, from: data) {
            self.history = saved
        } else {
            self.history = []
        }
    }
    
    public func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyStorageKey)
        }
    }
    
    public func recordHistory(manga: Manga, chapter: Chapter, pageIndex: Int, totalPages: Int) {
        // Eliminar entrada previa de este mismo manga para mantener la más reciente en la cima
        history.removeAll { $0.mangaId == manga.id }
        
        let newEntry = ReadingHistoryEntry(
            mangaId: manga.id,
            mangaTitle: manga.title,
            coverUrl: manga.coverUrl,
            chapterId: chapter.id,
            chapterIndex: chapter.index,
            chapterFileName: chapter.fileName,
            pageIndex: pageIndex,
            totalPages: max(totalPages, 1),
            updatedAt: Date()
        )
        history.insert(newEntry, at: 0)
        
        // Conservar los 100 registros más recientes
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        saveHistory()
    }
    
    public func deleteHistoryEntry(id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }
    
    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }
    
    /// Agrupación de historial por fechas relativas bilingüe ("Hoy", "Ayer", "Esta semana", "Anteriores")
    public var historyGroupedByDate: [(title: String, entries: [ReadingHistoryEntry])] {
        historyGroupedByDate(language: currentLanguage)
    }
    
    public func historyGroupedByDate(language: String) -> [(title: String, entries: [ReadingHistoryEntry])] {
        let isEn = language == "en"
        let calendar = Calendar.current
        var today: [ReadingHistoryEntry] = []
        var yesterday: [ReadingHistoryEntry] = []
        var thisWeek: [ReadingHistoryEntry] = []
        var earlier: [ReadingHistoryEntry] = []
        
        for entry in history {
            if calendar.isDateInToday(entry.updatedAt) {
                today.append(entry)
            } else if calendar.isDateInYesterday(entry.updatedAt) {
                yesterday.append(entry)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), entry.updatedAt > weekAgo {
                thisWeek.append(entry)
            } else {
                earlier.append(entry)
            }
        }
        
        var sections: [(title: String, entries: [ReadingHistoryEntry])] = []
        if !today.isEmpty { sections.append((isEn ? "Today" : "Hoy", today)) }
        if !yesterday.isEmpty { sections.append((isEn ? "Yesterday" : "Ayer", yesterday)) }
        if !thisWeek.isEmpty { sections.append((isEn ? "This Week" : "Esta semana", thisWeek)) }
        if !earlier.isEmpty { sections.append((isEn ? "Earlier" : "Anteriores", earlier)) }
        return sections
    }
    
    // MARK: - Preferencias del Lector
    
    public func updateReaderMode(_ mode: ReaderMode) {
        self.preferredReaderMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "kaizen_reader_mode")
    }
    
    public func updateReaderTheme(_ theme: ReaderTheme) {
        self.preferredReaderTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "kaizen_reader_theme")
    }
    
    private func loadReaderPreferences() {
        if let modeStr = UserDefaults.standard.string(forKey: "kaizen_reader_mode"),
           let mode = ReaderMode(rawValue: modeStr) {
            self.preferredReaderMode = mode
        }
        if let themeStr = UserDefaults.standard.string(forKey: "kaizen_reader_theme"),
           let theme = ReaderTheme(rawValue: themeStr) {
            self.preferredReaderTheme = theme
        }
    }
    
    public func loadLibrary(client: KaizenAPIClient, force: Bool = false) async {
        guard let session else { return }
        // Si no es forzado y ya hay mangas, permitir refresco si pasaron más de 60 segundos
        if !force && !mangas.isEmpty {
            if let last = lastLibrarySyncTime, Date().timeIntervalSince(last) < 60 {
                return
            }
        }
        
        isLoadingLibrary = mangas.isEmpty
        libraryErrorMessage = nil
        defer { isLoadingLibrary = false }
        
        do {
            async let fetchedMangas = client.fetchLibrary(serverUrl: session.serverUrl, token: session.apiToken)
            async let fetchedLibraries = client.fetchLibraries(serverUrl: session.serverUrl, token: session.apiToken)
            let (m, libs) = try await (fetchedMangas, fetchedLibraries)
            self.mangas = m
            self.libraries = libs
            self.lastLibrarySyncTime = Date()
            KaizenLogger.shared.info("Library", "Sincronizada biblioteca: \(m.count) mangas y \(libs.count) carpetas en el servidor")
        } catch let error as KaizenError {
            libraryErrorMessage = error.userMessage(language: currentLanguage)
            KaizenLogger.shared.error("Library", "Error sincronizando biblioteca: \(error.localizedDescription)")
        } catch {
            libraryErrorMessage = error.localizedDescription
            KaizenLogger.shared.error("Library", "Error inesperado sincronizando biblioteca: \(error.localizedDescription)")
        }
    }
    
    public func toggleFavorite(mangaId: Int, client: KaizenAPIClient) async {
        guard let session, let idx = mangas.firstIndex(where: { $0.id == mangaId }) else { return }
        let newStatus = !mangas[idx].isFavorite
        mangas[idx].isFavorite = newStatus
        
        do {
            try await client.toggleMangaFavorite(serverUrl: session.serverUrl, token: session.apiToken, mangaId: mangaId, isFavorite: newStatus)
        } catch {
            // Revertir si falla en el servidor
            mangas[idx].isFavorite = !newStatus
        }
    }
    
    public func updateMangaInState(_ manga: Manga) {
        if let idx = mangas.firstIndex(where: { $0.id == manga.id }) {
            mangas[idx] = manga
        }
    }
    
    public func setLanguage(_ language: String) {
        self.currentLanguage = language
        UserDefaults.standard.set(language, forKey: "kaizen_user_language")
        if var current = session {
            current.language = language
            self.session = current
            try? KeychainService.shared.saveSession(current)
        }
    }
    
    public func switchLanguage(to language: String, client: KaizenAPIClient? = nil) async {
        setLanguage(language)
        if let client, let current = session {
            try? await client.updateUserLanguage(
                serverUrl: current.serverUrl,
                token: current.apiToken,
                userId: current.id,
                language: language
            )
        }
    }
}
