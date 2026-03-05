import XCTest
@testable import PlantKeeperApp
@testable import PlantKeeperCore
import CoreLocation

private actor InMemoryPlantStore: PlantStore {
    private var plants: [UUID: PlantRecord]

    init(plants: [PlantRecord]) {
        self.plants = Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0) })
    }

    func allPlants() async throws -> [PlantRecord] {
        Array(plants.values)
    }

    func upsert(_ plant: PlantRecord) async throws {
        plants[plant.id] = plant
    }

    func delete(plantID: UUID) async throws {
        plants.removeValue(forKey: plantID)
    }

    func plant(withID id: UUID) async throws -> PlantRecord? {
        plants[id]
    }
}

private struct NoopNotificationScheduler: NotificationScheduling {
    func requestAuthorizationIfNeeded() async {}
    func scheduleDailyDigest(hour: Int, minute: Int) async {}
    func refreshUrgencyNotifications(plants: [PlantRecord], now: Date) async {}
}

private actor StubAppSettingsStore: AppSettingsStoring {
    func updateHomeLocation(name: String, latitude: Double?, longitude: Double?) async throws {}
    func homeCoordinates() async throws -> (name: String, latitude: Double, longitude: Double)? { nil }
    func digestTime() async throws -> (hour: Int, minute: Int) { (9, 0) }
}

private struct StubKeyStore: APIKeyStoring {
    func loadCloudAPIKey() -> String? { nil }
    func saveCloudAPIKey(_ key: String) -> Bool { true }
    func removeCloudAPIKey() -> Bool { true }
}

private struct StubAnalyzer: PlantAnalyzing {
    func analyzePhotoData(_ data: Data) async throws -> AIAnalysisResult {
        AIAnalysisResult(
            nameEnglish: "Stub",
            nameFrench: "Stub",
            confidence: 0.9,
            suggestedWateringIntervalDays: 7,
            suggestedCheckIntervalDays: 3,
            careHints: []
        )
    }
}

private struct StubLocationService: DeviceLocationProviding {
    func requestCurrentLocation() async throws -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
}

final class PlantListViewModelTests: XCTestCase {
    @MainActor
    func testRequestCheckPresentsSheetAfterDelay() async throws {
        let plant = makePlant(id: UUID())
        let viewModel = await makeViewModel(plants: [plant])
        await viewModel.loadPlants()

        XCTAssertNil(viewModel.activeSheet)
        viewModel.requestCheck(plantID: plant.id)
        XCTAssertNil(viewModel.activeSheet, "Check sheet should not present synchronously in the same tap cycle.")

        try await Task.sleep(nanoseconds: 180_000_000)

        guard case let .check(draft)? = viewModel.activeSheet else {
            XCTFail("Expected active check sheet after delay.")
            return
        }
        XCTAssertEqual(draft.plantID, plant.id)
    }

    @MainActor
    func testCheckSheetSurvivesLoadPlantsRefresh() async throws {
        let plant = makePlant(id: UUID())
        let viewModel = await makeViewModel(plants: [plant])
        await viewModel.loadPlants()

        viewModel.requestCheck(plantID: plant.id)
        try await Task.sleep(nanoseconds: 180_000_000)

        guard case .check? = viewModel.activeSheet else {
            XCTFail("Expected check sheet to be active before reload.")
            return
        }

        await viewModel.loadPlants()

        guard case .check? = viewModel.activeSheet else {
            XCTFail("Expected check sheet to remain active after reload.")
            return
        }
    }

    @MainActor
    private func makeViewModel(plants: [PlantRecord]) async -> PlantListViewModel {
        let store = InMemoryPlantStore(plants: plants)
        let settingsStore = StubAppSettingsStore()
        let plantService = PlantService(store: store)
        let plantListUseCase = PlantListUseCase(
            plantService: plantService,
            repository: store,
            notificationScheduler: NoopNotificationScheduler(),
            appSettingsStore: settingsStore
        )
        let plantEditorUseCase = PlantEditorUseCase(repository: store, aiService: StubAnalyzer())
        let settingsUseCase = SettingsUseCase(appSettingsStore: settingsStore, keyStore: StubKeyStore())

        return PlantListViewModel(
            plantListUseCase: plantListUseCase,
            plantEditorUseCase: plantEditorUseCase,
            settingsUseCase: settingsUseCase,
            locationService: StubLocationService()
        )
    }

    private func makePlant(id: UUID) -> PlantRecord {
        let now = Date()
        return PlantRecord(
            id: id,
            nameEnglish: "Basil",
            nameFrench: "Basilic",
            isOutdoor: false,
            wateringIntervalDays: 2,
            checkIntervalDays: 1,
            nextWaterDueAt: now,
            nextCheckDueAt: now
        )
    }
}
