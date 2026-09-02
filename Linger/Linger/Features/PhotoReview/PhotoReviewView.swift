import PortalTransitions
import SwiftUI
import UIKit

/// 照片 Tab 共用同一个回顾状态机
typealias PhotoReviewViewModel = ReviewViewModel

/// 照片首页：随机抽组后扇形展示三张精选，背景取中间照片主色渐变
struct PhotoReviewView: View {
    @ObservedObject var viewModel: PhotoReviewViewModel
    @EnvironmentObject private var preferencesStore: PreferencesStore

    @Namespace private var portalNamespace
    @Environment(CrossModel.self) private var portalModel
    /// 三张卡依次入场（从底部飞入）
    @State private var revealed = false
    @State private var gradientTop: Color = LingerTheme.canvasTop
    @State private var gradientBottom: Color = LingerTheme.canvasBottom
    /// overlay 详情页（不走 fullScreenCover，避免整页缩小）
    @State private var browseTarget: MediaItem?
    /// 只驱动「点卡 → 详情」正向飞行，返回不走反向
    @State private var portalItem: MediaItem?
    /// 进场时侧卡倾角，展开过程中插到直立
    @State private var heroRotation: Angle = .zero
    /// 详情正在溶解，首页卡先藏在底部等入场
    @State private var isDismissing = false

    /// 首页扇形中间那张（非精选照片回退时的兜底落点）
    private var centerFeaturedItem: MediaItem? {
        let items = viewModel.featuredItems
        guard !items.isEmpty else { return nil }
        return items.count > 1 ? items[1] : items[0]
    }

    /// 与详情页共用，保证进/退弹簧一致
    private var heroAnimation: Animation {
        PhotoBrowseLayout.heroAnimation
    }

