import SwiftUI

#if os(iOS)
import UIKit
private typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct AddPlantFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PlantListViewModel

    @State private var showingCamera = false
    @State private var isAnalyzing = false
    @State private var photoCaptureError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    if let selectedPhotoImage {
                        platformImageView(selectedPhotoImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    Text(photoStatusText)
                        .foregroundStyle(selectedPhotoImage == nil ? .secondary : .primary)
                    if isAnalyzing {
                        ProgressView("Analyzing plant...")
                    }
                    if let draftStatusMessage = viewModel.draftStatusMessage {
                        Text(draftStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(photoButtonTitle) { startPhotoCapture() }
                }

                Section("Plant Names") {
                    TextField("English name", text: $viewModel.activeDraft.nameEnglish)
                    TextField("French name", text: $viewModel.activeDraft.nameFrench)
                }

                Section("Care") {
                    Toggle("Outdoor plant", isOn: $viewModel.activeDraft.isOutdoor)
                    Stepper("Water every \(viewModel.activeDraft.wateringIntervalDays) day(s)", value: $viewModel.activeDraft.wateringIntervalDays, in: 1...60)
                    Stepper("Check every \(viewModel.activeDraft.checkIntervalDays) day(s)", value: $viewModel.activeDraft.checkIntervalDays, in: 1...60)
                }

                Section("Notes") {
                    TextEditor(text: $viewModel.activeDraft.notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(isEditing ? "Edit Plant" : "Add Plant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Button("Cancel") {
                        viewModel.cancelDraft()
                        dismiss()
                    }
                }
                ToolbarItem {
                    Button(isEditing ? "Update" : "Save") {
                        Task { await viewModel.addPlantFromDraft() }
                    }
                    .disabled(viewModel.activeDraft.nameEnglish.isEmpty && viewModel.activeDraft.nameFrench.isEmpty)
                }
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationCornerRadius(0)
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView(onImageData: handleCapturedImageData)
            }
            #else
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView(onImageData: handleCapturedImageData)
            }
            #endif
            .alert(
                "Photo Unavailable",
                isPresented: Binding(
                    get: { photoCaptureError != nil },
                    set: { newValue in
                        if !newValue { photoCaptureError = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(photoCaptureError ?? "Unknown error")
            }
        }
    }

    private func startPhotoCapture() {
        #if os(iOS)
        if let preflightError = CameraCaptureView.preflightErrorMessage {
            photoCaptureError = preflightError
            return
        }
        #endif
        showingCamera = true
    }

    private func handleCapturedImageData(_ imageData: Data?) {
        guard let imageData else { return }
        viewModel.activeDraft.photoData = imageData
        viewModel.activeDraft.photoIdentifier = nil
        viewModel.draftStatusMessage = nil
        Task {
            isAnalyzing = true
            await viewModel.analyzePhotoAndPrefill(imageData)
            isAnalyzing = false
        }
    }

    private var isEditing: Bool {
        viewModel.editingPlantID != nil
    }

    private var photoButtonTitle: String {
        selectedPhotoImage == nil ? "Take Photo" : "Replace Photo"
    }

    private var photoStatusText: String {
        selectedPhotoImage == nil ? "No photo selected" : "Photo selected"
    }

    private var selectedPhotoImage: PlatformImage? {
        if let photoData = viewModel.activeDraft.photoData,
           let image = PlatformImage(data: photoData) {
            return image
        }

        guard
            let photoURL = PlantPhotoStore.photoURL(for: viewModel.activeDraft.photoIdentifier),
            FileManager.default.fileExists(atPath: photoURL.path)
        else {
            return nil
        }

        return PlatformImage(contentsOfFile: photoURL.path)
    }

    @ViewBuilder
    private func platformImageView(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}
