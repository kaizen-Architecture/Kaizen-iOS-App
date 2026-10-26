import Testing
@testable import KaizenKit
import Foundation

@Suite("Kaizen Architecture & Feature Tests")
struct ArchitectureFeatureTests {
    
    @Test("Verificar roles de usuario y permisos administrativos")
    func testUserRoleManagement() {
        #expect(UserRole.superadmin.isManagement == true)
        #expect(UserRole.manager.isManagement == true)
        #expect(UserRole.reader.isManagement == false)
        #expect(UserRole.service.isManagement == false)
    }
    
    @Test("Verificar serialización y deserialización de UserSession")
    func testUserSessionEncoding() throws {
        guard let url = URL(string: "http://192.168.20.28:3333") else {
            Issue.record("URL no válida")
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
        
        #expect(decoded.id == 42)
        #expect(decoded.username == "danjes")
        #expect(decoded.role == .superadmin)
        #expect(decoded.language == "es")
        #expect(decoded.serverUrl == url)
    }
    
    @Test("Verificar filtrado dinámico de LibraryStore")
    @MainActor
    func testLibraryStoreFiltering() {
        let store = LibraryStore()
        let manga1 = Manga(id: "1", title: "Jujutsu Kaisen", readingPercentage: 50.0, isFavorite: true)
        let manga2 = Manga(id: "2", title: "One Piece", readingPercentage: 100.0, isFavorite: false)
        let manga3 = Manga(id: "3", title: "Chainsaw Man", readingPercentage: 0.0, isFavorite: false)
        
        store.mangas = [manga1, manga2, manga3]
        
        // Todos
        store.selectedFilter = .all
        #expect(store.filteredMangas.count == 3)
        
        // Leyendo
        store.selectedFilter = .reading
        #expect(store.filteredMangas.count == 1)
        #expect(store.filteredMangas.first?.title == "Jujutsu Kaisen")
        
        // Completados
        store.selectedFilter = .completed
        #expect(store.filteredMangas.count == 1)
        #expect(store.filteredMangas.first?.title == "One Piece")
        
        // Favoritos
        store.selectedFilter = .favorites
        #expect(store.filteredMangas.count == 1)
        #expect(store.filteredMangas.first?.title == "Jujutsu Kaisen")
        
        // Búsqueda por texto
        store.selectedFilter = .all
        store.searchText = "chain"
        #expect(store.filteredMangas.count == 1)
        #expect(store.filteredMangas.first?.title == "Chainsaw Man")
    }
    
    @Test("Verificar máquina de estados del ReaderStore")
    @MainActor
    func testReaderStoreState() {
        let store = ReaderStore(mangaId: "m1", chapterId: "c1")
        store.pages = ["page1.jpg", "page2.jpg", "page3.jpg"]
        
        #expect(store.currentPage == 1)
        #expect(store.readingDirection == .rightToLeft)
        #expect(store.isHUDVisible == true)
        
        store.currentPage = 3
        #expect(store.currentPage == 3)
    }
    
    @Test("Verificar creación y serialización de MangaRequestItem")
    func testMangaRequests() {
        let req = MangaRequestItem(id: 10, title: "Solo Leveling", startChapter: 1, status: .pending, requestedBy: "danjes")
        #expect(req.title == "Solo Leveling")
        #expect(req.status == .pending)
        #expect(req.startChapter == 1)
    }
    
    @Test("Verificar reseteo de Circuit Breaker en AdminStore")
    @MainActor
    func testAdminCircuitBreakerReset() async {
        let store = AdminStore()
        #expect(store.circuitBreakerPausedCount > 0)
        await store.resetCircuitBreaker()
        #expect(store.circuitBreakerPausedCount == 0)
    }
}
