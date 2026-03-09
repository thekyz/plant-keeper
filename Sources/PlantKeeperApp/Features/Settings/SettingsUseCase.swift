import Foundation

struct SettingsFormData {
    var openAIKey: String
    var homeLocationName: String
    var homeLatitude: String
    var homeLongitude: String
    var preferredPlantNameLanguage: PlantNameLanguage
}

enum SettingsUseCaseError: LocalizedError {
    case keychainWriteFailed
    case keychainDeleteFailed

    var errorDescription: String? {
        switch self {
        case .keychainWriteFailed:
            return "Could not save OpenAI key to Keychain."
        case .keychainDeleteFailed:
            return "Could not remove OpenAI key from Keychain."
        }
    }
}

actor SettingsUseCase {
    private let appSettingsStore: any AppSettingsStoring
    private let keyStore: APIKeyStoring
    private let apiKeyValidator: any OpenAIKeyValidating

    init(
        appSettingsStore: any AppSettingsStoring,
        keyStore: APIKeyStoring,
        apiKeyValidator: any OpenAIKeyValidating
    ) {
        self.appSettingsStore = appSettingsStore
        self.keyStore = keyStore
        self.apiKeyValidator = apiKeyValidator
    }

    func loadFormData() async throws -> SettingsFormData {
        let openAIKey = keyStore.loadCloudAPIKey() ?? ""
        let preferredPlantNameLanguage = try await appSettingsStore.preferredPlantNameLanguage()
        if let home = try await appSettingsStore.homeCoordinates() {
            return SettingsFormData(
                openAIKey: openAIKey,
                homeLocationName: home.name,
                homeLatitude: String(home.latitude),
                homeLongitude: String(home.longitude),
                preferredPlantNameLanguage: preferredPlantNameLanguage
            )
        }

        return SettingsFormData(
            openAIKey: openAIKey,
            homeLocationName: "Home",
            homeLatitude: "",
            homeLongitude: "",
            preferredPlantNameLanguage: preferredPlantNameLanguage
        )
    }

    func saveFormData(_ data: SettingsFormData) async throws {
        let key = data.openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            guard keyStore.removeCloudAPIKey() else {
                throw SettingsUseCaseError.keychainDeleteFailed
            }
        } else {
            guard keyStore.saveCloudAPIKey(key) else {
                throw SettingsUseCaseError.keychainWriteFailed
            }
        }

        try await appSettingsStore.updateHomeLocation(
            name: data.homeLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Home" : data.homeLocationName,
            latitude: Double(data.homeLatitude),
            longitude: Double(data.homeLongitude)
        )
        try await appSettingsStore.updatePreferredPlantNameLanguage(data.preferredPlantNameLanguage)
    }

    func validateOpenAIKey(_ key: String) async throws {
        try await apiKeyValidator.validateAPIKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
