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

    /// 上划位移 → 缩放：未上划为 1，最多缩到 80%
    static func swipeUpScale(forOffset offset: CGFloat) -> CGFloat {
        guard offset < 0 else { return 1 }
        let progress = min(1, -offset / swipeUpScaleDistance)
        return 1 - (1 - swipeUpMinScale) * progress
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
    @Namespace private var zoomNamespace
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

            VStack(spacing: 0) {
                topBar
                // 中间必须穿透，否则会挡住全屏分页的左右滑和上划
                Spacer()
                    .allowsHitTesting(false)
                bottomBar
            }

            if viewModel.isDeleting {
                deletingOverlay
            }
        }
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
            // UI 验证钩子：启动参数直达「回到那天」网格
            if ProcessInfo.processInfo.arguments.contains("-uiTestOpenDayGrid"),
               currentItem?.creationDate != nil {
                try? await Task.sleep(nanoseconds: 800_000_000)
                showDayGrid = true
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
            #endif
        }
        .fullScreenCover(isPresented: $showDayGrid) {
            if let item = currentItem, let day = item.creationDate {
                DayGridView(
                    day: day,
                    focusID: item.id,
                    photoLibrary: appState.photoLibrary,
                    allowedKinds: preferencesStore.allowedKinds.intersection(MediaKind.nonVideoKinds),
                    onDismiss: { showDayGrid = false }
                )
                .zoomTransition(sourceID: item.id, in: zoomNamespace)
            }
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
                .scaleEffect(isCurrent ? PhotoBrowseLayout.swipeUpScale(forOffset: dragOffsetY) : 1, anchor: .center)
                .offset(y: isCurrent ? dragOffsetY : 0)
                // 每张只用自己的 id 登记 destination。
                // 若把邻页绑到进场那张 portalItem 上，Portal 会按 hideView 把邻页藏成透明，左右滑就会闪。
                .portal(item: item, as: .destination, in: portalNamespace)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
            .zoomTransitionSource(id: item.id, in: zoomNamespace)
            .simultaneousGesture(markGesture(for: item))
            .simultaneousGesture(pinchGesture(for: item))
    }

    // MARK: - 手势

    /// 上划标记：仅竖直方向主导时生效，横向交给分页滚动
    private func markGesture(for item: MediaItem) -> some Gesture {
        DragGesture(minimumDistance: 25)
            .onChanged { value in
                guard !isFlyingOff, item.id == currentID else { return }
                let translation = value.translation
                if translation.height < 0, abs(translation.height) > abs(translation.width) {
                    dragOffsetY = translation.height
                }
            }
            .onEnded { value in
                guard !isFlyingOff, item.id == currentID else { return }
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

    /// 双指捏合居中照片 → 缩放进「回到那天」
    private func pinchGesture(for item: MediaItem) -> some Gesture {
        MagnificationGesture()
            .onEnded { value in
                guard item.id == currentID, value < 0.85 else { return }
                if item.creationDate != nil {
                    showDayGrid = true
                }
            }
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
