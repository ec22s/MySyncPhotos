/**
 * Backend — aws-blocks/index.ts
 *
 * MySyncPhotos: photo chunk storage and retrieval.
 * No authentication required. Each photo is split into Base64 chunks (<400 KiB)
 * and stored in a DistributedTable. The iOS app syncs the N newest photos.
 */
import { ApiNamespace, ApiError, Scope, DistributedTable, Realtime } from '@aws-blocks/blocks';
import type { RealtimeChannel } from '@aws-blocks/blocks';
import { z } from 'zod';

export type { RealtimeChannel } from '@aws-blocks/blocks';

const scope = new Scope('mysyncphotos');

// ─── Data ────────────────────────────────────────────────────────────────────
// Each item represents one chunk of a photo's Base64-encoded JPEG data.
const chunkSchema = z.object({
  photoId:     z.string(),   // partition key — UUID v4 identifying the photo
  chunkIndex:  z.number(),   // sort key     — zero-based chunk position
  totalChunks: z.number(),   // total number of chunks for this photo
  chunkData:   z.string(),   // Base64-encoded chunk (<400 KiB)
  createdAt:   z.string(),   // ISO-8601 capture timestamp (same for all chunks of a photo)
  deviceId:    z.string(),   // UUID of the uploading device
});

export type PhotoChunk = z.infer<typeof chunkSchema>;

const photoChunks = new DistributedTable(scope, 'photoChunks', {
  schema: chunkSchema,
  key: { partitionKey: 'photoId', sortKey: 'chunkIndex' },
  // GSI: look up all chunks of a photo by photoId alone (no sort key needed,
  // but having createdAt as sort key lets us scan recently uploaded photos).
  indexes: {
    'photoId-createdAt-index': { partitionKey: 'photoId', sortKey: 'createdAt' },
  },
});

// One row per photo, shared by ALL app users (no per-user key, no auth).
// Holds only lightweight metadata + a small thumbnail so the shared feed can be
// listed without reading any image chunks. A row is written only AFTER every
// chunk of the photo has been uploaded, so a listed photo is always complete.
const photoSchema = z.object({
  photoId:     z.string(),   // primary key — UUID v4
  feed:        z.string(),   // constant 'all' — index partition key for the shared feed
  createdAt:   z.string(),   // ISO-8601 capture timestamp (feed index sort key)
  totalChunks: z.number(),
  deviceId:    z.string(),   // uploading device (informational)
  thumbnail:   z.string(),   // Base64 JPEG thumbnail (~tens of KB)
});

const SHARED_FEED = 'all';
const MAX_THUMBNAIL_CHARS = 300_000; // keep each item well under the 400 KB item limit

const photos = new DistributedTable(scope, 'photos', {
  schema: photoSchema,
  key: { partitionKey: 'photoId' },
  indexes: {
    'feed-createdAt': { partitionKey: 'feed', sortKey: 'createdAt' },
  },
});

// ─── Realtime ────────────────────────────────────────────────────────────────
// One shared channel. After a photo is published to the feed, a small event is
// pushed so every connected app refreshes at once (replaces client polling).
// Delivery is best-effort: clients also re-sync whenever they (re)connect.
const feedEventSchema = z.object({
  photoId:   z.string(),
  createdAt: z.string(),
});
export type FeedEvent = z.infer<typeof feedEventSchema>;

const realtime = new Realtime(scope, 'live', {
  namespaces: {
    feed: Realtime.namespace(feedEventSchema),
  },
});

