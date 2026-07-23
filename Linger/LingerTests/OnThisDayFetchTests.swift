import XCTest
@testable import Linger

@MainActor
final class OnThisDayFetchTests: XCTestCase {
    func testFetchOnThisDayMatchesMonthDayAcrossYears() async throws {
        let calendar = Calendar.current
        let today = Date()
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        let thisYear = calendar.component(.year, from: today)

        var hitComponents = DateComponents()
        hitComponents.year = thisYear - 3
        hitComponents.month = month
        hitComponents.day = day
        let hitDate = calendar.date(from: hitComponents)!

        var missComponents = DateComponents()
        missComponents.year = thisYear - 2
        missComponents.month = month == 12 ? 1 : month + 1
        missComponents.day = 1
        let missDate = calendar.date(from: missComponents)!

        let mock = MockPhotoLibrary()
        mock.items = [
            MediaItem(id: "hit", mediaKind: .photo, creationDate: hitDate),
            MediaItem(id: "miss", mediaKind: .photo, creationDate: missDate)
        ]

        let result = try await mock.fetchOnThisDayItems(allowedKinds: [.photo], yearsBack: 12)
        XCTAssertEqual(result.map(\.id), ["hit"])
    }
}
