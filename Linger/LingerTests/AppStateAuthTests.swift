import XCTest
@testable import Linger

/// 根路由必须按相册权限决定：已授权不能再停在引导页
@MainActor
final class AppStateAuthTests: XCTestCase {
    private func makeState(status: PhotoAuthStatus) -> AppState {
        let mock = MockPhotoLibrary()
        mock.status = status
        let statsName = "linger.tests.auth.stats.\(UUID().uuidString)"
        let prefsName = "linger.tests.auth.prefs.\(UUID().uuidString)"
        let statsDefaults = UserDefaults(suiteName: statsName)!
        let prefsDefaults = UserDefaults(suiteName: prefsName)!
        statsDefaults.removePersistentDomain(forName: statsName)
        prefsDefaults.removePersistentDomain(forName: prefsName)
        return AppState(
            photoLibrary: mock,
            statsStore: StatsStore(defaults: statsDefaults),
            preferencesStore: PreferencesStore(defaults: prefsDefaults)
        )
    }

    func testAuthorizedEntersReview() {
        let state = makeState(status: .authorized)
        XCTAssertEqual(state.rootScreen, .review)
    }

    func testLimitedAccessAlsoEntersReview() {
        let state = makeState(status: .limited)
        XCTAssertEqual(state.rootScreen, .review)
    }

    func testNotDeterminedShowsPermission() {
        let state = makeState(status: .notDetermined)
        XCTAssertEqual(state.rootScreen, .permission)
    }

    /// 用户在设置里授权后，再次 refresh 必须离开授权页
    func testRefreshAuthAfterGrantLeavesPermission() {
        let mock = MockPhotoLibrary()
        mock.status = .notDetermined
        let statsName = "linger.tests.auth.refresh.stats.\(UUID().uuidString)"
        let prefsName = "linger.tests.auth.refresh.prefs.\(UUID().uuidString)"
        let statsDefaults = UserDefaults(suiteName: statsName)!
        let prefsDefaults = UserDefaults(suiteName: prefsName)!
        statsDefaults.removePersistentDomain(forName: statsName)
        prefsDefaults.removePersistentDomain(forName: prefsName)
        let state = AppState(
            photoLibrary: mock,
            statsStore: StatsStore(defaults: statsDefaults),
            preferencesStore: PreferencesStore(defaults: prefsDefaults)
        )
        XCTAssertEqual(state.rootScreen, .permission)

        mock.status = .authorized
        state.refreshAuth()
        XCTAssertEqual(state.rootScreen, .review)
    }
}
