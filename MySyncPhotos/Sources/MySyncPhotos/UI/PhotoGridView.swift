import SwiftUI
import CoreData

/// Root content view — the 3×3 (or user-configured) photo grid.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        PhotoGridView()
    }
}

/// The main photo grid screen.
struct PhotoGridView: View {

    @EnvironmentObject private var appState: AppState
    @AppStorage(AppConfig.photoLimitKey) private var photoLimit = AppConfig.defaultPhotoLimit
    @Environment(\.scenePhase) private var scenePhase

    // Core Data fetch for the grid.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PhotoRecord.createdAt, ascending: false)],
        animation: .default
    )
    private var records: FetchedResults<PhotoRecord>

    @State private var showCamera     = false
    @State private var showSettings   = false
    @State private var selectedRecord: PhotoRecord?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 3
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(records.prefix(photoLimit)) { record in
                        PhotoCellView(record: record)
                            .onTapGesture {
                                selectedRecord = record
                            }
                    }
                }
            }
            .navigationTitle("MySyncPhotos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCamera = true
                    } label: {
                        Image(systemName: "camera")
                    }
                }
                ToolbarItem(placement: .status) {
                    // Separate view so it observes the engine and connectivity itself;
                    // observing `appState` alone would not refresh when they change.
                    SyncStatusView(
                        engine: appState.syncEngine,
                        connectivity: appState.syncEngine.connectivity
                    )
                }
            }
            .refreshable {
                await appState.syncEngine.sync(trigger: .manual)
            }
            .sheet(isPresented: $showCamera) {
                CameraView()
            }
            .sheet(item: $selectedRecord) { record in
                PhotoDetailView(record: record)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            // While the app is active: sync now, then stay subscribed to the realtime
            // feed channel so other users' photos appear as soon as they are published.
            // The task (and its WebSocket) is cancelled when the app leaves the foreground.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await appState.syncEngine.runLiveSync()
            }
        }
    }
}
