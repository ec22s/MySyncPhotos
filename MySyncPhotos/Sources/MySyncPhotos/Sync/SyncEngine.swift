import Foundation
import UIKit

/// Why a sync was requested. Every trigger except `.background` also retries queued
/// uploads immediately (ignoring the retry back-off).
enum SyncTrigger {
    case foreground   // app launched or came to the foreground
    case manual       // pull-to-refresh
    case reconnect    // network path came back
    case background   // realtime event / realtime (re)connect / scheduled upload retry
}

/// Keeps the local photo list and the shared cloud feed in sync.
///
/// **Pull:** fetches the newest photos from the shared feed (thumbnails only for
/// photos not seen before) and stores them in Core Data.
///
/// **Push:** every captured photo is first written to `PendingUploadStore`, so a
/// photo taken offline is not lost. Queued photos are uploaded when the network
/// returns, when the server becomes reachable again, and on launch/foreground/refresh.
/// A photo leaves the queue only after all its chunks *and* its feed entry are stored.
@MainActor
final class SyncEngine: ObservableObject {

    // MARK: - Published state (drives the UI)

    /// A user-visible feed sync is running (`.background` syncs do not set this).
    @Published private(set) var isSyncing = false
    /// At least one photo is currently being uploaded.
    @Published private(set) var isUploading = false
    /// Photos captured on this device that are not yet published.
    @Published private(set) var pendingUploadCount = 0
    @Published private(set) var lastSyncError: Error?

    let connectivity: ConnectivityMonitor

    // MARK: - Dependencies

    private let repository: PhotoChunksRepository
    private let localStore: LocalStore
    private let pendingStore: PendingUploadStore
    private let encoder = ImageEncoder()

    // MARK: - Internal state

    private var syncRunning = false
    private var resyncRequested = false
    private var forceUploadRetry = false
    /// Set when the server could not be reached; the next success then retries uploads at once.
    private var serverWasUnreachable = false

    private var inFlightUploads = Set<String>()
    private var failureCount: [String: Int] = [:]
    private var retryNotBefore: [String: Date] = [:]
    /// Wakes up when the earliest failed upload is due for an automatic retry.
    private var retryTimer: Task<Void, Never>?

    private let realtime: FeedRealtimeClient

    // MARK: - Init

    init(
        repository: PhotoChunksRepository,
        localStore: LocalStore,
        pendingStore: PendingUploadStore = PendingUploadStore(),
        connectivity: ConnectivityMonitor? = nil
    ) {
        // Created here (not as a default argument) because the monitor is main-actor isolated.
        let connectivity = connectivity ?? ConnectivityMonitor()
        self.realtime = FeedRealtimeClient(fetchEndpoint: { try await repository.feedEndpoint() })
        self.repository = repository
        self.localStore = localStore
        self.pendingStore = pendingStore
        self.connectivity = connectivity
        refreshPendingCount()

        connectivity.onReconnect = { [weak self] in
            Task { await self?.sync(trigger: .reconnect) }
        }
    }

    // MARK: - Live sync

    /// Syncs now, then stays subscribed to the realtime feed channel until cancelled:
    /// every "new photo" event, and every (re)connect, refreshes the feed.
    /// Run it from a `.task(id: scenePhase)` so it only runs while the app is active.
    func runLiveSync() async {
        await sync(trigger: .foreground)
        await realtime.run(
            // Events sent while we were disconnected are lost, so catch up on every connect.
            onReady: { [weak self] in Task { @MainActor in await self?.sync(trigger: .background) } },
            onEvent: { [weak self] in Task { @MainActor in await self?.sync(trigger: .background) } }
        )
    }

    /// Runs one sync. A call made while a sync is running is coalesced into one
    /// follow-up run, so a reconnect or pull-to-refresh is never silently dropped.
    func sync(trigger: SyncTrigger = .manual, limit: Int? = nil) async {
        if syncRunning {
            resyncRequested = true
            if trigger != .background { forceUploadRetry = true }
            return
        }
        syncRunning = true
        var current = trigger
        repeat {
            resyncRequested = false
            let ignoreBackoff = current != .background || forceUploadRetry
            forceUploadRetry = false
            isSyncing = current != .background
            await performSync(ignoreBackoff: ignoreBackoff, limit: limit)
            current = .background
        } while resyncRequested
        isSyncing = false
        syncRunning = false
    }