// ─── API ─────────────────────────────────────────────────────────────────────
export const api = new ApiNamespace(scope, 'api', (_context) => ({

  /**
   * Channel that announces new photos in the shared feed. No auth: the app has
   * no login, and clients can only subscribe (publishing is server-side only).
   */
  async getFeedChannel(): Promise<RealtimeChannel<FeedEvent>> {
    return realtime.getChannel('feed', SHARED_FEED);
  },

  /**
   * Upload a single chunk.
   * The iOS app calls this for every chunk of a photo in parallel.
   * Last-upload wins: a newer write with the same (photoId, chunkIndex) key
   * simply overwrites the existing item — no conditional check needed.
   */
  async putChunk(
    photoId:     string,
    chunkIndex:  number,
    totalChunks: number,
    chunkData:   string,
    createdAt:   string,
    deviceId:    string,
  ): Promise<{ success: boolean }> {
    await photoChunks.put({
      photoId,
      chunkIndex,
      totalChunks,
      chunkData,
      createdAt,
      deviceId,
    });
    return { success: true };
  },

  /**
   * Upload multiple chunks in one call (batch).
   * DynamoDB batches cap at 25 items; the backend splits automatically via putBatch.
   */
  async putChunks(chunks: PhotoChunk[]): Promise<{ success: boolean; count: number }> {
    if (chunks.length === 0) return { success: true, count: 0 };
    await photoChunks.putBatch(chunks);
    return { success: true, count: chunks.length };
  },

  /**
   * Publish a photo to the shared feed. Call this AFTER all chunks are uploaded.
   * Same photoId published again overwrites the earlier entry (last upload wins).
   */
  async putPhoto(
    photoId:     string,
    totalChunks: number,
    createdAt:   string,
    deviceId:    string,
    thumbnail:   string,
  ): Promise<{ success: boolean }> {
    if (thumbnail.length > MAX_THUMBNAIL_CHARS) {
      throw new ApiError('thumbnail too large', 400, { name: 'InvalidArgument' });
    }
    await photos.put({
      photoId,
      feed: SHARED_FEED,
      createdAt,
      totalChunks,
      deviceId,
      thumbnail,
    });

    // Tell connected apps right away. The photo is already stored, so a failed
    // notification must not fail the upload (clients re-sync on reconnect anyway).
    try {
      await realtime.publish('feed', SHARED_FEED, { photoId, createdAt });
    } catch (error) {
      console.error('[putPhoto] realtime publish failed:', error);
    }
    return { success: true };
  },

  /**
   * List the N newest photos in the shared feed (all users), newest first.
   * One indexed query; image chunks are never read.
   *
   * `knownPhotoIds` are photos the client already holds a thumbnail for. For those
   * the `thumbnail` is returned as '' so periodic polling stays cheap: only photos
   * the client has not seen yet carry thumbnail data.
   */
  async listRecentPhotos(limit: number, knownPhotoIds: string[]): Promise<Array<{
    photoId:     string;
    totalChunks: number;
    createdAt:   string;
    deviceId:    string;
    thumbnail:   string;
  }>> {
    if (limit < 1 || limit > 100) {
      throw new ApiError('limit must be between 1 and 100', 400, { name: 'InvalidArgument' });
    }
    if (knownPhotoIds.length > 500) {
      throw new ApiError('knownPhotoIds must contain at most 500 ids', 400, { name: 'InvalidArgument' });
    }
    const known = new Set(knownPhotoIds);

    const items = await Array.fromAsync(
      photos.query({
        index: 'feed-createdAt',
        where: { feed: { equals: SHARED_FEED } },
        order: 'desc',
        limit,
      })
    );

    return items.map(({ photoId, totalChunks, createdAt, deviceId, thumbnail }) => ({
      photoId,
      totalChunks,
      createdAt,
      deviceId,
      thumbnail: known.has(photoId) ? '' : thumbnail,
    }));
  },

  /**
   * Get all chunks for a given photo, ordered by chunkIndex ascending.
   * The iOS app calls this lazily when the user taps a photo to view it.
   */
  async getPhotoChunks(photoId: string): Promise<PhotoChunk[]> {
    const chunks = await Array.fromAsync(
      photoChunks.query({ where: { photoId: { equals: photoId } } })
    ) as PhotoChunk[];

    if (chunks.length === 0) {
      throw new ApiError('Photo not found', 404, { name: 'PhotoNotFoundException' });
    }
    return chunks.sort((a, b) => a.chunkIndex - b.chunkIndex);
  },

  /**
   * Check which chunk indices have already been uploaded for a photo.
   * Used by the sync engine to resume interrupted uploads without re-uploading
   * chunks that already exist in the cloud.
   */
  async getUploadedChunkIndices(photoId: string): Promise<number[]> {
    const chunks = await Array.fromAsync(
      photoChunks.query({ where: { photoId: { equals: photoId } } })
    ) as PhotoChunk[];

    return chunks.map(c => c.chunkIndex).sort((a, b) => a - b);
  },
}));
