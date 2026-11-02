# MySyncPhotos — Requirements

_Last updated: 2026-10-31. Describes the app as currently built; see "Status and Known Gaps" for what is not done yet._

## Overview

MySyncPhotos is an iOS application that captures photos with the device rear camera, encodes them as Base64, splits them into chunks smaller than 400 KiB, and stores the chunks in the cloud. **All app users share one photo feed:** every photo any user takes is stored in the same database, and every app instance displays the newest photos from that shared feed. New photos from other users appear automatically, and photos taken while offline are uploaded automatically once the network is back. No login is required.

The backend is built with **AWS Blocks**: each Block (e.g. `DistributedTable`) runs locally with no AWS account required, and deploys to real AWS services (DynamoDB) without code changes. The iOS client uses the **BlocksRuntime** Swift package and a typed client generated from `blocks.spec.json`.

---

## Functional Requirements

### FR-1 Camera Capture

| ID | Requirement |
|----|-------------|
| FR-1.1 | The app shall capture photos using the built-in rear camera via `AVFoundation`. |
| FR-1.2 | A dedicated shutter button shall trigger a still-image capture. |
| FR-1.3 | Each captured photo shall be stored as a JPEG of **at most 640 KiB** (`AppConfig.maxPhotoBytes`). It is scaled down so its long edge is ≤ 2048 px (never scaled up), then saved at the highest JPEG quality between 0.8 and 0.3 that fits; if it still does not fit, it is scaled down further. The photo is drawn upright, so its orientation is part of the pixels rather than an EXIF tag. The 640 KiB JPEG becomes at most ~874 KB of Base64, i.e. at most 3 chunks. |
| FR-1.4 | The app shall request camera permission (`NSCameraUsageDescription`) the first time the camera screen opens, and handle denial with an alert that links to Settings. |
| FR-1.5 | Starting and stopping the `AVCaptureSession` shall run off the main thread. |
| FR-1.6 | Photos and the live preview shall be oriented to match the app's current interface orientation (portrait, upside-down, landscape left/right), on iPhone and iPad, so a photo looks upright on every device that displays it. The orientation is applied to the photo output connection at capture time and to the preview connection on every layout pass (`CaptureOrientation`). |

### FR-2 Base64 Encoding

| ID | Requirement |
|----|-------------|
| FR-2.1 | Each captured JPEG shall be encoded to a Base64 string using `Data.base64EncodedString()`. |
| FR-2.2 | Encoding shall run on a background actor to keep the UI responsive. |

### FR-3 Chunk Splitting

| ID | Requirement |
|----|-------------|
| FR-3.1 | The Base64 string shall be split into sequential chunks whose UTF-8 size is **strictly less than 400 KiB (409,600 bytes)**. The configured chunk size is 380,000 bytes (`AppConfig.maxChunkBytes`). |
| FR-3.2 | Each chunk shall carry a zero-based `chunkIndex` and the photo's `totalChunks`. |
| FR-3.3 | All chunks of one photo shall share a `photoId` (UUID v4) and a `createdAt` timestamp (ISO-8601). |

### FR-4 Cloud Storage — AWS Blocks (`DistributedTable`)

| ID | Requirement |
|----|-------------|
| FR-4.1 | Image data shall be stored in a `DistributedTable` named `photoChunks`: one item per chunk. |
| FR-4.2 | `photoChunks` schema: `photoId` (String, partition key), `chunkIndex` (Number, sort key), `totalChunks` (Number), `chunkData` (String), `createdAt` (String, ISO-8601), `deviceId` (String). |
| FR-4.3 | The shared feed shall be stored in a second `DistributedTable` named `photos`: one item per photo, holding metadata and a thumbnail only (no chunk data). Schema in "Data Model". |
| FR-4.4 | `photos` shall have an index `feed-createdAt` (partition key `feed`, sort key `createdAt`) so the newest N photos are read with a single descending query. |
| FR-4.5 | Locally, `DistributedTable` persists to the `.bb-data/` directory (no AWS account or credentials). On AWS it provisions DynamoDB tables with the indexes. |
| FR-4.6 | Each chunk upload shall be attempted up to three times with exponential back-off (base 0.5 s) before the photo is marked `failed`. A failed photo is then retried automatically (FR-6.8). |
| FR-4.7 | All calls to the backend shall use Swift Concurrency (`async/await`) via the generated BlocksRuntime client. |

