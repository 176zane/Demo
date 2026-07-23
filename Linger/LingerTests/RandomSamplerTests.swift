import XCTest
@testable import Linger

final class RandomSamplerTests: XCTestCase {
    func testSampleRespectsCountAndExclusion() {
        let candidates = (0..<50).map {
            MediaItem(id: "id-\($0)", mediaKind: .photo, creationDate: Date())
        }
        var rng = SeededGenerator(seed: 42)
        let result = RandomSampler.sample(
            from: candidates,
            count: 10,
            excluding: ["id-1", "id-2"],
            recentIDs: [],
            rng: &rng
        )

        XCTAssertEqual(result.count, 10)
        XCTAssertFalse(result.contains(where: { $0.id == "id-1" }))
        XCTAssertFalse(result.contains(where: { $0.id == "id-2" }))
        XCTAssertEqual(Set(result.map(\.id)).count, 10, "抽样结果应去重")
    }

    func testSampleEmptyLibrary() {
        var rng = SeededGenerator(seed: 1)
        let result = RandomSampler.sample(
            from: [],
            count: 20,
            excluding: [],
            rng: &rng
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testSamplePrefersFreshOverRecent() {
        let fresh = MediaItem(id: "fresh", mediaKind: .photo, creationDate: Date())
        let recent = MediaItem(id: "recent", mediaKind: .photo, creationDate: Date())
        var rng = SeededGenerator(seed: 7)
        let result = RandomSampler.sample(
            from: [fresh, recent],
            count: 1,
            excluding: [],
            recentIDs: ["recent"],
            rng: &rng
        )
        XCTAssertEqual(result.first?.id, "fresh")
    }

    func testZeroCountReturnsEmpty() {
        let candidates = [MediaItem(id: "a", mediaKind: .photo, creationDate: nil)]
        var rng = SeededGenerator(seed: 3)
        let result = RandomSampler.sample(
            from: candidates,
            count: 0,
            excluding: [],
            rng: &rng
        )
        XCTAssertTrue(result.isEmpty)
    }
}

/// 可复现的伪随机源，保证单测稳定
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }
}
