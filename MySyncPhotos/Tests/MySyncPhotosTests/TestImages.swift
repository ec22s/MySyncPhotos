import UIKit

/// Image factories shared by the test suites.
enum TestImages {

    /// Image of deterministic pseudo-random pixels. Noise barely compresses, so it is
    /// the worst case for JPEG size: if noise fits a size limit, real photos will too.
    static func noise(
        width: Int,
        height: Int,
        orientation: UIImage.Orientation = .up
    ) -> UIImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var state: UInt64 = 0x9E3779B97F4A7C15
        for i in stride(from: 0, to: bytes.count, by: 4) {
            // xorshift64: cheap deterministic pseudo-random bytes.
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            bytes[i]     = UInt8(truncatingIfNeeded: state)
            bytes[i + 1] = UInt8(truncatingIfNeeded: state >> 8)
            bytes[i + 2] = UInt8(truncatingIfNeeded: state >> 16)
            // alpha stays 255
        }
        let cgImage: CGImage = bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return ctx.makeImage()!
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    /// Smooth gradient, a stand-in for an ordinary photo (compresses well).
    static func gradient(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor.systemBlue.cgColor, UIColor.systemOrange.cgColor] as CFArray
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil
            )!
            ctx.cgContext.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: []
            )
        }
    }
}
