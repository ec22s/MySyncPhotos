import SwiftUI
import BlocksRuntime

@main
struct MySyncPhotosApp: App {

    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                // Must be injected from the parent: a view's own @FetchRequest
                // reads the environment it receives, not one it sets in its body.
                .environment(\.managedObjectContext, appState.localStore.viewContext)
        }
    }
}

/// Top-level app state.
/// The generated codegen plugin produces `Api` (not a `Blocks` wrapper class).
/// We hold one `Api` instance for the app's lifetime and share it via environment.
@MainActor
final class AppState: ObservableObject {

    /// Generated API client — one instance, shared app-wide.
    let api: Api

    let photoChunksRepo: PhotoChunksRepository
    let localStore: LocalStore
    let syncEngine: SyncEngine

    init() {
        // Point the client at the right backend (AppConfig.backendTarget):
        // - local: Simulator → localhost:3000, real device → 192.168.11.10:3000
        // - cloud: the API Gateway URL from `npm run deploy`
        let server = BlocksServer(name: "app", url: AppConfig.backendURL)
        api = Api(server: server)

        // Local dev server only: rewrite localhost in WebSocket URLs to the LAN IP
        // so they work on a real device. (Cloud URLs never contain localhost.)
        if AppConfig.useLANBackend {
            BlocksClient.baseHost = AppConfig.lanHost
        }

        localStore = LocalStore()
        photoChunksRepo = PhotoChunksRepository(api: api, server: server)
        syncEngine = SyncEngine(
            repository: photoChunksRepo,
            localStore: localStore
        )
    }
}
