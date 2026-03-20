import XCTest
@testable import BiteFM

final class FavoriteStateLogicTests: XCTestCase {
    func testBroadcastFavoriteSlugCaseInsensitive() {
        let slugs: Set<String> = ["ektoplasma", "Ektoplasma"]
        XCTAssertTrue(FavoriteStateLogic.isFavoriteBroadcast(slug: "EKTOPLASMA", title: "X", favoriteSlugs: slugs))
        XCTAssertTrue(FavoriteStateLogic.isFavoriteBroadcast(slug: "x", title: "Ektoplasma", favoriteSlugs: slugs))
    }
    
    func testEpisodeFavoriteByShowID() {
        let ids: Set<Int> = [77406]
        XCTAssertTrue(
            FavoriteStateLogic.isEpisodeFavorite(
                terminID: 77406,
                terminSlug: "any",
                favoriteShowIDs: ids,
                favoriteSlugs: []
            )
        )
        XCTAssertFalse(
            FavoriteStateLogic.isEpisodeFavorite(
                terminID: 1,
                terminSlug: "any",
                favoriteShowIDs: ids,
                favoriteSlugs: []
            )
        )
    }
    
    func testEpisodeFavoriteFallbackSlug() {
        XCTAssertTrue(
            FavoriteStateLogic.isEpisodeFavorite(
                terminID: 999,
                terminSlug: "au-revoir",
                favoriteShowIDs: [],
                favoriteSlugs: ["au-revoir"]
            )
        )
    }
    
    func testArchiveItemFavoriteCombinesBroadcastAndEpisode() {
        XCTAssertTrue(
            FavoriteStateLogic.isFavoriteArchiveItem(
                sendungSlug: "ektoplasma",
                terminSlug: "ep1",
                sendungTitel: "Ektoplasma",
                terminID: 1,
                favoriteSlugs: ["ektoplasma"],
                favoriteShowIDs: []
            )
        )
        XCTAssertTrue(
            FavoriteStateLogic.isFavoriteArchiveItem(
                sendungSlug: "x",
                terminSlug: "ep1",
                sendungTitel: "Y",
                terminID: 42,
                favoriteSlugs: [],
                favoriteShowIDs: [42]
            )
        )
    }
}