### FR-5 Photo Display

| ID | Requirement |
|----|-------------|
| FR-5.1 | The main screen shall display a grid of the newest photos from the shared feed, sorted by `createdAt` descending. The number of photos is user-configurable in Settings (4, 9, 16 or 25) with a default of 9. |
| FR-5.2 | Each cell shall show an aspect-fill thumbnail with rounded corners, a short capture timestamp, and a status badge when the photo is not `synced`. |
| FR-5.3 | Tapping a cell shall open the full-resolution photo in a modal sheet. Chunks are fetched and reassembled (chunk → Base64 → JPEG) **lazily at this point**, not before. |
| FR-5.4 | A photo with no thumbnail yet shall show a placeholder; a photo being uploaded by this device shall show a progress indicator. Photos listed in the shared feed are always complete (see FR-8.3). |
| FR-5.6 | The toolbar shall show the connection and upload state: "Offline" (with the number of photos waiting), "Syncing…", or "N waiting to upload". |
| FR-5.5 | The grid shall be a SwiftUI `LazyVGrid` with three columns. |

### FR-6 Synchronization

| ID | Requirement |
|----|-------------|
| FR-6.1 | The app shall sync on launch, when it returns to the foreground, on pull-to-refresh, when the network reconnects, when a realtime "new photo" event arrives or the realtime subscription is (re)established (FR-6.10), and when a failed upload is due for retry (FR-6.9). A sync queries the shared feed for the N newest photos, where N is the configured grid size. A sync requested while another is running is coalesced into one follow-up run, never dropped. |
| FR-6.2 | Feed photos not yet stored locally shall have their metadata **and thumbnail** saved to Core Data. The client sends the ids it already holds thumbnails for (`knownPhotoIds`) and the server returns an empty thumbnail for those, so a sync with nothing new transfers almost no image data. Chunk data shall not be downloaded until the user opens the photo. |
| FR-6.3 | A newly captured photo shall be written to the pending-upload queue (FR-6.8) and saved locally with its thumbnail at once, so it appears in the grid immediately and the camera screen closes without waiting for the network. It is then uploaded chunk by chunk in the background and finally published to the feed (FR-8.3). |
| FR-6.4 | Conflict rule — **last upload wins**: when a `photoId` exists both locally and in the feed with different `createdAt`, the later one replaces the earlier one locally; on the backend, writing an existing `photoId` or `(photoId, chunkIndex)` overwrites it. |
| FR-6.5 | Local state shall be persisted in Core Data (entity `PhotoRecord`: `photoId`, `createdAt`, `totalChunks`, `deviceId`, `syncStatus`, `thumbnailData`). |
| FR-6.6 | The UI shall reflect per-photo status: `pending` (queued, waiting for the network or a retry), `uploading`, `synced`, `failed` (last attempt failed; will be retried). `downloading` is defined but not currently used. |
| FR-6.7 | Pull-to-refresh shall trigger a sync. |
| FR-6.8 | **Offline queue.** Every captured photo's JPEG shall be saved to disk (`Application Support/PendingUploads/<photoId>.jpg`) before any other processing, and deleted only after all its chunks **and** its feed entry are stored. A file therefore means "not yet published", and the queue survives app restarts. Queued photos shall be uploaded automatically, oldest first, one photo at a time, when: the network reconnects; the server becomes reachable again after a failed request; the app launches or returns to the foreground; or the user pulls to refresh. No uploads are attempted while the system reports no network. |
| FR-6.9 | **Retry back-off.** A photo whose upload failed shall be retried automatically by a timer after 15 s, doubling after each further failure up to 300 s. Reconnect, launch, foreground and pull-to-refresh retry immediately regardless of back-off. Re-uploading is safe: chunks and the feed entry are overwritten by key. |
| FR-6.10 | **Live updates (AWS Blocks Realtime).** The backend shall publish `{photoId, createdAt}` on the shared realtime channel `feed/all` right after a photo is published (FR-8.3); a failed publish is logged and does not fail the upload. While in the foreground the app shall stay subscribed (WebSocket `ws://<host>:3000/realtime`, channel/token from `getFeedChannel`) and sync the feed on every event, so other users' photos appear within about a second. There is no polling. Because events sent while disconnected are lost, the app shall also sync each time the subscription is (re)established. After a drop it reconnects with a fresh token, back-off 1 s doubling to 15 s, and sends a keep-alive ping every 20 s. The subscription closes when the app leaves the foreground. Live syncs do not show the "Syncing…" indicator. |

