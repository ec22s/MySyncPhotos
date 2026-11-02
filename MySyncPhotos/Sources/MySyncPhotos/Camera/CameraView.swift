import SwiftUI
import AVFoundation

/// Live camera preview using `AVCaptureVideoPreviewLayer`.
/// Bridges UIKit's `AVCaptureSession` into SwiftUI via `UIViewRepresentable`.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Session changes are handled by CameraViewModel; nothing to update here.
    }

    // MARK: - PreviewUIView

    final class PreviewUIView: UIView {

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        var session: AVCaptureSession? {
            get { previewLayer.session }
            set {
                previewLayer.session = newValue
                previewLayer.videoGravity = .resizeAspectFill
            }
        }

        /// Runs on every size change, including device rotation, so the preview
        /// always matches the UI orientation.
        override func layoutSubviews() {
            super.layoutSubviews()
            let orientation = window?.windowScene?.interfaceOrientation ?? .portrait
            CaptureOrientation.apply(orientation, to: previewLayer.connection)
        }
    }
}

// MARK: - Full camera screen

/// Camera screen: live preview + shutter button.
struct CameraView: View {

    @StateObject private var viewModel = CameraViewModel()
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isCapturing = false
    @State private var showPermissionAlert = false

    var body: some View {
        ZStack {
            // Live preview
            if viewModel.isSessionRunning {
                CameraPreviewView(session: viewModel.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack {
                Spacer()

                // Shutter button
                Button {
                    Task { await capturePhoto() }
                } label: {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                        .frame(width: 72, height: 72)
                        .overlay {
                            if isCapturing {
                                ProgressView().tint(.white)
                            }
                        }
                }
                .disabled(isCapturing || !viewModel.isSessionRunning)
                .padding(.bottom, 48)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        viewModel.stopSession()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .task {
            await viewModel.setup()
            viewModel.startSession()
        }
        .onChange(of: viewModel.captureError) { error in
            if case .permissionDenied = error {
                showPermissionAlert = true
            }
        }
        .alert("Camera Access Required",
               isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("MySyncPhotos needs access to your camera to take photos.")
        }
    }

    // MARK: - Capture

    private func capturePhoto() async {
        isCapturing = true
        defer { isCapturing = false }
        do {
            let image = try await viewModel.capturePhoto()
            await appState.syncEngine.handleCapture(image: image)
            dismiss()
        } catch {
            // CameraViewModel already publishes the error; nothing more to do here.
        }
    }
}
