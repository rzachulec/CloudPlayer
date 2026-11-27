import Foundation
import XCTest
@testable import CloudPlayer

final class PlaybackTests: XCTestCase {
    private func track(_ id: Int) -> SCTrack {
        SCTrack(id: id, title: "Track \(id)", duration: 180_000)
    }

    func testQueueContextAndUserUpNextPriority() {
        var q = PlaybackQueue()
        let list = [track(1), track(2), track(3), track(4)]

        q.play(track: list[1], inContext: list, contextTitle: "Likes")
        XCTAssertEqual(q.current?.id, 2)
        XCTAssertEqual(q.contextQueue.map(\.id), [3, 4])

        // User-queued tracks jump ahead of context
        q.enqueueLater(track(99))
        q.enqueueNext(track(98))
        XCTAssertEqual(q.nextUpPreview?.id, 98)

        XCTAssertEqual(q.advance(manual: true)?.id, 98)
        XCTAssertEqual(q.advance(manual: true)?.id, 99)
        XCTAssertEqual(q.advance(manual: true)?.id, 3)
        XCTAssertEqual(q.advance(manual: true)?.id, 4)
        XCTAssertNil(q.advance(manual: true))
    }

    func testQueuePreviousRestartVsSwitch() {
        var q = PlaybackQueue()
        let list = [track(1), track(2), track(3)]
        q.play(track: list[0], inContext: list)
        _ = q.advance(manual: true) // now on 2, history = [1]

        // Past 3.5s → restart current
        XCTAssertEqual(q.previous(currentPosition: 10.0), .restartCurrent)
        XCTAssertEqual(q.current?.id, 2)

        // Under 3.5s → go back to 1, pushing 2 back onto contextQueue
        XCTAssertEqual(q.previous(currentPosition: 1.2), .switchTo(track(1)))
        XCTAssertEqual(q.current?.id, 1)
        XCTAssertEqual(q.contextQueue.first?.id, 2)
    }

    func testQueueRepeatModesAndShuffleRestore() {
        var q = PlaybackQueue()
        let list = (1...10).map(track)
        q.play(track: list[0], inContext: list)

        // Shuffle then unshuffle restores exact original remaining order
        q.toggleShuffle()
        XCTAssertTrue(q.shuffle)
        XCTAssertEqual(Set(q.contextQueue.map(\.id)), Set(2...10))
        q.toggleShuffle()
        XCTAssertFalse(q.shuffle)
        XCTAssertEqual(q.contextQueue.map(\.id), Array(2...10))

        // Repeat one repeats on auto-advance, advances on manual
        q.cycleRepeat() // .all
        q.cycleRepeat() // .one
        XCTAssertEqual(q.repeatMode, .one)
        XCTAssertEqual(q.advance(manual: false)?.id, 1)
        XCTAssertEqual(q.advance(manual: true)?.id, 2)
    }

    func testStreamResolverPrefersAVPlayerCompatibleFormats() {
        let opusHLS = SCTranscoding(
            url: URL(string: "https://api-v2.soundcloud.com/media/1/opus")!,
            preset: "opus_0_0",
            duration: 180_000,
            snipped: false,
            format: SCTranscodingFormat(protocolType: "hls", mimeType: #"audio/ogg; codecs="opus""#),
            quality: "sq"
        )
        let mp3Prog = SCTranscoding(
            url: URL(string: "https://api-v2.soundcloud.com/media/1/prog")!,
            preset: "mp3_0_1",
            duration: 180_000,
            snipped: false,
            format: SCTranscodingFormat(protocolType: "progressive", mimeType: "audio/mpeg"),
            quality: "sq"
        )
        let mp3HLS = SCTranscoding(
            url: URL(string: "https://api-v2.soundcloud.com/media/1/hls")!,
            preset: "mp3_0_1",
            duration: 180_000,
            snipped: false,
            format: SCTranscodingFormat(protocolType: "hls", mimeType: "audio/mpeg"),
            quality: "sq"
        )
        let aacHLS = SCTranscoding(
            url: URL(string: "https://api-v2.soundcloud.com/media/1/aac")!,
            preset: "aac_160k",
            duration: 180_000,
            snipped: false,
            format: SCTranscodingFormat(protocolType: "hls", mimeType: #"audio/mp4; codecs="mp4a.40.2""#),
            quality: "sq"
        )

        XCTAssertNil(StreamResolver.selectBestTranscoding(from: [opusHLS]))
        XCTAssertEqual(StreamResolver.selectBestTranscoding(from: [opusHLS, mp3Prog])?.url, mp3Prog.url)
        XCTAssertEqual(StreamResolver.selectBestTranscoding(from: [opusHLS, mp3Prog, mp3HLS])?.url, mp3HLS.url)
        XCTAssertEqual(StreamResolver.selectBestTranscoding(from: [opusHLS, mp3Prog, mp3HLS, aacHLS])?.url, aacHLS.url)
    }

    func testLossyCollectionPageSkipsMalformedItems() throws {
        let json = """
        {
          "collection": [
            { "created_at": "2026-01-01", "track": { "id": 10, "title": "Good Track", "duration": 120000 } },
            { "bad_entry": 123 },
            { "created_at": "2026-01-02", "track": { "id": 20, "title": "Another Track", "duration": 240000 } }
          ],
          "next_href": "https://api-v2.soundcloud.com/users/1/track_likes?offset=next"
        }
        """
        let page = try JSONDecoder().decode(SCCollectionPage<SCLikeItem>.self, from: Data(json.utf8))
        let validTracks = page.collection.compactMap(\.track)
        XCTAssertEqual(validTracks.map(\.id), [10, 20])
        XCTAssertEqual(page.nextHref, "https://api-v2.soundcloud.com/users/1/track_likes?offset=next")
    }
}
