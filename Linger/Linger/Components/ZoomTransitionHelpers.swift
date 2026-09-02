import SwiftUI

/// 照片详情以 overlay 呈现时，通知主壳层隐藏悬浮 TabBar
struct BrowseFullscreenKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// iOS 18 缩放转场（照片 → 全屏 / 网格）；低版本自动退化为默认转场
extension View {
    @ViewBuilder
    func zoomTransitionSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
