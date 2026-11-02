import Foundation

/// Durable queue of photos that have been captured but not yet published.
///
/// Each pending photo is its original JPEG on disk, named `<photoId>.jpg`.
/// **A file exists  ⇔  the photo still has to be uploaded.** The file is written
/// before anything else happens at capture time and removed only after the photo
/// is published, so photos taken offline (or interrupted by an app kill) survive
/// restarts and can be uploaded whenever the network is back.
struct PendingUploadStore: Sendable {

    private let directory: URL

    /// - Parameter directory: Override for tests. Defaults to
    ///   `Application Support/PendingUploads` (backed up, never purged by the system).
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingUploads", isDirectory: true)
        self.directory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Persists the JPEG for `photoId` atomically.
    func save(_ jpegData: Data, photoId: String) throws {
        try jpegData.write(
            to: fileURL(for: photoId),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    /// Returns the stored JPEG, or `nil` if the photo is not pending.
    func load(photoId: String) -> Data? {
        try? Data(contentsOf: fileURL(for: photoId))
    }

    /// Removes the photo from the queue (call after it has been published).
    func remove(photoId: String) {
        try? FileManager.default.removeItem(at: fileURL(for: photoId))
    }

    func contains(photoId: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: photoId).path)
    }

    /// IDs of all photos still waiting to be uploaded (unordered).
    func pendingPhotoIds() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "jpg" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    // MARK: - Private

    private func fileURL(for photoId: String) -> URL {
        directory.appendingPathComponent(photoId).appendingPathExtension("jpg")
    }
}
