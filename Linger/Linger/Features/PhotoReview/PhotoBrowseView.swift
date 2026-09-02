import ImageIO
import Photos
import PortalTransitions
import SwiftUI
import UIKit

/// 详情页照片槽：左右至少 20，上下距顶/底按钮各 30
enum PhotoBrowseLayout {
    static let horizontalInset: CGFloat = 20
    static let gapFromBars: CGFloat = 30
    /// 顶栏：padding.top 8 + 按钮 48
    static let topBarHeight: CGFloat = 56
    /// 底栏：按钮 48 + padding.bottom 16
    static let bottomBarHeight: CGFloat = 64

    /// 详情页照片圆角，进场时从首页卡的 10 插到此值
    static let photoCornerRadius: CGFloat = 18
    /// 首页点卡 → 详情：被点中的那张直接展开
    static let heroAnimation: Animation = .spring(duration: 0.52, bounce: 0.08)
    /// 详情返回：整页溶解后再播首页扇形入场
    static let dissolveDuration: TimeInterval = 0.42
    static let dissolveAnimation: Animation = .easeOut(duration: dissolveDuration)

    /// 上划跟手缩小的下限（相对原尺寸）
    static let swipeUpMinScale: CGFloat = 0.8
    /// 上划这么多 pt 时缩到下限
    static let swipeUpScaleDistance: CGFloat = 160
    /// 松手后判定为「标记删除」的上划距离
    static let swipeUpCommitDistance: CGFloat = 120
    /// 松手后继续飞出顶部的时长
    static let swipeUpFlyDuration: TimeInterval = 0.38

