import NutritionCore
import Observation
import SwiftUI
import UIKit

/// Observable mirror of `MealPhotoCapture`. Holds no decisions of its own.
@Observable
@MainActor
final class MealPhotoCaptureModel: Identifiable {
    private let capture: MealPhotoCapture
    let camera: AVFoundationMealPhotoCamera

    private(set) var step: MealPhotoCaptureStep = .notStarted
    private(set) var captureErrorMessage: String?

    init(camera: AVFoundationMealPhotoCamera, capture: MealPhotoCapture) {
        self.camera = camera
        self.capture = capture
    }

    func open() async {
        await capture.open()
        republish()
    }

    func takePhoto() async {
        await capture.takePhoto()
        republish()
    }

    func retake() {
        capture.retake()
        republish()
    }

    func usePhoto() {
        capture.usePhoto()
        republish()
    }

    func choosePhotoLibrary() {
        capture.choosePhotoLibrary()
        republish()
    }

    private func republish() {
        step = capture.step
        captureErrorMessage = capture.captureErrorMessage
    }
}

/// Full-screen camera: viewfinder, review with Retake / Use Photo, or an explanation when the camera
/// can't be used. Calls `onClose` when the person is done, with whether they chose the photo library.
struct MealPhotoCaptureView: View {
    let model: MealPhotoCaptureModel
    let onClose: (_ choosePhotoLibrary: Bool) -> Void

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onClose(false) } }
                }
        }
        .task { await model.open() }
        .onDisappear { model.camera.stop() }
        .onChange(of: model.step) { _, step in
            switch step {
            case .finished: onClose(false)
            case .photoLibraryChosen: onClose(true)
            default: break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .notStarted, .finished, .photoLibraryChosen:
            ProgressView()
        case .viewfinder:
            ZStack(alignment: .bottom) {
                CameraPreview(session: model.camera.session).ignoresSafeArea()
                VStack(spacing: 12) {
                    if let message = model.captureErrorMessage {
                        Text(message).padding(8).background(.thinMaterial, in: Capsule())
                    }
                    Button {
                        Task { await model.takePhoto() }
                    } label: {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                    }
                    .accessibilityLabel("Take meal photo")
                }
                .padding(.bottom, 24)
            }
            .onAppear { model.camera.start() }
        case .reviewing(let photo):
            VStack {
                if let image = UIImage(data: photo.imageData) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
                HStack {
                    Button("Retake") { model.retake() }
                    Spacer()
                    Button("Use Photo") { model.usePhoto() }.bold()
                }
                .padding()
            }
        case .cameraUnavailable(let explanation):
            ContentUnavailableView {
                Label(explanation.title, systemImage: "camera")
            } description: {
                Text(explanation.message)
            } actions: {
                if let settingsTitle = explanation.settingsActionTitle,
                   let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Button(settingsTitle) { UIApplication.shared.open(settingsURL) }
                }
                Button(explanation.photoLibraryActionTitle) { model.choosePhotoLibrary() }
            }
        }
    }
}
