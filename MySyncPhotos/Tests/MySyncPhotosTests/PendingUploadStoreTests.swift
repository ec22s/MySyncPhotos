import Testing
import Foundation
@testable import MySyncPhotos

/// The pending-upload queue is what lets photos taken offline survive until the
/// network returns, so its behaviour is worth pinning down.
@Suite("PendingUploadStore")
struct PendingUploadStoreTests {

    /// A store backed by a unique temp directory, plus a cleanup closure.
    private func makeStore() -> (store: PendingUploadStore, cleanup: () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-\(UUID().uuidString)", isDirectory: true)
        return (PendingUploadStore(directory: dir),
                { try? FileManager.default.removeItem(at: dir) })
    }

    @Test("Saved photo can be loaded back byte-for-byte")
    func saveAndLoad() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let bytes = Data((0..<1000).map { UInt8($0 % 256) })

        try store.save(bytes, photoId: "photo-1")

        #expect(store.load(photoId: "photo-1") == bytes)
        #expect(store.contains(photoId: "photo-1"))
    }

    @Test("A saved photo is pending until it is removed")
    func pendingUntilRemoved() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try store.save(Data([1, 2, 3]), photoId: "photo-1")
        #expect(store.pendingPhotoIds() == ["photo-1"])

        store.remove(photoId: "photo-1")
        #expect(store.pendingPhotoIds().isEmpty)
        #expect(store.load(photoId: "photo-1") == nil)
        #expect(!store.contains(photoId: "photo-1"))
    }

    @Test("Unknown photo id loads as nil and removing it is harmless")
    func unknownPhoto() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        #expect(store.load(photoId: "nope") == nil)
        store.remove(photoId: "nope")   // must not crash
        #expect(store.pendingPhotoIds().isEmpty)
    }

    @Test("All queued photos are listed")
    func listsAllPendingPhotos() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try store.save(Data([1]), photoId: "a")
        try store.save(Data([2]), photoId: "b")
        try store.save(Data([3]), photoId: "c")

        #expect(Set(store.pendingPhotoIds()) == ["a", "b", "c"])
    }

    @Test("Saving the same photo again replaces the stored bytes")
    func overwrite() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try store.save(Data([1, 1, 1]), photoId: "photo-1")
        try store.save(Data([9, 9]), photoId: "photo-1")

        #expect(store.load(photoId: "photo-1") == Data([9, 9]))
        #expect(store.pendingPhotoIds().count == 1)
    }

    @Test("The queue persists across store instances (survives an app restart)")
    func survivesRestart() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try PendingUploadStore(directory: dir).save(Data([7, 7, 7]), photoId: "offline-photo")

        let afterRestart = PendingUploadStore(directory: dir)
        #expect(afterRestart.pendingPhotoIds() == ["offline-photo"])
        #expect(afterRestart.load(photoId: "offline-photo") == Data([7, 7, 7]))
    }
}
