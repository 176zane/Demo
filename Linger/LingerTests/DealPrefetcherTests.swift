import XCTest
@testable import Linger

/// 抽组预取：后台补队列、取用出队、配置变化丢弃缓存
@MainActor
final class DealPrefetcherTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "linger.tests.prefetch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeMock(count: Int) -> MockPhotoLibrary {
        let mock = MockPhotoLibrary()
        mock.items = (0..<count).map {
            MediaItem(id: "pf-\($0)", mediaKind: .photo, creationDate: Date())
        }
        return mock
    }

    /// ensureFilled 应补齐两组，且组间照片互不重复
    func testEnsureFilledBuildsTwoDistinctDeals() async {
        let prefetcher = DealPrefetcher(defaults: makeDefaults())
        let mock = makeMock(count: 40)

        prefetcher.ensureFilled(size: 5, kinds: [.photo], photoLibrary: mock)
        await prefetcher.waitForRefill()

        XCTAssertEqual(prefetcher.cachedDealCount, 2)
        let first = prefetcher.takeDeal(size: 5, kinds: [.photo])!
        let second = prefetcher.takeDeal(size: 5, kinds: [.photo])!
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(second.count, 5)
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: Set(second.map(\.id))), "两组不应重复")
    }

    /// 取用后队列出队；空队列返回 nil
    func testTakeDealPopsQueue() async {
        let prefetcher = DealPrefetcher(defaults: makeDefaults())
        let mock = makeMock(count: 40)

        prefetcher.ensureFilled(size: 4, kinds: [.photo], photoLibrary: mock)
        await prefetcher.waitForRefill()

        XCTAssertNotNil(prefetcher.takeDeal(size: 4, kinds: [.photo]))
        XCTAssertNotNil(prefetcher.takeDeal(size: 4, kinds: [.photo]))
        XCTAssertNil(prefetcher.takeDeal(size: 4, kinds: [.photo]), "队列耗尽应返回 nil")
    }

    /// 张数或类型筛选变化时，旧缓存不可用
    func testConfigMismatchDiscardsCache() async {
        let prefetcher = DealPrefetcher(defaults: makeDefaults())
        let mock = makeMock(count: 40)

        prefetcher.ensureFilled(size: 5, kinds: [.photo], photoLibrary: mock)
        await prefetcher.waitForRefill()
        XCTAssertEqual(prefetcher.cachedDealCount, 2)

        // 换张数：直接取不到
        XCTAssertNil(prefetcher.takeDeal(size: 8, kinds: [.photo]))
        // 换筛选：重新补取后旧缓存被清空重建
        prefetcher.ensureFilled(size: 5, kinds: [.photo, .screenshot], photoLibrary: mock)
        await prefetcher.waitForRefill()
        XCTAssertNotNil(prefetcher.takeDeal(size: 5, kinds: [.photo, .screenshot]))
    }

    /// 相册资源不足时不应死循环，凑不齐即停止
    func testSmallLibraryStopsGracefully() async {
        let prefetcher = DealPrefetcher(defaults: makeDefaults())
        let mock = makeMock(count: 3)

        prefetcher.ensureFilled(size: 5, kinds: [.photo], photoLibrary: mock)
        await prefetcher.waitForRefill()

        // 第一组拿走全部 3 张后，第二组无可用照片，队列只有一组
        XCTAssertEqual(prefetcher.cachedDealCount, 1)
    }

    /// ViewModel 命中缓存时不再走抽取，直接进入浏览态
    func testViewModelUsesCachedDeal() async {
        let defaults = makeDefaults()
        let prefetcher = DealPrefetcher(defaults: defaults)
        let mock = makeMock(count: 40)

        // 与 PreferencesStore 默认配置（20 张 / 非视频全类型）保持一致
        prefetcher.ensureFilled(size: 20, kinds: MediaKind.nonVideoKinds, photoLibrary: mock)
        await prefetcher.waitForRefill()
        let cachedBefore = prefetcher.cachedDealCount
        XCTAssertGreaterThan(cachedBefore, 0)

        let statsName = "linger.tests.prefetch.stats.\(UUID().uuidString)"
        let prefsName = "linger.tests.prefetch.prefs.\(UUID().uuidString)"
        let viewModel = ReviewViewModel(
            photoLibrary: mock,
            statsStore: StatsStore(defaults: UserDefaults(suiteName: statsName)!),
            preferencesStore: PreferencesStore(defaults: UserDefaults(suiteName: prefsName)!),
            prefetcher: prefetcher
        )

        await viewModel.start()
        await prefetcher.waitForRefill()

        XCTAssertEqual(viewModel.phase, .browsing)
        XCTAssertFalse(viewModel.deal.items.isEmpty)
    }
}
