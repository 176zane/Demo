import XCTest
@testable import Linger

final class UserStatsBucketTests: XCTestCase {
    func testRecordByBucketAndReset() {
        var stats = UserStats.empty
        stats.recordViewed(bucket: .photo, count: 2)
        stats.recordDeleted(bucket: .video, count: 1, freedBytes: 1_024)
        XCTAssertEqual(stats.viewedCount, 2)
        XCTAssertEqual(stats.deletedByBucket[.video], 1)
        XCTAssertEqual(stats.totalFreedBytes, 1_024)
        stats.reset()
        XCTAssertEqual(stats, .empty)
    }

    /// 旧版 JSON 仅含 viewedCount/deletedCount 时应迁移到 photo 桶
    func testLegacyStatsMigration() throws {
        let json = """
        {"viewedCount":5,"deletedCount":3}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let stats = try JSONDecoder().decode(UserStats.self, from: data)
        XCTAssertEqual(stats.viewedByBucket[.photo], 5)
        XCTAssertEqual(stats.deletedByBucket[.photo], 3)
        XCTAssertEqual(stats.viewedCount, 5)
        XCTAssertEqual(stats.deletedCount, 3)
    }
}
