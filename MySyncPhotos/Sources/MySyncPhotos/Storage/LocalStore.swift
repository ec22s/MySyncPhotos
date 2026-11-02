import CoreData
import UIKit

/// Core Data stack that persists `PhotoRecord` entities on-device.
/// Use `LocalStore` to query and update sync state without hitting the network.
final class LocalStore: @unchecked Sendable {

    // MARK: - Core Data stack

    private let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// One shared programmatic model (no .xcdatamodeld file). Creating several
    /// instances of the same model causes Core Data class-registration warnings.
    private static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()
        model.entities = [PhotoRecord.entityDescription()]
        return model
    }()

    init() {
        container = NSPersistentContainer(name: "MySyncPhotos", managedObjectModel: Self.model)
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
        container.loadPersistentStores { _, error in
            if let error {
                // In production, surface this to the user instead of crashing.
                fatalError("Core Data failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Background context helper

    func performBackgroundTask<T: Sendable>(
        _ block: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { ctx in
                do {
                    let result = try block(ctx)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - CRUD

    /// Upsert a photo record. If a record with `photoId` already exists, only
    /// update fields that differ — preserving the local thumbnail if present.
    func upsertPhoto(
        photoId:       String,
        totalChunks:   Int,
        createdAt:     String,
        deviceId:      String,
        syncStatus:    SyncStatus = .pending,
        thumbnailData: Data? = nil
    ) async throws {
        try await performBackgroundTask { ctx in
            let record = try Self.fetchOrCreate(photoId: photoId, context: ctx)
            // Last-upload wins: only overwrite if incoming createdAt is newer.
            if let existing = record.createdAt, existing >= createdAt {
                // Same photo version — keep it, but fill in the chunk count once known
                // (a fresh capture is first saved with totalChunks = 0).
                // Only write when different: repeated feed syncs must not cause needless saves.
                if totalChunks > 0, record.totalChunks != Int32(totalChunks) {
                    record.totalChunks = Int32(totalChunks)
                }
                // Adopt the shared thumbnail only if we don't have one yet.
                if record.thumbnailData == nil, let thumbnailData {
                    record.thumbnailData = thumbnailData
                }
                if record.syncStatusEnum == .failed {
                    record.syncStatusEnum = .pending
                }
            } else {
                record.photoId      = photoId
                record.totalChunks  = Int32(totalChunks)
                record.createdAt    = createdAt
                record.deviceId     = deviceId
                record.syncStatusEnum = syncStatus
                // A newer version replaces the old thumbnail (nil until one is supplied).
                record.thumbnailData = thumbnailData
            }
            try ctx.save()
        }
    }

    /// Save a compressed thumbnail for a photo.
    func saveThumbnail(_ image: UIImage, for photoId: String) async throws {
        let data = image.jpegData(compressionQuality: 0.5)
        try await performBackgroundTask { ctx in
            let record = try Self.fetchOrCreate(photoId: photoId, context: ctx)
            record.thumbnailData = data
            try ctx.save()
        }
    }

    /// Fetch all photo records sorted by `createdAt` descending.
    func fetchPhotos(limit: Int) throws -> [PhotoRecord] {
        let request = PhotoRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = limit
        return try viewContext.fetch(request)
    }

    /// Update the sync status of a photo.
    func updateSyncStatus(_ status: SyncStatus, for photoId: String) async throws {
        try await performBackgroundTask { ctx in
            let record = try Self.fetchOrCreate(photoId: photoId, context: ctx)
            record.syncStatusEnum = status
            try ctx.save()
        }
    }

    /// Sendable copy of the fields needed to (re)upload a photo.
    struct PhotoSnapshot: Sendable {
        let photoId:       String
        let createdAt:     String
        let deviceId:      String
        let thumbnailData: Data?
    }

    /// Reads one photo's upload-relevant fields from a background context
    /// (always sees committed data, unlike the main context right after a save).
    func snapshot(photoId: String) async throws -> PhotoSnapshot? {
        try await performBackgroundTask { ctx in
            let request = PhotoRecord.fetchRequest()
            request.predicate = NSPredicate(format: "photoId == %@", photoId)
            request.fetchLimit = 1
            guard let record = try ctx.fetch(request).first,
                  let createdAt = record.createdAt else { return nil }
            return PhotoSnapshot(
                photoId:       photoId,
                createdAt:     createdAt,
                deviceId:      record.deviceId ?? AppConfig.deviceId,
                thumbnailData: record.thumbnailData
            )
        }
    }

    /// IDs of the newest photos for which a thumbnail is already stored.
    /// Sent to the server so it can skip re-sending those thumbnails.
    func photoIdsWithThumbnails(limit: Int) async throws -> [String] {
        try await performBackgroundTask { ctx in
            let request = PhotoRecord.fetchRequest()
            request.predicate = NSPredicate(format: "thumbnailData != nil")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            request.fetchLimit = limit
            return try ctx.fetch(request).compactMap(\.photoId)
        }
    }

    /// Returns all photo IDs currently stored locally.
    func allLocalPhotoIds() throws -> Set<String> {
        let request = PhotoRecord.fetchRequest()
        request.propertiesToFetch = ["photoId"]
        let records = try viewContext.fetch(request)
        return Set(records.compactMap(\.photoId))
    }

    // MARK: - Private helpers

    private static func fetchOrCreate(
        photoId: String,
        context: NSManagedObjectContext
    ) throws -> PhotoRecord {
        let request = PhotoRecord.fetchRequest()
        request.predicate = NSPredicate(format: "photoId == %@", photoId)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        let new = PhotoRecord(context: context)
        new.photoId = photoId
        return new
    }
}

// MARK: - SyncStatus

enum SyncStatus: String, Sendable {
    case pending     = "pending"
    case uploading   = "uploading"
    case downloading = "downloading"
    case synced      = "synced"
    case failed      = "failed"
}

// MARK: - PhotoRecord (NSManagedObject subclass)

@objc(PhotoRecord)
public final class PhotoRecord: NSManagedObject, Identifiable {

    public var id: String { photoId ?? UUID().uuidString }

    @NSManaged public var photoId:      String?
    @NSManaged public var totalChunks:  Int32
    @NSManaged public var createdAt:    String?
    @NSManaged public var deviceId:     String?
    @NSManaged public var syncStatus:   String?
    @NSManaged public var thumbnailData: Data?

    var syncStatusEnum: SyncStatus {
        get { SyncStatus(rawValue: syncStatus ?? "") ?? .pending }
        set { syncStatus = newValue.rawValue }
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoRecord> {
        NSFetchRequest<PhotoRecord>(entityName: "PhotoRecord")
    }

    /// Programmatic entity description — avoids needing an .xcdatamodeld file.
    static func entityDescription() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "PhotoRecord"
        entity.managedObjectClassName = "MySyncPhotos.PhotoRecord"

        func attr(_ name: String, type: NSAttributeType, optional: Bool = true) -> NSAttributeDescription {
            let d = NSAttributeDescription()
            d.name = name
            d.attributeType = type
            d.isOptional = optional
            return d
        }

        entity.properties = [
            attr("photoId",      type: .stringAttributeType),
            attr("totalChunks",  type: .integer32AttributeType, optional: false),
            attr("createdAt",    type: .stringAttributeType),
            attr("deviceId",     type: .stringAttributeType),
            attr("syncStatus",   type: .stringAttributeType),
            attr("thumbnailData", type: .binaryDataAttributeType),
        ]
        return entity
    }
}
