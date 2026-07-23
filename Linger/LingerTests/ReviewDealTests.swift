import XCTest
@testable import Linger

final class ReviewDealTests: XCTestCase {
    func testMarkDeleteAndAdvance() {
        let items = [
            MediaItem(id: "a", mediaKind: .photo, creationDate: Date()),
            MediaItem(id: "b", mediaKind: .photo, creationDate: Date())
        ]
        var deal = ReviewDeal(items: items)
        deal.markCurrentForDeletion()
        XCTAssertTrue(deal.markedForDeletion.contains("a"))
        XCTAssertEqual(deal.currentIndex, 1)
        XCTAssertEqual(deal.currentItem?.id, "b")
    }

    func testFinishedBrowsingTriggersConfirmPath() {
        let items = [MediaItem(id: "a", mediaKind: .video, creationDate: Date())]
        var deal = ReviewDeal(items: items)
        deal.keepCurrentAndAdvance()
        XCTAssertTrue(deal.hasFinishedBrowsing)
    }

    func testUnmarkDeletion() {
        var deal = ReviewDeal(items: [
            MediaItem(id: "a", mediaKind: .photo, creationDate: nil)
        ])
        deal.markCurrentForDeletion()
        deal.unmarkDeletion(id: "a")
        XCTAssertTrue(deal.markedForDeletion.isEmpty)
    }

    func testRemoveItemsAndRetainMarked() {
        var deal = ReviewDeal(
            items: [
                MediaItem(id: "a", mediaKind: .photo, creationDate: nil),
                MediaItem(id: "b", mediaKind: .photo, creationDate: nil)
            ],
            currentIndex: 2,
            markedForDeletion: ["a", "b"]
        )
        deal.removeItems(ids: ["a"])
        XCTAssertEqual(deal.items.map(\.id), ["b"])
        XCTAssertEqual(deal.markedForDeletion, ["b"])

        deal.retainMarkedForDeletion(ids: ["b", "missing"])
        XCTAssertEqual(deal.markedForDeletion, ["b"])
    }
}