### FR-7 No Authentication

| ID | Requirement |
|----|-------------|
| FR-7.1 | The app shall not require login or account creation. |
| FR-7.2 | No Auth Block shall be used. The backend API is unauthenticated. |
| FR-7.3 | A production access-control strategy is out of scope for v1 (see FR-8.6). |

### FR-8 Shared Photo Feed

| ID | Requirement |
|----|-------------|
| FR-8.1 | All app instances shall read from and write to the same backend and the same tables. There is no per-user or per-device partitioning; `deviceId` is informational only. |
| FR-8.2 | The feed shall show photos from all users, newest first, regardless of which device took them. |
| FR-8.3 | A photo shall be added to the `photos` table **only after all of its chunks are stored**, so a listed photo is always complete. |
| FR-8.4 | Each photo shall carry a thumbnail: 300 × 300 px, center-cropped, JPEG quality 0.5, Base64. The backend shall reject thumbnails longer than 300,000 characters. |
| FR-8.5 | The feed query shall accept a limit of 1–100 and shall not read any `chunkData`. |
| FR-8.6 | Because there is no authentication, anyone who can reach the backend can view and add photos. This is acceptable for local/LAN testing only. |

### FR-9 Backend Connectivity

| ID | Requirement |
|----|-------------|
| FR-9.1 | The Simulator shall use `http://localhost:3000/aws-blocks/api`. |
| FR-9.2 | A real device shall use `http://<AppConfig.lanHost>:3000/aws-blocks/api` (currently `192.168.11.10`), and `BlocksClient.baseHost` shall be set to the same host. |
| FR-9.3 | For LAN access the dev server shall bind `0.0.0.0` (`host` option in `aws-blocks/scripts/server.ts`). By default it binds loopback only; AWS Blocks warns that a wider bind exposes the unauthenticated API to the network. |
| FR-9.4 | The Mac's firewall shall allow inbound connections on port 3000 during device testing. |
| FR-9.5 | `AppConfig.backendTarget` selects `.local` (FR-9.1/9.2) or `.cloud`. `.cloud` uses `AppConfig.cloudBackendURL`, the `ApiUrl` from `npm run deploy`, on both Simulator and devices. |
| FR-9.6 | **Cloud deployment** (`npm run deploy`, AWS profile `******`, account ************, ap-northeast-1, stack `mysyncphotos-***-******-prod`). It is a disposable test stack: tables are deleted with the stack, no deletion protection or point-in-time recovery, logs are kept 7 days, API and WebSocket are throttled to 20 req/s (burst 40), and there is no web Hosting (S3/CloudFront). It creates API Gateway REST + WebSocket, one app Lambda, three on-demand DynamoDB tables, an SSM secret and a private config bucket. There is no VPC or NAT. |
| FR-9.7 | **Cloud realtime.** The deployed WebSocket rejects connections without `?token=<connectToken>` (HTTP 403). So the app reads the channel descriptor itself (the generated `getFeedChannel()` drops `connectToken`) and connects to `wsUrl?token=…`. Every 5 minutes it sends `{"action":"ping"}`, which keeps the connection under API Gateway's 10-minute idle timeout and refreshes its subscription before it expires (~1 h). The local dev server ignores both. |

---

## Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-1 | The app shall target **iOS 16.0** or later. (`Package.swift` also declares macOS 13 because BlocksRuntime requires it.) |
| NFR-2 | UI in **SwiftUI**; camera preview via `UIViewRepresentable` over `AVFoundation`. |
| NFR-3 | The client shall use **BlocksRuntime** from `aws-blocks-swift`, `.upToNextMinor(from: "0.1.0")` (resolved: 0.1.1). Version 0.2.0 does not exist yet. |
| NFR-4 | `Models.swift` and `API.swift` are generated from `blocks.spec.json` by `swift-code-generator` (run `MySyncPhotos/regenerate-api.sh`) and **committed** under `Sources/MySyncPhotos/Generated/`. `BlocksCodegenBuildPlugin` is not used in the Xcode project because it did not reliably locate the spec file there. |
| NFR-5 | The backend shall be a Node.js + TypeScript AWS Blocks project (`mysyncphotos-backend`) using `DistributedTable`. |
| NFR-6 | The app target builds in **Swift 5 language mode**, because the generated `API.swift` uses `BlocksServer`, which is not `Sendable` in BlocksRuntime 0.1.x. |
| NFR-7 | The Xcode project `MySyncPhotos.xcodeproj` is generated by **XcodeGen** from `MySyncPhotos/project.yml` (`xcodegen generate`). The camera usage string is set there. The signing Team is not stored in the project: it is read from the git-ignored `Signing.local.xcconfig` (`DEVELOPMENT_TEAM = <team id>`, see `Signing.xcconfig`), so regenerating the project does not reset it. Requires Xcode 26+. |
| NFR-8 | The chunk size limit, default grid size, retry policy and backend URLs shall each be defined once in `AppConfig`. |
| NFR-9 | Unit tests (Swift Testing, target `MySyncPhotosTests`) shall cover chunk splitting, Base64 round trip including multi-chunk photos, and the domain types. Run with Cmd+U in Xcode, or `xcodebuild test -project MySyncPhotos.xcodeproj -scheme MySyncPhotos -destination 'platform=iOS Simulator,name=<device>'`. They need an iOS Simulator (UIKit); `swift test` on the Mac cannot run them. |

---

## Local Development Setup

### Prerequisites

| Tool | Version |
|------|---------|
| Xcode | 26+ |
| Node.js | 22+ |
| npm | 10+ |
| XcodeGen | any recent (`brew install xcodegen`) |

No AWS account, Docker, DynamoDB Local or credentials are needed.

### 1. Start the backend

```bash
cd mysyncphotos-backend
npm install
npm run dev
# → http://localhost:3000  (API at /aws-blocks/api)
# → bound to 0.0.0.0 so a device on the LAN can reach it (FR-9.3)
# → data persisted in .bb-data/
```

To stop it cleanly use `npm run dev:stop`, then `npm run dev`.

### 2. After changing the backend API

```bash
cd mysyncphotos-backend
npm run spec
cp aws-blocks/blocks.spec.json ../MySyncPhotos/Sources/MySyncPhotos/blocks.spec.json
cd ../MySyncPhotos
./regenerate-api.sh
```

### 3. Build and run the app

```bash
cd MySyncPhotos
xcodegen generate            # only if project.yml or the file list changed
open MySyncPhotos.xcodeproj
```

- **Simulator:** press Cmd+R. The app uses `localhost:3000`.
- **Real device on the same Wi-Fi:** put your Team ID in `MySyncPhotos/Signing.local.xcconfig` (`DEVELOPMENT_TEAM = ABCDE12345`), then Cmd+R. The app uses `AppConfig.lanHost`; update it if the Mac's IP changes.
- **Testing offline sync:** take photos with Wi-Fi off (toolbar shows "Offline · N waiting"), then turn Wi-Fi on; the photos upload on their own and appear on other devices as soon as each is published.

---

## Backend API (`aws-blocks/index.ts`)

