import XCTest
@testable import Linger

final class MainTabTests: XCTestCase {
    /// Tab 必须保持产品锁定的顺序与中文标题，避免后续页面接入时导航错位。
    func testTabsUseLockedOrderAndChineseTitles() {
        XCTAssertEqual(MainTab.allCases, [.photos, .videos, .stats])
        XCTAssertEqual(MainTab.allCases.map(\.title), ["照片", "视频", "统计"])
    }

    /// 每个 Tab 都应提供独立的 SF Symbol，供悬浮导航栏统一渲染。
    func testTabsProvideDistinctSystemImages() {
        let systemImages = MainTab.allCases.map(\.systemImage)
        XCTAssertEqual(Set(systemImages).count, MainTab.allCases.count)
    }
}
