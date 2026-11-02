import Foundation

/// Central place for all tunable constants.
/// Change values here — never scatter magic numbers in the codebase.
enum AppConfig {

    // MARK: - Backend

    enum BackendTarget {
        /// `npm run dev` on the Mac (Simulator → localhost, device → LAN IP).
        case local
        /// The backend deployed to AWS with `npm run deploy`.
        case cloud
    }

    /// Which backend this build talks to. Switch and rebuild.
    static let backendTarget: BackendTarget = .cloud

    /// `ApiUrl` printed by `npm run deploy` (also in
    /// mysyncphotos-backend/.blocks-sandbox/config.json). Used when `backendTarget == .cloud`.
    /// Stack mysyncphotos-***-******-prod, account ************, ap-northeast-1.
    /// Changes if the stack is destroyed and deployed again.
    static let cloudBackendURL = "https://**********.execute-api.ap-northeast-1.amazonaws.com/prod/aws-blocks/api"

    /// `true` when talking to the Mac's dev server over the LAN (real device + local target).
    #if targetEnvironment(simulator)
    static let useLANBackend = false
    #else
    static let useLANBackend = backendTarget == .local
    #endif

    /// LAN IP of the Mac running `npm run dev`.
    /// Update this if your Mac's IP changes.
    static let lanHost      = "192.168.11.10"
    static let lanBackendURL   = "http://\(lanHost):3000/aws-blocks/api"
    static let localBackendURL = "http://localhost:3000/aws-blocks/api"

    /// The backend URL the app should use at runtime.
    static var backendURL: String {
        switch backendTarget {
        case .cloud:
            precondition(!cloudBackendURL.isEmpty,
                         "Set AppConfig.cloudBackendURL to the ApiUrl printed by `npm run deploy`.")
            return cloudBackendURL
        case .local:
            return useLANBackend ? lanBackendURL : localBackendURL
        }
    }

    // MARK: - Encoding

    /// Maximum size of a stored photo's JPEG (640 KiB). Photos are compressed to fit.
    /// Its Base64 form is ~4/3 larger (~874 KB), so a photo is at most 3 chunks.
    static let maxPhotoBytes: Int = 640 * 1024

    /// Photos are scaled down so their long edge is at most this many pixels.
    /// Chosen so a typical photo lands just under `maxPhotoBytes` at good quality.
    static let maxPhotoDimension: CGFloat = 2048

    /// Never scale a photo's long edge below this, even to meet `maxPhotoBytes`.
    static let minPhotoDimension: CGFloat = 320

    /// JPEG quality range searched when compressing (0.0 lowest – 1.0 best).
    /// The highest quality that fits `maxPhotoBytes` is used.
    static let maxJPEGQuality: CGFloat = 0.8
    static let minJPEGQuality: CGFloat = 0.3

    // MARK: - Chunking

    /// Maximum byte size per Base64 chunk.
    /// Must be strictly less than 400 KiB = 409,600 bytes.
    static let maxChunkBytes: Int = 380_000  // ~371 KiB — comfortable margin

    // MARK: - Grid

    /// Default number of photos shown in the grid.
    /// Users can change this in Settings; persisted via UserDefaults.
    static let defaultPhotoLimit: Int = 9

    /// UserDefaults key for the user-configured photo limit.
    static let photoLimitKey = "photoGridLimit"

    // MARK: - Sync

    /// Maximum number of upload attempts per chunk before the photo is marked failed.
    static let maxUploadRetries: Int = 3

    /// Base delay (seconds) for exponential back-off between chunk retries.
    static let retryBaseDelay: TimeInterval = 0.5

    // MARK: - Realtime

    /// After the live-update WebSocket drops, reconnect after this delay (seconds),
    /// doubling up to `realtimeReconnectMaxDelay`. Reset after a successful subscribe.
    static let realtimeReconnectBaseDelay: TimeInterval = 1
    static let realtimeReconnectMaxDelay: TimeInterval = 15

    /// WebSocket ping-frame interval (seconds); a failed ping triggers a reconnect.
    static let realtimePingInterval: TimeInterval = 20

    /// App-level `{"action":"ping"}` interval (seconds). Must stay below the AWS
    /// API Gateway 10-minute idle timeout.
    static let realtimeAppPingInterval: TimeInterval = 300

    /// A photo whose upload failed is retried automatically after this delay (seconds),
    /// doubling after each further failure up to `uploadRetryMaxDelay`.
    /// Launch, foreground, pull-to-refresh and reconnect retry immediately.
    static let uploadRetryBaseDelay: TimeInterval = 15
    static let uploadRetryMaxDelay: TimeInterval = 300

    // MARK: - Device identity

    /// UserDefaults key where the device UUID is persisted.
    static let deviceIdKey = "deviceUUID"

    /// Returns a stable device UUID, creating and persisting one on first launch.
    static var deviceId: String {
        if let stored = UserDefaults.standard.string(forKey: deviceIdKey) {
            return stored
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: deviceIdKey)
        return new
    }
}
