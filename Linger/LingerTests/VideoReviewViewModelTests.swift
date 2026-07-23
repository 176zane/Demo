import XCTest
@testable import Linger

@MainActor
final class VideoReviewViewModelTests: XCTestCase {
    func testDeleteUndoWithinWindowDoesNotCallDeleteAssets() async {
        let mock = MockPhotoLibrary()
        mock.items = [
            MediaItem(id: "v1", mediaKind: .video, creationDate: Date()),
            MediaItem(id: "v2", mediaKind: .video, creationDate: Date())
        ]
        let (stats, prefs) = makeStores()
        let vm = VideoReviewViewModel(
            photoLibrary: mock,
            statsStore: stats,
            preferencesStore: prefs
        )
        vm.undoWindowNanoseconds = 2_000_000_000
        await vm.start()

        let deletedID = vm.currentItem?.id
        XCTAssertNotNil(deletedID)

        await vm.deleteCurrent()
        XCTAssertTrue(vm.showUndoToast)
        XCTAssertEqual(mock.deleteCallCount, 0, "撤销窗内不应真正删除")

        vm.undoPendingDelete()
        XCTAssertEqual(mock.deleteCallCount, 0)
        XCTAssertEqual(vm.currentItem?.id, deletedID)
    }

    func testFlushAfterDeleteCallsDeleteOnce() async {
        let mock = MockPhotoLibrary()
        mock.items = [
            MediaItem(id: "v1", mediaKind: .video, creationDate: Date()),
            MediaItem(id: "v2", mediaKind: .video, creationDate: Date())
        ]
        let (stats, prefs) = makeStores()
        let vm = VideoReviewViewModel(
            photoLibrary: mock,
            statsStore: stats,
            preferencesStore: prefs
        )
        await vm.start()
        let deletedID = vm.currentItem!.id
        await vm.deleteCurrent()
        XCTAssertEqual(mock.deleteCallCount, 0)

        await vm.flushPendingDeletes()
        XCTAssertEqual(mock.deleteCallCount, 1)
        XCTAssertTrue(mock.deleted.contains(deletedID))
        XCTAssertEqual(stats.stats.deletedByBucket[.video], 1)
    }

    private func makeStores() -> (StatsStore, PreferencesStore) {
        let s = "linger.tests.video.stats.\(UUID().uuidString)"
        let p = "linger.tests.video.prefs.\(UUID().uuidString)"
        let sd = UserDefaults(suiteName: s)!
        let pd = UserDefaults(suiteName: p)!
        sd.removePersistentDomain(forName: s)
        pd.removePersistentDomain(forName: p)
        return (StatsStore(defaults: sd), PreferencesStore(defaults: pd))
    }
}
