import XCTest
@testable import Linger

/// 照片首页精选三张 + 浏览页返回统一删除
@MainActor
final class PhotoBrowseFlowTests: XCTestCase {
    private func makeViewModel(mock: MockPhotoLibrary) -> ReviewViewModel {
        let statsName = "linger.tests.browse.stats.\(UUID().uuidString)"
        let prefsName = "linger.tests.browse.prefs.\(UUID().uuidString)"
        let statsDefaults = UserDefaults(suiteName: statsName)!
        let prefsDefaults = UserDefaults(suiteName: prefsName)!
        statsDefaults.removePersistentDomain(forName: statsName)
        prefsDefaults.removePersistentDomain(forName: prefsName)

        return ReviewViewModel(
            photoLibrary: mock,
            statsStore: StatsStore(defaults: statsDefaults),
            preferencesStore: PreferencesStore(defaults: prefsDefaults)
        )
    }

    /// 抽组后应从本组随机挑出最多三张互不重复的精选
    func testFeaturedTrioPickedFromDeal() async {
        let mock = MockPhotoLibrary()
        mock.items = (0..<10).map {
            MediaItem(id: "p-\($0)", mediaKind: .photo, creationDate: Date())
        }
        let viewModel = makeViewModel(mock: mock)

        await viewModel.start()

        XCTAssertEqual(viewModel.featuredItems.count, 3)
        XCTAssertEqual(Set(viewModel.featuredItems.map(\.id)).count, 3, "精选不应重复")
        let dealIDs = Set(viewModel.deal.items.map(\.id))
        XCTAssertTrue(viewModel.featuredItems.allSatisfy { dealIDs.contains($0.id) })
    }

    /// 组内不足三张时精选数量随组收窄
    func testFeaturedTrioShrinksWithSmallDeal() async {
        let mock = MockPhotoLibrary()
        mock.items = [
            MediaItem(id: "only-1", mediaKind: .photo, creationDate: Date()),
            MediaItem(id: "only-2", mediaKind: .photo, creationDate: Date())
        ]
        let viewModel = makeViewModel(mock: mock)

        await viewModel.start()

        XCTAssertEqual(viewModel.featuredItems.count, 2)
    }

    /// 浏览页返回时批量删除标记项，并从本组移除、刷新精选
    func testDeleteMarkedFromBrowseRemovesAndRefreshes() async {
        let mock = MockPhotoLibrary()
        mock.items = (0..<6).map {
            MediaItem(id: "b-\($0)", mediaKind: .photo, creationDate: Date())
        }
        let viewModel = makeViewModel(mock: mock)
        viewModel.applyTestingState(
            deal: ReviewDeal(items: mock.items, currentIndex: 0, markedForDeletion: []),
            phase: .browsing
        )
        viewModel.refreshFeatured()

        await viewModel.deleteMarkedFromBrowse(ids: ["b-0", "b-3"])

        XCTAssertEqual(mock.deleteCallCount, 1)
        XCTAssertEqual(Set(mock.deleted), ["b-0", "b-3"])
        XCTAssertFalse(viewModel.deal.items.contains(where: { $0.id == "b-0" || $0.id == "b-3" }))
        // 精选应全部来自剩余照片
        let remaining = Set(viewModel.deal.items.map(\.id))
        XCTAssertTrue(viewModel.featuredItems.allSatisfy { remaining.contains($0.id) })
    }

    /// 空集合不应触发删除调用
    func testDeleteMarkedFromBrowseIgnoresEmptySet() async {
        let mock = MockPhotoLibrary()
        mock.items = [MediaItem(id: "keep", mediaKind: .photo, creationDate: Date())]
        let viewModel = makeViewModel(mock: mock)
        viewModel.applyTestingState(
            deal: ReviewDeal(items: mock.items, currentIndex: 0, markedForDeletion: []),
            phase: .browsing
        )

        await viewModel.deleteMarkedFromBrowse(ids: [])

        XCTAssertEqual(mock.deleteCallCount, 0)
    }

