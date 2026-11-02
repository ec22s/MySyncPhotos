import Testing
import Foundation
@testable import MySyncPhotos

/// Pins the realtime wire protocol. The stock BlocksRuntime 0.1.1 client failed exactly
/// here (it read `payload`, the server sends `data`), so these cases matter.
@Suite("FeedRealtimeClient protocol")
struct FeedRealtimeClientTests {

    private let channel = "mysyncphotos-live/feed/all"

    @Test("Subscribe message carries action, channel and token as valid JSON")
    func subscribeMessage() throws {
        let endpoint = FeedRealtimeClient.Endpoint(
            url: URL(string: "ws://localhost:3000/realtime")!,
            channel: channel,
            token: "tok\"en"   // must be escaped, not break the JSON
        )
        let text = FeedRealtimeClient.subscribeMessage(for: endpoint)
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String]
        )
        #expect(json == ["action": "subscribe", "channel": channel, "token": "tok\"en"])
    }

    @Test("Descriptor from the cloud: wss URL kept, connect token carried")
    func cloudDescriptor() throws {
        let endpoint = try FeedRealtimeClient.Endpoint(descriptor: [
            "__blocks": "realtime/channel",
            "channel": channel,
            "wsUrl": "wss://abc123.execute-api.ap-northeast-1.amazonaws.com/rt",
            "token": "chan-token",
            "connectToken": "conn-token",
        ], baseHost: "localhost")

        #expect(endpoint.url.absoluteString == "wss://abc123.execute-api.ap-northeast-1.amazonaws.com/rt")
        #expect(endpoint.token == "chan-token")
        #expect(endpoint.connectToken == "conn-token")
    }

    @Test("Descriptor from the dev server on a real device: localhost rewritten to the LAN IP")
    func lanDescriptor() throws {
        let endpoint = try FeedRealtimeClient.Endpoint(descriptor: [
            "channel": channel, "wsUrl": "ws://localhost:3000/realtime", "token": "t",
        ], baseHost: "192.168.11.10")

        #expect(endpoint.url.absoluteString == "ws://192.168.11.10:3000/realtime")
        #expect(endpoint.connectToken == nil)
    }

    @Test("Descriptor missing a required field is rejected")
    func incompleteDescriptor() {
        #expect(throws: FeedRealtimeClient.DescriptorError.missingField("token")) {
            try FeedRealtimeClient.Endpoint(descriptor: [
                "channel": channel, "wsUrl": "ws://localhost:3000/realtime",
            ], baseHost: "localhost")
        }
    }

    @Test("Connect URL appends the connect token as ?token=, percent-encoded")
    func connectURLWithToken() throws {
        let endpoint = FeedRealtimeClient.Endpoint(
            url: URL(string: "wss://abc.execute-api.ap-northeast-1.amazonaws.com/rt")!,
            channel: channel, token: "t",
            connectToken: "eyJhIjoxfQ.sig+/="
        )
        let components = try #require(URLComponents(url: endpoint.connectURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/rt")
        #expect(components.percentEncodedQuery?.contains("%2B") == true, "'+' must be escaped")
        #expect(components.queryItems?.first { $0.name == "token" }?.value == "eyJhIjoxfQ.sig+/=")
    }

    @Test("Without a connect token the URL is unchanged (local dev server)")
    func connectURLWithoutToken() {
        let url = URL(string: "ws://localhost:3000/realtime")!
        let endpoint = FeedRealtimeClient.Endpoint(url: url, channel: channel, token: "t")
        #expect(endpoint.connectURL == url)
    }

    @Test("A message with a 'data' body (what the AWS Blocks server sends) is a feed change")
    func dataBody() {
        let frame = #"{"type":"message","channel":"\#(channel)","data":{"photoId":"p1","createdAt":"t"}}"#
        #expect(FeedRealtimeClient.event(fromText: frame, channel: channel) == .feedChanged)
    }

    @Test("A message with a 'payload' body is accepted too")
    func payloadBody() {
        let frame = #"{"type":"message","channel":"\#(channel)","payload":{"photoId":"p1"}}"#
        #expect(FeedRealtimeClient.event(fromText: frame, channel: channel) == .feedChanged)
    }

    @Test("subscribe_success for our channel means the subscription is established")
    func subscribed() {
        let frame = #"{"type":"subscribe_success","channel":"\#(channel)"}"#
        #expect(FeedRealtimeClient.event(fromText: frame, channel: channel) == .subscribed)
    }

    @Test("An error frame is a rejection that carries the server's reason")
    func rejected() {
        let frame = #"{"type":"error","channel":"\#(channel)","message":"Unauthorized: invalid or expired token"}"#
        #expect(FeedRealtimeClient.event(fromText: frame, channel: channel)
                == .rejected("Unauthorized: invalid or expired token"))
    }

    @Test("Frames for other channels, bodiless messages and garbage are ignored")
    func ignored() {
        let other = #"{"type":"message","channel":"someone/else","data":{}}"#
        let noBody = #"{"type":"message","channel":"\#(channel)"}"#
        let otherError = #"{"type":"error","channel":"someone/else","message":"x"}"#
        for frame in [other, noBody, otherError, "not json", #"{"channel":"x"}"#] {
            #expect(FeedRealtimeClient.event(fromText: frame, channel: channel) == .ignored,
                    "Expected ignored for \(frame)")
        }
    }
}
