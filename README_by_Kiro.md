# MySyncPhotos

iOS app built on **AWS Blocks** that captures photos, encodes them as Base64 chunks, stores them in the cloud via `DistributedTable`, and keeps a 3×3 (user-configurable) grid of the newest photos in sync across devices.

---

## Project Structure

```
project2/
├── requirements.md               ← Full feature spec
├── README.md                     ← This file
│
├── mysyncphotos-backend/         ← Node.js + TypeScript (AWS Blocks backend)
│   ├── aws-blocks/
│   │   ├── index.ts              ← API + DistributedTable definitions
│   │   └── blocks.spec.json      ← Generated spec (copy to iOS project)
│   └── package.json
│
└── MySyncPhotos/                 ← iOS app (SwiftUI + BlocksRuntime)
    ├── Package.swift
    ├── Sources/MySyncPhotos/
    │   ├── blocks.spec.json      ← Copied from backend
    │   ├── App/
    │   ├── Camera/
    │   ├── Encoding/
    │   ├── Storage/
    │   ├── Sync/
    │   └── UI/
    └── Tests/MySyncPhotosTests/
```

---

## Local Development

### Prerequisites

| Tool    | Version |
|---------|---------|
| Node.js | 22+     |
| npm     | 10+     |
| Xcode   | 26+     |
| Swift   | 6.2+    |

> No AWS account needed. No Docker. No DynamoDB Local. Everything runs in-process.

---

### 1. Start the backend

```bash
cd mysyncphotos-backend
npm run dev
```

The server starts at **http://0.0.0.0:3000** — accessible from both Simulator (`localhost`) and real devices on the same Wi-Fi (`192.168.11.10`).
API endpoint: `http://192.168.11.10:3000/aws-blocks/api`
Data persisted to: `.bb-data/` (local filesystem)

---

### 2. (Re-)generate the spec after backend changes

```bash
cd mysyncphotos-backend
npm run spec
cp aws-blocks/blocks.spec.json ../MySyncPhotos/Sources/MySyncPhotos/blocks.spec.json
```

---

### 3. Open the iOS app in Xcode

```bash
open MySyncPhotos/MySyncPhotos.xcodeproj
```

**Simulator** — select any iOS 16+ Simulator and press **Cmd+R**. The app uses `localhost:3000` automatically.

**Real device on Wi-Fi** — the app detects it's on a real device and switches to `192.168.11.10:3000`. If your Mac's IP is different, update `AppConfig.lanHost` in `AppConfig.swift` before building.

Signing: put your Apple Developer Team ID in `MySyncPhotos/Signing.local.xcconfig` (git-ignored):

```
DEVELOPMENT_TEAM = ABCDE12345
```

It lives outside the Xcode project, so `xcodegen generate` never resets it.

> Make sure your Mac's firewall allows inbound connections on port 3000, or temporarily disable it for local development.
> The dev server is bound to `0.0.0.0` for this, which exposes the unauthenticated API to your whole network. Use it on a network you trust.

---

### 4. Try offline sync and live updates

- **Offline queue:** turn Wi-Fi off and take a few photos. They appear in the grid right away and the toolbar shows "Offline · N waiting". Turn Wi-Fi back on: they upload on their own.
- **Live updates:** with two devices (or Simulator + device) open, take a photo on one. It shows up on the other about a second after the upload finishes, with no pull-to-refresh (AWS Blocks Realtime over WebSocket).

---

### 5. Run the tests

In Xcode press **Cmd+U**, or from the terminal (use any Simulator you have installed):

```bash
cd MySyncPhotos
xcodebuild test -project MySyncPhotos.xcodeproj -scheme MySyncPhotos \
  -destination 'platform=iOS Simulator,name=<your simulator>'
```

The tests need an iOS Simulator because they use UIKit, so `swift test` on the Mac will not work.
They cover chunk splitting, Base64 round-trips (including multi-chunk photos), and domain types.

---

## Deploying the backend to AWS

The backend is deployed as a **disposable test stack**. Its tables are deleted with the stack, there are no backups, and the API is throttled to 20 req/s. See `aws-blocks/index.cdk.ts`.

| | |
|---|---|
| Account / region | ************ / ap-northeast-1 (AWS profile **`******`**) |
| Stack | `mysyncphotos-***-******-prod` |
| API | `https://**********.execute-api.ap-northeast-1.amazonaws.com/prod/aws-blocks/api` |
| Realtime | `wss://**********.execute-api.ap-northeast-1.amazonaws.com/rt` |

```bash
cd mysyncphotos-backend
AWS_PROFILE=****** AWS_REGION=ap-northeast-1 npm run deploy    # create / update (~12 min first time)
AWS_PROFILE=****** AWS_REGION=ap-northeast-1 npm run destroy   # delete everything, incl. cloud photos
```

The first deploy needed a one-time `cdk bootstrap aws://************/ap-northeast-1`, which is already done.

**Pointing the app at a backend:** in `AppConfig.swift`, set `backendTarget` to `.cloud` (the current setting) or `.local`, then rebuild. After a destroy and redeploy the API URL changes. Copy the new `ApiUrl` into `AppConfig.cloudBackendURL`.

> The cloud API has **no login**: anyone who knows the URL can view and add photos. That is acceptable for a short test; run `npm run destroy` when you're done, and add authentication before real use.

---

## How It Works

```
Camera → JPEG saved to on-disk queue (survives offline / app restart)
            ↓
   Base64 → split into <400 KiB chunks
            ↓   (when online; retried automatically if it fails)
   POST /aws-blocks/api  (BlocksRuntime JSON-RPC)
            ↓
   DistributedTable Blocks: photoChunks (data) + photos (shared feed)
            ↓   queue file deleted only after chunks AND feed entry are stored
   Realtime block pushes "new photo" over WebSocket → SyncEngine syncs the feed
            ↓
   PhotoGridView (LazyVGrid) shows all users' photos, newest first
            ↓
   User taps photo → lazy chunk fetch → reassemble → UIImage
```

## Key Design Decisions

| Decision | Choice |
|----------|--------|
| Grid size | User-configurable (default 9), stored in `UserDefaults` |
| Conflict resolution | Last `createdAt` timestamp wins |
| Chunk reassembly | Lazy — only when user opens a photo |
| Offline photos | JPEG queued on disk, uploaded automatically on reconnect |
| New photos from others | AWS Blocks Realtime push; app re-syncs on every event and (re)connect |
| Storage Block | `DistributedTable` only (no `FileBucket`) |
| Auth | None — no login required |
