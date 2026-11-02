import AVFoundation
import UIKit

/// Maps the app's interface orientation onto AVFoundation capture connections.
///
/// Without this, AVFoundation tags every photo (and draws the preview) as if the device
/// were held in portrait. That is why landscape shots, most visibly on iPad, came out
/// rotated by 90°. The photo's pixels are always sensor-oriented; the connection's
/// rotation decides which orientation is written into the JPEG so every viewer shows it upright.
enum CaptureOrientation {

    /// Rotation in degrees for iOS 17+ `AVCaptureConnection.videoRotationAngle`.
    /// (0° = landscape with the home button / Apple logo side on the right, 90° = portrait.)
    static func rotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait:           return 90
        case .portraitUpsideDown: return 270
        case .landscapeRight:     return 0
        case .landscapeLeft:      return 180
        default:                  return 90
        }
    }

    /// Equivalent value for iOS 16, where only `videoOrientation` exists.
    /// `UIInterfaceOrientation` and `AVCaptureVideoOrientation` use the same names for
    /// the same physical orientations.
    static func videoOrientation(for orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch orientation {
        case .portrait:           return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft:      return .landscapeLeft
        case .landscapeRight:     return .landscapeRight
        default:                  return .portrait
        }
    }

    /// Orientation of the window the app is currently shown in.
    @MainActor
    static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.interfaceOrientation ?? .portrait
    }

    /// Points `connection` at the given interface orientation (no-op if unsupported).
    static func apply(_ orientation: UIInterfaceOrientation, to connection: AVCaptureConnection?) {
        guard let connection else { return }
        if #available(iOS 17.0, *) {
            let angle = rotationAngle(for: orientation)
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation(for: orientation)
        }
    }
}
