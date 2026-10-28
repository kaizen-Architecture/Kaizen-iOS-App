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
    
    // Estanterías y colecciones lógicas del lector
    public var shelves: [UserShelf] = []
    
    public var isAuthenticated: Bool {
        session != nil
    }
    
    public var isManagement: Bool {
        session?.role.isManagement ?? false
    }
    
    public init() {
        // Intentar restaurar sesión guardada de forma segura en Keychain
        if let savedSession = try? KeychainService.shared.loadSession() {
            self.session = savedSession
            self.currentLanguage = savedSession.language
        }
        loadShelves()
    }
    
    public func setSession(_ session: UserSession) {
        self.session = session
        self.currentLanguage = session.language
        try? KeychainService.shared.saveSession(session)
        loadShelves()
    }
    
    public func logout() {
        self.session = nil
        self.mangas = []
        self.libraries = []
        self.serverSettings = nil
        KeychainService.shared.clearSession()
    }
    
    // MARK: - Gestión de Estanterías Lógicas
    
    private var shelvesStorageKey: String {
        let uid = session?.id ?? 0
        return "kaizen_user_shelves_\(uid)"
    }
    
    public func loadShelves() {
        if let data = UserDefaults.standard.data(forKey: shelvesStorageKey),
           let saved = try? JSONDecoder().decode([UserShelf].self, from: data) {
            self.shelves = saved
        } else {
            // Estanterías por defecto sugeridas
            self.shelves = [
                UserShelf(name: "Joyas de la corona", icon: "crown.fill"),
                UserShelf(name: "Volver a leer", icon: "arrow.clockwise"),
                UserShelf(name: "Pendientes prioritarios", icon: "flame.fill")
            ]
            saveShelves()
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
    
    public func loadLibrary(client: KaizenAPIClient, force: Bool = false) async {
        guard let session else { return }
        if !force && !mangas.isEmpty { return }
        
        isLoadingLibrary = true
        libraryErrorMessage = nil
        defer { isLoadingLibrary = false }
        
        do {
            async let fetchedMangas = client.fetchLibrary(serverUrl: session.serverUrl, token: session.apiToken)
            async let fetchedLibraries = client.fetchLibraries(serverUrl: session.serverUrl, token: session.apiToken)
            let (m, libs) = try await (fetchedMangas, fetchedLibraries)
            self.mangas = m
            self.libraries = libs
        } catch let error as KaizenError {
            libraryErrorMessage = error.userMessage(language: currentLanguage)
        } catch {
            libraryErrorMessage = error.localizedDescription
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
    
    public func switchLanguage(to language: String, client: KaizenAPIClient) async {
        self.currentLanguage = language
        if var current = session {
            current.language = language
            self.session = current
            try? KeychainService.shared.saveSession(current)
            try? await client.updateUserLanguage(
                serverUrl: current.serverUrl,
                token: current.apiToken,
                userId: current.id,
                language: language
            )
        }
    }
}
