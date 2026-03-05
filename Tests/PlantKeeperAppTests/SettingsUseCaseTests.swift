import XCTest
@testable import PlantKeeperApp

private final class RecordingKeyStore: @unchecked Sendable, APIKeyStoring {
    var loadedKey: String?
    var saveResult = true
    var removeResult = true
    var lastSavedKey: String?
    var removeCalled = false

    func loadCloudAPIKey() -> String? { loadedKey }

    func saveCloudAPIKey(_ key: String) -> Bool {
        lastSavedKey = key
        return saveResult
    }

    func removeCloudAPIKey() -> Bool {
        removeCalled = true
        return removeResult
    }
}

final class SettingsUseCaseTests: XCTestCase {
    func testLoadFormDataReturnsStoredKeyAndCoordinates() async throws {
        let settingsStore = MockAppSettingsStore(
            coordinates: (name: "Patio", latitude: 50.5, longitude: 4.2)
        )
        let keyStore = RecordingKeyStore()
        keyStore.loadedKey = "secret"
        let useCase = SettingsUseCase(appSettingsStore: settingsStore, keyStore: keyStore)

        let form = try await useCase.loadFormData()

        XCTAssertEqual(form.openAIKey, "secret")
        XCTAssertEqual(form.homeLocationName, "Patio")
        XCTAssertEqual(form.homeLatitude, "50.5")
        XCTAssertEqual(form.homeLongitude, "4.2")
    }

    func testLoadFormDataFallsBackToDefaultHomeValues() async throws {
        let useCase = SettingsUseCase(
            appSettingsStore: MockAppSettingsStore(),
            keyStore: RecordingKeyStore()
        )

        let form = try await useCase.loadFormData()

        XCTAssertEqual(form.homeLocationName, "Home")
        XCTAssertEqual(form.homeLatitude, "")
        XCTAssertEqual(form.homeLongitude, "")
    }

    func testSaveFormDataSavesTrimmedKeyAndCoordinates() async throws {
        let settingsStore = MockAppSettingsStore()
        let keyStore = RecordingKeyStore()
        let useCase = SettingsUseCase(appSettingsStore: settingsStore, keyStore: keyStore)

        try await useCase.saveFormData(
            SettingsFormData(
                openAIKey: "  key-123  ",
                homeLocationName: "  Garden  ",
                homeLatitude: "50.12",
                homeLongitude: "4.31"
            )
        )

        XCTAssertEqual(keyStore.lastSavedKey, "key-123")
        let updated = await settingsStore.lastUpdatedHome
        XCTAssertEqual(updated?.name, "  Garden  ")
        XCTAssertEqual(updated?.latitude, 50.12)
        XCTAssertEqual(updated?.longitude, 4.31)
    }

    func testSaveFormDataUsesDefaultHomeNameWhenBlank() async throws {
        let settingsStore = MockAppSettingsStore()
        let keyStore = RecordingKeyStore()
        let useCase = SettingsUseCase(appSettingsStore: settingsStore, keyStore: keyStore)

        try await useCase.saveFormData(
            SettingsFormData(
                openAIKey: "key",
                homeLocationName: "   ",
                homeLatitude: "",
                homeLongitude: ""
            )
        )

        let updated = await settingsStore.lastUpdatedHome
        XCTAssertEqual(updated?.name, "Home")
        XCTAssertNil(updated?.latitude)
        XCTAssertNil(updated?.longitude)
    }

    func testSaveFormDataThrowsWhenKeyWriteFails() async {
        let settingsStore = MockAppSettingsStore()
        let keyStore = RecordingKeyStore()
        keyStore.saveResult = false
        let useCase = SettingsUseCase(appSettingsStore: settingsStore, keyStore: keyStore)

        do {
            try await useCase.saveFormData(
                SettingsFormData(
                    openAIKey: "key",
                    homeLocationName: "Home",
                    homeLatitude: "",
                    homeLongitude: ""
                )
            )
            XCTFail("Expected save to throw.")
        } catch let error as SettingsUseCaseError {
            switch error {
            case .keychainWriteFailed:
                break
            default:
                XCTFail("Expected keychainWriteFailed, got \(error).")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveFormDataThrowsWhenKeyDeleteFails() async {
        let settingsStore = MockAppSettingsStore()
        let keyStore = RecordingKeyStore()
        keyStore.removeResult = false
        let useCase = SettingsUseCase(appSettingsStore: settingsStore, keyStore: keyStore)

        do {
            try await useCase.saveFormData(
                SettingsFormData(
                    openAIKey: "   ",
                    homeLocationName: "Home",
                    homeLatitude: "",
                    homeLongitude: ""
                )
            )
            XCTFail("Expected save to throw.")
        } catch let error as SettingsUseCaseError {
            switch error {
            case .keychainDeleteFailed:
                break
            default:
                XCTFail("Expected keychainDeleteFailed, got \(error).")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(keyStore.removeCalled)
    }
}
