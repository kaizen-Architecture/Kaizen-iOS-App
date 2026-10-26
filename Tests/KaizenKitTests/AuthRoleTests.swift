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
    func testLibraryStoreFiltering() {
        let store = LibraryStore()
        let manga1 = Manga(id: "1", title: "Jujutsu Kaisen", readingPercentage: 50.0, isFavorite: true)
        let manga2 = Manga(id: "2", title: "One Piece", readingPercentage: 100.0, isFavorite: false)
        let manga3 = Manga(id: "3", title: "Chainsaw Man", readingPercentage: 0.0, isFavorite: false)
        
        store.mangas = [manga1, manga2, manga3]
        
        store.selectedFilter = .all
        XCTAssertEqual(store.filteredMangas.count, 3)
        
        store.selectedFilter = .reading
        XCTAssertEqual(store.filteredMangas.count, 1)
        XCTAssertEqual(store.filteredMangas.first?.title, "Jujutsu Kaisen")
        
        store.selectedFilter = .completed
        XCTAssertEqual(store.filteredMangas.count, 1)
        XCTAssertEqual(store.filteredMangas.first?.title, "One Piece")
        
        store.selectedFilter = .favorites
        XCTAssertEqual(store.filteredMangas.count, 1)
        XCTAssertEqual(store.filteredMangas.first?.title, "Jujutsu Kaisen")
        
        store.selectedFilter = .all
        store.searchText = "chain"
        XCTAssertEqual(store.filteredMangas.count, 1)
        XCTAssertEqual(store.filteredMangas.first?.title, "Chainsaw Man")
    }
}
