import CoreLocation
import ImageIO
import MapKit
import Photos
import SwiftUI
import UIKit

/// 回到那天：当天照片两排横向滚动，顶底栏对齐参考截图
struct DayGridView: View {
    let day: Date
    let focusID: String
    let photoLibrary: PhotoLibraryServing
    let allowedKinds: Set<MediaKind>
    var onDismiss: () -> Void

    init(
        day: Date,
        focusID: String,
        photoLibrary: PhotoLibraryServing,
        allowedKinds: Set<MediaKind>,
        onDismiss: @escaping () -> Void
    ) {
        self.day = day
        self.focusID = focusID
        self.photoLibrary = photoLibrary
        self.allowedKinds = allowedKinds
        self.onDismiss = onDismiss
        _resolvedDay = State(initialValue: day)
    }

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// 页内解析后的日期（验证扫描横竖混合日时会改）
    @State private var resolvedDay: Date
    /// 重置 / 对焦时滚到指定格子
    @State private var scrollTargetID: String?
    /// 横向偏移，给底栏刻度条算进度
    @State private var scrollOffsetX: CGFloat = 0
    @State private var contentWidth: CGFloat = 1
    @State private var viewportWidth: CGFloat = 1
    /// 点格子后打开的当天照片详情
    @State private var selectedItem: MediaItem?

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if isLoading {
                    Spacer()
                    ProgressView("回到那天…")
                        .tint(.white)
                        .foregroundStyle(.white)
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    errorState(errorMessage)
                    Spacer()
                } else if items.isEmpty {
                    Spacer()
                    errorState("这一天没有可展示的照片")
                    Spacer()
                } else {
                    // 两排夹在顶栏和底栏之间垂直居中，不要把剩余高度撑满
                    Spacer(minLength: 12)
                    twoRowStrip
                    Spacer(minLength: 12)
                }

