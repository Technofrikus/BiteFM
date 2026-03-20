import XCTest
@testable import BiteFM

final class FavoriteTrackItemDecodingTests: XCTestCase {
    func testDecodesStartOffsetFromTimeInt() throws {
        let json = """
        {
          "id": 1001,
          "title": "Example Song",
          "time": 125,
          "broadcast": {
            "id": 1,
            "slug": "show-slug",
            "title": "Show"
          },
          "show": {
            "id": 2,
            "slug": "ep",
            "date": "2020-01-01",
            "subtitle": "Ep",
            "is_playable": true
          }
        }
        """
        let data = Data(json.utf8)
        let item = try JSONDecoder().decode(FavoriteTrackItem.self, from: data)
        XCTAssertEqual(item.startOffsetSeconds, 125, accuracy: 0.01)
    }
}
