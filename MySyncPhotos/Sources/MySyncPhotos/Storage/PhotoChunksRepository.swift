import Foundation
import BlocksRuntime

/// Wraps the generated `Api` with retry logic and domain-level types.
/// The rest of the app never touches the raw generated API directly.
actor PhotoChunksRepository {

    // MARK: - Dependencies

    private let api: Api
    /// Same server as `api`; used for calls whose generated wrapper loses data.
    private let rawClient: BlocksClient

    // MARK: - Init

    init(api: Api, server: BlocksServer) {
        self.api = api
        self.rawClient = BlocksClient(server: server)
    }

    // MARK: - Upload

    /// Uploads all chunks for a photo concurrently, retrying failures with
    /// exponential back-off up to `AppConfig.maxUploadRetries` times.
    func uploadChunks(
        photoId:   String,
        chunks:    [String],
        createdAt: String,
        deviceId:  String
    ) async throws {
        let total = chunks.count
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, chunkData) in chunks.enumerated() {
                group.addTask {
                    try await self.uploadChunk(
                        photoId:     photoId,
                        chunkIndex:  index,
                        totalChunks: total,
                        chunkData:   chunkData,
                        createdAt:   createdAt,
                        deviceId:    deviceId
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Shared feed

    /// Publishes a fully-uploaded photo to the shared feed (visible to all users).
    /// Call only after `uploadChunks` has succeeded.
    func publishPhoto(
        photoId:         String,
        totalChunks:     Int,
        createdAt:       String,
        deviceId:        String,
        thumbnailBase64: String
    ) async throws {
        _ = try await api.putPhoto(
            photoId:     photoId,
            totalChunks: Double(totalChunks),
            createdAt:   createdAt,
            deviceId:    deviceId,
            thumbnail:   thumbnailBase64
        )
    }

    /// Returns the N newest photos across ALL users, newest first.
    /// `thumbnailBase64` is empty for photos listed in `knownPhotoIds`
    /// (the caller already has their thumbnails).
    func listRecentPhotos(limit: Int, knownPhotoIds: [String]) async throws -> [PhotoMeta] {
        // Generated method takes Double for the limit parameter.
        let result = try await api.listRecentPhotos(limit: Double(limit), knownPhotoIds: knownPhotoIds)
        return result.map {
            PhotoMeta(
                photoId:         $0.photoId,
                totalChunks:     Int($0.totalChunks),
                createdAt:       $0.createdAt,
                deviceId:        $0.deviceId,
                thumbnailBase64: $0.thumbnail
            )
        }
    }

    // MARK: - Realtime

    /// Fresh descriptor for the live-update channel.
    ///
    /// Calls `api.getFeedChannel` directly instead of through the generated
    /// `Api.getFeedChannel()`: the generated version drops `connectToken`, which the
    /// deployed (AWS) WebSocket requires on connect (`?token=`).
    func feedEndpoint() async throws -> FeedRealtimeClient.Endpoint {
        let request = BlocksRequest(method: "api.getFeedChannel", params: [], id: BlocksRequest.nextId())
        guard let data = try await rawClient.execute(request),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCError(message: "Invalid channel descriptor for api.getFeedChannel")
        }
        return try FeedRealtimeClient.Endpoint(descriptor: json, baseHost: BlocksClient.baseHost)
    }

    // MARK: - Download chunks (lazy)

    /// Fetches all chunks for a photo ordered by chunkIndex.
    /// Called lazily only when the user taps a photo.
    func fetchChunks(photoId: String) async throws -> [String] {
        let items = try await api.getPhotoChunks(photoId: photoId)
        // Sort by chunkIndex (Double in generated type) ascending.
        let sorted = items.sorted { $0.chunkIndex < $1.chunkIndex }
        return sorted.map(\.chunkData)
    }

    // MARK: - Resume support

    /// Returns the set of chunk indices already uploaded for a photo.
    func uploadedChunkIndices(photoId: String) async throws -> Set<Int> {
        let indices = try await api.getUploadedChunkIndices(photoId: photoId)
        return Set(indices.map { Int($0) })
    }

    // MARK: - Private helpers

    private func uploadChunk(
        photoId:     String,
        chunkIndex:  Int,
        totalChunks: Int,
        chunkData:   String,
        createdAt:   String,
        deviceId:    String
    ) async throws {
        var lastError: Error?
        for attempt in 0..<AppConfig.maxUploadRetries {
            do {
                // Generated method uses Double for numeric params.
                _ = try await api.putChunk(
                    photoId:     photoId,
                    chunkIndex:  Double(chunkIndex),
                    totalChunks: Double(totalChunks),
                    chunkData:   chunkData,
                    createdAt:   createdAt,
                    deviceId:    deviceId
                )
                return
            } catch {
                lastError = error
                let delay = AppConfig.retryBaseDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw RepositoryError.uploadFailed(
            photoId:    photoId,
            chunkIndex: chunkIndex,
            underlying: lastError
        )
    }
}

// MARK: - Domain types

struct PhotoMeta: Sendable {
    let photoId:         String
    let totalChunks:     Int
    let createdAt:       String
    let deviceId:        String
    let thumbnailBase64: String
}

// MARK: - Errors

enum RepositoryError: LocalizedError {
    case uploadFailed(photoId: String, chunkIndex: Int, underlying: Error?)

    var errorDescription: String? {
        switch self {
        case let .uploadFailed(photoId, chunkIndex, underlying):
            let base = "Failed to upload chunk \(chunkIndex) of photo \(photoId)"
            if let err = underlying { return "\(base): \(err.localizedDescription)" }
            return base
        }
    }
}
