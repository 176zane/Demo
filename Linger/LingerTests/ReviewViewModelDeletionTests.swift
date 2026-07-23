import XCTest
@testable import Linger

/// 覆盖组末删除：部分失败应留在确认页并可重试
@MainActor
final class ReviewViewModelDeletionTests: XCTestCase {
    func testPartialDeleteFailureStaysOnConfirmAndKeepsFailedItems() async {
        let mock = MockPhotoLibrary()
        mock.items = [
            MediaItem(id: "ok", mediaKind: .photo, creationDate: Date()),
            MediaItem(id: "bad", mediaKind: .photo, creationDate: Date())
        ]
        mock.deleteResultOverride = DeleteResult(
            requestedIDs: ["ok", "bad"],
            deletedIDs: ["ok"],
            failedIDs: ["bad"],
            errorDescription: "部分照片删除失败"
        )

        let (stats, prefs) = makeIsolatedStores()
        let viewModel = ReviewViewModel(
            photoLibrary: mock,
            statsStore: stats,
            preferencesStore: prefs
        )

        viewModel.applyTestingState(
            deal: ReviewDeal(
                items: mock.items,
                currentIndex: 2,
                markedForDeletion: ["ok", "bad"]
            ),
            phase: .confirming
        )

        await viewModel.confirmDeletion(selectedIDs: ["ok", "bad"])

        XCTAssertEqual(viewModel.phase, .confirming)
        XCTAssertNotNil(viewModel.deleteError)
        XCTAssertEqual(viewModel.deal.markedForDeletion, ["bad"])
        XCTAssertEqual(viewModel.deal.items.map(\.id), ["bad"])
        XCTAssertEqual(stats.stats.deletedCount, 1)
    }

    func testDeleteThrownErrorStaysOnConfirm() async {
        let mock = MockPhotoLibrary()
        mock.items = [
            MediaItem(id: "a", mediaKind: .photo, creationDate: Date())
        ]
        mock.deleteShouldThrow = PhotoLibraryError.deleteFailed("用户取消")

        let (stats, prefs) = makeIsolatedStores()
        let viewModel = ReviewViewModel(
            photoLibrary: mock,
            statsStore: stats,
            preferencesStore: prefs
        )

        viewModel.applyTestingState(
            deal: ReviewDeal(items: mock.items, currentIndex: 1, markedForDeletion: ["a"]),
            phase: .confirming
        )

        await viewModel.confirmDeletion(selectedIDs: ["a"])

        XCTAssertEqual(viewModel.phase, .confirming)
        XCTAssertNotNil(viewModel.deleteError)
        XCTAssertEqual(viewModel.deal.markedForDeletion, ["a"])
    }

    func testFullSuccessAdvancesToNextDeal() async {
        let mock = MockPhotoLibrary()
        mock.items = (0..<5).map {
            MediaItem(id: "n-\($0)", mediaKind: .photo, creationDate: Date())
        }
        mock.deleteResultOverride = DeleteResult(
            requestedIDs: ["n-0"],
            deletedIDs: ["n-0"],
            failedIDs: [],
            errorDescription: nil
        )

        let (stats, prefs) = makeIsolatedStores()
        prefs.dealSize = 10

        let viewModel = ReviewViewModel(
            photoLibrary: mock,
            statsStore: stats,
            preferencesStore: prefs
        )

        viewModel.applyTestingState(
            deal: ReviewDeal(
                items: [mock.items[0]],
                currentIndex: 1,
                markedForDeletion: ["n-0"]
            ),
            phase: .confirming
        )

        await viewModel.confirmDeletion(selectedIDs: ["n-0"])

        XCTAssertEqual(viewModel.phase, .browsing)
        XCTAssertNil(viewModel.deleteError)
        XCTAssertFalse(viewModel.deal.items.isEmpty)
    }

    /// 使用唯一 suite，避免测试间 UserDefaults 串味
    private func makeIsolatedStores() -> (StatsStore, PreferencesStore) {
        let statsName = "linger.tests.stats.\(UUID().uuidString)"
        let prefsName = "linger.tests.prefs.\(UUID().uuidString)"
        let statsDefaults = UserDefaults(suiteName: statsName)!
        let prefsDefaults = UserDefaults(suiteName: prefsName)!
        statsDefaults.removePersistentDomain(forName: statsName)
        prefsDefaults.removePersistentDomain(forName: prefsName)
        return (StatsStore(defaults: statsDefaults), PreferencesStore(defaults: prefsDefaults))
    }
}
