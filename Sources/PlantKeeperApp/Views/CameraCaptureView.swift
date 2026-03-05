import SwiftUI

#if os(iOS)
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    let onImageData: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    static var preflightErrorMessage: String? {
        if configuredSourceType != nil {
            return nil
        }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            return "Photo capture is unavailable because NSCameraUsageDescription is missing in Info.plist."
        }
        return "Photo capture is unavailable because NSPhotoLibraryUsageDescription is missing in Info.plist."
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.configuredSourceType ?? .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageData: onImageData, dismiss: dismiss)
    }

    private static var configuredSourceType: UIImagePickerController.SourceType? {
        if UIImagePickerController.isSourceTypeAvailable(.camera),
           hasUsageDescription(for: "NSCameraUsageDescription") {
            return .camera
        }
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary),
           hasUsageDescription(for: "NSPhotoLibraryUsageDescription") {
            return .photoLibrary
        }
        return nil
    }

    private static func hasUsageDescription(for key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImageData: (Data?) -> Void
        let dismiss: DismissAction

        init(onImageData: @escaping (Data?) -> Void, dismiss: DismissAction) {
            self.onImageData = onImageData
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.originalImage] as? UIImage)
            onImageData(image?.jpegData(compressionQuality: 0.85))
            dismiss()
        }
    }
}

#else

struct CameraCaptureView: View {
    let onImageData: (Data?) -> Void

    var body: some View {
        Text("Camera is only available on iOS.")
            .onAppear { onImageData(nil) }
    }
}
#endif