    // MARK: - Capture

    /// Called by `CameraView` after a capture. Saves the photo durably and shows it in the
    /// grid immediately, then uploads in the background. Returns quickly, online or not.
    func handleCapture(image: UIImage) async {
        let photoId   = UUID().uuidString
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let deviceId  = AppConfig.deviceId

        // Reserve first so a background sync can't pick this photo up half-saved.
        guard reserve(photoId) else { return }

        let jpegData: Data
        do {
            jpegData = try await encoder.jpegData(from: image)
        } catch {
            release(photoId)
            lastSyncError = error
            return
        }
        let thumbnailData = await encoder.thumbnailJPEG(from: image)

        do {
            // 1. Durable copy first: from here on the photo survives offline use and app kills.
            try pendingStore.save(jpegData, photoId: photoId)
            // 2. Local record (with thumbnail) so the grid shows it right away.
            try await localStore.upsertPhoto(
                photoId:       photoId,
                totalChunks:   0,
                createdAt:     createdAt,
                deviceId:      deviceId,
                syncStatus:    .pending,
                thumbnailData: thumbnailData
            )
        } catch {
            pendingStore.remove(photoId: photoId)
            release(photoId)
            lastSyncError = error
            return
        }
        refreshPendingCount()

        // 3. Upload without blocking the camera screen.
        Task {
            await self.runUpload(
                photoId:       photoId,
                createdAt:     createdAt,
                deviceId:      deviceId,
                thumbnailData: thumbnailData,
                jpegData:      jpegData
            )
        }
    }

    // MARK: - Pull + push

    private func performSync(ignoreBackoff: Bool, limit: Int?) async {
        guard connectivity.isOnline else { return }   // queued photos wait for reconnect

        let photoLimit = limit ?? (UserDefaults.standard.integer(forKey: AppConfig.photoLimitKey)
            .nonZero ?? AppConfig.defaultPhotoLimit)

        do {
            // Pull the shared feed. The server skips thumbnails we already hold.
            let known = try await localStore.photoIdsWithThumbnails(limit: 200)
            let feed  = try await repository.listRecentPhotos(limit: photoLimit, knownPhotoIds: known)
            for meta in feed {
                try await localStore.upsertPhoto(
                    photoId:       meta.photoId,
                    totalChunks:   meta.totalChunks,
                    createdAt:     meta.createdAt,
                    deviceId:      meta.deviceId,
                    syncStatus:    .synced,
                    thumbnailData: meta.thumbnailBase64.isEmpty
                        ? nil : Data(base64Encoded: meta.thumbnailBase64)
                )
            }
            lastSyncError = nil

            // The server answered, so this is a good moment to push queued photos.
            let recovered = serverWasUnreachable
            serverWasUnreachable = false
            await uploadPendingPhotos(ignoreBackoff: ignoreBackoff || recovered)
        } catch {
            serverWasUnreachable = true
            lastSyncError = error
        }
    }

    /// Uploads every queued photo, oldest first, one photo at a time.
    private func uploadPendingPhotos(ignoreBackoff: Bool) async {
        var queued: [LocalStore.PhotoSnapshot] = []
        for photoId in pendingStore.pendingPhotoIds() where !inFlightUploads.contains(photoId) {
            if let snapshot = try? await localStore.snapshot(photoId: photoId) {
                queued.append(snapshot)
            }
        }
        queued.sort { $0.createdAt < $1.createdAt }

        for snapshot in queued {
            guard connectivity.isOnline else { break }
            if !ignoreBackoff,
               let notBefore = retryNotBefore[snapshot.photoId], notBefore > Date() {
                continue   // failed recently; wait for the back-off to elapse
            }
            guard reserve(snapshot.photoId) else { continue }
            guard let jpegData = pendingStore.load(photoId: snapshot.photoId) else {
                release(snapshot.photoId)
                continue
            }
            await runUpload(
                photoId:       snapshot.photoId,
                createdAt:     snapshot.createdAt,
                deviceId:      snapshot.deviceId,
                thumbnailData: snapshot.thumbnailData,
                jpegData:      jpegData
            )
        }
    }

