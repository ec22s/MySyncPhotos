//
// API.swift
// Auto-generated from OpenRPC spec — do not edit.
//

import Foundation
import BlocksRuntime

public class Api {
    private let client: BlocksClient

    public init(server: BlocksServer = Servers.local) {
        self.client = BlocksClient(server: server)
    }

    /// Calls `api.getFeedChannel`.
    public func getFeedChannel() async throws -> RealtimeChannel<GetFeedChannel.ResultMessage> {
        let request = BlocksRequest(method: "api.getFeedChannel", params: [], id: BlocksRequest.nextId())
        let result = try await client.execute(request)
        guard let result else { throw RPCError(message: "Unexpected null result for api.getFeedChannel") }
        guard let descriptor = try JSONSerialization.jsonObject(with: result) as? [String: Any] else {
            throw RPCError(message: "Invalid channel descriptor for api.getFeedChannel")
        }
        return RealtimeChannel<GetFeedChannel.ResultMessage>.fromJSON(descriptor, baseHost: BlocksClient.baseHost) { data in
            try JSONDecoder().decode(GetFeedChannel.ResultMessage.self, from: data)
        }
    }

    /// Calls `api.getPhotoChunks`.
    public func getPhotoChunks(photoId: String) async throws -> [GetPhotoChunks.Result] {
        let request = BlocksRequest(method: "api.getPhotoChunks", params: [photoId], id: BlocksRequest.nextId())
        let result = try await client.execute(request)
        guard let result else { throw RPCError(message: "Unexpected null result for api.getPhotoChunks") }
        return try JSONDecoder().decode([GetPhotoChunks.Result].self, from: result)
    }

    /// Calls `api.getUploadedChunkIndices`.
    public func getUploadedChunkIndices(photoId: String) async throws -> [Double] {
        let request = BlocksRequest(method: "api.getUploadedChunkIndices", params: [photoId], id: BlocksRequest.nextId())
        let result = try await client.execute(request)
        guard let result else { throw RPCError(message: "Unexpected null result for api.getUploadedChunkIndices") }
        return try JSONDecoder().decode([Double].self, from: result)
    }

    /// Calls `api.listRecentPhotos`.
    public func listRecentPhotos(limit: Double, knownPhotoIds: [String]) async throws -> [ListRecentPhotos.Result] {
        let request = BlocksRequest(method: "api.listRecentPhotos", params: [limit, knownPhotoIds], id: BlocksRequest.nextId())
        let result = try await client.execute(request)
        guard let result else { throw RPCError(message: "Unexpected null result for api.listRecentPhotos") }
        return try JSONDecoder().decode([ListRecentPhotos.Result].self, from: result)
    }

    /// Calls `api.putChunk`.
    public func putChunk(photoId: String, chunkIndex: Double, totalChunks: Double, chunkData: String, createdAt: String, deviceId: String) async throws -> PutChunk.Result {
        let request = BlocksRequest(method: "api.putChunk", params: [photoId, chunkIndex, totalChunks, chunkData, createdAt, deviceId], id: BlocksRequest.nextId())
        let result = try await client.execute(request)
        guard let result else { throw RPCError(message: "Unexpected null result for api.putChunk") }
        return try JSONDecoder().decode(PutChunk.Result.self, from: result)
    }

    /// Calls `api.putChunks`.
    public func putChunks(chunks: [PutChunks.Chunk]) async throws -> PutChunks.Result {
        let request = BlocksRequest(method: "api.putChunks", params: [chunks], id: BlocksRequest.nextId())
        let result = try await client.execute(request)
        guard let result else { throw RPCError(message: "Unexpected null result for api.putChunks") }
        return try JSONDecoder().decode(PutChunks.Result.self, from: result)
    }

    /// Calls `api.putPhoto`.
    public func putPhoto(photoId: String, totalChunks: Double, createdAt: String, deviceId: String, thumbnail: String) async throws -> PutPhoto.Result {
        let request = BlocksRequest(method: "api.putPhoto", params: [photoId, totalChunks, createdAt, deviceId, thumbnail], id: BlocksRequest.nextId())
        let result = try await client.execute(request)
        guard let result else { throw RPCError(message: "Unexpected null result for api.putPhoto") }
        return try JSONDecoder().decode(PutPhoto.Result.self, from: result)
    }

    public enum GetFeedChannel {

        public struct ResultMessage: Codable {
            public let createdAt: String
            public let photoId: String
        }
    }

    public enum GetPhotoChunks {

        public struct Result: Codable {
            public let chunkData: String
            public let chunkIndex: Double
            public let createdAt: String
            public let deviceId: String
            public let photoId: String
            public let totalChunks: Double
        }
    }

    public enum ListRecentPhotos {

        public struct Result: Codable {
            public let createdAt: String
            public let deviceId: String
            public let photoId: String
            public let thumbnail: String
            public let totalChunks: Double
        }
    }

    public enum PutChunk {

        public struct Result: Codable {
            public let success: Bool
        }
    }

    public enum PutChunks {

        public struct Chunk: Codable {
            public let chunkData: String
            public let chunkIndex: Double
            public let createdAt: String
            public let deviceId: String
            public let photoId: String
            public let totalChunks: Double
        }

        public struct Result: Codable {
            public let count: Double
            public let success: Bool
        }
    }

    public enum PutPhoto {

        public struct Result: Codable {
            public let success: Bool
        }
    }
}


// MARK: - Servers

public enum Servers {
    public static let local = BlocksServer(name: "local", url: "http://localhost:3000/aws-blocks/api")
}
