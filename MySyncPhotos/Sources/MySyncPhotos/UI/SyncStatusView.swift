import SwiftUI

/// Small status line for the grid's toolbar: offline / syncing / waiting to upload.
/// Observes the engine and connectivity directly so it updates live.
struct SyncStatusView: View {

    @ObservedObject var engine: SyncEngine
    @ObservedObject var connectivity: ConnectivityMonitor

    var body: some View {
        if !connectivity.isOnline {
            Label(offlineText, systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if engine.isSyncing || engine.isUploading {
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.7)
                Text("Syncing…").font(.caption).foregroundStyle(.secondary)
            }
        } else if engine.pendingUploadCount > 0 {
            Label("\(engine.pendingUploadCount) waiting to upload",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var offlineText: String {
        engine.pendingUploadCount > 0
            ? "Offline · \(engine.pendingUploadCount) waiting"
            : "Offline"
    }
}
