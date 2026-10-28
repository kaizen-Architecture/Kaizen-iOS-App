import XCTest
@testable import Kaizen

final class AuthRoleXCTests: XCTestCase {
    func testUserRoleManagement() {
        XCTAssertTrue(UserRole.superadmin.isManagement)
        XCTAssertTrue(UserRole.manager.isManagement)
        XCTAssertFalse(UserRole.reader.isManagement)
        XCTAssertFalse(UserRole.service.isManagement)
    }
    
    func testUserSessionEncoding() throws {
        guard let url = URL(string: "http://192.168.20.28:3333") else {
            XCTFail("URL no válida")
            return
        }
        
        let session = UserSession(
            id: 42,
            username: "danjes",
            role: .superadmin,
            language: "es",
            apiToken: "0123456789abcdef",
            serverUrl: url
        )
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(UserSession.self, from: data)
        
        XCTAssertEqual(decoded.id, 42)
        XCTAssertEqual(decoded.username, "danjes")
        XCTAssertEqual(decoded.role, .superadmin)
        XCTAssertEqual(decoded.language, "es")
        XCTAssertEqual(decoded.serverUrl, url)
    }
    
    @MainActor
    func testLibraryFiltering() {
        let manga1 = Manga(id: 1, title: "Jujutsu Kaisen", readingPercentage: 50.0, isFavorite: true)
        let manga2 = Manga(id: 2, title: "One Piece", readingPercentage: 100.0, isFavorite: false)
        let manga3 = Manga(id: 3, title: "Chainsaw Man", readingPercentage: 0.0, isFavorite: false)
        let mangas = [manga1, manga2, manga3]
        
        let reading = mangas.filter { $0.readingPercentage > 0 && $0.readingPercentage < 100 }
        XCTAssertEqual(reading.count, 1)
        XCTAssertEqual(reading.first?.title, "Jujutsu Kaisen")
        
        let caughtUp = mangas.filter { $0.readingPercentage >= 100 }
        XCTAssertEqual(caughtUp.count, 1)
        XCTAssertEqual(caughtUp.first?.title, "One Piece")
        
        let favorites = mangas.filter { $0.isFavorite }
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.title, "Jujutsu Kaisen")
    }
    
    @MainActor
    func testUserShelfManagement() {
        let appState = AppState()
        let initialShelvesCount = appState.shelves.count
        
        appState.createShelf(name: "Joyas Especiales", icon: "sparkles")
        XCTAssertEqual(appState.shelves.count, initialShelvesCount + 1)
        guard let shelf = appState.shelves.last else {
            XCTFail("Shelf no encontrada")
            return
        }
        XCTAssertEqual(shelf.name, "Joyas Especiales")
        
        XCTAssertFalse(appState.isMangaInShelf(shelfId: shelf.id, mangaId: 42))
        appState.toggleMangaInShelf(shelfId: shelf.id, mangaId: 42)
        XCTAssertTrue(appState.isMangaInShelf(shelfId: shelf.id, mangaId: 42))
        appState.toggleMangaInShelf(shelfId: shelf.id, mangaId: 42)
        XCTAssertFalse(appState.isMangaInShelf(shelfId: shelf.id, mangaId: 42))
        
        appState.deleteShelf(id: shelf.id)
        XCTAssertEqual(appState.shelves.count, initialShelvesCount)
    }
    
    /// Forma real de `GET /api/v1/mangas` en el servidor Kaizen (id numérico, metadata y readingStatus anidados).
    func testMangaDecodesServerShape() throws {
        let json = """
        [{
          "id": 7, "isFavorite": true, "title": "Berserk", "libraryId": 1,
          "createdAt": "2026-10-26T12:35:23.123Z",
          "metadata": {
            "cover": "http://192.168.20.28:3333/api/v1/mangas/7/cover",
            "summary": "Dark fantasy.", "authors": ["Kentaro Miura"],
            "genres": ["Fantasy"], "status": "ONGOING", "synonyms": ["ベルセルク"]
          },
          "library": { "id": 1, "path": "/manga" },
          "readingStatus": {
            "totalChapters": 10, "readChapters": 4, "unreadChapters": 6,
            "percentageComplete": 40, "isFullyRead": false
          }
        }]
        """.data(using: .utf8)!
        
        let mangas = try JSONDecoder().decode([Manga].self, from: json)
        XCTAssertEqual(mangas.count, 1)
        XCTAssertEqual(mangas[0].id, 7)
        XCTAssertEqual(mangas[0].title, "Berserk")
        XCTAssertEqual(mangas[0].coverUrl, "http://192.168.20.28:3333/api/v1/mangas/7/cover")
        XCTAssertEqual(mangas[0].authors, ["Kentaro Miura"])
        XCTAssertEqual(mangas[0].totalChapters, 10)
        XCTAssertEqual(mangas[0].unreadCount, 6)
        XCTAssertEqual(mangas[0].readingPercentage, 40)
        XCTAssertTrue(mangas[0].isFavorite)
    }
    
    func testServerURLParsing() {
        XCTAssertEqual(ServerURL.parse("192.168.20.28:3333")?.absoluteString, "http://192.168.20.28:3333")
        XCTAssertEqual(ServerURL.parse(" http://kaizen.local:3333/ ")?.absoluteString, "http://kaizen.local:3333")
        XCTAssertEqual(ServerURL.parse("https://example.com")?.absoluteString, "https://example.com")
        XCTAssertNil(ServerURL.parse(""))
        XCTAssertNil(ServerURL.parse("ftp://example.com"))
    }
    
    func testFriendlyErrorsAreBilingual() {
        XCTAssertTrue(KaizenError.invalidCredentials.userMessage(language: "es").contains("incorrectos"))
        XCTAssertTrue(KaizenError.invalidCredentials.userMessage(language: "en").contains("Wrong"))
        XCTAssertTrue(KaizenError.cannotReachServer(host: "192.168.20.28").userMessage(language: "es").contains("192.168.20.28"))
        XCTAssertTrue(KaizenError.tokenRejected.userMessage(language: "en").contains("API Token"))
    }
    
    @MainActor
    func testGenreAndStatusFiltering() {
        let m1 = Manga(id: 1, title: "Solo Leveling", genres: ["Action", "Fantasy"], status: "COMPLETED")
        let m2 = Manga(id: 2, title: "Omniscient Reader", genres: ["Action", "Psychological"], status: "ONGOING")
        let m3 = Manga(id: 3, title: "Horimiya", genres: ["Romance", "Comedy"], status: "COMPLETED")
        let list = [m1, m2, m3]
        
        let actionMangas = list.filter { $0.genres?.contains("Action") ?? false }
        XCTAssertEqual(actionMangas.count, 2)
        
        let ongoingMangas = list.filter { $0.status?.uppercased() == "ONGOING" }
        XCTAssertEqual(ongoingMangas.count, 1)
        XCTAssertEqual(ongoingMangas.first?.title, "Omniscient Reader")
        
        let completedAction = list.filter { ($0.status?.uppercased() == "COMPLETED") && ($0.genres?.contains("Action") ?? false) }
        XCTAssertEqual(completedAction.count, 1)
        XCTAssertEqual(completedAction.first?.title, "Solo Leveling")
    }
    
    @MainActor
    func testReadingHistoryManagement() {
        let appState = AppState()
        appState.clearHistory()
        XCTAssertTrue(appState.history.isEmpty)
        
        let manga = Manga(id: 10, title: "Tower of God")
        let chapter = Chapter(id: 101, mangaId: 10, index: 5, fileName: "ch_005.cbz")
        
        appState.recordHistory(
            manga: manga,
            chapter: chapter,
            pageIndex: 12,
            totalPages: 30
        )
        
        XCTAssertEqual(appState.history.count, 1)
        XCTAssertEqual(appState.history[0].mangaTitle, "Tower of God")
        XCTAssertEqual(appState.history[0].chapterIndex, 5)
        XCTAssertEqual(appState.history[0].pageIndex, 12)
        
        // Actualizar el mismo capítulo en otra página no debe duplicar la entrada
        appState.recordHistory(
            manga: manga,
            chapter: chapter,
            pageIndex: 20,
            totalPages: 30
        )
        XCTAssertEqual(appState.history.count, 1)
        XCTAssertEqual(appState.history[0].pageIndex, 20)
        
        // Borrar entrada
        let entryId = appState.history[0].id
        appState.deleteHistoryEntry(id: entryId)
        XCTAssertTrue(appState.history.isEmpty)
    }
    
    @MainActor
    func testLanguageSwitchingPersistence() {
        let appState = AppState()
        appState.setLanguage("en")
        XCTAssertEqual(appState.currentLanguage, "en")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "kaizen_user_language"), "en")
        
        appState.setLanguage("es")
        XCTAssertEqual(appState.currentLanguage, "es")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "kaizen_user_language"), "es")
    }
    
    func testKaizenSourceItemModel() {
        let s1 = KaizenSourceItem(name: "mangadex", isInstalled: true, isActive: true, isFailed: false, origin: "MANGAL")
        XCTAssertEqual(s1.id, "mangadex")
        XCTAssertTrue(s1.isActive)
        XCTAssertFalse(s1.isFailed)
        
        let s2 = KaizenSourceItem(name: "olympus_AI", isInstalled: true, isActive: false, isFailed: true, origin: "AI_GENERATED")
        XCTAssertFalse(s2.isActive)
        XCTAssertTrue(s2.isFailed)
    }
    
    func testFailedDownloadJobModel() {
        let job = FailedDownloadJob(
            id: "job-101",
            mangaId: 5,
            mangaTitle: "Chainsaw Man",
            chapterIndex: 120.0,
            source: "olympus",
            failedReason: "Cloudflare blocked request",
            attempts: 3,
            isPaused: false
        )
        XCTAssertEqual(job.id, "job-101")
        XCTAssertEqual(job.mangaId, 5)
        XCTAssertEqual(job.mangaTitle, "Chainsaw Man")
        XCTAssertEqual(job.chapterIndex, 120.0)
        XCTAssertEqual(job.source, "olympus")
        XCTAssertEqual(job.failedReason, "Cloudflare blocked request")
        XCTAssertEqual(job.attempts, 3)
        XCTAssertFalse(job.isPaused)
    }
    
    @MainActor
    func testSessionRememberDisabled() {
        let appState = AppState()
        guard let url = URL(string: "http://192.168.20.28:3333") else { return }
        let session = UserSession(id: 1, username: "admin", role: .superadmin, language: "es", apiToken: "tok", serverUrl: url)
        
        // When remember is false, it should set session in memory and record the disabled preference
        appState.setSession(session, remember: false)
        XCTAssertEqual(appState.session?.username, "admin")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "kaizen_remember_login_disabled"))
        
        // When remember is true, it clears the disabled preference
        appState.setSession(session, remember: true)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "kaizen_remember_login_disabled"))
    }
}

