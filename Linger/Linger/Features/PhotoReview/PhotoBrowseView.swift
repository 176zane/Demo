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
    /// 分页滚动当前居中的照片 id
    @State private var currentID: String?
    /// 上划标记待删的 id（有序，便于撤销最近一次）
    @State private var markedIDs: [String] = []
    /// 当前照片上划位移（仅作用于居中页）
    @State private var dragOffsetY: CGFloat = 0
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
        _currentID = State(initialValue: startItem.id)
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

            VStack(spacing: 0) {
                // 顶底栏进场即在，只让中间照片和背景走 Portal
                topBar
                pager
                    .padding(.top, PhotoBrowseLayout.gapFromBars)
                    .padding(.bottom, PhotoBrowseLayout.gapFromBars)
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

    /// LazyHStack + paging：懒加载相邻页，滚动手感与系统相册一致
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
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
        // 首帧强制滚到被点的那张，避免 LazyHStack 停在组里第一张
        .onAppear {
            currentID = startItem.id
        }
    }

    private func photoPage(_ item: MediaItem) -> some View {
        let isCurrent = item.id == currentID
        // 不用 padding+overlay：overlay 会铺回整页，左右 20 会被吃掉
        return GeometryReader { geo in
            let maxSize = CGSize(
                width: max(0, geo.size.width - PhotoBrowseLayout.horizontalInset * 2),
                height: geo.size.height
            )
            let size = PhotoBrowseLayout.fittedSize(
                aspect: item.displayAspectRatio,
                in: maxSize
            )
            MediaCardView(item: item, showsPlaceholderCanvas: false, contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: PhotoBrowseLayout.photoCornerRadius, style: .continuous))
                .opacity(photoOpacity(for: item, isCurrent: isCurrent))
                // 正向飞行落点：始终接到被点开的那张，避免和首页 source 对不上
                .portal(
                    item: isCurrent ? (portalItem ?? item) : item,
                    as: .destination,
                    in: portalNamespace
                )
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
            .offset(y: isCurrent ? dragOffsetY : 0)
            .zoomTransitionSource(id: item.id, in: zoomNamespace)
            .simultaneousGesture(markGesture(for: item))
            .simultaneousGesture(pinchGesture(for: item))
    }

    /// 上划时渐隐；进场飞行由 Portal 自己藏 destination
    private func photoOpacity(for item: MediaItem, isCurrent: Bool) -> Double {
        isCurrent ? currentCardOpacity : 1
    }

    /// 上划时渐隐，提示将被标记删除
    private var currentCardOpacity: Double {
        guard dragOffsetY < 0 else { return 1 }
        return max(0.35, 1 - Double(-dragOffsetY) / 500)
    }

    // MARK: - 手势

    /// 上划标记：仅竖直方向主导时生效，横向交给分页滚动
    private func markGesture(for item: MediaItem) -> some Gesture {
        DragGesture(minimumDistance: 25)
            .onChanged { value in
                guard item.id == currentID else { return }
                let translation = value.translation
                if translation.height < 0, abs(translation.height) > abs(translation.width) {
                    dragOffsetY = translation.height
                }
            }
            .onEnded { value in
                guard item.id == currentID else { return }
                let translation = value.translation
                if translation.height < -120, abs(translation.height) > abs(translation.width) {
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

    /// 上划：先飞出再从列表移除并翻到下一张；列表清空则直接走返回删除
    private func markCurrentForDeletion() {
        guard let item = currentItem else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            dragOffsetY = -700
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let items = visibleItems
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
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

    /// 翻到新照片：同步收藏态、记录浏览、按当前照片重取背景主色
    private func syncCurrentItem() async {
        guard let item = currentItem else { return }
        isFavorite = item.isFavorite
        viewModel.recordBrowseView(item)

        // 进场那一帧：颜色已随英雄弹簧走到目标，再赋值会硬切
        if skipInitialGradientSync {
            skipInitialGradientSync = false
            return
        }

        guard let colors = await DominantColorExtractor.gradient(forLocalIdentifier: item.id) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.45)) {
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
