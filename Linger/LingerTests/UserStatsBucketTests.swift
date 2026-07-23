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
}
