import UIKit

/// Converts a UIImage → JPEG → Base64 string → array of chunks.
/// All work runs on a background actor so the main thread stays responsive.
actor ImageEncoder {

    // MARK: - Public API

    /// Compresses `image` (see `jpegData(from:)`), Base64-encodes the result, and splits
    /// it into chunks where each chunk's UTF-8 byte count is ≤ `AppConfig.maxChunkBytes`.
    ///
    /// - Returns: An ordered array of Base64 chunk strings.
    /// - Throws: `EncodingError` if JPEG conversion fails.
    func encode(image: UIImage) throws -> [String] {
        encode(jpegData: try jpegData(from: image))
    }

    /// Base64-encodes already-compressed JPEG bytes and splits them into chunks.
    /// Used when re-uploading a photo that was queued on disk.
    func encode(jpegData: Data) -> [String] {
        split(base64: jpegData.base64EncodedString())
    }

    /// Compresses a captured photo to a JPEG of at most `maxBytes` (default 640 KiB).
    /// Runs on this actor, off the main thread.
    ///
    /// 1. Scales the photo down so its long edge is ≤ `maxDimension` (never scales up).
    ///    Drawing also bakes the photo's orientation into the pixels, so the result is
    ///    stored upright without depending on an EXIF orientation tag.
    /// 2. Picks the highest JPEG quality in `minJPEGQuality…maxJPEGQuality` that fits.
    /// 3. If it still does not fit at the lowest quality, scales down by 20% and repeats.
    func jpegData(
        from image: UIImage,
        maxBytes: Int = AppConfig.maxPhotoBytes,
        maxDimension: CGFloat = AppConfig.maxPhotoDimension
    ) throws -> Data {
        var size = Self.fittedSize(image.size, maxDimension: maxDimension)
        var smallestAttempt: Data?

        while true {
            let upright = Self.render(image, size: size)
            if let fitting = Self.bestJPEG(upright, maxBytes: maxBytes) {
                return fitting
            }
            smallestAttempt = upright.jpegData(compressionQuality: AppConfig.minJPEGQuality)
                ?? smallestAttempt

            let next = CGSize(width: (size.width * 0.8).rounded(), height: (size.height * 0.8).rounded())
            if max(next.width, next.height) < AppConfig.minPhotoDimension { break }
            size = next
        }

        // Pathological input that never fits: return the smallest version we made.
        guard let smallestAttempt else { throw EncodingError.jpegConversionFailed }
        return smallestAttempt
    }

    /// Square 300×300 JPEG thumbnail used by the grid and the shared feed.
    func thumbnailJPEG(from image: UIImage) -> Data? {
        image.thumbnail(size: CGSize(width: 300, height: 300))
            .jpegData(compressionQuality: 0.5)
    }

    // MARK: - Compression helpers

    /// `size` scaled so its long edge is at most `maxDimension`, in whole pixels.
    static func fittedSize(_ size: CGSize, maxDimension: CGFloat) -> CGSize {
        let longEdge = max(size.width, size.height)
        let scale = longEdge > maxDimension ? maxDimension / longEdge : 1
        return CGSize(
            width:  max(1, (size.width  * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
    }

    /// Redraws `image` at exactly `size` pixels, upright (orientation `.up`).
    private static func render(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1        // `size` is in pixels
        format.opaque = true    // JPEG has no alpha channel
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Highest-quality JPEG of `image` that is at most `maxBytes`, or `nil` if even
    /// the lowest allowed quality is too large. Binary-searches the quality.
    private static func bestJPEG(_ image: UIImage, maxBytes: Int) -> Data? {
        if let data = image.jpegData(compressionQuality: AppConfig.maxJPEGQuality),
           data.count <= maxBytes {
            return data   // common case: fits at the preferred quality
        }
        guard let floor = image.jpegData(compressionQuality: AppConfig.minJPEGQuality),
              floor.count <= maxBytes else {
            return nil
        }

        var best = floor
        var low  = AppConfig.minJPEGQuality
        var high = AppConfig.maxJPEGQuality
        for _ in 0..<6 {   // ≈0.01 quality resolution
            let mid = (low + high) / 2
            guard let data = image.jpegData(compressionQuality: mid) else { break }
            if data.count <= maxBytes {
                best = data
                low = mid
            } else {
                high = mid
            }
        }
        return best
    }

    // MARK: - Chunk splitting

    /// Splits a Base64 string into chunks each smaller than `AppConfig.maxChunkBytes`.
    func split(base64: String) -> [String] {
        let maxBytes = AppConfig.maxChunkBytes
        var chunks: [String] = []
        var startIndex = base64.startIndex

        while startIndex < base64.endIndex {
            // Advance by up to maxBytes UTF-8 code units, staying on character boundaries.
            let remaining = base64[startIndex...]
            let chunkEnd = base64.utf8
                .index(startIndex, offsetBy: maxBytes, limitedBy: base64.endIndex)
                ?? base64.endIndex
            // Align to the nearest character boundary (UTF-8 may split a multibyte char).
            let safeEnd = base64.utf8.index(chunkEnd, offsetBy: 0)
                .samePosition(in: base64)
                ?? base64.endIndex

            // Verify the resulting slice is within bounds.
            let end = safeEnd <= base64.endIndex ? safeEnd : base64.endIndex
            if end <= startIndex {
                // Safety: avoid infinite loop on edge cases.
                chunks.append(String(remaining))
                break
            }
            chunks.append(String(base64[startIndex..<end]))
            startIndex = end
        }
        return chunks
    }

    // MARK: - Reassembly (lazy — called when user opens a photo)

    /// Reassembles an ordered array of Base64 chunks back into a UIImage.
    ///
    /// - Parameter chunks: Chunks sorted by `chunkIndex` ascending.
    /// - Returns: Decoded `UIImage`, or `nil` if the Base64 is malformed.
    func reassemble(chunks: [String]) -> UIImage? {
        let base64 = chunks.joined()
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Errors

enum EncodingError: LocalizedError {
    case jpegConversionFailed

    var errorDescription: String? {
        switch self {
        case .jpegConversionFailed:
            return "Failed to convert the captured image to JPEG."
        }
    }
}
