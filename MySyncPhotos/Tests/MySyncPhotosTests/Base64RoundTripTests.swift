import Testing
import UIKit
@testable import MySyncPhotos

@Suite("Base64 round-trip")
struct Base64RoundTripTests {

    let encoder = ImageEncoder()

    @Test("1×1 pixel JPEG encodes to non-empty Base64")
    func encodeSmallImage() async throws {
        let image  = makePixel()
        let chunks = try await encoder.encode(image: image)
        #expect(!chunks.isEmpty)
        #expect(chunks.joined().isEmpty == false)
    }

    @Test("Encoded then reassembled image is non-nil")
    func encodeDecodeRoundTrip() async throws {
        let original = makePixel()
        let chunks   = try await encoder.encode(image: original)
        let result   = await encoder.reassemble(chunks: chunks)
        #expect(result != nil)
    }

    @Test("Encoding stored JPEG bytes gives the same chunks as encoding the image")
    func encodeFromStoredJPEG() async throws {
        // Retrying a queued photo re-encodes from the saved JPEG, so both paths must agree.
        let image  = makeNoiseImage(side: 600)
        let jpeg   = try await encoder.jpegData(from: image)

        let fromBytes = await encoder.encode(jpegData: jpeg)
        let fromImage = try await encoder.encode(image: image)

        #expect(fromBytes == fromImage)
        #expect(fromBytes.joined() == jpeg.base64EncodedString())
    }

    @Test("Large photo splits into several chunks (each < 400 KiB) and reassembles to the same size")
    func multiChunkRoundTrip() async throws {
        let original = makeNoiseImage(side: 1000)   // incompressible → big JPEG
        let chunks   = try await encoder.encode(image: original)

        #expect(chunks.count > 1, "Noise image should need more than one chunk")
        for chunk in chunks {
            #expect(chunk.utf8.count < 400 * 1024)
        }

        let result = await encoder.reassemble(chunks: chunks)
        #expect(result != nil)
        #expect(result?.size == original.size)
    }

    @Test("Chunks reassembled in the wrong order do not give the original image")
    func wrongOrderIsDetected() async throws {
        let original = makeNoiseImage(side: 1000)
        let chunks   = try await encoder.encode(image: original)
        try #require(chunks.count > 1)

        let correct = await encoder.reassemble(chunks: chunks)
        let wrong   = await encoder.reassemble(chunks: Array(chunks.reversed()))

        // Wrong order either fails to decode (nil) or decodes to different pixels.
        #expect(wrong == nil || wrong?.pngData() != correct?.pngData())
    }

    // MARK: - Helpers

    private func makeNoiseImage(side: Int) -> UIImage {
        TestImages.noise(width: side, height: side)
    }

    /// Creates a 1×1 red UIImage suitable for encoding tests.
    private func makePixel() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
