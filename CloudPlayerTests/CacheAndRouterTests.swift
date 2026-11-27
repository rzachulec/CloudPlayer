import Foundation
import XCTest
@testable import CloudPlayer

final class CacheAndRouterTests: XCTestCase {
    func testAPICacheMemoryAndDiskRoundTrip() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudplayer-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = APICache(directory: dir)
        let tracks = [SCTrack(id: 1, title: "Alpha", duration: 100_000), SCTrack(id: 2, title: "Beta", duration: 200_000)]

        await cache.save(tracks, key: "likes:42")
        let loaded = await cache.load([SCTrack].self, key: "likes:42")
        XCTAssertEqual(loaded?.map(\.id), [1, 2])

        // Re-instantiate pointing at same disk dir to verify disk persistence
        let coldCache = APICache(directory: dir)
        let fromDisk = await coldCache.load([SCTrack].self, key: "likes:42")
        XCTAssertEqual(fromDisk?.map(\.title), ["Alpha", "Beta"])

        await coldCache.clearAll()
        let afterClear = await coldCache.load([SCTrack].self, key: "likes:42")
        XCTAssertNil(afterClear)
    }

    func testWaveformDownsampling() {
        let wf = SCWaveform(width: 1800, height: 140, samples: Array(repeating: 70, count: 1000))
        let bars = wf.normalizedBars(count: 100)
        XCTAssertEqual(bars.count, 100)
        XCTAssertEqual(bars[0], 0.5, accuracy: 0.001)
    }

    @MainActor
    func testAppRouterNavigationStack() {
        let router = AppRouter(initial: .likes)
        XCTAssertFalse(router.canGoBack)
        XCTAssertFalse(router.canGoForward)
        XCTAssertEqual(router.selectedSidebar, .likes)

        router.selectSidebar(.home)
        XCTAssertEqual(router.current, .home)
        XCTAssertTrue(router.canGoBack)

        router.search("dnb")
        XCTAssertEqual(router.current, .search("dnb"))
        XCTAssertNil(router.selectedSidebar)

        router.goBack()
        XCTAssertEqual(router.current, .home)
        XCTAssertTrue(router.canGoForward)

        router.goForward()
        XCTAssertEqual(router.current, .search("dnb"))
        XCTAssertFalse(router.canGoForward)

        // Navigating to a new route clears forward stack
        router.goBack()
        router.selectSidebar(.history)
        XCTAssertFalse(router.canGoForward)
        XCTAssertEqual(router.current, .history)
    }
}