    /// 横图应铺满可用宽度，从而左右正好是 inset
    func testFittedSizeLandscapeUsesFullWidth() {
        let bounds = CGSize(width: 360, height: 500)
        let size = PhotoBrowseLayout.fittedSize(aspect: 16.0 / 9.0, in: bounds)
        XCTAssertEqual(size.width, 360, accuracy: 0.5)
        XCTAssertLessThanOrEqual(size.width, bounds.width)
        XCTAssertLessThanOrEqual(size.height, bounds.height)
    }

    /// 上划缩放：未上划保持 1，位移越大越接近 80%，且不会更小
    func testSwipeUpScaleMapsOffsetToEightyPercentFloor() {
        XCTAssertEqual(PhotoBrowseLayout.swipeUpScale(forOffset: 0), 1, accuracy: 0.001)
        XCTAssertEqual(PhotoBrowseLayout.swipeUpScale(forOffset: 40), 1, accuracy: 0.001)

        let half = PhotoBrowseLayout.swipeUpScaleDistance / 2
        XCTAssertEqual(PhotoBrowseLayout.swipeUpScale(forOffset: -half), 0.9, accuracy: 0.001)
        XCTAssertEqual(
            PhotoBrowseLayout.swipeUpScale(forOffset: -PhotoBrowseLayout.swipeUpScaleDistance),
            PhotoBrowseLayout.swipeUpMinScale,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PhotoBrowseLayout.swipeUpScale(forOffset: -800),
            PhotoBrowseLayout.swipeUpMinScale,
            accuracy: 0.001
        )
    }

    /// 更瘦的竖图以高度为限，宽度必须小于可用宽（左右大于最小 inset）
    func testFittedSizePortraitKeepsWidthInsideBounds() {
        let bounds = CGSize(width: 360, height: 500)
        let size = PhotoBrowseLayout.fittedSize(aspect: 9.0 / 16.0, in: bounds)
        XCTAssertEqual(size.height, 500, accuracy: 0.5)
        XCTAssertLessThan(size.width, bounds.width)
        XCTAssertLessThanOrEqual(size.width, bounds.width)
    }

    /// 中卡几何中心打开中卡；侧卡中心压在中卡下面，应交给中卡（和肉眼看到的一致）
    func testFanTapPrefersFrontCardInOverlap() {
        let canvas = CGSize(width: 393, height: 852)
        let cards = (0..<3).map { FanCardLayout.card(position: $0, canvasWidth: canvas.width) }

        let centerPt = FanCardHitTesting.cardCenter(
            canvasSize: canvas,
            offset: cards[1].offset,
            revealed: true
        )
        XCTAssertEqual(
            FanCardHitTesting.hitIndex(at: centerPt, canvasSize: canvas, cards: cards, revealed: true),
            1
        )

        let leftCenter = FanCardHitTesting.cardCenter(
            canvasSize: canvas,
            offset: cards[0].offset,
            revealed: true
        )
        XCTAssertEqual(
            FanCardHitTesting.hitIndex(at: leftCenter, canvasSize: canvas, cards: cards, revealed: true),
            1,
            "左卡中心被中卡盖住时应打开中卡"
        )
    }

    /// 中卡未旋转大框会盖住侧卡露出部分；命中必须按旋转后的真实矩形，侧卡赢自己的露出区
    func testFanTapOnLeftPeekIsNotSwallowedByCenterFrame() {
        let canvas = CGSize(width: 393, height: 852)
        let cards = (0..<3).map { FanCardLayout.card(position: $0, canvasWidth: canvas.width) }
        let left = cards[0]
        let leftCenter = FanCardHitTesting.cardCenter(
            canvasSize: canvas,
            offset: left.offset,
            revealed: true
        )
        // 左卡本地左上附近（可见露出），转到画布坐标
        let theta = left.rotationDegrees * .pi / 180
        let local = CGPoint(x: -left.size.width * 0.38, y: -left.size.height * 0.42)
        let peek = CGPoint(
            x: leftCenter.x + local.x * Foundation.cos(theta) - local.y * Foundation.sin(theta),
            y: leftCenter.y + local.x * Foundation.sin(theta) + local.y * Foundation.cos(theta)
        )

        XCTAssertEqual(
            FanCardHitTesting.hitIndex(at: peek, canvasSize: canvas, cards: cards, revealed: true),
            0,
            "点左卡露出部分应打开左卡"
        )
        XCTAssertFalse(
            FanCardHitTesting.contains(peek, canvasSize: canvas, card: cards[1], revealed: true),
            "该露出点不应落在中卡真实矩形内"
        )
    }

