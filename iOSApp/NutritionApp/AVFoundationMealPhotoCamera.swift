import AVFoundation
import NutritionCore
import SwiftUI
import UIKit

/// `MealPhotoCamera` backed by the iPhone's back camera. Needs `NSCameraUsageDescription` in Info.plist
/// (see README). It only talks to the hardware; every decision about what the person sees is in
/// `MealPhotoCapture`.
final class AVFoundationMealPhotoCamera: NSObject, MealPhotoCamera {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "MealPhotoCamera.session")
    private var isConfigured = false
    private var pendingCapture: CheckedContinuation<CapturedMealPhoto, Error>?

    enum CameraError: Error {
        case noPhotoData
        case configurationFailed
    }

    private var backCamera: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    var hasCamera: Bool { backCamera != nil }

    var authorizationStatus: CameraAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Starts the live viewfinder. Call when the viewfinder appears.
    func start() {
        sessionQueue.async { [self] in
            if !isConfigured { isConfigured = configure() }
            if isConfigured, !session.isRunning { session.startRunning() }
        }
    }

    /// Stops the camera. Call when the capture view goes away.
    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capturePhoto() async throws -> CapturedMealPhoto {
        guard isConfigured else { throw CameraError.configurationFailed }
        return try await withCheckedThrowingContinuation { continuation in
            pendingCapture = continuation
            let settings = photoOutput.availablePhotoCodecTypes.contains(.jpeg)
                ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                : AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configure() -> Bool {
        guard let device = backCamera, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else { return false }
        session.addInput(input)
        session.addOutput(photoOutput)
        return true
    }
}

extension AVFoundationMealPhotoCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let continuation = pendingCapture
        pendingCapture = nil
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation?.resume(returning: CapturedMealPhoto(imageData: data, fileExtension: "jpg"))
        } else {
            continuation?.resume(throwing: CameraError.noPhotoData)
        }
    }
}

/// The live camera image behind the shutter button.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
