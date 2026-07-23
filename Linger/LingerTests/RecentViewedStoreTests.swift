import XCTest
@testable import Linger

@MainActor
final class RecentViewedStoreTests: XCTestCase {
    func testRememberPersistsAcrossInstances() {
        let suiteName = "linger.tests.recent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = RecentViewedStore(defaults: defaults, cap: 10)
        store.remember(["a", "b", "c"])
        XCTAssertTrue(store.contains("a"))
        XCTAssertTrue(store.contains("c"))

        // 新实例应从 UserDefaults 恢复
        let restored = RecentViewedStore(defaults: defaults, cap: 10)
        XCTAssertTrue(restored.contains("a"))
        XCTAssertTrue(restored.contains("b"))
        XCTAssertTrue(restored.contains("c"))

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testCapEvictsOldest() {
        let suiteName = "linger.tests.recent.cap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = RecentViewedStore(defaults: defaults, cap: 3)
        store.remember(["1", "2", "3"])
        store.remember(["4"])

        XCTAssertFalse(store.contains("1"), "超出上限时应淘汰最旧项")
        XCTAssertTrue(store.contains("2"))
        XCTAssertTrue(store.contains("4"))

        defaults.removePersistentDomain(forName: suiteName)
    }
}
