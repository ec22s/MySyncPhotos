import Testing
import Foundation
@testable import MySyncPhotos

/// Tests that PhotoMeta round-trips through expected field types.
/// These don't touch the network — they validate our domain types.
@Suite("PhotoMeta serialization")
struct PhotoChunksSerializerTests {

    @Test("PhotoMeta fields are preserved")
    func fieldPreservation() {
        let meta = PhotoMeta(
            photoId:         "PHOTO-001",
            totalChunks:     3,
            createdAt:       "2026-10-31T10:00:00Z",
            deviceId:        "DEVICE-001",
            thumbnailBase64: "dGh1bWI="
        )
        #expect(meta.photoId         == "PHOTO-001")
        #expect(meta.totalChunks     == 3)
        #expect(meta.createdAt       == "2026-10-31T10:00:00Z")
        #expect(meta.deviceId        == "DEVICE-001")
        #expect(meta.thumbnailBase64 == "dGh1bWI=")
    }

    @Test("createdAt ISO-8601 parses to valid Date")
    func isoDateParsing() {
        let iso = "2026-10-31T10:00:00Z"
        let date = ISO8601DateFormatter().date(from: iso)
        #expect(date != nil)
    }

    @Test("AppConfig.maxChunkBytes is less than 400 KiB")
    func chunkSizeConstant() {
        #expect(AppConfig.maxChunkBytes < 400 * 1024)
        #expect(AppConfig.maxChunkBytes > 0)
    }

    @Test("AppConfig.deviceId is stable across calls")
    func deviceIdStability() {
        let id1 = AppConfig.deviceId
        let id2 = AppConfig.deviceId
        #expect(id1 == id2)
        #expect(UUID(uuidString: id1) != nil, "deviceId should be a valid UUID")
    }

    @Test("SyncStatus raw values match expected strings")
    func syncStatusRawValues() {
        #expect(SyncStatus.pending.rawValue     == "pending")
        #expect(SyncStatus.uploading.rawValue   == "uploading")
        #expect(SyncStatus.downloading.rawValue == "downloading")
        #expect(SyncStatus.synced.rawValue      == "synced")
        #expect(SyncStatus.failed.rawValue      == "failed")
    }
}
