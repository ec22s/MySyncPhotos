import Testing
import UIKit
@testable import MySyncPhotos

/// Photos are stored compressed to at most `AppConfig.maxPhotoBytes` (640 KiB).
@Suite("Photo compression")
struct PhotoCompressionTests {

    let encoder = ImageEncoder()

    @Test("A large worst-case photo is compressed to at most maxPhotoBytes")
    func largePhotoFitsLimit() async throws {
        // 12 MP of noise: far larger than the limit at any normal JPEG quality.
        let original = TestImages.noise(width: 4000, height: 3000)
        let data = try await encoder.jpegData(from: original)

        #expect(data.count <= AppConfig.maxPhotoBytes,
                "Got \(data.count) bytes, limit \(AppConfig.maxPhotoBytes)")
    }

    @Test("Large photo is scaled to the maximum dimension, keeping its aspect ratio")
    func largePhotoIsScaled() async throws {
        let original = TestImages.gradient(width: 4000, height: 3000)
        let data  = try await encoder.jpegData(from: original)
        let image = try #require(UIImage(data: data))

        #expect(max(image.size.width, image.size.height) == AppConfig.maxPhotoDimension)
        #expect(abs(image.size.width / image.size.height - 4.0 / 3.0) < 0.01)
        #expect(data.count <= AppConfig.maxPhotoBytes)
    }

    @Test("A small photo is not scaled up")
    func smallPhotoNotUpscaled() async throws {
        let original = TestImages.gradient(width: 800, height: 600)
        let data  = try await encoder.jpegData(from: original)
        let image = try #require(UIImage(data: data))

        #expect(image.size == CGSize(width: 800, height: 600))
    }

    @Test("An easy-to-compress photo keeps the highest quality (no needless loss)")
    func easyPhotoKeepsHighQuality() async throws {
        let original = TestImages.gradient(width: 2000, height: 1500)
        let data = try await encoder.jpegData(from: original)

        // Same pixels, preferred quality: compression must not have gone lower.
        let reference = try #require(
            TestImages.gradient(width: 2000, height: 1500)
                .jpegData(compressionQuality: AppConfig.maxJPEGQuality)
        )
        #expect(abs(data.count - reference.count) < reference.count / 10)
    }

    @Test("A sideways-tagged photo is stored upright (orientation baked into pixels)")
    func orientationIsBakedIn() async throws {
        // Sensor-shaped 400×200 pixels tagged `.right` display as a 200×400 portrait.
        let tagged = TestImages.noise(width: 400, height: 200, orientation: .right)
        #expect(tagged.size == CGSize(width: 200, height: 400))

        let data   = try await encoder.jpegData(from: tagged)
        let stored = try #require(UIImage(data: data))

        #expect(stored.imageOrientation == .up)
        #expect(stored.size == CGSize(width: 200, height: 400))
        let cg = try #require(stored.cgImage)
        #expect(cg.width == 200 && cg.height == 400, "Pixels themselves must be portrait")
    }

    @Test("fittedSize only ever shrinks, and keeps the aspect ratio")
    func fittedSize() {
        #expect(ImageEncoder.fittedSize(CGSize(width: 4032, height: 3024), maxDimension: 2560)
                == CGSize(width: 2560, height: 1920))
        #expect(ImageEncoder.fittedSize(CGSize(width: 3024, height: 4032), maxDimension: 2560)
                == CGSize(width: 1920, height: 2560))
        #expect(ImageEncoder.fittedSize(CGSize(width: 1000, height: 500), maxDimension: 2560)
                == CGSize(width: 1000, height: 500))
    }
}
