import XCTest
@testable import Linger

final class RelativeDateLabelTests: XCTestCase {
    func testYearsAgo() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23))!
        let past = calendar.date(from: DateComponents(year: 2020, month: 7, day: 23))!
        XCTAssertEqual(RelativeDateLabel.text(for: past, now: now, calendar: calendar), "6 年前")
    }

    func testToday() {
        let now = Date()
        XCTAssertEqual(RelativeDateLabel.text(for: now, now: now), "今天")
    }
}
