import SwiftUI

struct CheckInSheetView: View {
    let plantName: String
    let onMarkGood: () -> Void
    let onSaveNote: (String, Data?) -> Void
    let onCancel: () -> Void

    @State private var note = ""
    @State private var photoData: Data?
    @State private var showingCamera = false
    @State private var photoCaptureError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("All good?")
                        .font(.headline)
                    Text(plantName)
                        .foregroundStyle(.secondary)

                    Button {
                        submitCheck()
                    } label: {
                        Text("Yes!")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }

                Section("Observation") {
                    ZStack(alignment: .topLeading) {
                        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Add a note ...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $note)
                    }
                    .frame(minHeight: 120)

                    if photoData != nil {
                        Label("Photo attached", systemImage: "photo.fill")
                            .foregroundStyle(.secondary)
                    }

                    #if os(iOS)
                    Button(photoData == nil ? "Add Photo" : "Retake Photo") {
                        startPhotoCapture()
                    }
                    #endif
                }
            }
            .navigationTitle("Checking")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            #if os(iOS)
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
        photoData = imageData
    }

    private func submitCheck() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNote.isEmpty && photoData == nil {
            onMarkGood()
        } else {
            onSaveNote(note, photoData)
        }
    }
}
