import Foundation
import XCTest
@testable import CloudPlayer

final class Milestone4ModelTests: XCTestCase {
    func testPlaylistPartialTrackStubsDecoding() throws {
        let json = """
        {
          "id": 777,
          "title": "Late Night Mix",
          "track_count": 3,
          "tracks": [
            { "id": 101, "title": "Full Track", "duration": 210000 },
            { "id": 102 },
            { "id": 103 }
          ]
        }
        """
        let playlist = try JSONDecoder().decode(SCPlaylist.self, from: Data(json.utf8))
        XCTAssertEqual(playlist.id, 777)
        XCTAssertEqual(playlist.hydratedTracks.map(\.id), [101])
        XCTAssertEqual(playlist.missingTrackIDs, [102, 103])
    }

    func testMixedSelectionDecoding() throws {
        let json = """
        {
          "collection": [
            {
              "urn": "soundcloud:selections:1",
              "title": "More of what you like",
              "description": "Suggestions based on what you've liked or played",
              "items": {
                "collection": [
                  { "id": 55, "title": "Chill Mix", "track_count": 25 },
                  { "unexpected_null_title": true }
                ]
              }
            }
          ]
        }
        """
        let page = try JSONDecoder().decode(SCCollectionPage<SCMixedSelection>.self, from: Data(json.utf8))
        XCTAssertEqual(page.collection.count, 1)
        XCTAssertEqual(page.collection[0].title, "More of what you like")
        XCTAssertEqual(page.collection[0].items?.collection.count, 1)
        XCTAssertEqual(page.collection[0].items?.collection[0].title, "Chill Mix")
    }
}
