import Foundation
import os
import BlocksRuntime

private let logger = Logger(subsystem: "com.example.MySyncPhotos", category: "Realtime")

/// Live "new photo" notifications over the AWS Blocks Realtime WebSocket.
///
/// The channel, URL and token come from the generated `Api.getFeedChannel()`.
/// The socket is handled here instead of with `RealtimeChannel.subscribe()` from
/// BlocksRuntime 0.1.1, because that version:
///  - reads the message body from `"payload"`, while the AWS Blocks Realtime server
///    sends `"data"`, so it would never deliver a message (fixed upstream, unreleased);
///  - never reconnects, and gives no signal when the subscription is established.
/// When a fixed aws-blocks-swift is released this can be replaced by `channel.subscribe()`.
struct FeedRealtimeClient: Sendable {

    enum DescriptorError: Error, Equatable {
        case missingField(String)
        case invalidURL(String)
    }

    struct Endpoint: Sendable, Equatable {
        let url: URL
        let channel: String
        let token: String
        /// Connect-time token. The deployed (AWS API Gateway) WebSocket rejects a
        /// connection without it (HTTP 403); the local dev server ignores it.
        var connectToken: String? = nil

        /// URL to open: `url` plus `?token=<connectToken>` when a connect token exists.
        var connectURL: URL {
            guard let connectToken,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url
            }
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "token", value: connectToken)]
            // URLQueryItem leaves '+' unescaped; escape it so a token can't be misread as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
            return components.url ?? url
        }
    }

    /// What one server frame means for us.
    enum Event: Equatable {
        case subscribed            // server confirmed the subscription
        case feedChanged           // a photo was published to the feed
        case rejected(String)      // server refused the subscription (e.g. stale token)
        case ignored               // anything else (other channels, unknown frames)
    }

    /// Fetches a fresh channel descriptor. Called on every (re)connect, because tokens
    /// expire and a dev-server restart invalidates all previously issued tokens.
    let fetchEndpoint: @Sendable () async throws -> Endpoint
    var session: URLSession = .shared

    // MARK: - Run loop

    /// Stays subscribed until the calling task is cancelled, reconnecting with
    /// back-off after any failure.
    ///
    /// - Parameters:
    ///   - onReady: Called each time a subscription is established. Events sent while
    ///     disconnected are lost, so the caller should re-sync here.
    ///   - onEvent: Called when a new photo is announced.
    func run(onReady: @escaping @Sendable () -> Void,
             onEvent: @escaping @Sendable () -> Void) async {
        var delay = AppConfig.realtimeReconnectBaseDelay
        while !Task.isCancelled {
            var established = false
            do {
                let endpoint = try await fetchEndpoint()
                established = try await listen(endpoint, onReady: onReady, onEvent: onEvent)
            } catch is CancellationError {
                return
            } catch {
                logger.info("Realtime connection ended: \(error.localizedDescription, privacy: .public)")
            }
            if Task.isCancelled { return }

            // A connection that got as far as subscribing resets the back-off.
            if established { delay = AppConfig.realtimeReconnectBaseDelay }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay = min(delay * 2, AppConfig.realtimeReconnectMaxDelay)
        }
    }

    /// One connection: subscribe, then dispatch frames until the socket fails or the
    /// task is cancelled. Returns whether the subscription was established.
    private func listen(_ endpoint: Endpoint,
                        onReady: @Sendable () -> Void,
                        onEvent: @Sendable () -> Void) async throws -> Bool {
        let task = session.webSocketTask(with: endpoint.connectURL)
        task.resume()

        // Keep-alive, two kinds:
        // - WebSocket ping frames: a failed ping cancels the socket, which ends `receive()`
        //   below, so a dead connection (e.g. Wi-Fi gone) is detected instead of hanging.
        // - App-level `{"action":"ping"}`: the AWS deployment drops idle connections after
        //   10 minutes and expires subscriptions after ~1 hour unless pinged.
        //   (The local dev server ignores this message.)
        let appPingEvery = max(1, Int(AppConfig.realtimeAppPingInterval / AppConfig.realtimePingInterval))
        let pinger = Task {
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConfig.realtimePingInterval * 1_000_000_000))
                if Task.isCancelled { return }
                task.sendPing { error in
                    if error != nil { task.cancel(with: .goingAway, reason: nil) }
                }
                tick += 1
                if tick % appPingEvery == 0 {
                    task.send(.string(Self.pingMessage)) { error in
                        if error != nil { task.cancel(with: .goingAway, reason: nil) }
                    }
                }
            }
        }
        defer {
            pinger.cancel()
            task.cancel(with: .normalClosure, reason: nil)
        }

        var established = false
        try await withTaskCancellationHandler {
            try await task.send(.string(Self.subscribeMessage(for: endpoint)))
            while true {
                let message = try await task.receive()
                let text: String
                switch message {
                case .string(let string): text = string
                case .data(let data):     text = String(decoding: data, as: UTF8.self)
                @unknown default:         continue
                }
                switch Self.event(fromText: text, channel: endpoint.channel) {
                case .subscribed:
                    established = true
                    logger.info("Realtime subscribed to \(endpoint.channel, privacy: .public)")
                    onReady()
                case .feedChanged:
                    onEvent()
                case .rejected(let reason):
                    throw RealtimeError.websocket("Subscription rejected: \(reason)", nil)
                case .ignored:
                    continue
                }
            }
        } onCancel: {
            task.cancel(with: .normalClosure, reason: nil)
        }
        return established
    }

    // MARK: - Protocol (pure, unit-tested)

    /// Keeps the connection and its subscriptions alive on the AWS deployment.
    static let pingMessage = #"{"action":"ping"}"#

    /// `{"action":"subscribe","channel":…,"token":…}`, JSON-escaped.
    /// (`connectToken` goes in the URL, never in this message.)
    static func subscribeMessage(for endpoint: Endpoint) -> String {
        let object = ["action": "subscribe", "channel": endpoint.channel, "token": endpoint.token]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Classifies one server frame. The server's message body is `data`; `payload`
    /// is accepted too for compatibility with other AWS Blocks runtimes.
    static func event(fromText text: String, channel: String) -> Event {
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else {
            return .ignored
        }
        let frameChannel = json["channel"] as? String
        switch type {
        case "subscribe_success" where frameChannel == channel:
            return .subscribed
        case "message" where frameChannel == channel:
            return (json["data"] ?? json["payload"]) != nil ? .feedChanged : .ignored
        case "error" where frameChannel == nil || frameChannel == channel:
            return .rejected(json["message"] as? String ?? "unknown error")
        default:
            return .ignored
        }
    }
}

// MARK: - Channel descriptor

extension FeedRealtimeClient.Endpoint {

    /// Builds an endpoint from the `getFeedChannel` result
    /// `{ channel, wsUrl, token, connectToken? }`.
    ///
    /// - Parameter baseHost: When not `"localhost"`, a `://localhost` in `wsUrl` is
    ///   rewritten to it (dev server reached from a real device over the LAN).
    init(descriptor json: [String: Any], baseHost: String) throws {
        guard let channel = json["channel"] as? String else {
            throw FeedRealtimeClient.DescriptorError.missingField("channel")
        }
        guard var wsUrl = json["wsUrl"] as? String else {
            throw FeedRealtimeClient.DescriptorError.missingField("wsUrl")
        }
        guard let token = json["token"] as? String else {
            throw FeedRealtimeClient.DescriptorError.missingField("token")
        }
        if baseHost != "localhost" {
            wsUrl = wsUrl.replacingOccurrences(of: "://localhost", with: "://\(baseHost)")
        }
        guard let url = URL(string: wsUrl) else {
            throw FeedRealtimeClient.DescriptorError.invalidURL(wsUrl)
        }
        self.init(
            url: url,
            channel: channel,
            token: token,
            connectToken: json["connectToken"] as? String
        )
    }
}
