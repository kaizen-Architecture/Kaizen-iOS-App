import XCTest
@testable import KaizenKit

final class BatchAndCoreModelsTests: XCTestCase {
    func testChapterDecodesOptionalSourceMetadata() throws {
        let json = """
        {
            "id": 101,
            "mangaId": 42,
            "index": 12,
            "fileName": "Chapter 12.cbz",
            "isRead": false,
            "lastReadPage": 3,
            "source": "SourceA"
        }
        """.data(using: .utf8)!

        let chapter = try JSONDecoder().decode(Chapter.self, from: json)
        XCTAssertEqual(chapter.id, 101)
        XCTAssertEqual(chapter.index, 12)
        XCTAssertEqual(chapter.source, "SourceA")

        let legacyJson = """
        {
            "id": 102,
            "index": 13,
            "source": null
        }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(Chapter.self, from: legacyJson)
        XCTAssertNil(legacy.source)
    }

    func testChapterBatchResponseDecoding() throws {
        let json = """
        {
            "success": true,
            "action": "delete",
            "mangaId": 42,
            "processedCount": 20,
            "failedIds": [999]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ChapterBatchResponse.self, from: json)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.action, "delete")
        XCTAssertEqual(response.mangaId, 42)
        XCTAssertEqual(response.processedCount, 20)
        XCTAssertEqual(response.failedIds, [999])
    }

    func testBetterSourceScanStatusDecoding() throws {
        let json = """
        {
            "isRunning": true,
            "cancelled": false,
            "processedCount": 4,
            "totalCount": 20,
            "totalReleasingInLibrary": 82,
            "totalReadingReleasingInLibrary": 18,
            "currentMangaTitle": "Example Series",
            "recommendations": [
                {
                    "mangaId": 101,
                    "title": "Example Series",
                    "currentSource": "SourceA",
                    "currentMaxChapter": 160,
                    "bestSource": "SourceB",
                    "bestMatchedTitle": "Example Series",
                    "bestMaxChapter": 172,
                    "delta": 12,
                    "isReading": true
                }
            ]
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(BetterSourceScanStatus.self, from: json)
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.progressRatio, 0.2, accuracy: 0.001)
        XCTAssertEqual(status.recommendations.count, 1)
        XCTAssertEqual(status.recommendations.first?.delta, 12)
        XCTAssertEqual(status.recommendations.first?.bestSource, "SourceB")
    }

    func testKaizenCoreDiagnosticsDecoding() throws {
        let json = """
        {
            "kaizenMangal": {
                "available": true,
                "version": "1.2.4",
                "contractVersion": 2,
                "binaryPath": "/config/bin/kaizen-mangal",
                "doctor": {
                    "ok": true,
                    "tls_profile": { "configured": "chrome_133", "resolved": "chrome_133", "chrome_major": 133 },
                    "browser": { "available": true, "mode": "cdp" },
                    "solver": { "configured": false, "reachable": false, "fallback_enabled": false },
                    "warnings": []
                }
            },
            "versionCheck": {
                "usingManagedBinary": true,
                "canRollback": true,
                "autoUpdateEnabled": true,
                "coreUpdateAvailable": false,
                "kaizenUpdateAvailable": false,
                "contractCompatible": true,
                "compatibilityStatus": "up_to_date",
                "compatibilityMessage": "All up to date"
            }
        }
        """.data(using: .utf8)!

        let diagnostics = try JSONDecoder().decode(KaizenCoreDiagnostics.self, from: json)
        XCTAssertTrue(diagnostics.kaizenMangal.available)
        XCTAssertEqual(diagnostics.kaizenMangal.version, "1.2.4")
        XCTAssertEqual(diagnostics.kaizenMangal.contractVersion, 2)
        XCTAssertEqual(diagnostics.kaizenMangal.doctor?.tlsProfile?.resolved, "chrome_133")
        XCTAssertEqual(diagnostics.versionCheck?.canRollback, true)
        XCTAssertEqual(diagnostics.versionCheck?.compatibilityStatus, "up_to_date")
    }

    func testAIStudioTemplateUsesKaizenMangalContract() {
        let lua = AIStudioStore.buildKaizenMangalTemplate(baseURL: "https://example.org", forceHeadlessFallback: false)
        XCTAssertTrue(lua.contains("function SearchManga(query)"))
        XCTAssertTrue(lua.contains("function MangaChapters(mangaURL)"))
        XCTAssertTrue(lua.contains("function ChapterPages(chapterURL)"))
        XCTAssertTrue(lua.contains("Http.client()"))
        XCTAssertTrue(lua.contains("Headless.browser()"))
        XCTAssertTrue(lua.contains("browser:sync_cookies()"))
        XCTAssertTrue(lua.contains("page:close()"))
        XCTAssertTrue(lua.contains("table.insert("))
    }
}