                if !isLoading, errorMessage == nil, !items.isEmpty {
                    bottomBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
        }
        .overlay {
            if let opened = selectedItem {
                DayPhotoDetailView(
                    item: opened,
                    photoLibrary: photoLibrary,
                    onDismiss: {
                        withAnimation(PhotoBrowseLayout.dayGridFadeAnimation) {
                            selectedItem = nil
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(PhotoBrowseLayout.dayGridFadeAnimation, value: selectedItem?.id)
        .task { await load() }
    }

    private var background: some View {
        Color.black
            .ignoresSafeArea()
    }

    /// 顶栏：返回 + 汉堡菜单；中间标题绝对居中；右侧完成
    private var header: some View {
        ZStack {
            HStack(spacing: 10) {
                GlassCircleButton(systemName: "chevron.left") {
                    onDismiss()
                }
                .accessibilityLabel("返回详情")

                GlassCircleButton(systemName: "line.3.horizontal") {
                    // 截图有入口，当前版本只保留外观，避免空菜单误点出系统框
                }
                .accessibilityLabel("当天选项")

                Spacer()

                GlassCircleButton(systemName: "checkmark") {
                    onDismiss()
                }
                .accessibilityLabel("完成")
            }

            VStack(spacing: 2) {
                Text("回到那天")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(PhotoBrowseLayout.dayPageDateText(resolvedDay))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .allowsHitTesting(false)
        }
    }

    /// 底栏：重置到开头 + 中间刻度条 + 暂不可用的撤销
    private var bottomBar: some View {
        HStack(spacing: 12) {
            GlassCircleButton(systemName: "arrow.counterclockwise") {
                resetToLeading()
            }
            .accessibilityLabel("回到当天开头")

            DayGridScrubber(progress: scrubberProgress) { newProgress in
                seek(to: newProgress)
            }

            GlassCircleButton(systemName: "arrow.uturn.backward") {}
                .opacity(0.35)
                .disabled(true)
                .accessibilityLabel("撤销")
                .accessibilityHint("当前没有可撤销的操作")
        }
    }

    /// 两排等高、格子按每张自己的宽高比变宽，整条一起横向滚动
    private var twoRowStrip: some View {
        GeometryReader { geo in
            let rowHeight = DayGridLayout.rowHeight(canvasWidth: geo.size.width)
            let aspects = items.map { item in
                (item.id, item.displayAspectRatio)
            }
            let packed = DayGridLayout.packPhotosAndHints(
                photoAspects: aspects,
                rowHeight: rowHeight
            )
            let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            let stripHeight = rowHeight * 2 + DayGridLayout.spacing

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DayGridLayout.spacing) {
                        ForEach(0..<DayGridLayout.rowCount, id: \.self) { row in
                            HStack(spacing: DayGridLayout.spacing) {
                                ForEach(packed.rows[row]) { cell in
                                    cellView(cell, itemByID: itemByID)
                                        .id(cell.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(
                        GeometryReader { contentGeo in
                            Color.clear.preference(
                                key: DayGridScrollOffsetKey.self,
                                value: DayGridScrollMetrics(
                                    offsetX: -contentGeo.frame(in: .named("dayGridScroll")).minX,
                                    contentWidth: contentGeo.size.width
                                )
                            )
                        }
                    )
                }
                .coordinateSpace(name: "dayGridScroll")
                .onPreferenceChange(DayGridScrollOffsetKey.self) { metrics in
                    scrollOffsetX = metrics.offsetX
                    contentWidth = max(metrics.contentWidth, 1)
                    viewportWidth = max(geo.size.width, 1)
                }
                .onChange(of: scrollTargetID) { _, target in
                    guard let target else { return }
                    withAnimation(.easeOut(duration: 0.28)) {
                        proxy.scrollTo(target, anchor: .leading)
                    }
                    scrollTargetID = nil
                }
                .task {
                    // 等两排落地后再滚到捏合进来的那张
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    proxy.scrollTo(focusID, anchor: .center)
                }
            }
            .frame(height: stripHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func cellView(
        _ cell: DayGridLayout.PlacedCell,
        itemByID: [String: MediaItem]
    ) -> some View {
        if DayGridLayout.isHintID(cell.id) {
            hintCell(cell)
        } else if let item = itemByID[cell.id] {
            dayCell(item, width: cell.width, height: cell.height)
        }
    }

    private func dayCell(_ item: MediaItem, width: CGFloat, height: CGFloat) -> some View {
        let isFocus = item.id == focusID
        return AsyncPhotoView(localIdentifier: item.id, contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: DayGridLayout.cornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if item.mediaKind == .livePhoto {
                    liveBadge
                }
            }
            .overlay {
                if isFocus {
                    RoundedRectangle(cornerRadius: DayGridLayout.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                }
            }
            .onTapGesture {
                withAnimation(PhotoBrowseLayout.dayGridFadeAnimation) {
                    selectedItem = item
                }
            }
            .accessibilityLabel(isFocus ? "打开当天这张照片" : "打开当天其他照片")
    }

    /// 与参考图一致：同心圆 +「实况」
    private var liveBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "livephoto")
                .font(.system(size: 10, weight: .semibold))
            Text("实况")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(8)
    }

    /// 末尾教学格：少图时也撑出两排，外观贴近参考图
    private func hintCell(_ cell: DayGridLayout.PlacedCell) -> some View {
        let isPinch = cell.id == DayGridLayout.hintPinchID
        return RoundedRectangle(cornerRadius: DayGridLayout.cornerRadius, style: .continuous)
            .fill(Color(white: 0.16))
            .overlay {
                VStack(spacing: 10) {
                    if isPinch {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    VStack(spacing: 4) {
                        Text(isPinch ? "双指缩放" : "上滑…")
                            .font(.footnote.weight(.semibold))
                        if isPinch {
                            Text("调整内容大小")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                }
                .padding(12)
            }
            .frame(width: cell.width, height: cell.height)
            .accessibilityLabel(isPinch ? "双指缩放，调整内容大小" : "上滑提示")
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("返回") { onDismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    /// 刻度条进度：已滑过的内容占可滑范围的比例
    private var scrubberProgress: CGFloat {
        let travel = max(contentWidth - viewportWidth, 1)
        return min(max(scrollOffsetX / travel, 0), 1)
    }

    private func resetToLeading() {
        guard let first = items.first?.id else { return }
        scrollTargetID = first
    }

    /// 刻度条拖到某一比例时，滚到对应横向位置附近的格子
    private func seek(to progress: CGFloat) {
        let clamped = min(max(progress, 0), 1)
        let travel = max(contentWidth - viewportWidth, 0)
        scrollOffsetX = travel * clamped
        // 用第一张做锚，后续由用户继续拖格子；进度条先跟手
        if clamped <= 0.02, let first = items.first?.id {
            scrollTargetID = first
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchDay = await resolveFetchDay()
            resolvedDay = fetchDay
            items = try await photoLibrary.fetchItems(on: fetchDay, allowedKinds: allowedKinds)
            #if DEBUG
            logPackedCellsForVerification()
            if ProcessInfo.processInfo.arguments.contains("-uiTestOpenDayPhotoDetail") {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if let first = items.first {
                    selectedItem = first
                }
            }
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 验证时优先打开同时有横图和竖图的那天，避免精选日只有一张横图
    private func resolveFetchDay() async -> Date {
        #if DEBUG
        if let override = PhotoBrowseLayout.debugOverrideDay() {
            NSLog("[DayGrid] override=%@", PhotoBrowseLayout.dayPageDateText(override))
            return override
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTestDayGridMixed") {
            let calendar = Calendar(identifier: .gregorian)
            let candidates = [
                "2012-08-08", "2012-08-09", "2012-08-07", "2012-08-10",
                "2018-03-30", "2018-03-31",
                "2011-05-03", "2011-03-13",
                "2009-10-18", "2009-10-10"
            ]
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd"
            for raw in candidates {
                guard let candidate = formatter.date(from: raw) else { continue }
                let found = (try? await photoLibrary.fetchItems(on: candidate, allowedKinds: allowedKinds)) ?? []
                let hasLandscape = found.contains(where: \.isLandscape)
                let hasPortrait = found.contains(where: { !$0.isLandscape })
                NSLog(
                    "[DayGrid] scan %@ count=%d L=%d P=%d",
                    raw,
                    found.count,
                    hasLandscape ? 1 : 0,
                    hasPortrait ? 1 : 0
                )
                if hasLandscape && hasPortrait {
                    return candidate
                }
            }
        }
        #endif
        return day
    }

    #if DEBUG
    private func logPackedCellsForVerification() {
        let rowHeight = DayGridLayout.rowHeight(canvasWidth: 393)
        let packed = DayGridLayout.packPhotosAndHints(
            photoAspects: items.map { ($0.id, $0.displayAspectRatio) },
            rowHeight: rowHeight
        )
        NSLog("[DayGrid] day=%@ count=%d", PhotoBrowseLayout.dayPageDateText(resolvedDay), items.count)
        for item in items {
            NSLog(
                "[DayGrid] photo %dx%d aspect=%.3f",
                item.pixelWidth,
                item.pixelHeight,
                item.displayAspectRatio
            )
        }
        for (row, cells) in packed.rows.enumerated() {
            for cell in cells {
                NSLog(
                    "[DayGrid] cell row=%d id=%@ %.1fx%.1f aspect=%.3f",
                    row,
                    cell.id,
                    cell.width,
                    cell.height,
                    cell.width / cell.height
                )
            }
        }
    }
    #endif
}

/// ScrollView 内容相对视口的横向度量
private struct DayGridScrollMetrics: Equatable {
    var offsetX: CGFloat
    var contentWidth: CGFloat
}

private struct DayGridScrollOffsetKey: PreferenceKey {
    static var defaultValue = DayGridScrollMetrics(offsetX: 0, contentWidth: 1)
    static func reduce(value: inout DayGridScrollMetrics, nextValue: () -> DayGridScrollMetrics) {
        value = nextValue()
    }
}

/// 底栏中间的刻度条：灰刻度 + 居中白针，拖动能改浏览进度
private struct DayGridScrubber: View {
    var progress: CGFloat
    var onSeek: (CGFloat) -> Void

    private let tickCount = 52

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }

                HStack(spacing: 3) {
                    ForEach(0..<tickCount, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(tickOpacity(index)))
                            .frame(width: 1.6, height: tickHeight(index))
                    }
                }
                .padding(.horizontal, 14)

                // 参考图白针固定在正中，表示当前视口
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.4, height: min(28, geo.size.height - 12))
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, 0), geo.size.width)
                        onSeek(x / max(geo.size.width, 1))
                    }
            )
        }
        .frame(height: 48)
        .accessibilityLabel("当天进度")
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }

    /// 刻度高低错落，看起来像相机对焦环
    private func tickHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [10, 16, 12, 22, 14, 18, 11, 20]
        return pattern[index % pattern.count]
    }

    /// 当前进度附近的刻度稍亮，其余压暗
    private func tickOpacity(_ index: Int) -> Double {
        let position = CGFloat(index) / CGFloat(max(tickCount - 1, 1))
        let distance = abs(position - progress)
        return distance < 0.04 ? 0.85 : 0.28
    }
}

/// 捏合过渡：详情背后露出当天格子，未加载时用占位块
struct DayPinchBackdrop: View {
    let items: [MediaItem]
    let progress: CGFloat
    let focusID: String

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        var cells: [DayPinchCell] = items.prefix(12).map {
            DayPinchCell(id: $0.id, photoID: $0.id)
        }
        var placeholderIndex = 0
        while cells.count < 9 {
            cells.append(DayPinchCell(id: "ph-\(placeholderIndex)", photoID: nil))
            placeholderIndex += 1
        }

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(cells) { cell in
                Group {
                    if let photoID = cell.photoID, photoID != focusID {
                        AsyncPhotoView(localIdentifier: photoID, contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    }
                }
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .opacity(0.45 + 0.5 * progress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 过渡网格的一格：真照片或占位
private struct DayPinchCell: Identifiable {
    let id: String
    let photoID: String?
}

/// 地点文案：省 + 市 + 区，去掉空段和紧挨着的重复（北京/北京市）
enum PhotoPlaceName {
    static func format(
        administrativeArea: String?,
        locality: String?,
        subLocality: String?
    ) -> String? {
        let raw = [administrativeArea, locality, subLocality]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var unique: [String] = []
        for part in raw {
            if unique.last != part {
                unique.append(part)
            }
        }
        let text = unique.joined()
        return text.isEmpty ? nil : text
    }

    /// 从相册坐标反查地名；没有定位或失败时返回 nil，详情页就只显示日期
    static func resolve(localIdentifier: String) async -> String? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let location = assets.firstObject?.location else { return nil }
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let mark = marks.first else { return nil }
            return format(
                administrativeArea: mark.administrativeArea,
                locality: mark.locality,
                subLocality: mark.subLocality
            )
        } catch {
            return nil
        }
    }

    /// 拍摄点：地标名 + 省市区 + 坐标海拔
    static func resolvePlace(localIdentifier: String) async -> PhotoInfoPlace? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject, let location = asset.location else { return nil }
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(location)
            let mark = marks.first
            let area = format(
                administrativeArea: mark?.administrativeArea,
                locality: mark?.locality,
                subLocality: mark?.subLocality
            )
            let rawTitle = mark?.name
            let title: String?
            if let rawTitle, let area, rawTitle.contains(area) || area.contains(rawTitle) {
                title = nil
            } else {
                title = rawTitle
            }
            let altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
            return PhotoInfoPlace(
                title: title,
                area: area,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: altitude
            )
        } catch {
            return PhotoInfoPlace(
                title: nil,
                area: nil,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.verticalAccuracy >= 0 ? location.altitude : nil
            )
        }
    }
}

/// 相片信息页用到的拍摄点
struct PhotoInfoPlace: Equatable {
    var title: String?
    var area: String?
    var latitude: Double
    var longitude: Double
    var altitude: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 相片信息页数字文案，和参考图对齐
enum PhotoInfoFormatting {
    static func apertureText(_ fNumber: Double) -> String {
        String(format: "f%g", fNumber)
    }

    static func shutterText(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 1 {
            let denom = max(Int((1.0 / seconds).rounded()), 1)
            return "1/\(denom) s"
        }
        return String(format: "%.1f s", seconds)
    }

    static func isoText(_ iso: Int) -> String {
        "ISO \(iso)"
    }

    static func focalText(_ millimeters: Double) -> String {
        String(format: "%.0f mm", millimeters)
    }

    static func fileSizeText(bytes: Int64) -> String {
        let value = Double(max(bytes, 0))
        if value >= 1_000_000_000 {
            return String(format: "%.1f GB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1f MB", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1f KB", value / 1_000)
        }
        return "\(bytes) B"
    }

    static func deviceText(make: String?, model: String?) -> String? {
        let trimmedMake = make?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedMake.isEmpty && trimmedModel.isEmpty { return nil }
        if trimmedMake.isEmpty { return trimmedModel }
        if trimmedModel.isEmpty { return trimmedMake }
        if trimmedModel.localizedCaseInsensitiveContains(trimmedMake) { return trimmedModel }
        return "\(trimmedMake) \(trimmedModel)"
    }

    static func fullDateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        return formatter.string(from: date)
    }

    static func resolutionText(width: Int, height: Int) -> String {
        "\(width) × \(height)"
    }
}

/// 详情大图 ↔ 信息页底图：顶对齐、铺满宽、高度封顶
enum DayPhotoDetailLayout {
    static let infoBackdropMaxHeightRatio: CGFloat = 0.40
    /// 时间标题叠在照片下沿的重叠高度
    static let infoTitleOverlap: CGFloat = 92
    /// 下拉超过这个距离就关信息页，回到详情
    static let infoDismissDistance: CGFloat = 96
    /// 甩得够快时，预测落点过这个距离也关
    static let infoDismissPredictDistance: CGFloat = 180
    /// 列表顶部允许的误差，避免小数导致手势判不准
    static let infoScrollTopSlop: CGFloat = 8

    static func infoBackdropHeight(
        aspect: CGFloat,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat
    ) -> CGFloat {
        let safeAspect = aspect > 0 ? aspect : (16.0 / 9.0)
        let fullWidthHeight = canvasWidth / safeAspect
        let cap = max(canvasHeight * infoBackdropMaxHeightRatio, 160)
        return min(max(fullWidthHeight, 160), cap)
    }

    /// 松手时要不要关掉信息页：位移够，或甩得够快
    static func shouldDismissInfo(translationHeight: CGFloat, predictedHeight: CGFloat) -> Bool {
        translationHeight > infoDismissDistance || predictedHeight > infoDismissPredictDistance
    }

    static func isInfoScrollAtTop(_ minY: CGFloat) -> Bool {
        minY >= -infoScrollTopSlop
    }
}

/// 信息页 ScrollView 内容顶边，用来判断是不是还贴在顶部
private struct InfoScrollMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 从 PhotoKit / EXIF 抽出信息页要展示的字段
enum PhotoInfoLoader {
    static func load(for item: MediaItem) async -> PhotoInfoSnapshot {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)
        let asset = assets.firstObject
        let exif = await readExif(for: asset)
        let resources = asset.map { PHAssetResource.assetResources(for: $0) } ?? []
        let filename = resources.first?.originalFilename
        let bytes = await AssetByteEstimator.estimatedBytes(forLocalIdentifier: item.id)
        let place = await PhotoPlaceName.resolvePlace(localIdentifier: item.id)
        return PhotoInfoSnapshot(
            capturedAt: item.creationDate ?? asset?.creationDate,
            device: PhotoInfoFormatting.deviceText(make: exif.make, model: exif.model),
            aperture: exif.fNumber.map(PhotoInfoFormatting.apertureText),
            shutter: exif.exposure.map(PhotoInfoFormatting.shutterText),
            iso: exif.iso.map(PhotoInfoFormatting.isoText),
            focal: exif.focal.map(PhotoInfoFormatting.focalText),
            filename: filename,
            resolution: (item.pixelWidth > 0 && item.pixelHeight > 0)
                ? PhotoInfoFormatting.resolutionText(width: item.pixelWidth, height: item.pixelHeight)
                : nil,
            fileSize: bytes > 0 ? PhotoInfoFormatting.fileSizeText(bytes: bytes) : nil,
            place: place
        )
    }

    private struct RawExif {
        var make: String?
        var model: String?
        var fNumber: Double?
        var exposure: Double?
        var iso: Int?
        var focal: Double?
    }

    private static func readExif(for asset: PHAsset?) async -> RawExif {
        guard let asset else { return RawExif() }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                if info?[PHImageCancelledKey] as? Bool == true {
                    continuation.resume(returning: RawExif())
                    return
                }
                continuation.resume(returning: parseExif(data))
            }
        }
    }

    private static func parseExif(_ data: Data?) -> RawExif {
        var result = RawExif()
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return result
        }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        result.make = tiff?[kCGImagePropertyTIFFMake] as? String
        result.model = tiff?[kCGImagePropertyTIFFModel] as? String

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        result.fNumber = doubleValue(exif?[kCGImagePropertyExifFNumber])
        result.exposure = doubleValue(exif?[kCGImagePropertyExifExposureTime])
        if let isoList = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Any],
           let first = isoList.first {
            result.iso = intValue(first)
        }
        result.focal = doubleValue(exif?[kCGImagePropertyExifFocalLenIn35mmFilm])
            ?? doubleValue(exif?[kCGImagePropertyExifFocalLength])
        return result
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let number = raw as? NSNumber { return number.intValue }
        if let value = raw as? Int { return value }
        return nil
    }
}

/// 信息页一次装完的展示数据
struct PhotoInfoSnapshot: Equatable {
    var capturedAt: Date?
    var device: String?
    var aperture: String?
    var shutter: String?
    var iso: String?
    var focal: String?
    var filename: String?
    var resolution: String?
    var fileSize: String?
    var place: PhotoInfoPlace?

    var cameraValues: [(value: String, label: String)] {
        var rows: [(String, String)] = []
        if let aperture { rows.append((aperture, "光圈")) }
        if let shutter { rows.append((shutter, "快门")) }
        if let iso { rows.append((iso, "感光度")) }
        if let focal { rows.append((focal, "焦距")) }
        return rows
    }
}

/// 「回到那天」点开的照片详情：左上地点/日期/实况，中间大图，底栏收藏、信息、分享
struct DayPhotoDetailView: View {
    let item: MediaItem
    let photoLibrary: PhotoLibraryServing
    var onDismiss: () -> Void

    @State private var placeName: String?
    @State private var isFavorite: Bool
    @State private var showInfo = false
    @State private var infoSnapshot: PhotoInfoSnapshot?
    @State private var isLoadingInfo = false
    @State private var isPreparingShare = false
    @State private var shareImage: UIImage?
    @State private var dragOffsetY: CGFloat = 0
    @State private var infoDragY: CGFloat = 0
    /// 信息页列表内容的 minY，贴顶时才允许下拉关页
    @State private var infoScrollMinY: CGFloat = 0
    /// 这次下拉已经接手后就锁住，避免 scrollDisabled 每帧开关把页面打闪
    @State private var isInfoDismissDragging = false

    init(item: MediaItem, photoLibrary: PhotoLibraryServing, onDismiss: @escaping () -> Void) {
        self.item = item
        self.photoLibrary = photoLibrary
        self.onDismiss = onDismiss
        _isFavorite = State(initialValue: item.isFavorite)
    }

    /// 1 = 照片铺在顶上当信息页底图。下拉只平移整页，不改照片尺寸，避免每帧重排闪烁
    private var infoReveal: CGFloat {
        showInfo ? 1 : 0
    }

    var body: some View {
        GeometryReader { geo in
            let backdropHeight = DayPhotoDetailLayout.infoBackdropHeight(
                aspect: item.displayAspectRatio,
                canvasWidth: geo.size.width,
                canvasHeight: geo.size.height
            )

            ZStack {
                Color.black.ignoresSafeArea()

                // 始终只有一份照片，用 infoReveal 在「居中」和「贴顶放大」之间插值
                photoLayer(in: geo)

                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                    actionBar
                        .padding(.bottom, 28)
                }
                .safeAreaPadding(.top)
                .opacity(showInfo ? 0 : 1)
                .allowsHitTesting(!showInfo)

                if showInfo {
                    photoInfoPanel(backdropHeight: backdropHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .statusBarHidden()
        .contentShape(Rectangle())
        .simultaneousGesture(pageVerticalDrag)
        .task {
            placeName = await PhotoPlaceName.resolve(localIdentifier: item.id)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestOpenDayPhotoInfo") {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await presentInfoPanel()
            }
            #endif
        }
        .sheet(isPresented: Binding(
            get: { shareImage != nil },
            set: { if !$0 { shareImage = nil } }
        )) {
            if let shareImage {
                DayPhotoShareSheet(items: [shareImage])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let placeName {
                Text(placeName)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Text(item.creationDate.map(PhotoBrowseLayout.dayPageDateText) ?? "")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            if item.mediaKind == .livePhoto {
                HStack(spacing: 4) {
                    Image(systemName: "livephoto")
                        .font(.system(size: 11, weight: .semibold))
                    Text("实况")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibility)
    }

    private var headerAccessibility: String {
        var parts: [String] = []
        if let placeName { parts.append(placeName) }
        if let day = item.creationDate {
            parts.append(PhotoBrowseLayout.dayPageDateText(day))
        }
        if item.mediaKind == .livePhoto { parts.append("实况") }
        return parts.joined(separator: "，")
    }

    /// 详情：左右留白居中；信息页：铺满宽、贴物理顶，作为底层
    private func photoLayer(in geo: GeometryProxy) -> some View {
        let aspect = item.displayAspectRatio
        let detailMax = CGSize(
            width: max(geo.size.width - 32, 1),
            height: max(geo.size.height * 0.56, 1)
        )
        let detailSize = PhotoBrowseLayout.fittedSize(aspect: aspect, in: detailMax)
        let infoHeight = DayPhotoDetailLayout.infoBackdropHeight(
            aspect: aspect,
            canvasWidth: geo.size.width,
            canvasHeight: geo.size.height
        )
        let infoSize = CGSize(width: geo.size.width, height: infoHeight)
        let reveal = infoReveal
        let width = detailSize.width + (infoSize.width - detailSize.width) * reveal
        let height = detailSize.height + (infoSize.height - detailSize.height) * reveal
        let detailY = geo.size.height / 2
        let infoY = infoSize.height / 2
        let y = detailY + (infoY - detailY) * reveal

        return MediaCardView(item: item, showsPlaceholderCanvas: false, contentMode: .fill)
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8 * (1 - reveal), style: .continuous))
            .position(
                x: geo.size.width / 2,
                y: y + (showInfo ? max(infoDragY, 0) : dragOffsetY)
            )
            // 跟手位移不要走隐式动画，否则会和手指抢，整页闪
            .animation(nil, value: infoDragY)
    }

    private var actionBar: some View {
        HStack(spacing: 28) {
            detailCircleButton(systemName: isFavorite ? "heart.fill" : "heart", label: isFavorite ? "取消收藏" : "收藏") {
                toggleFavorite()
            }
            detailCircleButton(systemName: "info", label: "照片信息") {
                Task { await presentInfoPanel() }
            }
            detailCircleButton(systemName: "square.and.arrow.up", label: "分享") {
                prepareShare()
            }
            .overlay {
                if isPreparingShare {
                    ProgressView().tint(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func detailCircleButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 竖滑统一入口：信息页下拉关信息，详情页下拉回网格
    private var pageVerticalDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if showInfo {
                    handleInfoDragChanged(value)
                } else if value.translation.height > 0 {
                    dragOffsetY = value.translation.height
                }
            }
            .onEnded { value in
                if showInfo {
                    handleInfoDragEnded(value)
                } else if value.translation.height > 100 {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffsetY = 0
                    }
                }
            }
    }

    /// 信息内容叠在铺顶照片上：顶上透明露出底图，黑底从照片下沿开始
    private func photoInfoPanel(backdropHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // 极淡色才能稳定接到触摸；Color.clear 在部分系统上点不中
            Color.white.opacity(0.001)
                .frame(height: max(backdropHeight - DayPhotoDetailLayout.infoTitleOverlap, 48))
                .contentShape(Rectangle())
                .accessibilityLabel("下拉关闭信息")
                .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 56)
                .overlay(alignment: .bottomLeading) {
                    infoTimeHeader
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }
                .contentShape(Rectangle())

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            infoCameraSection
                            infoFileSection
                            if let place = infoSnapshot?.place {
                                infoLocationSection(place)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: InfoScrollMinYKey.self,
                                    value: proxy.frame(in: .named("infoScroll")).minY
                                )
                            }
                        }
                    }
                    .coordinateSpace(name: "infoScroll")
                    .onPreferenceChange(InfoScrollMinYKey.self) { newValue in
                        // 只有真的离开顶部才写回，避免每帧 setState 打闪
                        if abs(newValue - infoScrollMinY) > 0.5 {
                            infoScrollMinY = newValue
                        }
                    }
                    .scrollDisabled(isInfoDismissDragging)

                    infoBottomBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                }
                .background(Color.black)
            }
        }
        .offset(y: max(infoDragY, 0))
        .animation(nil, value: infoDragY)
        .ignoresSafeArea(edges: .bottom)
        .accessibilityAddTraits(.isModal)
    }

    private var infoTimeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RelativeDateLabel.text(for: infoSnapshot?.capturedAt ?? item.creationDate))
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white)
            if let date = infoSnapshot?.capturedAt ?? item.creationDate {
                Text(PhotoInfoFormatting.fullDateTimeText(date))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoCameraSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("相片信息", systemImage: "camera")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let device = infoSnapshot?.device {
                    HStack(spacing: 4) {
                        Text("设备")
                            .foregroundStyle(.white.opacity(0.45))
                        Text(device)
                            .foregroundStyle(.white)
                    }
                    .font(.footnote)
                }
            }

            if let values = infoSnapshot?.cameraValues, !values.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 4) {
                            Text(item.value)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(item.label)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private var infoFileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoFileRow(title: "文件名", value: infoSnapshot?.filename)
            infoFileRow(title: "分辨率", value: infoSnapshot?.resolution)
            infoFileRow(title: "文件大小", value: infoSnapshot?.fileSize)
        }
    }

    private func infoFileRow(title: String, value: String?) -> some View {
        HStack {
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 4, height: 4)
            Text(title)
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(value ?? "—")
                .foregroundStyle(.white)
        }
        .font(.subheadline)
    }

    private func infoLocationSection(_ place: PhotoInfoPlace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("拍摄位置", systemImage: "location")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            ZStack(alignment: .bottomTrailing) {
                PhotoInfoMapView(coordinate: place.coordinate)
                    .frame(height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)

                if let altitude = place.altitude {
                    Text("海拔 \(Int(altitude.rounded())) m")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white, in: Capsule())
                        .padding(8)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                if let title = place.title {
                    Text(title)
                        .foregroundStyle(.white)
                }
                Spacer()
                if let area = place.area {
                    Text(area)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .font(.subheadline)
        }
    }

    private var infoBottomBar: some View {
        HStack {
            Spacer()
            Button {
                dismissInfoPanel()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 132, height: 48)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭信息")
            Spacer()
            Button {
                dismissInfoPanel()
                onDismiss()
            } label: {
                Image(systemName: "square.stack")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回到当天照片")
        }
    }

    private func handleInfoDragChanged(_ value: DragGesture.Value) {
        let pullingDown = value.translation.height > 0
        guard pullingDown else { return }
        let atTop = DayPhotoDetailLayout.isInfoScrollAtTop(infoScrollMinY)
        guard atTop || isInfoDismissDragging else { return }
        // 手势挂在不跟着 offset 的根上，避免面板移走后手势结束、另一套手势还在写位移
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isInfoDismissDragging = true
            infoDragY = value.translation.height
        }
    }

    private func handleInfoDragEnded(_ value: DragGesture.Value) {
        isInfoDismissDragging = false
        if DayPhotoDetailLayout.shouldDismissInfo(
            translationHeight: value.translation.height,
            predictedHeight: value.predictedEndTranslation.height
        ) {
            dismissInfoPanel()
        } else {
            withAnimation(PhotoBrowseLayout.infoPhotoMoveAnimation) {
                infoDragY = 0
            }
        }
    }

    @MainActor
    private func presentInfoPanel() async {
        if infoSnapshot == nil {
            isLoadingInfo = true
            infoSnapshot = await PhotoInfoLoader.load(for: item)
            isLoadingInfo = false
        }
        withAnimation(PhotoBrowseLayout.infoPhotoMoveAnimation) {
            showInfo = true
            infoDragY = 0
        }
    }

    private func dismissInfoPanel() {
        isInfoDismissDragging = false
        withAnimation(PhotoBrowseLayout.infoPhotoMoveAnimation) {
            showInfo = false
            infoDragY = 0
        }
    }

    private func toggleFavorite() {
        let target = !isFavorite
        isFavorite = target
        Task {
            do {
                try await photoLibrary.setFavorite(target, id: item.id)
            } catch {
                isFavorite = !target
            }
        }
    }

    private func prepareShare() {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            let image = await Self.loadFullImage(localIdentifier: item.id)
            isPreparingShare = false
            if let image {
                shareImage = image
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
            let box = DayPhotoImageResumeBox()
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
}

/// 信息页里的静态地图，只展示拍摄点
private struct PhotoInfoMapView: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            )
        ) {
            Marker("", coordinate: coordinate)
                .tint(.green)
        }
        .mapStyle(.standard)
    }
}

private struct DayPhotoShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 防御 PHImageManager 重复回调导致 continuation 二次 resume
private final class DayPhotoImageResumeBox: @unchecked Sendable {
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
