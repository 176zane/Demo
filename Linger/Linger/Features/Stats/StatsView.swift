import SwiftUI

/// 统计 Tab：分桶查看/删除/腾出空间（无 Pro）
struct StatsView: View {
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @EnvironmentObject private var appState: AppState

    @State private var showResetConfirm = false
    @State private var showSettings = false

    private let recentStore = RecentViewedStore.shared

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("使用统计")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 8)

                    bucketCard(title: "照片", bucket: .photo)
                    bucketCard(title: "截屏", bucket: .screenshot)
                    bucketCard(title: "视频", bucket: .video)

                    freedSpaceCard

                    resetRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }

            // 不用 NavigationStack 顶栏：系统浅色毛玻璃上滑时会露白条
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        LingerTheme.canvasTop,
                        LingerTheme.canvasTop.opacity(0.92),
                        LingerTheme.canvasTop.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
                .allowsHitTesting(false)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)

            HStack {
                Spacer()
                GlassCircleButton(systemName: "gearshape") {
                    showSettings = true
                }
                .accessibilityLabel("设置")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(
            LinearGradient(
                colors: [LingerTheme.canvasTop, LingerTheme.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(statsStore)
                .environmentObject(preferencesStore)
                .environmentObject(appState)
        }
        .alert("重置浏览记录？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                statsStore.resetAll()
                recentStore.clear()
                // 去重记录清空后，预取队列里的旧组也一并作废
                DealPrefetcher.shared.invalidate()
            }
        } message: {
            Text("将清空已浏览/已删除统计与近期去重记录。此操作不可撤销。")
        }
    }

    private func bucketCard(title: String, bucket: StatsBucket) -> some View {
        let viewed = statsStore.stats.viewedByBucket[bucket] ?? 0
        let deleted = statsStore.stats.deletedByBucket[bucket] ?? 0
        let bytes = statsStore.stats.freedBytesByBucket[bucket] ?? 0

        return VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            HStack {
                metric(icon: "eye.fill", tint: LingerTheme.accentBlue, label: "查看", value: "\(viewed)")
                Spacer()
                metric(icon: "trash.fill", tint: LingerTheme.accentRed, label: "删除", value: "\(deleted)")
                Spacer()
                metric(icon: "internaldrive.fill", tint: LingerTheme.accentGreen, label: "清理", value: byteString(bytes))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var freedSpaceCard: some View {
        let total = statsStore.stats.totalFreedBytes
        let fractions = normalizedFractions()

        return VStack(alignment: .leading, spacing: 12) {
            Text("腾出空间")
                .font(.headline)
                .foregroundStyle(.white)
            Text(byteString(total))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            SegmentedStorageBar(fractions: fractions)

            HStack(spacing: 14) {
                legend(color: LingerTheme.accentBlue, title: "照片", pct: fractions[.photo] ?? 0)
                legend(color: LingerTheme.accentRed, title: "截屏", pct: fractions[.screenshot] ?? 0)
                legend(color: LingerTheme.accentGreen, title: "视频", pct: fractions[.video] ?? 0)
            }
            .font(.caption)
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resetRow: some View {
        Button {
            showResetConfirm = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("重置浏览记录")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("浏览了 \(statsStore.stats.viewedCount) 个项目，其中 \(statsStore.stats.deletedCount) 个已删除。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func metric(icon: String, tint: Color, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(color: Color, title: String, pct: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(Int((pct * 100).rounded()))%")
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func normalizedFractions() -> [StatsBucket: Double] {
        let total = Double(max(0, statsStore.stats.totalFreedBytes))
        guard total > 0 else { return [:] }
        var result: [StatsBucket: Double] = [:]
        for bucket in StatsBucket.allCases {
            let bytes = Double(statsStore.stats.freedBytesByBucket[bucket] ?? 0)
            result[bucket] = bytes / total
        }
        return result
    }

    private func byteString(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 字节" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
