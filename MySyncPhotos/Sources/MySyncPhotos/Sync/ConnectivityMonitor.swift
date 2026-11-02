import Foundation
import Network

/// Observes network reachability and tells the sync engine when the device
/// comes back online, so queued photos can be uploaded without user action.
@MainActor
final class ConnectivityMonitor: ObservableObject {

    /// `true` when the system reports a usable network path.
    /// (A usable path does not guarantee the backend is reachable; the sync
    /// engine also handles request failures.)
    @Published private(set) var isOnline = true

    /// Called on the main actor when the path changes from offline to online.
    var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.example.MySyncPhotos.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.apply(online: online)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func apply(online: Bool) {
        let wasOnline = isOnline
        guard online != wasOnline else { return }
        isOnline = online
        if online { onReconnect?() }
    }
}