    /// Uploads one photo's chunks, then publishes it to the shared feed.
    /// The caller must have called `reserve(photoId)`; this releases it when done.
    /// Safe to repeat: chunks and the feed entry are overwritten by key.
    private func runUpload(
        photoId:       String,
        createdAt:     String,
        deviceId:      String,
        thumbnailData: Data?,
        jpegData:      Data
    ) async {
        defer { release(photoId) }

        guard connectivity.isOnline else {
            try? await localStore.updateSyncStatus(.pending, for: photoId)   // waits for reconnect
            return
        }

        do {
            try await localStore.updateSyncStatus(.uploading, for: photoId)

            let chunks = await encoder.encode(jpegData: jpegData)
            try await localStore.upsertPhoto(          // records the chunk count
                photoId:     photoId,
                totalChunks: chunks.count,
                createdAt:   createdAt,
                deviceId:    deviceId
            )

            try await repository.uploadChunks(
                photoId:   photoId,
                chunks:    chunks,
                createdAt: createdAt,
                deviceId:  deviceId
            )

            // Publish only after every chunk is stored, so others never see a partial photo.
            var thumbnail = thumbnailData
            if thumbnail == nil, let image = UIImage(data: jpegData) {
                thumbnail = await encoder.thumbnailJPEG(from: image)
            }
            try await repository.publishPhoto(
                photoId:         photoId,
                totalChunks:     chunks.count,
                createdAt:       createdAt,
                deviceId:        deviceId,
                thumbnailBase64: thumbnail?.base64EncodedString() ?? ""
            )
        } catch {
            noteFailure(photoId)
            try? await localStore.updateSyncStatus(.failed, for: photoId)
            lastSyncError = error
            return
        }

        // Published: the photo no longer needs to be queued.
        pendingStore.remove(photoId: photoId)
        failureCount[photoId] = nil
        retryNotBefore[photoId] = nil
        refreshPendingCount()
        try? await localStore.updateSyncStatus(.synced, for: photoId)
    }

    // MARK: - Bookkeeping

    @discardableResult
    private func reserve(_ photoId: String) -> Bool {
        let inserted = inFlightUploads.insert(photoId).inserted
        isUploading = !inFlightUploads.isEmpty
        return inserted
    }

    private func release(_ photoId: String) {
        inFlightUploads.remove(photoId)
        isUploading = !inFlightUploads.isEmpty
    }

    private func refreshPendingCount() {
        pendingUploadCount = pendingStore.pendingPhotoIds().count
    }

    /// Exponential back-off for automatic retries of a failed photo.
    private func noteFailure(_ photoId: String) {
        let failures = (failureCount[photoId] ?? 0) + 1
        failureCount[photoId] = failures
        let delay = min(
            AppConfig.uploadRetryBaseDelay * pow(2.0, Double(failures - 1)),
            AppConfig.uploadRetryMaxDelay
        )
        retryNotBefore[photoId] = Date().addingTimeInterval(delay)
        scheduleRetryTimer()
    }

    /// There is no polling any more, so failed uploads need their own wake-up:
    /// sync once the earliest back-off has elapsed. A sync that fails again
    /// reschedules through `noteFailure`.
    private func scheduleRetryTimer() {
        guard let due = retryNotBefore.values.min() else { return }
        retryTimer?.cancel()
        let delay = max(0, due.timeIntervalSinceNow) + 0.5
        retryTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.sync(trigger: .background)
        }
    }
}

// MARK: - Helpers

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

extension UIImage {
    /// Square, center-cropped (aspect-fill) thumbnail — no letterbox bars.
    func thumbnail(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // size is already in pixels; keeps the payload small
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let rect = aspectFillRect(in: CGRect(origin: .zero, size: size))
            draw(in: rect)
        }
    }

    private func aspectFillRect(in bounds: CGRect) -> CGRect {
        let wRatio = bounds.width  / self.size.width
        let hRatio = bounds.height / self.size.height
        let scale  = max(wRatio, hRatio)
        let w = self.size.width  * scale
        let h = self.size.height * scale
        return CGRect(
            x: bounds.minX + (bounds.width  - w) / 2,
            y: bounds.minY + (bounds.height - h) / 2,
            width: w, height: h
        )
    }
}