    /// 双指捏合：照片跟手缩放的下限 / 上限
    static let pinchMinScale: CGFloat = 0.6
    static let pinchMaxScale: CGFloat = 1.5
    /// 松手时小于此值才进「回到那天」，否则弹回 1
    static let pinchCommitScale: CGFloat = 0.85
    /// 松手回弹，比系统默认弹簧软，避免「啪」一下回去
    static let pinchBounceBackAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.86)
    /// 「回到那天」叠在详情上淡入淡出，不用系统 cover 从底部滑上来
    static let dayGridFadeDuration: TimeInterval = 0.42
    static let dayGridFadeAnimation: Animation = .easeInOut(duration: dayGridFadeDuration)
    /// 点信息：照片上移放大铺到顶，跟信息页一起走
    static let infoPhotoMoveAnimation: Animation = .spring(response: 0.48, dampingFraction: 0.88)

    /// 上划位移 → 缩放：未上划为 1，最多缩到 80%
    static func swipeUpScale(forOffset offset: CGFloat) -> CGFloat {
        guard offset < 0 else { return 1 }
        let progress = min(1, -offset / swipeUpScaleDistance)
        return 1 - (1 - swipeUpMinScale) * progress
    }

    /// 上划位移 → 灵动岛红晕亮度：未上划为 0，到提交距离为 1，再往上封顶
    static func swipeUpDeleteGlowIntensity(forOffset offset: CGFloat) -> CGFloat {
        guard offset < 0 else { return 0 }
        return min(1, -offset / swipeUpCommitDistance)
    }

    /// 顶部硬件切口：灵动岛 / 刘海 / 无。用来决定上划删除红晕画在哪。
    enum TopCutoutKind: Equatable {
        case none
        case notch
        case island
    }

    /// 顶安全区：≥59 灵动岛（14 Pro 起），约 44–58 刘海（X–14），更小则无切口。
    static func topCutoutKind(topSafeInset: CGFloat) -> TopCutoutKind {
        if topSafeInset >= 59 { return .island }
        if topSafeInset >= 44 { return .notch }
        return .none
    }

    /// 红晕要套住的切口框：岛是居中胶囊，刘海更宽且贴顶。
    static func topCutoutGlowFrame(kind: TopCutoutKind) -> (size: CGSize, topInset: CGFloat) {
        switch kind {
        case .island:
            return (CGSize(width: 126, height: 37), 11.5)
        case .notch:
            return (CGSize(width: 210, height: 32), 0)
        case .none:
            return (.zero, 0)
        }
    }

    /// 在可用框内按宽高比居中缩放，宽度不超过 bounds（从而左右不少于 inset）
    static func fittedSize(aspect: CGFloat, in bounds: CGSize) -> CGSize {
        let widthLimit = max(0, bounds.width)
        let heightLimit = max(0, bounds.height)
        let safeAspect = aspect > 0 ? aspect : (3.0 / 4.0)
        guard widthLimit > 0, heightLimit > 0 else { return .zero }

        var width = widthLimit
        var height = width / safeAspect
        if height > heightLimit {
            height = heightLimit
            width = height * safeAspect
        }
        if width > widthLimit {
            width = widthLimit
            height = width / safeAspect
        }
        return CGSize(width: width, height: height)
    }

    /// 详情打开后应停在哪一张：优先首页点进来的那张，不在本组则退到第一张。
    /// 精选三张是从整组乱序抽的，分页仍按组顺序排；不能默认停在组头。
    static func landingID(startID: String, visibleIDs: [String]) -> String? {
        if visibleIDs.contains(startID) {
            return startID
        }
        return visibleIDs.first
    }

    /// 分页首帧常把 currentID 回写成组头。若用户还没滑走，纠正回点进来的那张。
    static func idAfterFirstFrameEcho(
        currentID: String?,
        intended: String,
        visibleHead: String?
    ) -> String {
        if currentID != intended, currentID == visibleHead, intended != visibleHead {
            return intended
        }
        return currentID ?? intended
    }

    /// 捏合倍率锁在 0.6–1.5，避免缩没或放得撑破屏幕
    static func pinchScale(for magnification: CGFloat) -> CGFloat {
        min(pinchMaxScale, max(pinchMinScale, magnification))
    }

    /// 只有明显捏小才进当天网格；放大或轻捏都当取消
    static func shouldOpenDayGrid(forPinch magnification: CGFloat) -> Bool {
        magnification < pinchCommitScale
    }

    /// 往里捏时顶底栏跟着淡出；放大保持不透明，避免栏跟着照片涨
    static func pinchChromeOpacity(for scale: CGFloat) -> CGFloat {
        guard scale < 1 else { return 1 }
        let span = 1 - pinchMinScale
        guard span > 0 else { return 1 }
        return min(1, max(0, (scale - pinchMinScale) / span))
    }

    /// 「回到那天」顶栏日期，与设计稿一致：2018/5/30
    static func dayPageDateText(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: day)
    }

    #if DEBUG
    /// 验证钩子：`-uiTestDayGridDate=2012-08-08` 强制打开指定自然日
    static func debugOverrideDay() -> Date? {
        guard let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("-uiTestDayGridDate=") })?
            .split(separator: "=").last else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(raw))
    }
    #endif
}

/// 「回到那天」两排横滑：横图宽格、竖图窄格，较短的一排接下一张
enum DayGridLayout {
    static let rowCount = 2
    static let spacing: CGFloat = 10
    static let cornerRadius: CGFloat = 22
    /// 缺尺寸或非法宽高比时的回退，跟 MediaItem.displayAspectRatio 一致
    static let fallbackAspect: CGFloat = 3.0 / 4.0
    /// 末尾提示卡仍用竖格，不跟照片抢比例
    static let hintAspect: CGFloat = 9.0 / 16.0
    static let landscapeAspect: CGFloat = 16.0 / 9.0
    static let portraitAspect: CGFloat = 9.0 / 16.0
    static let hintPinchID = "hint-pinch"
    static let hintSwipeID = "hint-swipe"
    /// 提示卡走竖格 9:16，垫在照片后面
    static let hintAspects: [(id: String, aspect: CGFloat)] = [
        (hintPinchID, hintAspect),
        (hintSwipeID, hintAspect)
    ]

    struct PlacedCell: Equatable, Identifiable {
        var id: String
        var row: Int
        var width: CGFloat
        var height: CGFloat
    }