| Method | Used by app | Purpose |
|--------|-------------|---------|
| `putChunk(photoId, chunkIndex, totalChunks, chunkData, createdAt, deviceId)` | Yes | Store one chunk (overwrites on same key). |
| `putPhoto(photoId, totalChunks, createdAt, deviceId, thumbnail)` | Yes | Publish a complete photo to the shared feed. |
| `listRecentPhotos(limit, knownPhotoIds)` | Yes | Newest N photos across all users. Thumbnails are returned only for ids not in `knownPhotoIds` (max 500 ids); known ones get `''`. |
| `getPhotoChunks(photoId)` | Yes | All chunks of a photo, ordered by `chunkIndex` (lazy full-size load). |
| `getFeedChannel()` | Yes | Realtime channel descriptor (`channel`, `wsUrl`, `token`) for live "new photo" events. |
| `putChunks(chunks[])` | No | Batch chunk upload. |
| `getUploadedChunkIndices(photoId)` | No | Chunk indices already stored (for resumable uploads). |

---

## Data Model

### `photoChunks` (image data)

| Attribute | Type | Description |
|-----------|------|-------------|
| `photoId` | String (PK) | UUID v4 |
| `chunkIndex` | Number (SK) | Zero-based position |
| `totalChunks` | Number | Chunks in this photo |
| `chunkData` | String | Base64 chunk (< 400 KiB) |
| `createdAt` | String | ISO-8601 capture time |
| `deviceId` | String | Uploading device UUID (`UserDefaults`) |

### `photos` (shared feed)

| Attribute | Type | Description |
|-----------|------|-------------|
| `photoId` | String (PK) | UUID v4 |
| `feed` | String | Constant `"all"`; partition key of the feed index |
| `createdAt` | String | ISO-8601 capture time; sort key of the feed index |
| `totalChunks` | Number | Chunks stored in `photoChunks` |
| `deviceId` | String | Uploading device (informational) |
| `thumbnail` | String | Base64 JPEG, 300 × 300 px |

Index `feed-createdAt`: partition `feed`, sort `createdAt`. Queried with `order: 'desc'`, `limit: N`.

### Local Core Data: `PhotoRecord`

`photoId`, `createdAt`, `totalChunks`, `deviceId`, `syncStatus`, `thumbnailData`.

---

## Architecture Overview

```
project2/
├── requirements.md
├── README.md
├── mysyncphotos-backend/            # Node.js + TypeScript (AWS Blocks)
│   └── aws-blocks/
│       ├── index.ts                 # Tables + API
│       ├── blocks.spec.json         # Generated OpenRPC spec
│       └── scripts/server.ts        # Dev server (host 0.0.0.0)
└── MySyncPhotos/                    # iOS app
    ├── project.yml                  # XcodeGen definition → MySyncPhotos.xcodeproj
    ├── Signing.xcconfig             # Includes git-ignored Signing.local.xcconfig (Team ID)
    ├── Package.swift                # SwiftPM manifest (BlocksRuntime dependency)
    ├── regenerate-api.sh            # Regenerates Generated/*.swift from the spec
    ├── Sources/MySyncPhotos/
    │   ├── blocks.spec.json         # Copy of the backend spec
    │   ├── Generated/               # Models.swift, API.swift (generated, committed)
    │   ├── App/                     # MySyncPhotosApp, AppConfig
    │   ├── Camera/                  # CameraView, CameraViewModel
    │   ├── Encoding/                # ImageEncoder (JPEG → Base64 → chunks → image)
    │   ├── Storage/                 # PhotoChunksRepository, LocalStore (Core Data),
    │   │                            # PendingUploadStore (on-disk offline queue)
    │   ├── Sync/                    # SyncEngine (pull, push, retry timer), ConnectivityMonitor,
    │   │                            # FeedRealtimeClient (live-update WebSocket)
    │   └── UI/                      # PhotoGridView, PhotoCellView, PhotoDetailView,
    │                                # SettingsView, SyncStatusView
    └── Tests/MySyncPhotosTests/     # ChunkSplitter, Base64RoundTrip, PendingUploadStore,
                                     # PhotoChunksSerializer
```

---

## Out of Scope (v1)

- Authentication, per-user photo ownership or privacy
- Photo deletion
- Video capture
- Push notifications for sync events
- Production AWS deployment and IAM configuration

---

## Status and Known Gaps

