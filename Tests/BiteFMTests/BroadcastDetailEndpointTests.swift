import XCTest
@testable import BiteFMCore

final class BroadcastDetailEndpointTests: XCTestCase {
    func testUsesOfficialDateOnlyBroadcastDetailPathFirst() {
        let urls = BroadcastDetailEndpoint.urls(
            showSegment: "60minutes",
            dateSegment: "02.05.2026",
            terminSlug: "60minutes",
            markAsListened: false
        )

        XCTAssertEqual(
            urls.map(\.absoluteString),
            [
                "https://www.byte.fm/api/v1/broadcasts/60minutes/02.05.2026/?listen=no",
                "https://www.byte.fm/api/v1/broadcasts/60minutes/02.05.2026/60minutes/?listen=no"
            ]
        )
    }

    func testListenedRequestOmitsListenNoQuery() {
        let urls = BroadcastDetailEndpoint.urls(
            showSegment: "bytefm-mixtape",
            dateSegment: "01.05.2026",
            terminSlug: "guest-mix",
            markAsListened: true
        )

        XCTAssertEqual(
            urls.map(\.absoluteString),
            [
                "https://www.byte.fm/api/v1/broadcasts/bytefm-mixtape/01.05.2026/",
                "https://www.byte.fm/api/v1/broadcasts/bytefm-mixtape/01.05.2026/guest-mix/"
            ]
        )
    }

    func testNormalizesTypographicDashesInFallbackTerminSlug() {
        let urls = BroadcastDetailEndpoint.urls(
            showSegment: "example",
            dateSegment: "01.05.2026",
            terminSlug: "foo\u{2013}bar",
            markAsListened: false
        )

        XCTAssertEqual(urls.last?.absoluteString, "https://www.byte.fm/api/v1/broadcasts/example/01.05.2026/foo-bar/?listen=no")
    }
}