    /// 行高按屏宽收一档，两排居中，不要把剩余屏幕撑满（否则一张横图会像整页大图）
    static func rowHeight(canvasWidth: CGFloat) -> CGFloat {
        min(168, max(118, canvasWidth * 0.38))
    }

    /// 只表示朝向，不再决定格子宽高比
    enum CellSpec: Equatable {
        case landscape
        case portrait

        var aspect: CGFloat {
            switch self {
            case .landscape: return DayGridLayout.landscapeAspect
            case .portrait: return DayGridLayout.portraitAspect
            }
        }

        static func forPhotoAspect(_ aspect: CGFloat) -> CellSpec {
            aspect > 1 ? .landscape : .portrait
        }

        static func forPhoto(pixelWidth: Int, pixelHeight: Int) -> CellSpec {
            pixelWidth > pixelHeight ? .landscape : .portrait
        }
    }

    /// 侧向拍摄的照片像素是横的，要把宽高对调后再判断朝向
    static func orientedDimensions(
        pixelWidth: Int,
        pixelHeight: Int,
        orientation: CGImagePropertyOrientation
    ) -> (width: Int, height: Int) {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return (pixelHeight, pixelWidth)
        default:
            return (pixelWidth, pixelHeight)
        }
    }

    /// 格子用照片自己的宽高比；非法值回退，不再收成 16:9 / 9:16
    static func cellAspect(for photoAspect: CGFloat) -> CGFloat {
        photoAspect > 0 ? photoAspect : fallbackAspect
    }

    /// 行高固定，宽度 = 行高 × 这张图自己的宽高比
    static func cellWidth(aspect: CGFloat, rowHeight: CGFloat) -> CGFloat {
        max(rowHeight * cellAspect(for: aspect), 1)
    }

    static func cellWidth(for spec: CellSpec, rowHeight: CGFloat) -> CGFloat {
        max(rowHeight * spec.aspect, 1)
    }

    /// 砌砖：下一张放进当前更短的那一排，两排一起横滑
    static func pack(
        aspects: [(id: String, aspect: CGFloat)],
        rowHeight: CGFloat,
        spacing: CGFloat = spacing
    ) -> (rows: [[PlacedCell]], contentWidth: CGFloat) {
        var rows: [[PlacedCell]] = Array(repeating: [], count: rowCount)
        var widths = Array(repeating: CGFloat(0), count: rowCount)
        for item in aspects {
            let width = cellWidth(aspect: item.aspect, rowHeight: rowHeight)
            let row = widths[0] <= widths[1] ? 0 : 1
            if !rows[row].isEmpty {
                widths[row] += spacing
            }
            rows[row].append(
                PlacedCell(id: item.id, row: row, width: width, height: rowHeight)
            )
            widths[row] += width
        }
        return (rows, widths.max() ?? 0)
    }

    /// 照片按原比例入列，后面再接两张操作提示卡
    static func packPhotosAndHints(
        photoAspects: [(id: String, aspect: CGFloat)],
        rowHeight: CGFloat
    ) -> (rows: [[PlacedCell]], contentWidth: CGFloat) {
        pack(aspects: photoAspects + hintAspects, rowHeight: rowHeight)
    }

    static func isHintID(_ id: String) -> Bool {
        id == hintPinchID || id == hintSwipeID
    }
}

/// 全屏浏览页：横向分页滚动、上划标记删除（返回时统一删除）、捏合居中照片回到那天
struct PhotoBrowseView: View {
    @ObservedObject var viewModel: PhotoReviewViewModel
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferencesStore: PreferencesStore

