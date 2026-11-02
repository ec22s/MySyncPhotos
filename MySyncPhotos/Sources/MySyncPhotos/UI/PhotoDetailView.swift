import SwiftUI

/// Full-resolution photo detail sheet.
/// Chunks are fetched and reassembled lazily — only when this view appears.
struct PhotoDetailView: View {

    @ObservedObject var record: PhotoRecord
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var image:     UIImage?
    @State private var isLoading  = false
    @State private var loadError: Error?

    private let encoder = ImageEncoder()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading photo…")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text(error.localizedDescription)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry") {
                            Task { await loadPhoto() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(formattedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .task { await loadPhoto() }
    }

    // MARK: - Loading

    private func loadPhoto() async {
        guard let photoId = record.photoId else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let chunks = try await appState.photoChunksRepo.fetchChunks(photoId: photoId)
            let assembled = await encoder.reassemble(chunks: chunks)
            image = assembled

            // Cache the full-size image as thumbnail if not already set
            if record.thumbnailData == nil, let assembled {
                let thumb = assembled.thumbnail(size: CGSize(width: 300, height: 300))
                try? await appState.localStore.saveThumbnail(thumb, for: photoId)
            }
        } catch {
            loadError = error
        }
    }

    private var formattedTitle: String {
        guard let iso = record.createdAt,
              let date = ISO8601DateFormatter().date(from: iso) else {
            return "Photo"
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