    /// 右卡右上露出部分应打开右卡
    func testFanTapOnRightPeekIsNotSwallowedByCenterFrame() {
        let canvas = CGSize(width: 393, height: 852)
        let cards = (0..<3).map { FanCardLayout.card(position: $0, canvasWidth: canvas.width) }
        let right = cards[2]
        let rightCenter = FanCardHitTesting.cardCenter(
            canvasSize: canvas,
            offset: right.offset,
            revealed: true
        )
        let theta = right.rotationDegrees * .pi / 180
        let local = CGPoint(x: right.size.width * 0.38, y: -right.size.height * 0.42)
        let peek = CGPoint(
            x: rightCenter.x + local.x * Foundation.cos(theta) - local.y * Foundation.sin(theta),
            y: rightCenter.y + local.x * Foundation.sin(theta) + local.y * Foundation.cos(theta)
        )

        XCTAssertEqual(
            FanCardHitTesting.hitIndex(at: peek, canvasSize: canvas, cards: cards, revealed: true),
            2,
            "点右卡露出部分应打开右卡"
        )
        XCTAssertFalse(
            FanCardHitTesting.contains(peek, canvasSize: canvas, card: cards[1], revealed: true)
        )
    }

    /// 首页精选是组内乱序抽的三张，详情按整组顺序排。
    /// 落地页必须是点进来的那张，不能退回组里第一张。
    func testBrowseLandingIDIsTappedPhotoNotDealHead() {
        let dealIDs = (0..<10).map { "p-\($0)" }
        let tapped = "p-7"

        XCTAssertEqual(
            PhotoBrowseLayout.landingID(startID: tapped, visibleIDs: dealIDs),
            "p-7"
        )
        XCTAssertNotEqual(
            PhotoBrowseLayout.landingID(startID: tapped, visibleIDs: dealIDs),
            dealIDs.first
        )
    }

    /// 分页首帧回写组头时，应纠正回点进来的那张；用户已滑走则不拽回
    func testBrowseLandingCorrectsFirstFrameEchoOnly() {
        XCTAssertEqual(
            PhotoBrowseLayout.idAfterFirstFrameEcho(
                currentID: "p-0",
                intended: "p-7",
                visibleHead: "p-0"
            ),
            "p-7"
        )
        XCTAssertEqual(
            PhotoBrowseLayout.idAfterFirstFrameEcho(
                currentID: "p-8",
                intended: "p-7",
                visibleHead: "p-0"
            ),
            "p-8",
            "用户已经滑走时不要拽回起点"
        )
        XCTAssertEqual(
            PhotoBrowseLayout.idAfterFirstFrameEcho(
                currentID: "p-7",
                intended: "p-7",
                visibleHead: "p-0"
            ),
            "p-7"
        )
    }

    /// 点中的照片已不在可浏览列表时，退到当前第一张；空列表则无法落地
    func testBrowseLandingIDFallsBackWhenTappedMissing() {
        XCTAssertEqual(
            PhotoBrowseLayout.landingID(startID: "gone", visibleIDs: ["a", "b"]),
            "a"
        )
        XCTAssertNil(PhotoBrowseLayout.landingID(startID: "x", visibleIDs: []))
    }

    /// 空白处不应命中任何卡
    func testFanTapOnEmptyCanvasHitsNothing() {
        let canvas = CGSize(width: 393, height: 852)
        let cards = (0..<3).map { FanCardLayout.card(position: $0, canvasWidth: canvas.width) }
        let miss = CGPoint(x: 20, y: 40)
        XCTAssertNil(
            FanCardHitTesting.hitIndex(at: miss, canvasSize: canvas, cards: cards, revealed: true)
        )
    }
}
