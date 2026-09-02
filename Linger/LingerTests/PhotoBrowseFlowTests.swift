import ImageIO
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

    /// 上划删除红晕：未上划为 0，到提交距离为 1，再往上不再更亮
    func testSwipeUpDeleteGlowTracksOffsetThenCaps() {
        XCTAssertEqual(PhotoBrowseLayout.swipeUpDeleteGlowIntensity(forOffset: 0), 0, accuracy: 0.001)
        XCTAssertEqual(PhotoBrowseLayout.swipeUpDeleteGlowIntensity(forOffset: 40), 0, accuracy: 0.001)

        let half = PhotoBrowseLayout.swipeUpCommitDistance / 2
        XCTAssertEqual(
            PhotoBrowseLayout.swipeUpDeleteGlowIntensity(forOffset: -half),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PhotoBrowseLayout.swipeUpDeleteGlowIntensity(forOffset: -PhotoBrowseLayout.swipeUpCommitDistance),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PhotoBrowseLayout.swipeUpDeleteGlowIntensity(forOffset: -800),
            1,
            accuracy: 0.001
        )
    }

    /// 顶安全区：≥59 灵动岛，约 44–58 刘海，更小则无切口。岛和刘海都要画红晕。
    func testTopCutoutKindUsesTopSafeInset() {
        XCTAssertEqual(PhotoBrowseLayout.topCutoutKind(topSafeInset: 59), .island)
        XCTAssertEqual(PhotoBrowseLayout.topCutoutKind(topSafeInset: 62), .island)
        XCTAssertEqual(PhotoBrowseLayout.topCutoutKind(topSafeInset: 47), .notch)
        XCTAssertEqual(PhotoBrowseLayout.topCutoutKind(topSafeInset: 44), .notch)
        XCTAssertEqual(PhotoBrowseLayout.topCutoutKind(topSafeInset: 20), .none)
        XCTAssertEqual(PhotoBrowseLayout.topCutoutKind(topSafeInset: 0), .none)
    }

    /// 刘海比岛更宽、更贴顶，红晕框必须跟着切口走
    func testTopCutoutGlowFrameMatchesNotchAndIsland() {
        let notch = PhotoBrowseLayout.topCutoutGlowFrame(kind: .notch)
        let island = PhotoBrowseLayout.topCutoutGlowFrame(kind: .island)
        XCTAssertGreaterThan(notch.size.width, island.size.width)
        XCTAssertLessThan(notch.topInset, island.topInset)
        XCTAssertEqual(PhotoBrowseLayout.topCutoutGlowFrame(kind: .none).size, .zero)
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

    /// 捏合缩放锁在 0.6–1.5，中间值原样跟手
    func testPinchScaleClampsToAllowedRange() {
        XCTAssertEqual(PhotoBrowseLayout.pinchScale(for: 1), 1, accuracy: 0.001)
        XCTAssertEqual(PhotoBrowseLayout.pinchScale(for: 1.2), 1.2, accuracy: 0.001)
        XCTAssertEqual(PhotoBrowseLayout.pinchScale(for: 0.8), 0.8, accuracy: 0.001)
        XCTAssertEqual(PhotoBrowseLayout.pinchScale(for: 0.3), PhotoBrowseLayout.pinchMinScale, accuracy: 0.001)
        XCTAssertEqual(PhotoBrowseLayout.pinchScale(for: 2.4), PhotoBrowseLayout.pinchMaxScale, accuracy: 0.001)
        XCTAssertEqual(PhotoBrowseLayout.pinchMinScale, 0.6, accuracy: 0.001)
        XCTAssertEqual(PhotoBrowseLayout.pinchMaxScale, 1.5, accuracy: 0.001)
    }

    /// 捏合缩小过阈值才进「回到那天」，放大或轻捏松手都该回弹
    func testPinchCommitsOnlyWhenShrunkPastThreshold() {
        XCTAssertTrue(PhotoBrowseLayout.shouldOpenDayGrid(forPinch: 0.7))
        XCTAssertTrue(PhotoBrowseLayout.shouldOpenDayGrid(forPinch: 0.6))
        XCTAssertFalse(PhotoBrowseLayout.shouldOpenDayGrid(forPinch: 0.85))
        XCTAssertFalse(PhotoBrowseLayout.shouldOpenDayGrid(forPinch: 1.0))
        XCTAssertFalse(PhotoBrowseLayout.shouldOpenDayGrid(forPinch: 1.4))
    }

    /// 往里捏时顶底栏跟着淡，放大时栏保持不透明
    func testPinchChromeFadesOnlyWhenPinchingIn() {
        XCTAssertEqual(PhotoBrowseLayout.pinchChromeOpacity(for: 1), 1, accuracy: 0.001)
        XCTAssertEqual(PhotoBrowseLayout.pinchChromeOpacity(for: 1.4), 1, accuracy: 0.001)
        XCTAssertEqual(
            PhotoBrowseLayout.pinchChromeOpacity(for: PhotoBrowseLayout.pinchMinScale),
            0,
            accuracy: 0.001
        )
        let mid = (PhotoBrowseLayout.pinchMinScale + 1) / 2
        let opacity = PhotoBrowseLayout.pinchChromeOpacity(for: mid)
        XCTAssertGreaterThan(opacity, 0.2)
        XCTAssertLessThan(opacity, 0.8)
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

    /// 同一行高下，横格 16:9 必须比竖格 9:16 宽
    func testDayGridLandscapeCellWiderThanPortrait() {
        let rowHeight: CGFloat = 200
        let landscape = DayGridLayout.cellWidth(aspect: DayGridLayout.landscapeAspect, rowHeight: rowHeight)
        let portrait = DayGridLayout.cellWidth(aspect: DayGridLayout.portraitAspect, rowHeight: rowHeight)
        XCTAssertGreaterThan(landscape, portrait)
        XCTAssertEqual(landscape, rowHeight * (16.0 / 9.0), accuracy: 0.5)
        XCTAssertEqual(portrait, rowHeight * (9.0 / 16.0), accuracy: 0.5)
        XCTAssertEqual(landscape / rowHeight, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertEqual(portrait / rowHeight, 9.0 / 16.0, accuracy: 0.01)
    }

    /// 不管原图是 4:3 还是 3:4，格子只收成 16:9 / 9:16
    func testDayGridSnapsPhotoAspectToTwoSpecs() {
        XCTAssertEqual(DayGridLayout.snappedCellAspect(for: 4.0 / 3.0), 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(DayGridLayout.snappedCellAspect(for: 16.0 / 9.0), 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(DayGridLayout.snappedCellAspect(for: 1.0), 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(DayGridLayout.snappedCellAspect(for: 3.0 / 4.0), 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(DayGridLayout.snappedCellAspect(for: 9.0 / 16.0), 9.0 / 16.0, accuracy: 0.001)
    }

    /// 侧向 EXIF 要把像素宽高对调，竖拍才能进 9:16
    func testDayGridOrientsSidewaysPixelsBeforePickingCell() {
        let swapped = DayGridLayout.orientedDimensions(
            pixelWidth: 4032,
            pixelHeight: 3024,
            orientation: .right
        )
        XCTAssertEqual(swapped.width, 3024)
        XCTAssertEqual(swapped.height, 4032)
        XCTAssertEqual(
            DayGridLayout.CellSpec.forPhoto(pixelWidth: swapped.width, pixelHeight: swapped.height),
            .portrait
        )

        let landscape = DayGridLayout.orientedDimensions(
            pixelWidth: 4032,
            pixelHeight: 3024,
            orientation: .up
        )
        XCTAssertEqual(
            DayGridLayout.CellSpec.forPhoto(pixelWidth: landscape.width, pixelHeight: landscape.height),
            .landscape
        )
    }

    /// 资源朝向直接决定格子：横 16:9，竖 9:16
    func testDayGridCellSpecFollowsPhotoOrientation() {
        XCTAssertEqual(DayGridLayout.CellSpec.forPhoto(pixelWidth: 1920, pixelHeight: 1080), .landscape)
        XCTAssertEqual(DayGridLayout.CellSpec.forPhoto(pixelWidth: 1080, pixelHeight: 1920), .portrait)
        let landscapeItem = MediaItem(
            id: "h",
            mediaKind: .photo,
            creationDate: Date(),
            pixelWidth: 4000,
            pixelHeight: 2250
        )
        let portraitItem = MediaItem(
            id: "v",
            mediaKind: .photo,
            creationDate: Date(),
            pixelWidth: 2250,
            pixelHeight: 4000
        )
        XCTAssertTrue(landscapeItem.isLandscape)
        XCTAssertFalse(portraitItem.isLandscape)
        XCTAssertEqual(DayGridLayout.snappedCellAspect(for: landscapeItem.displayAspectRatio), 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(DayGridLayout.snappedCellAspect(for: portraitItem.displayAspectRatio), 9.0 / 16.0, accuracy: 0.001)
    }

    /// 砌砖结果里只许出现这两种宽高比（含提示卡）
    func testDayGridPackedCellsUseOnlySixteenNineAndNineSixteen() {
        let packed = DayGridLayout.packPhotosAndHints(
            photoAspects: [("wide", 4.0 / 3.0), ("tall", 2.0 / 3.0), ("square", 1.0)],
            rowHeight: 160
        )
        let cells = packed.rows.flatMap { $0 }
        XCTAssertFalse(cells.isEmpty)
        for cell in cells {
            let aspect = cell.width / cell.height
            let isLandscape = abs(aspect - 16.0 / 9.0) < 0.02
            let isPortrait = abs(aspect - 9.0 / 16.0) < 0.02
            XCTAssertTrue(isLandscape || isPortrait, "unexpected aspect \(aspect) for \(cell.id)")
        }
    }

    /// 四张及以上应铺满两排，较短的一排接下一张（砌砖）
    func testDayGridPacksIntoTwoRows() {
        let aspects: [(id: String, aspect: CGFloat)] = [
            ("a", 16.0 / 9.0),
            ("b", 3.0 / 4.0),
            ("c", 16.0 / 9.0),
            ("d", 3.0 / 4.0)
        ]
        let packed = DayGridLayout.pack(aspects: aspects, rowHeight: 160)
        XCTAssertEqual(packed.rows.count, 2)
        let total = packed.rows[0].count + packed.rows[1].count
        XCTAssertEqual(total, 4)
        XCTAssertFalse(packed.rows[0].isEmpty)
        XCTAssertFalse(packed.rows[1].isEmpty)
        XCTAssertGreaterThan(packed.contentWidth, 0)
    }

    /// 行高按屏宽收一档，两排加间距不能接近整屏高
    func testDayGridRowHeightStaysCompact() {
        let height = DayGridLayout.rowHeight(canvasWidth: 393)
        XCTAssertLessThan(height, 180)
        XCTAssertGreaterThan(height, 110)
        let twoRows = height * 2 + DayGridLayout.spacing
        XCTAssertLessThan(twoRows, 400)
    }

    /// 提示卡会垫进两排，当天只有一张照片时下排也不该空着
    func testDayGridPacksHintsSoBothRowsFill() {
        let packed = DayGridLayout.packPhotosAndHints(
            photoAspects: [("only", 16.0 / 9.0)],
            rowHeight: 140
        )
        XCTAssertFalse(packed.rows[0].isEmpty)
        XCTAssertFalse(packed.rows[1].isEmpty)
        XCTAssertTrue(packed.rows.joined().contains { DayGridLayout.isHintID($0.id) })
    }

    /// 地点拼成「省市区」，相邻重复去掉
    func testPhotoPlaceNameJoinsProvinceCityDistrict() {
        XCTAssertEqual(
            PhotoPlaceName.format(
                administrativeArea: "广东省",
                locality: "广州市",
                subLocality: "番禺区"
            ),
            "广东省广州市番禺区"
        )
        XCTAssertEqual(
            PhotoPlaceName.format(
                administrativeArea: "北京市",
                locality: "北京市",
                subLocality: "朝阳区"
            ),
            "北京市朝阳区"
        )
        XCTAssertNil(
            PhotoPlaceName.format(administrativeArea: nil, locality: nil, subLocality: nil)
        )
    }

    /// 信息页底图铺满屏宽，竖图高度封顶，避免占满整屏
    func testInfoBackdropHeightUsesFullWidthAndCapsPortrait() {
        let landscape = DayPhotoDetailLayout.infoBackdropHeight(
            aspect: 16.0 / 9.0,
            canvasWidth: 393,
            canvasHeight: 852
        )
        XCTAssertEqual(landscape, 393.0 / (16.0 / 9.0), accuracy: 1)
        let portrait = DayPhotoDetailLayout.infoBackdropHeight(
            aspect: 9.0 / 16.0,
            canvasWidth: 393,
            canvasHeight: 852
        )
        XCTAssertLessThan(portrait, 852 * 0.42)
        XCTAssertGreaterThan(portrait, 160)
    }

    /// 信息页下拉：位移够或甩得够快才回到详情，轻拉要弹回
    func testInfoPageDismissesOnPullDownThreshold() {
        XCTAssertTrue(
            DayPhotoDetailLayout.shouldDismissInfo(translationHeight: 120, predictedHeight: 120)
        )
        XCTAssertTrue(
            DayPhotoDetailLayout.shouldDismissInfo(translationHeight: 40, predictedHeight: 220)
        )
        XCTAssertFalse(
            DayPhotoDetailLayout.shouldDismissInfo(translationHeight: 40, predictedHeight: 50)
        )
        XCTAssertTrue(DayPhotoDetailLayout.isInfoScrollAtTop(0))
        XCTAssertTrue(DayPhotoDetailLayout.isInfoScrollAtTop(-4))
        XCTAssertFalse(DayPhotoDetailLayout.isInfoScrollAtTop(-40))
    }

    /// 相片信息页的参数/体积/设备文案跟截图一致
    func testPhotoInfoFormattingMatchesReference() {
        XCTAssertEqual(PhotoInfoFormatting.apertureText(1.6), "f1.6")
        XCTAssertEqual(PhotoInfoFormatting.shutterText(1.0 / 5814.0), "1/5814 s")
        XCTAssertEqual(PhotoInfoFormatting.isoText(32), "ISO 32")
        XCTAssertEqual(PhotoInfoFormatting.focalText(26), "26 mm")
        XCTAssertEqual(PhotoInfoFormatting.fileSizeText(bytes: 3_900_000), "3.9 MB")
        XCTAssertEqual(
            PhotoInfoFormatting.deviceText(make: "Apple", model: "iPhone 12"),
            "Apple iPhone 12"
        )
        var components = DateComponents()
        components.year = 2022
        components.month = 8
        components.day = 14
        components.hour = 14
        components.minute = 15
        let day = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertEqual(PhotoInfoFormatting.fullDateTimeText(day), "2022年8月14日 星期日 14:15")
    }

    /// 回到那天日期文案与图示一致：2018/5/30
    func testDayPageDateTextUsesSlashFormat() {
        var components = DateComponents()
        components.year = 2018
        components.month = 5
        components.day = 30
        let day = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertEqual(PhotoBrowseLayout.dayPageDateText(day), "2018/5/30")
    }
}
