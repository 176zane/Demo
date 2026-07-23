import XCTest
@testable import Linger

@MainActor
final class StatsAndPreferencesTests: XCTestCase {
    func testStatsPersistAndAccumulate() {
        let suiteName = "linger.tests.stats.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = StatsStore(defaults: suite)
        store.recordViewed(3)
        store.recordDeleted(2)
        XCTAssertEqual(store.stats.viewedCount, 3)
        XCTAssertEqual(store.stats.deletedCount, 2)

        let reloaded = StatsStore(defaults: suite)
        XCTAssertEqual(reloaded.stats.viewedCount, 3)
        XCTAssertEqual(reloaded.stats.deletedCount, 2)
    }

    func testResetAllClearsBuckets() {
        let suiteName = "linger.tests.reset.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = StatsStore(defaults: suite)
        store.recordViewed(bucket: .screenshot, count: 2)
        store.recordDeleted(bucket: .video, count: 1, bytes: 500)
        store.resetAll()
        XCTAssertEqual(store.stats, .empty)

        let reloaded = StatsStore(defaults: suite)
        XCTAssertEqual(reloaded.stats, .empty)
    }

    func testPreferencesDealSizeClamped() {
        let name = "linger.tests.prefs.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.set(99, forKey: "linger.preferences.dealSize")

        let store = PreferencesStore(defaults: suite)
        XCTAssertEqual(store.dealSize, 20)

        store.dealSize = 10
        XCTAssertEqual(store.dealSize, 10)
    }

    func testToggleKindKeepsAtLeastOne() {
        let suite = UserDefaults(suiteName: "linger.tests.kinds.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: suite)
        store.allowedKinds = [.photo]
        store.toggleKind(.photo)
        XCTAssertEqual(store.allowedKinds, [.photo])
    }
}
