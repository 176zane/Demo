import SwiftUI

/// 应用主导航的三个固定入口。
enum MainTab: Hashable, CaseIterable {
    case photos
    case videos
    case stats

    /// 面向用户展示的中文标题。
    var title: String {
        switch self {
        case .photos:
            return "照片"
        case .videos:
            return "视频"
        case .stats:
            return "统计"
        }
    }

    /// 与截图液体玻璃 Dock 一致的 SF Symbol
    var systemImage: String {
        switch self {
        case .photos:
            return "square.stack.fill"
        case .videos:
            return "play.square.fill"
        case .stats:
            return "person.fill"
        }
    }
}

/// 悬浮液体玻璃胶囊 TabBar（iOS 26+ 使用系统 Liquid Glass；低版本回退毛玻璃）
struct FloatingTabBar: View {
    @Binding var selection: MainTab
    @Namespace private var selectionNamespace

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassBar
            } else {
                legacyGlassBar
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: - iOS 26 Liquid Glass

    @available(iOS 26.0, *)
    private var liquidGlassBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(MainTab.allCases, id: \.self) { tab in
                    liquidTabButton(tab)
                }
            }
            .padding(5)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
    }

    @available(iOS 26.0, *)
    private func liquidTabButton(_ tab: MainTab) -> some View {
        let selected = selection == tab
        return Button {
            // 仅更新选中态；指示器局部动画，不带动整页
            selection = tab
        } label: {
            tabLabel(tab, selected: selected)
        }
        .buttonStyle(.plain)
        .background {
            if selected {
                Capsule()
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(.white.opacity(0.35)), in: .capsule)
                    .matchedGeometryEffect(id: "tabSelection", in: selectionNamespace)
            }
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.18), value: selection)
    }

    // MARK: - iOS 17–25 回退（轻量，避免 Material 动画卡顿）

    private var legacyGlassBar: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                legacyTabButton(tab)
            }
        }
        .padding(5)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.55))
                .background {
                    Capsule().fill(.thinMaterial)
                }
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
                }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }

    private func legacyTabButton(_ tab: MainTab) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            tabLabel(tab, selected: selected)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .matchedGeometryEffect(id: "tabSelection", in: selectionNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.18), value: selection)
    }

    private func tabLabel(_ tab: MainTab, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? AnyShapeStyle(activeIconGradient) : AnyShapeStyle(Color.white.opacity(0.58)))
            Text(tab.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .contentShape(Capsule())
    }

    /// 选中态图标：柔和蓝紫渐变（对齐参考截图）
    private var activeIconGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.55, green: 0.62, blue: 1.0),
                Color(red: 0.42, green: 0.38, blue: 0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