    let startItem: MediaItem
    /// 与首页共用渐变，避免详情盖上时颜色再跳一次
    @Binding var gradientTop: Color
    @Binding var gradientBottom: Color
    /// 与首页共用的 Portal 项：只负责点卡进详情的正向飞行
    @Binding var portalItem: MediaItem?
    let portalNamespace: Namespace.ID
    /// 返回：详情溶解，首页再播三卡入场
    var onDismiss: (MediaItem?) -> Void
    /// 分页滚动当前居中的照片 id；进场后由 landOnStartItem 写入，避免首帧停在组头
    @State private var currentID: String?
    /// 只落地一次，避免分页重建时把用户已经滑到的页拽回去
    @State private var didLandOnStartItem = false
    /// 上划标记待删的 id（有序，便于撤销最近一次）
    @State private var markedIDs: [String] = []
    /// 当前照片上划位移（只作用在照片本身，不推整页）
    @State private var dragOffsetY: CGFloat = 0
    /// 松手后正在飞出顶部，忽略新的上划
    @State private var isFlyingOff = false
    /// 首次进入已由首页同步过渐变，跳过一次取色，防止硬切
    @State private var skipInitialGradientSync = true
    @State private var isFavorite = false
    @State private var showDayGrid = false
    /// 当前照片的捏合缩放，跟手写，松手再决定进网格或弹回
    @State private var pinchScale: CGFloat = 1
    /// 双指还在屏幕上，用来挡住上划和分页抢手势
    @State private var isPinching = false
    @State private var shareItem: ShareItem?
    @State private var isPreparingShare = false
    /// 返回流程是否已处理删除（防 onDisappear 兜底重复删）
    @State private var didFinish = false

    init(
        viewModel: PhotoReviewViewModel,
        startItem: MediaItem,
        gradientTop: Binding<Color>,
        gradientBottom: Binding<Color>,
        portalItem: Binding<MediaItem?>,
        portalNamespace: Namespace.ID,
        onDismiss: @escaping (MediaItem?) -> Void
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.startItem = startItem
        _gradientTop = gradientTop
        _gradientBottom = gradientBottom
        _portalItem = portalItem
        self.portalNamespace = portalNamespace
        self.onDismiss = onDismiss
        // 先空着，等分页挂载后再写入。若这里就赋 startItem.id，
        // ScrollView 收不到「变化」，会停在组里第一张，再把 currentID 回写成那张。
        _currentID = State(initialValue: nil)
    }

    /// 去掉已标记删除后的可浏览列表
    private var visibleItems: [MediaItem] {
        viewModel.deal.items.filter { item in !markedIDs.contains(item.id) }
    }

