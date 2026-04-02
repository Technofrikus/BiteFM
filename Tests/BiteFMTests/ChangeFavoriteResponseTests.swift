import XCTest
@testable import BiteFMCore

final class ChangeFavoriteResponseTests: XCTestCase {
    func testDecodeBroadcastOnly() throws {
        let json = """
        {
          "error": 0,
          "status": "OK",
          "value": true,
          "id": 34686,
          "broadcast": {
            "id": 278,
            "slug": "ektoplasma",
            "title": "Ektoplasma"
          }
        }
        """
        let data = Data(json.utf8)
        let r = try JSONDecoder().decode(ChangeFavoriteResponse.self, from: data)
        XCTAssertEqual(r.error, 0)
        XCTAssertTrue(r.value)
        XCTAssertEqual(r.broadcast?.slug, "ektoplasma")
        XCTAssertNil(r.show)
    }
    
    func testDecodeWithShow() throws {
        let json = """
        {
          "error": 0,
          "status": "OK",
          "value": true,
          "id": 93389,
          "show": {
            "id": 77406,
            "slug": "au-revoir",
            "date": "2016-07-02",
            "subtitle": "Au Revoir",
            "is_playable": true
          },
          "broadcast": {
            "id": 278,
            "slug": "ektoplasma",
            "title": "Ektoplasma"
          }
        }
        """
        let data = Data(json.utf8)
        let r = try JSONDecoder().decode(ChangeFavoriteResponse.self, from: data)
        XCTAssertEqual(r.show?.id, 77406)
        XCTAssertEqual(r.broadcast?.title, "Ektoplasma")
    }
}
