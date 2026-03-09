import XCTest
import CoreLocation
@testable import PlantKeeperApp
@testable import PlantKeeperCore

private enum TestLocationError: Error {
    case failed
}

final class PlantListViewModelTests: XCTestCase {
    @MainActor
    func testRequestCheckPresentsSheetAfterDelay() async throws {
        let plant = TestFixture.makePlant(id: UUID())
        let viewModel = await TestFixture.makeViewModel(plants: [plant])
        await viewModel.loadPlants()

        XCTAssertNil(viewModel.activeSheet)
        viewModel.requestCheck(plantID: plant.id)
        XCTAssertNil(viewModel.activeSheet)

        try await Task.sleep(nanoseconds: 180_000_000)

        guard case let .check(draft)? = viewModel.activeSheet else {
            XCTFail("Expected active check sheet after delay.")
            return
        }
        XCTAssertEqual(draft.plantID, plant.id)
    }

    @MainActor
    func testCheckSheetSurvivesLoadPlantsRefresh() async throws {
        let plant = TestFixture.makePlant(id: UUID())
        let viewModel = await TestFixture.makeViewModel(plants: [plant])
        await viewModel.loadPlants()

        viewModel.requestCheck(plantID: plant.id)
        try await Task.sleep(nanoseconds: 180_000_000)
        guard case .check? = viewModel.activeSheet else {
            XCTFail("Expected check sheet before reload.")
            return
        }

        await viewModel.loadPlants()
        guard case .check? = viewModel.activeSheet else {
            XCTFail("Expected check sheet after reload.")
            return
        }
    }

    @MainActor
    func testPresentSettingsLoadsInputsAndShowsSheet() async {
        let settingsStore = MockAppSettingsStore(
            coordinates: (name: "Yard", latitude: 50.01, longitude: 4.11),
            preferredPlantNameLanguage: .french
        )
        let viewModel = await TestFixture.makeViewModel(plants: [], settingsStore: settingsStore)

        await viewModel.presentSettings()

        XCTAssertTrue(viewModel.isPresentingSettings)
        XCTAssertEqual(viewModel.homeLocationNameInput, "Yard")
        XCTAssertEqual(viewModel.homeLatitudeInput, "50.01")
        XCTAssertEqual(viewModel.homeLongitudeInput, "4.11")
        XCTAssertEqual(viewModel.preferredPlantNameLanguageInput, .french)
    }

    @MainActor
    func testLoadPlantsUsesPreferredPlantNameLanguage() async {
        let plant = TestFixture.makePlant(nameEnglish: "Mint", nameFrench: "Menthe")
        let settingsStore = MockAppSettingsStore(preferredPlantNameLanguage: .french)
        let viewModel = await TestFixture.makeViewModel(plants: [plant], settingsStore: settingsStore)

        await viewModel.loadPlants()

        XCTAssertEqual(viewModel.rows.first?.displayName, "Menthe")
    }

    @MainActor
    func testValidateOpenAIKeyStoresSuccessMessage() async {
        let validator = MockOpenAIKeyValidator()
        let viewModel = await TestFixture.makeViewModel(plants: [], apiKeyValidator: validator)
        viewModel.openAIKeyInput = " sk-test "

        let isValid = await viewModel.validateOpenAIKey()

        XCTAssertTrue(isValid)
        XCTAssertEqual(validator.validatedKeys, ["sk-test"])
        XCTAssertEqual(viewModel.openAIKeyValidationMessage, "OpenAI key looks valid.")
        XCTAssertTrue(viewModel.isOpenAIKeyValidationSuccess)
        XCTAssertFalse(viewModel.isValidatingOpenAIKey)
    }