    var body: some View {
        ZStack {
            background

            switch viewModel.phase {
            case .loading:
                ProgressView("抽取回忆中…")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .empty:
                emptyState
            case .error(let message):
                errorState(message)
            case .browsing, .confirming:
                fanContent
            }

            VStack {
                topBar
                Spacer()
                bottomToast
            }

            // overlay 而不是 fullScreenCover：背景保持原尺寸
            if let item = browseTarget {
                PhotoBrowseView(
                    viewModel: viewModel,
                    startItem: item,
                    gradientTop: $gradientTop,
                    gradientBottom: $gradientBottom,
                    portalItem: $portalItem,
                    portalNamespace: portalNamespace,
                    onDismiss: dismissBrowse
                )
                .transition(.identity)
                .zIndex(10)
            }
        }
        .portalTransition(
            item: $portalItem,
            in: portalNamespace,
            animation: heroAnimation,
            transition: .none,
            completion: handlePortalCompletion
        ) { item in
            AsyncPhotoView(
                localIdentifier: item.id,
                contentMode: .fill,
                showsPlaceholderCanvas: false
            )
        } configuration: { content, isActive in
            content
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isActive ? PhotoBrowseLayout.photoCornerRadius : 10,
                        style: .continuous
                    )
                )
                // 从首页卡倾角插到详情直立
                .rotationEffect(isActive ? .zero : heroRotation)
        }
        // 溶解一开始就露出首页底栏；三张卡仍等溶解后再从底部飞入
        .preference(key: BrowseFullscreenKey.self, value: browseTarget != nil && !isDismissing)
        .task(id: featuredKey) {
            await refreshAppearance()
        }
    }

    /// 正向飞完拆掉 Portal 登记，避免详情左右滑时 destination 仍按 hideView 藏照片
    private func handlePortalCompletion(_ finished: Bool) {
        guard finished else { return }
        cancelPortalWithoutReverse()
    }

    /// 点卡：从这张照片直接展开到详情对应页
    private func openBrowse(_ item: MediaItem) {
        guard !isDismissing else { return }
        let hadCache = DominantColorExtractor.cachedGradient(forLocalIdentifier: item.id) != nil
        heroRotation = rotation(forFeatured: item)
        browseTarget = item
        portalItem = item
        withAnimation(heroAnimation) {
            applyCachedGradient(for: item.id)
        }
        if !hadCache {
            Task { @MainActor in
                await applyGradient(for: item.id, animation: heroAnimation)
            }
        }
    }

    /// 详情整页溶解，拆掉 Portal 后重播三张卡从底部入场
    private func dismissBrowse(returning current: MediaItem?) {
        guard !isDismissing else { return }
        isDismissing = true
        // 立刻藏到底部，溶解过程中不要露出旧扇形
        revealed = false

        let landing = centerFeaturedItem ?? current
        if let landing {
            let landingCached = DominantColorExtractor.cachedGradient(forLocalIdentifier: landing.id)
            withAnimation(PhotoBrowseLayout.dissolveAnimation) {
                applyCachedGradient(for: landing.id)
            }
            if landingCached == nil {
                Task { @MainActor in
                    await applyGradient(for: landing.id, animation: PhotoBrowseLayout.dissolveAnimation)
                }
            }
        }

        Task { @MainActor in
            let nanos = UInt64(PhotoBrowseLayout.dissolveDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            cancelPortalWithoutReverse()
            browseTarget = nil
            isDismissing = false
            try? await Task.sleep(nanoseconds: 50_000_000)
            revealed = true
        }
    }

    /// 清掉 Portal 状态但不播反向飞行，否则会和溶解抢同一张照片
    private func cancelPortalWithoutReverse() {
        portalModel.info.removeAll { $0.namespace == portalNamespace }
        portalItem = nil
    }

    /// 仅在已缓存时立刻改色（供 withAnimation 块内同步调用）
    private func applyCachedGradient(for id: String) {
        guard let colors = DominantColorExtractor.cachedGradient(forLocalIdentifier: id) else {
            return
        }
        gradientTop = colors.top
        gradientBottom = colors.bottom
    }

    /// 取色后按指定动画写入渐变；已是目标色则不动
    private func applyGradient(for id: String, animation: Animation?) async {
        guard let colors = await DominantColorExtractor.gradient(forLocalIdentifier: id) else {
            return
        }
        if let animation {
            withAnimation(animation) {
                gradientTop = colors.top
                gradientBottom = colors.bottom
            }
        } else {
            gradientTop = colors.top
            gradientBottom = colors.bottom
        }
    }

    /// 精选三张的稳定 key，用于驱动动画重放
    private var featuredKey: String {
        viewModel.featuredItems.map(\.id).joined(separator: "|")
    }

    // MARK: - 背景

    private var background: some View {
        LinearGradient(
            colors: [gradientTop, gradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    /// 中间照片取平均主色 → 上浅下深渐变；失败保持主题默认色
    private func refreshAppearance() async {
        // 详情或溶解中不要重放入场，避免和返回动画打架
        guard browseTarget == nil, !isDismissing else { return }
        revealed = false
        guard !viewModel.featuredItems.isEmpty else { return }

        // 让布局先落位，再触发依次入场
        try? await Task.sleep(nanoseconds: 60_000_000)
        guard browseTarget == nil, !isDismissing else { return }
        revealed = true

        let items = viewModel.featuredItems
        let middle = items.count > 1 ? items[1] : items[0]
        // 预热三张精选主色，点开时转场能立刻跟上展开动画
        for item in items {
            _ = await DominantColorExtractor.dominantColor(forLocalIdentifier: item.id)
        }
        withAnimation(.easeInOut(duration: 0.8)) {
            applyCachedGradient(for: middle.id)
        }

        #if DEBUG
        // UI 验证钩子：启动参数直达浏览页
        if browseTarget == nil {
            if ProcessInfo.processInfo.arguments.contains("-uiTestOpenSideBrowse"),
               let side = items.first {
                openBrowse(side)
            } else if ProcessInfo.processInfo.arguments.contains("-uiTestOpenBrowse") {
                openBrowse(middle)
            }
        }
        #endif
    }

    // MARK: - 扇形三卡

    private var fanContent: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(viewModel.featuredItems.enumerated()), id: \.element.id) { position, item in
                    fanCard(item, position: position, geo: geo)
                        // 视觉层不接收点击，避免中卡未旋转矩形 / 阴影吞掉侧卡
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleFanTap(at: location, in: geo)
            }
        }
    }

    /// 按旋转后的真实卡片几何命中，从高 zIndex 到低，保证点侧卡不会变成中间那张
    private func handleFanTap(at location: CGPoint, in geo: GeometryProxy) {
        guard revealed, !isDismissing else { return }
        let cards = viewModel.featuredItems.indices.map {
            FanCardLayout.card(position: $0, canvasWidth: geo.size.width)
        }
        guard let index = FanCardHitTesting.hitIndex(
            at: location,
            canvasSize: geo.size,
            cards: cards,
            revealed: true
        ), viewModel.featuredItems.indices.contains(index) else {
            return
        }
        openBrowse(viewModel.featuredItems[index])
    }

    /// position: 0 左后 / 1 中前 / 2 右后
    private func fanCard(_ item: MediaItem, position: Int, geo: GeometryProxy) -> some View {
        let layout = cardLayout(position: position, geo: geo)
        // 命中形状必须和裁剪一致，并放在 shadow 之前，否则中间卡的矩形+阴影会吞掉侧卡
        let cardShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return AsyncPhotoView(localIdentifier: item.id, contentMode: .fill)
            .frame(width: layout.size.width, height: layout.size.height)
            .clipShape(cardShape)
            .contentShape(.interaction, cardShape)
            .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
            // 先落到扇形位置再登记 Portal，点卡时从可见框展开
            .offset(
                x: layout.offset.width,
                y: revealed ? layout.offset.height - geo.size.height * 0.05 : geo.size.height * 0.9
            )
            .portal(item: item, as: .source, in: portalNamespace)
            .rotationEffect(revealed ? layout.rotation : .zero)
            .compositingGroup()
            .opacity(cardOpacity(for: item))
            .zIndex(layout.zIndex)
            // 只在入场时弹簧；藏到底部必须瞬间到位，否则会先飞下去
            .animation(
                revealed
                    ? .spring(response: 0.62, dampingFraction: 0.82).delay(layout.delay)
                    : nil,
                value: revealed
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("查看照片")
            .accessibilityAction {
                openBrowse(item)
            }
    }

    private struct FanLayout {
        let size: CGSize
        let offset: CGSize
        let rotation: Angle
        let zIndex: Double
        let delay: Double
    }

    /// 详情盖住首页时压暗未被点中的侧卡
    private var isCoveringHomeCards: Bool {
        browseTarget != nil && !isDismissing
    }

    /// 左 / 中 / 右精选卡的倾角，给飞行层做回退插值
    private func rotation(forFeatured item: MediaItem?) -> Angle {
        guard let item, let index = viewModel.featuredItems.firstIndex(where: { $0.id == item.id }) else {
            return .zero
        }
        switch index {
        case 0: return .degrees(-11)
        case 2: return .degrees(9)
        default: return .zero
        }
    }

    /// 侧卡略压暗；被 Portal 接走的那张由库自己藏照片
    private func cardOpacity(for item: MediaItem) -> Double {
        guard revealed else { return 0 }
        if isCoveringHomeCards, item.id != portalItem?.id {
            return 0.32
        }
        return 1
    }

    private func cardLayout(position: Int, geo: GeometryProxy) -> FanLayout {
        let card = FanCardLayout.card(position: position, canvasWidth: geo.size.width)
        return FanLayout(
            size: card.size,
            offset: card.offset,
            rotation: .degrees(card.rotationDegrees),
            zIndex: card.zIndex,
            delay: FanCardLayout.entranceDelay(position: position)
        )
    }

    // MARK: - 顶栏 / 提示

    private var topBar: some View {
        HStack(spacing: 12) {
            // 左上角筛选胶囊：本组数量 + 类型开关（不含视频）+ 那年今日入口
            Menu {
                Button {
                    viewModel.showOnThisDay = true
                } label: {
                    Label("那年今日", systemImage: "sparkles")
                }
                Button {
                    Task { await viewModel.loadNextDeal() }
                } label: {
                    Label("换一组", systemImage: "arrow.clockwise")
                }
                Divider()
                ForEach(MediaKind.nonVideoKinds.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { kind in
                    Button {
                        preferencesStore.toggleKind(kind)
                    } label: {
                        HStack {
                            Text(kind.displayName)
                            if preferencesStore.allowedKinds.contains(kind) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                    Text("照片")
                        .font(.subheadline.weight(.semibold))
                    Text("\(viewModel.deal.items.count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .background(LingerTheme.glassFill, in: Capsule())
            }
            .accessibilityLabel("照片筛选")

            Spacer()

            GlassCircleButton(systemName: "gearshape") {
                viewModel.showSettings = true
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var bottomToast: some View {
        VStack(spacing: 12) {
            if let toast = viewModel.toastMessage {
                ToastBanner(message: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 96)
        .animation(.easeInOut(duration: 0.2), value: viewModel.toastMessage)
    }

    // MARK: - 空态 / 错误态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
            Text("没有符合筛选条件的内容")
                .foregroundStyle(.white)
            Text("可以在设置里调整类型筛选")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            Button("打开设置") { viewModel.showSettings = true }
                .buttonStyle(.borderedProminent)
            Button("再试一次") {
                Task { await viewModel.loadNextDeal() }
            }
            .foregroundStyle(.white)
        }
        .padding(.bottom, 72)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("出了点问题")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("重试") {
                Task { await viewModel.loadNextDeal() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 72)
    }
}

/// 扇形三卡的尺寸 / 位移 / 倾角，首页绘制和点击命中共用，避免两套数字漂移
enum FanCardLayout {
    /// position: 0 左后 / 1 中前 / 2 右后
    static func card(position: Int, canvasWidth: CGFloat) -> FanCardHitTesting.Card {
        let sideSize = CGSize(width: canvasWidth * 0.46, height: canvasWidth * 0.46 * 1.32)
        let centerSize = CGSize(width: canvasWidth * 0.52, height: canvasWidth * 0.52 * 1.36)
        switch position {
        case 0:
            return FanCardHitTesting.Card(
                index: 0,
                size: sideSize,
                offset: CGSize(width: -canvasWidth * 0.26, height: -36),
                rotationDegrees: -11,
                zIndex: 1
            )
        case 2:
            return FanCardHitTesting.Card(
                index: 2,
                size: sideSize,
                offset: CGSize(width: canvasWidth * 0.26, height: -44),
                rotationDegrees: 9,
                zIndex: 0.5
            )
        default:
            return FanCardHitTesting.Card(
                index: 1,
                size: centerSize,
                offset: CGSize(width: 0, height: 30),
                rotationDegrees: 0,
                zIndex: 2
            )
        }
    }

    /// 入场弹簧错开：左 → 右 → 中
    static func entranceDelay(position: Int) -> Double {
        switch position {
        case 0: return 0
        case 2: return 0.14
        default: return 0.3
        }
    }
}

/// 按旋转后的真实矩形命中扇形卡，从高 zIndex 到低，避免中卡未旋转框吞掉侧卡
enum FanCardHitTesting {
    struct Card: Equatable {
        var index: Int
        var size: CGSize
        var offset: CGSize
        var rotationDegrees: Double
        var zIndex: Double
    }

    /// 卡片中心：ZStack 居中后再叠加 offset；入场后额外上移 5% 屏高
    static func cardCenter(canvasSize: CGSize, offset: CGSize, revealed: Bool) -> CGPoint {
        let extraY: CGFloat = revealed ? -canvasSize.height * 0.05 : canvasSize.height * 0.9
        return CGPoint(
            x: canvasSize.width / 2 + offset.width,
            y: canvasSize.height / 2 + offset.height + extraY
        )
    }

    /// 点是否落在该卡旋转后的矩形内
    static func contains(
        _ point: CGPoint,
        canvasSize: CGSize,
        card: Card,
        revealed: Bool
    ) -> Bool {
        let center = cardCenter(canvasSize: canvasSize, offset: card.offset, revealed: revealed)
        let dx = point.x - center.x
        let dy = point.y - center.y
        // rotationEffect 正角度为顺时针；逆旋转回到卡片本地坐标
        let theta = card.rotationDegrees * .pi / 180
        let localX = dx * Foundation.cos(theta) + dy * Foundation.sin(theta)
        let localY = -dx * Foundation.sin(theta) + dy * Foundation.cos(theta)
        return abs(localX) <= card.size.width / 2 && abs(localY) <= card.size.height / 2
    }

    /// 从高 zIndex 到低，返回点中的卡片 index；空白处为 nil
    static func hitIndex(
        at point: CGPoint,
        canvasSize: CGSize,
        cards: [Card],
        revealed: Bool
    ) -> Int? {
        let ordered = cards.sorted { $0.zIndex > $1.zIndex }
        for card in ordered where contains(point, canvasSize: canvasSize, card: card, revealed: revealed) {
            return card.index
        }
        return nil
    }
}
