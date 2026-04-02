/*
  BroadcastDetailTrackMatchTests.swift
  BiteFM
*/

import XCTest
@testable import BiteFMCore

final class BroadcastDetailTrackMatchTests: XCTestCase {
    func testResolvesOffsetByTrackTitle() throws {
        let json = """
        {
          "id": 1,
          "broadcast_title": "X",
          "show_subtitle": "",
          "show_time": "",
          "show_date": "",
          "moderator": "",
          "recordings": [
            {
              "recording_url": "https://example.com/a.mp3",
              "playlist": [
                { "artist": "Artist", "title": "Target Song", "time": 333 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!
        let detail = try JSONDecoder().decode(BroadcastDetail.self, from: json)
        XCTAssertEqual(detail.startSeconds(matchingFavoriteTrackTitle: "Target Song"), 333)
    }
}
