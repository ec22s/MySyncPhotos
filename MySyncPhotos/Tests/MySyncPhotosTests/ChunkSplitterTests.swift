import Testing
import Foundation
@testable import MySyncPhotos

@Suite("ImageEncoder chunk splitting")
struct ChunkSplitterTests {

    let encoder = ImageEncoder()

    @Test("Empty string produces no chunks")
    func emptyString() async {
        let chunks = await encoder.split(base64: "")
        #expect(chunks.isEmpty)
    }

    @Test("Short string produces a single chunk")
    func shortString() async {
        let input = "SGVsbG8gV29ybGQ="  // "Hello World" in Base64
        let chunks = await encoder.split(base64: input)
        #expect(chunks.count == 1)
        #expect(chunks[0] == input)
    }

    @Test("Each chunk fits maxChunkBytes and is strictly below 400 KiB")
    func chunkSizeLimit() async {
        // Generate a Base64 string several times larger than one chunk.
        let bigData = Data(repeating: 0xAB, count: AppConfig.maxChunkBytes * 3)
        let base64  = bigData.base64EncodedString()
        let chunks  = await encoder.split(base64: base64)

        #expect(chunks.count > 1, "Input should require more than one chunk")
        for chunk in chunks {
            let byteCount = chunk.utf8.count
            #expect(byteCount <= AppConfig.maxChunkBytes,
                    "Chunk of \(byteCount) bytes exceeds configured size \(AppConfig.maxChunkBytes)")
            // Product requirement: strictly less than 400 KiB (409,600 bytes).
            #expect(byteCount < 400 * 1024,
                    "Chunk of \(byteCount) bytes is not below 400 KiB")
        }
    }

    @Test("Reassembled chunks produce the original string")
    func roundTrip() async {
        let original = Data(repeating: 0xFF, count: AppConfig.maxChunkBytes * 2 + 1)
            .base64EncodedString()
        let chunks     = await encoder.split(base64: original)
        let reassembled = chunks.joined()
        #expect(reassembled == original)
    }

    @Test("Multiple chunks cover the entire input without gaps or overlaps")
    func fullCoverage() async {
        let input  = String(repeating: "A", count: AppConfig.maxChunkBytes * 2 + 500)
        let chunks = await encoder.split(base64: input)
        #expect(chunks.joined() == input)
    }
}