- **Offline sync and live updates are implemented but not yet verified on a device.** What is verified: the app builds; 21 unit tests pass on the Simulator (including the on-disk queue surviving a restart); the backend's `knownPhotoIds` behaviour was checked against the running dev server. What is not: an actual offline → online transition, and two devices updating each other, on hardware.
- **Camera orientation (FR-1.6) is confirmed working on iPad.** Photos taken before the fix are stored rotated and are not corrected automatically.
- **Photo compression (FR-1.3) is unit-tested but not yet measured on a device.** Photos taken before it was added stay at their original size.
- **Unit test coverage is limited to the encoding, queue, orientation and domain layers.** `SyncEngine` (triggers, back-off, coalescing), `PhotoChunksRepository` (network), `LocalStore` (Core Data) and the UI have no automated tests.
- **Photos that failed before the offline queue existed** have no queued JPEG and cannot be retried; they stay `failed`/`uploading` locally.
- **Uploads restart from the first chunk.** A retry re-sends all chunks of a photo (safe, but wasteful on a flaky connection); `getUploadedChunkIndices` exists for resuming but is not used.
- **Realtime uses an app-side WebSocket client, not `RealtimeChannel.subscribe()`.** BlocksRuntime 0.1.1 reads the message body from `payload` while the server sends `data`, so it would drop every event; it also never reconnects. The fix exists in the AWS Blocks monorepo but is unreleased (aws-blocks-swift tags: 0.1.0, 0.1.1). `FeedRealtimeClient` can be replaced once a fixed version ships.
- **swift-code-generator 0.1.1 emits an unqualified channel type** (`RealtimeChannel<ResultMessage>`, which does not compile). `regenerate-api.sh` rewrites it to `RealtimeChannel<GetFeedChannel.ResultMessage>`; the rewrite is a no-op once the generator is fixed.
- **Cloud deployment is verified from the Mac, not yet from the app.** Checked after `npm run deploy`: the API answers (empty feed), the WebSocket returns 403 without a connect token and subscribes with one, the app ping is accepted, and WebSocket ping frames get a pong. Not checked: the app uploading to and syncing via the cloud. **The cloud API has no login.** Delete the stack (`npm run destroy`) after testing.
- **Realtime is verified against the dev server, not yet on two devices.** Checked: subscribe succeeds on `localhost` and `192.168.11.10`, and re-publishing a photo pushes a `data` event. Not checked: photos appearing live on a second physical device.
- **"Offline" follows the system network state.** A reachable network with an unreachable backend is handled by request failures and back-off rather than by the indicator.
- **Photos uploaded before the shared feed was added** have chunks in `photoChunks` but no `photos` row, so they do not appear. Retake or backfill.
- The feed index uses one partition (`feed = "all"`). This is fine at test scale; high volume would need sharding.
- `photoChunks` still defines an unused index `photoId-createdAt-index` (redundant, candidate for removal), and two API methods (`putChunks`, `getUploadedChunkIndices`) are unused by the app.
- End-to-end sync between two devices has not been verified on hardware.

---

## Decisions

| # | Decision |
|---|----------|
| OQ-1 | **Grid size is user-configurable** (4 / 9 / 16 / 25, default 9), stored in `UserDefaults`. |
| OQ-2 | **Last upload wins** for the same photo (FR-6.4). |
| OQ-3 | **Lazy reassembly.** Metadata and thumbnails sync eagerly; full-size chunks load only when a photo is opened (FR-5.3, FR-6.2). |
| OQ-4 | **No `FileBucket`.** Everything stays in `DistributedTable` (now two tables: `photoChunks` and `photos`). |
| OQ-5 | **One shared feed for all users** (FR-8). Thumbnails travel with the feed metadata so the grid never needs full-size downloads. |
| OQ-7 | **Failed and offline uploads are retried automatically** from an on-disk queue of the original JPEGs (FR-6.8, FR-6.9). |
| OQ-9 | **Live updates use the AWS Blocks `Realtime` block** (WebSocket push), replacing the earlier 10 s polling (FR-6.10). |

## Open Questions

| # | Question |
|---|----------|
| OQ-6 | Which access-control approach for production (API key, Cognito, signed uploads)? Needed before anything beyond LAN testing. |
| OQ-8 | Should old photos without a `photos` row be backfilled? |
