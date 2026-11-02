import Testing
import AVFoundation
import UIKit
@testable import MySyncPhotos

/// Guards the orientation tables that decide how photos are tagged. A wrong entry
/// shows up as rotated or upside-down photos, which can't be seen in the Simulator
/// (it has no camera), so the mapping is pinned here.
@Suite("CaptureOrientation")
struct CaptureOrientationTests {

    @Test("Rotation angles for each interface orientation (iOS 17+)")
    func rotationAngles() {
        #expect(CaptureOrientation.rotationAngle(for: .portrait) == 90)
        #expect(CaptureOrientation.rotationAngle(for: .portraitUpsideDown) == 270)
        #expect(CaptureOrientation.rotationAngle(for: .landscapeRight) == 0)
        #expect(CaptureOrientation.rotationAngle(for: .landscapeLeft) == 180)
    }

    @Test("Legacy video orientation matches the interface orientation (iOS 16)")
    func videoOrientations() {
        #expect(CaptureOrientation.videoOrientation(for: .portrait) == .portrait)
        #expect(CaptureOrientation.videoOrientation(for: .portraitUpsideDown) == .portraitUpsideDown)
        #expect(CaptureOrientation.videoOrientation(for: .landscapeLeft) == .landscapeLeft)
        #expect(CaptureOrientation.videoOrientation(for: .landscapeRight) == .landscapeRight)
    }

    @Test("Both tables agree: the angle implied by the legacy orientation is the same")
    func tablesAgree() {
        // Legacy orientation → angle, per Apple's migration guidance.
        let legacyAngle: [AVCaptureVideoOrientation: CGFloat] = [
            .portrait: 90, .portraitUpsideDown: 270, .landscapeRight: 0, .landscapeLeft: 180,
        ]
        let all: [UIInterfaceOrientation] =
            [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
        for orientation in all {
            let legacy = CaptureOrientation.videoOrientation(for: orientation)
            #expect(legacyAngle[legacy] == CaptureOrientation.rotationAngle(for: orientation))
        }
    }

    @Test("Unknown orientation falls back to portrait")
    func unknownFallsBackToPortrait() {
        #expect(CaptureOrientation.rotationAngle(for: .unknown) == 90)
        #expect(CaptureOrientation.videoOrientation(for: .unknown) == .portrait)
    }
}
