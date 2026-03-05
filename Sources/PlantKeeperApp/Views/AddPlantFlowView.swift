import SwiftUI

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
                    if viewModel.activeDraft.photoData != nil {
                        Text("Photo captured")
                    } else {
                        Text("No photo selected")
                            .foregroundStyle(.secondary)
                    }
                    if isAnalyzing {
                        ProgressView("Analyzing plant...")
                    }

                    Button("Take Photo") { startPhotoCapture() }
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
            .navigationTitle("Add Plant")
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
                    Button("Save") {
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
        viewModel.activeDraft.photoData = imageData
        guard let imageData else { return }
        Task {
            isAnalyzing = true
            await viewModel.analyzePhotoAndPrefill(imageData)
            isAnalyzing = false
        }
    }
}