    private var currentItem: MediaItem? {
        visibleItems.first { $0.id == currentID }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [gradientTop, gradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // 分页从一开始就铺满全屏，上划只是在这层里移动，不必再临时提到另一层
            pager
                .ignoresSafeArea()
                // 捏合时锁分页，避免双指被当成左右滑
                .scrollDisabled(isPinching)

            VStack(spacing: 0) {
                topBar
                // 中间必须穿透，否则会挡住全屏分页的左右滑和上划
                Spacer()
                    .allowsHitTesting(false)
                bottomBar
            }
            .opacity(PhotoBrowseLayout.pinchChromeOpacity(for: pinchScale))
            .allowsHitTesting(pinchScale >= 0.98)

            // 上划时在灵动岛 / 刘海周围铺红晕，跟手变亮，表达「要删」
            DynamicIslandDeleteGlow(
                intensity: PhotoBrowseLayout.swipeUpDeleteGlowIntensity(forOffset: dragOffsetY)
            )

            if viewModel.isDeleting {
                deletingOverlay
            }

            // 叠在详情上淡入，避免 fullScreenCover 从底部推上来
            if showDayGrid, let item = currentItem {
                #if DEBUG
                let day = PhotoBrowseLayout.debugOverrideDay() ?? item.creationDate
                #else
                let day = item.creationDate
                #endif
                if let day {
                    DayGridView(
                        day: day,
                        focusID: item.id,
                        photoLibrary: appState.photoLibrary,
                        allowedKinds: preferencesStore.allowedKinds.intersection(MediaKind.nonVideoKinds),
                        onDismiss: dismissDayGrid
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
        }
        .animation(PhotoBrowseLayout.dayGridFadeAnimation, value: showDayGrid)
        .statusBarHidden()
        // 返回：整页溶解，不把照片缩回首页卡
        .opacity(didFinish ? 0 : 1)
        .allowsHitTesting(!didFinish)
        .animation(PhotoBrowseLayout.dissolveAnimation, value: didFinish)
        // overlay 呈现，无系统交互式下滑；捏合只用于「回到那天」
        .interactiveDismissDisabled()
        // 兜底：任何路径下视图消失时，若还有未处理的删除标记则统一删除
        .onDisappear {
            if !didFinish, !markedIDs.isEmpty {
                let ids = Set(markedIDs)
                markedIDs = []
                Task { await viewModel.deleteMarkedFromBrowse(ids: ids) }
            }
        }
        // 翻页 / 标记后同步收藏态、背景色与浏览统计
        .task(id: currentID) {
            await syncCurrentItem()
        }
        .task {
            #if DEBUG
            // UI 验证钩子：等分页落地后再淡入「回到那天」
            if ProcessInfo.processInfo.arguments.contains("-uiTestOpenDayGrid") {
                var waited: UInt64 = 0
                while currentItem?.creationDate == nil, waited < 2_000_000_000 {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    waited += 50_000_000
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
                if currentItem?.creationDate != nil {
                    presentDayGrid()
                }
            }
            // 进详情后自动返回，便于录制溶解 + 扇形入场
            if ProcessInfo.processInfo.arguments.contains("-uiTestDismissBrowse") {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                finishAndDismiss()
            }
            // 进详情后停在上划中途，核对缩小且不被顶栏裁断
            if ProcessInfo.processInfo.arguments.contains("-uiTestSwipeUpHold") {
                try? await Task.sleep(nanoseconds: 900_000_000)
                dragOffsetY = -200
            }
            // 进详情后走完整上划飞出
            if ProcessInfo.processInfo.arguments.contains("-uiTestSwipeUpFly") {
                try? await Task.sleep(nanoseconds: 900_000_000)
                markCurrentForDeletion()
            }
            // 停在指定捏合倍率，核对照片跟手缩放区间 0.6–1.5
            if let raw = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("-uiTestPinchScale=") })?
                .split(separator: "=").last,
               let value = Double(raw) {
                try? await Task.sleep(nanoseconds: 800_000_000)
                pinchScale = PhotoBrowseLayout.pinchScale(for: CGFloat(value))
            }
            #endif
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
    }

    // MARK: - 横向分页

    /// 横向分页：组最多 30 张，用 HStack 预挂载，避免 Lazy 回收后重新出图闪白
    private var pager: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(visibleItems) { item in
                        photoPage(item)
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .task {
                await landOnStartItem(using: proxy)
            }
            .onChange(of: currentID) { _, _ in
                prefetchNeighbors()
            }
        }
    }

    /// 分页挂载后再滚到点进来的那张。
    /// 首帧 ScrollView 会按 offset 0 回写组头，所以落地后再纠正一次。
    private func landOnStartItem(using proxy: ScrollViewProxy) async {
        guard !didLandOnStartItem else { return }
        let visibleIDs = visibleItems.map(\.id)
        guard let target = PhotoBrowseLayout.landingID(
            startID: startItem.id,
            visibleIDs: visibleIDs
        ) else {
            return
        }

        didLandOnStartItem = true
        currentID = target
        proxy.scrollTo(target, anchor: .center)
        prefetchNeighbors()

        try? await Task.sleep(nanoseconds: 30_000_000)
        guard !Task.isCancelled else { return }
        let corrected = PhotoBrowseLayout.idAfterFirstFrameEcho(
            currentID: currentID,
            intended: target,
            visibleHead: visibleIDs.first
        )
        if corrected != currentID {
            currentID = corrected
            proxy.scrollTo(corrected, anchor: .center)
        }
    }

    private func photoPage(_ item: MediaItem) -> some View {
        let isCurrent = item.id == currentID
        return GeometryReader { geo in
            let chrome = PhotoBrowseLayout.topBarHeight
                + PhotoBrowseLayout.bottomBarHeight
                + PhotoBrowseLayout.gapFromBars * 2
            let maxSize = CGSize(
                width: max(0, geo.size.width - PhotoBrowseLayout.horizontalInset * 2),
                height: max(0, geo.size.height - chrome)
            )
            let size = PhotoBrowseLayout.fittedSize(
                aspect: item.displayAspectRatio,
                in: maxSize
            )
            MediaCardView(item: item, showsPlaceholderCanvas: false, contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: PhotoBrowseLayout.photoCornerRadius, style: .continuous))
                // 上划缩小和捏合缩放叠乘：同一时刻通常只有一种手势在动
                .scaleEffect(isCurrent ? currentPhotoScale : 1, anchor: .center)
                .offset(y: isCurrent ? dragOffsetY : 0)
                // 每张只用自己的 id 登记 destination。
                // 若把邻页绑到进场那张 portalItem 上，Portal 会按 hideView 把邻页藏成透明，左右滑就会闪。
                .portal(item: item, as: .destination, in: portalNamespace)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
            .simultaneousGesture(markGesture(for: item))
            .simultaneousGesture(pinchGesture(for: item))
    }

    // MARK: - 手势

    /// 当前页展示缩放：上划跟手 × 捏合跟手
    private var currentPhotoScale: CGFloat {
        PhotoBrowseLayout.swipeUpScale(forOffset: dragOffsetY) * pinchScale
    }

    /// 上划标记：仅竖直方向主导时生效，横向交给分页滚动
    private func markGesture(for item: MediaItem) -> some Gesture {
        DragGesture(minimumDistance: 25)
            .onChanged { value in
                guard !isFlyingOff, !isPinching, item.id == currentID else { return }
                let translation = value.translation
                if translation.height < 0, abs(translation.height) > abs(translation.width) {
                    dragOffsetY = translation.height
                }
            }
            .onEnded { value in
                guard !isFlyingOff, !isPinching, item.id == currentID else { return }
                let translation = value.translation
                if translation.height < -PhotoBrowseLayout.swipeUpCommitDistance,
                   abs(translation.height) > abs(translation.width) {
                    markCurrentForDeletion()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffsetY = 0
                    }
                }
            }
    }

    /// 双指捏合：过程中照片跟手缩放（0.6–1.5）；松手捏小则进当天，否则弹回
    private func pinchGesture(for item: MediaItem) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard item.id == currentID, !isFlyingOff else { return }
                // 跟手时关掉隐式动画，否则会拖一拍，看起来生硬
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isPinching = true
                    pinchScale = PhotoBrowseLayout.pinchScale(for: value)
                }
            }
            .onEnded { value in
                guard item.id == currentID, !isFlyingOff else {
                    resetPinchScale()
                    return
                }
                isPinching = false
                let clamped = PhotoBrowseLayout.pinchScale(for: value)
                pinchScale = clamped
                if PhotoBrowseLayout.shouldOpenDayGrid(forPinch: value),
                   item.creationDate != nil {
                    // 保持当前缩小尺寸，网格淡入盖上，背景不跟着动
                    presentDayGrid()
                } else {
                    withAnimation(PhotoBrowseLayout.pinchBounceBackAnimation) {
                        pinchScale = 1
                    }
                }
            }
    }

    /// 手势中断或从网格返回时，把捏合状态清干净
    private func resetPinchScale() {
        isPinching = false
        pinchScale = 1
    }

    /// 当天页淡入盖住详情，不走系统从底部上来的 cover
    private func presentDayGrid() {
        withAnimation(PhotoBrowseLayout.dayGridFadeAnimation) {
            showDayGrid = true
        }
    }

    /// 当天页淡出后，照片回到原尺寸
    private func dismissDayGrid() {
        withAnimation(PhotoBrowseLayout.dayGridFadeAnimation) {
            showDayGrid = false
        }
        pinchScale = 1
        isPinching = false
    }

    /// 上划：松手后按当前 80% 尺寸继续向上飞出顶部，再从列表移除
    private func markCurrentForDeletion() {
        guard let item = currentItem, !isFlyingOff else { return }
        isFlyingOff = true
        // 飞过整屏高度，保证缩小后的照片从顶部完全离开
        let flyOffset = -(UIScreen.main.bounds.height + 160)
        withAnimation(.easeIn(duration: PhotoBrowseLayout.swipeUpFlyDuration)) {
            dragOffsetY = flyOffset
        }
        Task { @MainActor in
            let nanos = UInt64(PhotoBrowseLayout.swipeUpFlyDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            let items = visibleItems
            guard let index = items.firstIndex(where: { $0.id == item.id }) else {
                isFlyingOff = false
                dragOffsetY = 0
                return
            }
            let nextID: String?
            if index + 1 < items.count {
                nextID = items[index + 1].id
            } else if index > 0 {
                nextID = items[index - 1].id
            } else {
                nextID = nil
            }

            markedIDs.append(item.id)
            dragOffsetY = 0
            isFlyingOff = false
            if let nextID {
                currentID = nextID
            } else {
                finishAndDismiss()
            }
        }
    }

    /// 撤销最近一次标记，并跳回那张照片
    private func undoLastMark() {
        guard let lastID = markedIDs.popLast() else { return }
        currentID = lastID
    }

    /// 返回：立刻开始溶解，删除在后台处理，不打断回首页动画
    private func finishAndDismiss() {
        guard !didFinish else { return }
        didFinish = true
        let returning = currentItem
        let ids = Set(markedIDs)
        onDismiss(returning)
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            await viewModel.deleteMarkedFromBrowse(ids: ids)
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 14) {
            GlassCircleButton(systemName: "chevron.left") {
                finishAndDismiss()
            }
            .accessibilityLabel(markedIDs.isEmpty ? "返回" : "返回并删除标记的照片")

            progressLine

            GlassCircleButton(systemName: "square.and.arrow.up") {
                prepareShare()
            }
            .accessibilityLabel("分享")
            .overlay {
                if isPreparingShare {
                    ProgressView().tint(.white)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// 顶部细线进度：当前位置 / 可浏览总数
    private var progressLine: some View {
        let total = max(visibleItems.count, 1)
        let position = (visibleItems.firstIndex { $0.id == currentID } ?? 0) + 1
        return GeometryReader { geo in
            let fraction = CGFloat(position) / CGFloat(total)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(8, geo.size.width * fraction), height: 3)
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.2), value: position)
        }
        .frame(height: 48)
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        HStack(spacing: 14) {
            GlassCircleButton(systemName: isFavorite ? "heart.fill" : "heart") {
                toggleFavorite()
            }
            .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")

            Spacer()

            // 拍摄时间胶囊
            HStack(spacing: 8) {
                Text(RelativeDateLabel.text(for: currentItem?.creationDate))
                    .font(.subheadline.weight(.semibold))
                if !markedIDs.isEmpty {
                    Text("待删 \(markedIDs.count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.7), in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            GlassCircleButton(systemName: "arrow.uturn.backward") {
                undoLastMark()
            }
            .opacity(markedIDs.isEmpty ? 0.35 : 1)
            .disabled(markedIDs.isEmpty)
            .accessibilityLabel("撤销删除标记")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var deletingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            ProgressView("正在删除…")
                .tint(.white)
                .foregroundStyle(.white)
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 状态同步

    /// 预缓存当前页左右各两张，减少滑到邻页时的解码空白
    private func prefetchNeighbors() {
        let items = visibleItems
        guard let index = items.firstIndex(where: { $0.id == currentID }) ?? items.firstIndex(where: { $0.id == startItem.id }) else {
            return
        }
        let neighborIDs = items.indices
            .filter { abs($0 - index) <= 2 }
            .map { items[$0].id }
        let scale = UIScreen.main.scale
        let target = CGSize(
            width: max(UIScreen.main.bounds.width, 1) * scale,
            height: max(UIScreen.main.bounds.height, 1) * scale
        )
        ImageLoader.shared.startCaching(identifiers: neighborIDs, targetSize: target)
    }

    /// 翻到新照片：同步收藏态、记录浏览、按当前照片重取背景主色
    private func syncCurrentItem() async {
        guard let item = currentItem else { return }
        isFavorite = item.isFavorite
        viewModel.recordBrowseView(item)
        prefetchNeighbors()

        // 进场那一帧：颜色已随英雄弹簧走到目标，再赋值会硬切
        if skipInitialGradientSync {
            skipInitialGradientSync = false
            return
        }

        // 等翻页停稳再换色；中途又滑走则取消，避免背景跟着连闪
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled, currentID == item.id else { return }

        guard let colors = await DominantColorExtractor.gradient(forLocalIdentifier: item.id) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            gradientTop = colors.top
            gradientBottom = colors.bottom
        }
    }

    private func toggleFavorite() {
        guard let item = currentItem else { return }
        let target = !isFavorite
        isFavorite = target
        Task {
            let ok = await viewModel.setFavorite(target, itemID: item.id)
            if !ok {
                isFavorite = !target
            }
        }
    }

    /// 加载原图后弹分享面板
    private func prepareShare() {
        guard let item = currentItem, !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            let image = await Self.loadFullImage(localIdentifier: item.id)
            isPreparingShare = false
            if let image {
                shareItem = ShareItem(image: image)
            }
        }
    }

    private static func loadFullImage(localIdentifier: String) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            let box = ImageResumeOnceBox()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                box.resume(continuation, with: image)
            }
        }
    }

    /// 防御 PHImageManager 重复回调导致 continuation 二次 resume
    private final class ImageResumeOnceBox: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func resume(_ continuation: CheckedContinuation<UIImage?, Never>, with image: UIImage?) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: image)
        }
    }
}