    @MainActor
    func testStartAndCancelDraftResetPresentationState() async {
        let plant = TestFixture.makePlant(nameEnglish: "Existing")
        let viewModel = await TestFixture.makeViewModel(plants: [plant])

        viewModel.startNewPlantDraft()
        XCTAssertTrue(viewModel.isPresentingAddPlant)
        XCTAssertNil(viewModel.editingPlantID)

        viewModel.cancelDraft()
        XCTAssertFalse(viewModel.isPresentingAddPlant)
        XCTAssertEqual(viewModel.activeDraft.nameEnglish, "")
    }

    @MainActor
    func testUseCurrentLocationForHomeUpdatesFields() async {
        let location = MockLocationService(latitude: 50.8503, longitude: 4.3517)
        let viewModel = await TestFixture.makeViewModel(plants: [], locationService: location)
        viewModel.homeLocationNameInput = "Home"

        await viewModel.useCurrentLocationForHome()

        XCTAssertEqual(viewModel.homeLatitudeInput, "50.850300")
        XCTAssertEqual(viewModel.homeLongitudeInput, "4.351700")
        XCTAssertEqual(viewModel.homeLocationNameInput, "Current Location")
        XCTAssertFalse(viewModel.isResolvingCurrentLocation)
    }

    @MainActor
    func testUseCurrentLocationForHomeStoresErrorOnFailure() async {
        let location = MockLocationService(error: TestLocationError.failed)
        let viewModel = await TestFixture.makeViewModel(plants: [], locationService: location)

        await viewModel.useCurrentLocationForHome()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isResolvingCurrentLocation)
    }

    @MainActor
    func testAnalyzePhotoAndPrefillAppliesResult() async {
        let result = AIAnalysisResult(
            nameEnglish: "Rose",
            nameFrench: "Rose FR",
            confidence: 0.8,
            suggestedWateringIntervalDays: 4,
            suggestedCheckIntervalDays: 2,
            careHints: []
        )
        let viewModel = await TestFixture.makeViewModel(plants: [], analyzer: MockPlantAnalyzer(result: result))

        await viewModel.analyzePhotoAndPrefill(Data([0x01]))

        XCTAssertEqual(viewModel.activeDraft.nameEnglish, "Rose")
        XCTAssertEqual(viewModel.activeDraft.nameFrench, "Rose FR")
        XCTAssertEqual(viewModel.activeDraft.wateringIntervalDays, 4)
        XCTAssertEqual(viewModel.activeDraft.checkIntervalDays, 2)
        XCTAssertNil(viewModel.draftStatusMessage)
    }

    @MainActor
    func testAnalyzePhotoAndPrefillStoresNoticeForPlaceholderResult() async {
        let result = AIAnalysisResult(
            nameEnglish: "Unknown Plant",
            nameFrench: "Plante inconnue",
            confidence: 0.35,
            suggestedWateringIntervalDays: 7,
            suggestedCheckIntervalDays: 3,
            careHints: ["Needs manual confirmation"],
            identificationStatus: .placeholder
        )
        let viewModel = await TestFixture.makeViewModel(plants: [], analyzer: MockPlantAnalyzer(result: result))

        await viewModel.analyzePhotoAndPrefill(Data([0x01]))

        XCTAssertEqual(viewModel.activeDraft.nameEnglish, "")
        XCTAssertEqual(viewModel.activeDraft.nameFrench, "")
        XCTAssertEqual(viewModel.activeDraft.aiConfidence, 0.35)
        XCTAssertEqual(
            viewModel.draftStatusMessage,
            "Photo saved, but plant identification needs an OpenAI API key in Settings."
        )
    }

    @MainActor
    func testAnalyzePhotoAndPrefillStoresErrorOnFailure() async {
        let viewModel = await TestFixture.makeViewModel(plants: [], analyzer: ThrowingPlantAnalyzer())

        await viewModel.analyzePhotoAndPrefill(Data([0x01]))

        XCTAssertEqual(viewModel.errorMessage, "Photo captured, but AI analysis failed.")
    }

    @MainActor
    func testRetryAIIdentificationUsesSavedPhotoIdentifier() async throws {
        let savedIdentifier = try PlantPhotoStore.savePhotoData(Data([0xAA, 0xBB]), for: UUID())
        let result = AIAnalysisResult(
            nameEnglish: "Fern",
            nameFrench: "Fougere",
            confidence: 0.84,
            suggestedWateringIntervalDays: 6,
            suggestedCheckIntervalDays: 2,
            careHints: []
        )
        let viewModel = await TestFixture.makeViewModel(plants: [], analyzer: MockPlantAnalyzer(result: result))
        viewModel.activeDraft.photoIdentifier = savedIdentifier

        await viewModel.retryAIIdentification()

        XCTAssertEqual(viewModel.activeDraft.nameEnglish, "Fern")
        XCTAssertEqual(viewModel.activeDraft.nameFrench, "Fougere")
        XCTAssertEqual(viewModel.activeDraft.wateringIntervalDays, 6)
        XCTAssertEqual(viewModel.activeDraft.checkIntervalDays, 2)
        if let url = PlantPhotoStore.photoURL(for: savedIdentifier) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    func testAddPlantFromDraftPersistsAndReloadsRows() async {
        let viewModel = await TestFixture.makeViewModel(plants: [])
        viewModel.startNewPlantDraft()
        viewModel.activeDraft.nameEnglish = "New Plant"
        viewModel.activeDraft.nameFrench = "Nouvelle Plante"

        await viewModel.addPlantFromDraft()

        XCTAssertFalse(viewModel.isPresentingAddPlant)
        XCTAssertTrue(viewModel.rows.contains(where: { $0.displayName == "New Plant" }))
    }

    @MainActor
    func testMarkWateredAndSnoozeFlow() async {
        let plant = TestFixture.makePlant(id: UUID(), nextWaterDueAt: Date(), nextCheckDueAt: Date())
        let viewModel = await TestFixture.makeViewModel(plants: [plant])
        await viewModel.loadPlants()

        await viewModel.markWatered(plantID: plant.id)
        XCTAssertTrue(viewModel.rows.contains(where: { $0.id == plant.id }))

        viewModel.requestSnooze(plantID: plant.id)
        XCTAssertEqual(viewModel.activeSnoozeDraft?.plantID, plant.id)
        if let draft = viewModel.activeSnoozeDraft {
            await viewModel.confirmSnooze(from: draft)
        }
        XCTAssertNil(viewModel.activeSnoozeDraft)
    }

    @MainActor
    func testCheckAndObservationFlowsClearSheet() async throws {
        let plant = TestFixture.makePlant(id: UUID(), nameEnglish: "CheckMe")
        let viewModel = await TestFixture.makeViewModel(plants: [plant])
        await viewModel.loadPlants()

        let checkDraft = CheckDraft(plantID: plant.id, plantName: "CheckMe")
        viewModel.activeSheet = .check(checkDraft)
        await viewModel.confirmCheckAllGood(from: checkDraft)
        XCTAssertNil(viewModel.activeSheet)

        viewModel.activeSheet = .check(checkDraft)
        await viewModel.saveCheckObservation(from: checkDraft, note: "Observed", photoData: Data([0x01]))
        XCTAssertNil(viewModel.activeSheet)
    }

    @MainActor
    func testWateringDateAndLogDeletionFlows() async {
        let now = Date(timeIntervalSince1970: 20_000)
        let earlier = now.addingTimeInterval(-3_600)
        let plant = TestFixture.makePlant(
            id: UUID(),
            wateringLogs: [WateringLog(timestamp: now), WateringLog(timestamp: earlier)],
            lastWateredAt: now,
            nextWaterDueAt: now,
            nextCheckDueAt: now
        )
        let viewModel = await TestFixture.makeViewModel(plants: [plant])
        await viewModel.loadPlants()

        let addDraft = WateringDateDraft(
            plantID: plant.id,
            plantName: "Basil",
            mode: .add,
            initialDate: now
        )
        viewModel.activeSheet = .wateringDate(addDraft)
        await viewModel.saveWateringDate(from: addDraft, selectedDate: now.addingTimeInterval(-7_200))
        XCTAssertNil(viewModel.activeSheet)

        let editDraft = WateringDateDraft(
            plantID: plant.id,
            plantName: "Basil",
            mode: .edit(sortedLogIndex: 0),
            initialDate: now
        )
        viewModel.activeSheet = .wateringDate(editDraft)
        await viewModel.saveWateringDate(from: editDraft, selectedDate: now.addingTimeInterval(-10_800))
        XCTAssertNil(viewModel.activeSheet)

        await viewModel.deleteWateringLog(plantID: plant.id, sortedLogIndex: 0)
        XCTAssertTrue(viewModel.rows.contains(where: { $0.id == plant.id }))
    }

    @MainActor
    func testHandleOverflowActionVariants() async {
        let plant = TestFixture.makePlant(id: UUID(), photoIdentifier: "existing.jpg", nameEnglish: "OverflowPlant")
        let viewModel = await TestFixture.makeViewModel(plants: [plant])
        await viewModel.loadPlants()

        await viewModel.handleOverflowAction(.setWateringDate, plantID: plant.id)
        if case let .wateringDate(draft)? = viewModel.activeSheet {
            XCTAssertEqual(draft.plantID, plant.id)
        } else {
            XCTFail("Expected watering-date sheet.")
        }

        await viewModel.handleOverflowAction(.wateringLogs, plantID: plant.id)
        if case let .wateringLogs(draft)? = viewModel.activeSheet {
            XCTAssertEqual(draft.plantID, plant.id)
        } else {
            XCTFail("Expected watering-logs sheet.")
        }

        await viewModel.handleOverflowAction(.edit, plantID: plant.id)
        XCTAssertEqual(viewModel.editingPlantID, plant.id)
        XCTAssertTrue(viewModel.isPresentingAddPlant)
        XCTAssertEqual(viewModel.activeDraft.photoIdentifier, "existing.jpg")

        await viewModel.handleOverflowAction(.markChecked, plantID: plant.id)
        XCTAssertNil(viewModel.errorMessage)

        await viewModel.handleOverflowAction(.delete, plantID: plant.id)
        XCTAssertFalse(viewModel.rows.contains(where: { $0.id == plant.id }))
    }

    @MainActor
    func testSaveSettingsClosesSheetAndReloadsPlants() async {
        let viewModel = await TestFixture.makeViewModel(plants: [])
        viewModel.isPresentingSettings = true
        viewModel.openAIKeyInput = "abc123"
        viewModel.homeLocationNameInput = "Terrace"
        viewModel.homeLatitudeInput = "50.0"
        viewModel.homeLongitudeInput = "4.0"

        await viewModel.saveSettings()

        XCTAssertFalse(viewModel.isPresentingSettings)
        XCTAssertNotNil(viewModel.rows)
    }

    @MainActor
    func testSaveSettingsKeepsSheetOpenWhenChangedKeyValidationFails() async {
        struct ValidationFailed: LocalizedError {
            var errorDescription: String? { "Invalid OpenAI key." }
        }

        let validator = MockOpenAIKeyValidator()
        validator.result = .failure(ValidationFailed())
        let viewModel = await TestFixture.makeViewModel(plants: [], apiKeyValidator: validator)
        viewModel.isPresentingSettings = true
        viewModel.openAIKeyInput = "bad-key"

        await viewModel.saveSettings()

        XCTAssertTrue(viewModel.isPresentingSettings)
        XCTAssertEqual(viewModel.openAIKeyValidationMessage, "Invalid OpenAI key.")
        XCTAssertFalse(viewModel.isOpenAIKeyValidationSuccess)
    }
}
