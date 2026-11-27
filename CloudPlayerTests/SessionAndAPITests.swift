import Foundation
import XCTest
@testable import CloudPlayer

final class SessionAndAPITests: XCTestCase {
    private final class InMemoryPersistence: SessionPersistence, @unchecked Sendable {
        var stored: SoundCloudSession?
        func load() -> SoundCloudSession? { stored }
        func save(_ session: SoundCloudSession) throws { stored = session }
        func clear() throws { stored = nil }
    }

    @MainActor
    func testSessionStoreLifecycle() {
        let persistence = InMemoryPersistence()
        let store = SessionStore(persistence: persistence)

        store.bootstrap()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.session)

        let initial = SoundCloudSession(oauthToken: "tok_123", refreshToken: "ref_456", clientID: "cid_abc")
        store.save(initial)
        XCTAssertEqual(store.state, .signedIn)
        XCTAssertEqual(persistence.stored?.oauthToken, "tok_123")

        store.updateClientID("cid_new")
        XCTAssertEqual(store.session?.clientID, "cid_new")
        XCTAssertEqual(persistence.stored?.clientID, "cid_new")

        store.signOut()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.session)
        XCTAssertNil(persistence.stored)
    }

    func testFileSessionPersistenceRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudplayer-test-\(UUID().uuidString)/session.json")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }

        let persistence = FileSessionPersistence(url: tmp)
        XCTAssertNil(persistence.load())

        let session = SoundCloudSession(oauthToken: "oauth_xyz", refreshToken: "refresh_1", clientID: "cid_999", userID: 42, username: "tester")
        try persistence.save(session)

        let loaded = persistence.load()
        XCTAssertEqual(loaded?.oauthToken, "oauth_xyz")
        XCTAssertEqual(loaded?.refreshToken, "refresh_1")
        XCTAssertEqual(loaded?.clientID, "cid_999")
        XCTAssertEqual(loaded?.userID, 42)
        XCTAssertEqual(loaded?.username, "tester")

        try persistence.clear()
        XCTAssertNil(persistence.load())
    }

    func testClientIDExtractionFromHTMLAndJS() {
        let html = """
        <html><body>
        <script crossorigin src="https://a-v2.sndcdn.com/assets/0-abc123.js"></script>
        <script crossorigin src="https://a-v2.sndcdn.com/assets/49-def456.js"></script>
        </body></html>
        """
        let urls = SoundCloudAPI.extractAssetScriptURLs(from: html)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.last?.absoluteString, "https://a-v2.sndcdn.com/assets/49-def456.js")

        let js = #"const cfg={foo:1,client_id:"AbCdEfGhIjKlMnOpQrStUvWxYz012345",bar:2};"#
        XCTAssertEqual(SoundCloudAPI.extractClientID(fromJS: js), "AbCdEfGhIjKlMnOpQrStUvWxYz012345")
    }

    func testSCUserDecodingAndImageVariant() throws {
        let json = """
        {
          "id": 123456,
          "username": "jan",
          "full_name": "Jan Test",
          "permalink": "jan-test",
          "permalink_url": "https://soundcloud.com/jan-test",
          "avatar_url": "https://i1.sndcdn.com/avatars-000123-abc-large.jpg",
          "followers_count": 10,
          "followings_count": 20,
          "likes_count": 300,
          "track_count": 5,
          "verified": true
        }
        """
        let user = try JSONDecoder().decode(SCUser.self, from: Data(json.utf8))
        XCTAssertEqual(user.id, 123456)
        XCTAssertEqual(user.displayName, "Jan Test")
        XCTAssertEqual(user.likesCount, 300)
        XCTAssertEqual(
            user.avatarURL(size: .large)?.absoluteString,
            "https://i1.sndcdn.com/avatars-000123-abc-t500x500.jpg"
        )
    }

    func testSoundCloudAPIFetchCurrentUserAndClientIDRefresh() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        var requests: [URLRequest] = []
        MockURLProtocol.handler = { req in
            requests.append(req)
            let url = req.url!.absoluteString
            if url.contains("api-v2.soundcloud.com/me") {
                XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "OAuth my_token")
                if url.contains("client_id=stale_cid") {
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                    return (resp, Data())
                }
                XCTAssertTrue(url.contains("client_id=FreshClientID1234567890123456"))
                let body = #"{"id":99,"username":"demo","likes_count":7}"#
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(body.utf8))
            }
            if url == "https://soundcloud.com" || url == "https://soundcloud.com/" {
                let html = #"<script src="https://a-v2.sndcdn.com/assets/app-1.js"></script>"#
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(html.utf8))
            }
            if url == "https://a-v2.sndcdn.com/assets/app-1.js" {
                let js = #"window.__sc={client_id:"FreshClientID1234567890123456"};"#
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(js.utf8))
            }
            XCTFail("Unexpected URL: \(url)")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        let api = SoundCloudAPI(session: mockSession)
        await api.configure(session: SoundCloudSession(oauthToken: "my_token", clientID: "stale_cid"))

        let user = try await api.fetchCurrentUser()
        XCTAssertEqual(user.id, 99)
        XCTAssertEqual(user.username, "demo")
        XCTAssertEqual(user.likesCount, 7)
        let updatedCID = await api.currentClientID()
        XCTAssertEqual(updatedCID, "FreshClientID1234567890123456")
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