/// 分享内容包装（供 sheet(item:) 使用）
private struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 系统分享面板包装
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 顶部切口周围的上划删除红晕：灵动岛或刘海都画，无切口不画，不拦截手势
private struct DynamicIslandDeleteGlow: View {
    /// 0…1，越大越亮
    let intensity: CGFloat

    var body: some View {
        GeometryReader { geo in
            let topInset = max(geo.safeAreaInsets.top, Self.windowTopSafeInset())
            let kind = PhotoBrowseLayout.topCutoutKind(topSafeInset: topInset)
            if kind != .none, intensity > 0.001 {
                cutoutHalo(kind: kind)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 两层模糊胶囊：内圈贴切口，外圈散开，亮度随 intensity 抬高
    private func cutoutHalo(kind: PhotoBrowseLayout.TopCutoutKind) -> some View {
        let frame = PhotoBrowseLayout.topCutoutGlowFrame(kind: kind)
        let innerGrow = 10 * intensity
        let outerGrow = 22 * intensity
        // 暗红 → 亮警示红，跟手上划
        let red = Color(
            red: 0.42 + 0.58 * intensity,
            green: 0.04,
            blue: 0.08
        )
        return ZStack {
            Capsule(style: .continuous)
                .fill(red.opacity(0.22 + 0.38 * intensity))
                .frame(
                    width: frame.size.width + 36 + outerGrow,
                    height: frame.size.height + 22 + outerGrow
                )
                .blur(radius: 18 + 14 * intensity)
            Capsule(style: .continuous)
                .fill(red.opacity(0.28 + 0.42 * intensity))
                .frame(
                    width: frame.size.width + 14 + innerGrow,
                    height: frame.size.height + 8 + innerGrow
                )
                .blur(radius: 8 + 6 * intensity)
        }
        .padding(.top, frame.topInset)
    }

    /// GeometryReader 在 ignoresSafeArea 下偶发读到 0，回退到前台窗口
    private static func windowTopSafeInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = active?.windows.first(where: \.isKeyWindow) ?? active?.windows.first
        return window?.safeAreaInsets.top ?? 0
    }
}
