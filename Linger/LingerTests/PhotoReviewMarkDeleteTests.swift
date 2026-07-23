import XCTest
@testable import Linger

/// 照片 Tab：上划只标记，确认前不得调用 deleteAssets
@MainActor
final class PhotoReviewMarkDeleteTests: XCTestCase {
    func testMarkDeleteDoesNotCallDeleteAssetsUntilConfirm() async {
        let mock = MockPhotoLibrary()
        mock.items = [
            MediaItem(id: "p1", mediaKind: .photo, creationDate: Date()),
            MediaItem(id: "p2", mediaKind: .screenshot, creationDate: Date())
        ]

        let statsName = "linger.tests.photo.mark.\(UUID().uuidString)"
        let prefsName = "linger.tests.photo.prefs.\(UUID().uuidString)"
        let statsDefaults = UserDefaults(suiteName: statsName)!
        let prefsDefaults = UserDefaults(suiteName: prefsName)!
        statsDefaults.removePersistentDomain(forName: statsName)
        prefsDefaults.removePersistentDomain(forName: prefsName)

        let stats = StatsStore(defaults: statsDefaults)
        let prefs = PreferencesStore(defaults: prefsDefaults)
        let viewModel = ReviewViewModel(
            photoLibrary: mock,
            statsStore: stats,
            preferencesStore: prefs
        )

        viewModel.applyTestingState(
            deal: ReviewDeal(items: mock.items, currentIndex: 0, markedForDeletion: []),
            phase: .browsing
        )

        viewModel.markDeleteCurrent()

        XCTAssertTrue(viewModel.deal.markedForDeletion.contains("p1"))
        XCTAssertTrue(mock.deleted.isEmpty, "标记删除阶段不应调用 deleteAssets")
        XCTAssertEqual(mock.deleteCallCount, 0)

        await viewModel.confirmDeletion(selectedIDs: ["p1"])

        XCTAssertEqual(mock.deleteCallCount, 1)
        XCTAssertTrue(mock.deleted.contains("p1"))
    }
}
