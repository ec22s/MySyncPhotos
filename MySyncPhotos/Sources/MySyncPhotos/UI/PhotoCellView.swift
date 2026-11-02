import SwiftUI

/// A single cell in the photo grid.
/// Shows thumbnail + timestamp overlay + sync status indicator.
struct PhotoCellView: View {

    @ObservedObject var record: PhotoRecord

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                thumbnailView(size: geo.size)
                overlayView
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Subviews

    @ViewBuilder
    private func thumbnailView(size: CGSize) -> some View {
        if let data = record.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if record.syncStatusEnum == .downloading ||
               record.syncStatusEnum == .uploading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var overlayView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ts = formattedTimestamp {
                Text(ts)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
            }
            statusBadge
        }
        .padding(4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch record.syncStatusEnum {
        case .uploading:
            badge("arrow.up.circle.fill", color: .blue)
        case .downloading:
            badge("arrow.down.circle.fill", color: .blue)
        case .failed:
            badge("exclamationmark.circle.fill", color: .red)
        case .pending:
            badge("clock.circle.fill", color: .orange)
        case .synced:
            EmptyView()
        }
    }

    private func badge(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.caption)
            .foregroundStyle(color)
            .shadow(radius: 1)
    }

    private var formattedTimestamp: String? {
        guard let iso = record.createdAt,
              let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}
