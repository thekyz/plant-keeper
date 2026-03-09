import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PlantListViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI") {
                    SecureField("OpenAI API key", text: $viewModel.openAIKeyInput)
                    Button {
                        Task { await viewModel.validateOpenAIKey() }
                    } label: {
                        Label("Check Key", systemImage: "checkmark.shield")
                    }
                    .disabled(viewModel.isValidatingOpenAIKey || !viewModel.canValidateOpenAIKey)
                    if viewModel.isValidatingOpenAIKey {
                        ProgressView("Checking key...")
                    }
                    if let validationMessage = viewModel.openAIKeyValidationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(viewModel.isOpenAIKeyValidationSuccess ? .green : .red)
                    }
                    Text("Used for cloud fallback when on-device confidence is low.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Home Outdoor Location") {
                    TextField("Location name", text: $viewModel.homeLocationNameInput)
                    Button {
                        Task { await viewModel.useCurrentLocationForHome() }
                    } label: {
                        Label("Use Current Location", systemImage: "location.fill")
                    }
                    .disabled(viewModel.isResolvingCurrentLocation)
                    if viewModel.isResolvingCurrentLocation {
                        ProgressView("Resolving location...")
                    }
                    #if os(iOS)
                    TextField("Latitude", text: $viewModel.homeLatitudeInput)
                        .keyboardType(.decimalPad)
                    TextField("Longitude", text: $viewModel.homeLongitudeInput)
                        .keyboardType(.decimalPad)
                    #else
                    TextField("Latitude", text: $viewModel.homeLatitudeInput)
                    TextField("Longitude", text: $viewModel.homeLongitudeInput)
                    #endif
                    Text("WeatherKit adjustments are applied only to outdoor plants.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationCornerRadius(0)
            #endif
            .toolbar {
                ToolbarItem {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem {
                    Button("Save") {
                        Task { await viewModel.saveSettings() }
                    }
                }
            }
        }
    }
}
