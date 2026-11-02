@preconcurrency import AVFoundation
import UIKit
import SwiftUI

/// Controls the AVCaptureSession and publishes the captured image.
@MainActor
final class CameraViewModel: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var isSessionRunning = false
    @Published var captureError: CameraError?
    @Published var lastCapture: UIImage?

    // MARK: - AVFoundation objects

    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?

    // MARK: - Setup

    /// Requests camera permission and configures the capture session.
    func setup() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await configureSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await configureSession()
            } else {
                captureError = .permissionDenied
            }
        case .denied, .restricted:
            captureError = .permissionDenied
        @unknown default:
            captureError = .permissionDenied
        }
    }

    /// Serial queue for blocking AVCaptureSession calls (start/stop).
    private let sessionQueue = DispatchQueue(label: "com.example.MySyncPhotos.camera-session")

    /// Starts the capture session on a background queue, then updates UI state on main.
    func startSession() {
        let session = self.session
        sessionQueue.async { [weak self] in
            if !session.isRunning { session.startRunning() }
            let running = session.isRunning
            DispatchQueue.main.async { self?.isSessionRunning = running }
        }
    }

    /// Stops the capture session on a background queue.
    func stopSession() {
        let session = self.session
        sessionQueue.async { [weak self] in
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async { self?.isSessionRunning = false }
        }
    }

    // MARK: - Capture

    /// Captures a single still photo.
    @discardableResult
    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: CameraError.sessionNotRunning)
                return
            }
            self.captureCompletion = { image in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: CameraError.captureFailed)
                }
            }
            // Tell AVFoundation how the device is held right now, so the photo is
            // written upright (otherwise landscape shots come out rotated 90°).
            CaptureOrientation.apply(
                CaptureOrientation.currentInterfaceOrientation(),
                to: self.photoOutput.connection(with: .video)
            )

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Private

    private func configureSession() async {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Rear camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            captureError = .noCamera
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage?
        if let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        } else {
            image = nil
        }
        Task { @MainActor [weak self] in
            self?.lastCapture = image
            self?.captureCompletion?(image)
            self?.captureCompletion = nil
        }
    }
}

// MARK: - Errors

enum CameraError: LocalizedError {
    case permissionDenied
    case noCamera
    case sessionNotRunning
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access is required. Please enable it in Settings."
        case .noCamera:
            return "No rear camera found on this device."
        case .sessionNotRunning:
            return "The camera session is not running."
        case .captureFailed:
            return "Failed to capture the photo."
        }
    }
}
