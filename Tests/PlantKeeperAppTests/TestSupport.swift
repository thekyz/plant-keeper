import Foundation
import CoreLocation
import SwiftData
@testable import PlantKeeperApp
@testable import PlantKeeperCore

actor MockPlantStore: PlantStore {
    private var plants: [UUID: PlantRecord]
    private(set) var upsertedPlantIDs: [UUID] = []
    private(set) var deletedPlantIDs: [UUID] = []

    init(plants: [PlantRecord] = []) {
        self.plants = Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0) })
    }

    func allPlants() async throws -> [PlantRecord] {
        Array(plants.values)
    }

    func upsert(_ plant: PlantRecord) async throws {
        plants[plant.id] = plant
        upsertedPlantIDs.append(plant.id)
    }

    func delete(plantID: UUID) async throws {
        plants.removeValue(forKey: plantID)
        deletedPlantIDs.append(plantID)
    }

    func plant(withID id: UUID) async throws -> PlantRecord? {
        plants[id]
    }

    func setPlant(_ plant: PlantRecord) {
        plants[plant.id] = plant
    }
}

actor MockAppSettingsStore: AppSettingsStoring {
    var digest: (hour: Int, minute: Int)
    var coordinates: (name: String, latitude: Double, longitude: Double)?
    var storedPreferredPlantNameLanguage: PlantNameLanguage
    private(set) var lastUpdatedHome: (name: String, latitude: Double?, longitude: Double?)?
    private(set) var lastUpdatedPreferredPlantNameLanguage: PlantNameLanguage?

    init(
        digest: (hour: Int, minute: Int) = (9, 0),
        coordinates: (name: String, latitude: Double, longitude: Double)? = nil,
        preferredPlantNameLanguage: PlantNameLanguage = .english
    ) {
        self.digest = digest
        self.coordinates = coordinates
        self.storedPreferredPlantNameLanguage = preferredPlantNameLanguage
    }

    func updateHomeLocation(name: String, latitude: Double?, longitude: Double?) async throws {
        lastUpdatedHome = (name, latitude, longitude)
        if let latitude, let longitude {
            coordinates = (name, latitude, longitude)
        } else {
            coordinates = nil
        }
    }

    func homeCoordinates() async throws -> (name: String, latitude: Double, longitude: Double)? {
        coordinates
    }

    func digestTime() async throws -> (hour: Int, minute: Int) {
        digest
    }

    func updatePreferredPlantNameLanguage(_ language: PlantNameLanguage) async throws {
        storedPreferredPlantNameLanguage = language
        lastUpdatedPreferredPlantNameLanguage = language
    }

    func preferredPlantNameLanguage() async throws -> PlantNameLanguage {
        storedPreferredPlantNameLanguage
    }
}

actor MockNotificationScheduler: NotificationScheduling {
    private(set) var requestedAuthorization = false
    private(set) var scheduledDigest: (hour: Int, minute: Int)?
    private(set) var refreshedPayload: (count: Int, now: Date)?

    func requestAuthorizationIfNeeded() async {
        requestedAuthorization = true
    }

    func scheduleDailyDigest(hour: Int, minute: Int) async {
        scheduledDigest = (hour, minute)
    }

    func refreshUrgencyNotifications(plants: [PlantRecord], now: Date) async {
        refreshedPayload = (plants.count, now)
    }
}

struct MockAPIKeyStore: APIKeyStoring {
    var loadedKey: String?
    var saveResult = true
    var removeResult = true

    func loadCloudAPIKey() -> String? { loadedKey }
    func saveCloudAPIKey(_ key: String) -> Bool { saveResult }
    func removeCloudAPIKey() -> Bool { removeResult }
}

final class MockOpenAIKeyValidator: @unchecked Sendable, OpenAIKeyValidating {
    var result: Result<Void, Error> = .success(())
    private(set) var validatedKeys: [String] = []

    func validateAPIKey(_ key: String) async throws {
        validatedKeys.append(key)
        try result.get()
    }
}

struct MockPlantAnalyzer: PlantAnalyzing {
    let result: AIAnalysisResult

    init(
        result: AIAnalysisResult = AIAnalysisResult(
            nameEnglish: "Stub",
            nameFrench: "Stub",
            confidence: 0.9,
            suggestedWateringIntervalDays: 7,
            suggestedCheckIntervalDays: 3,
            careHints: []
        )
    ) {
        self.result = result
    }

    func analyzePhotoData(_ data: Data) async throws -> AIAnalysisResult {
        result
    }
}

struct ThrowingPlantAnalyzer: PlantAnalyzing {
    struct ErrorStub: Error {}
    func analyzePhotoData(_ data: Data) async throws -> AIAnalysisResult {
        throw ErrorStub()
    }
}

struct MockLocationService: DeviceLocationProviding {
    var result: Result<CLLocationCoordinate2D, Error>

    init(latitude: Double = 0, longitude: Double = 0) {
        result = .success(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    init(error: Error) {
        result = .failure(error)
    }

    func requestCurrentLocation() async throws -> CLLocationCoordinate2D {
        try result.get()
    }
}

enum TestFixture {
    static func makePlant(
        id: UUID = UUID(),
        createdAt: Date = Date(timeIntervalSince1970: 1_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_000_000),
        photoIdentifier: String? = nil,
        nameEnglish: String = "Basil",
        nameFrench: String = "Basilic",
        isOutdoor: Bool = false,
        wateringIntervalDays: Int = 2,
        checkIntervalDays: Int = 1,
        wateringLogs: [WateringLog] = [],
        lastWateredAt: Date? = nil,
        lastCheckedAt: Date? = nil,
        nextWaterDueAt: Date = Date(timeIntervalSince1970: 1_000_000),
        nextCheckDueAt: Date = Date(timeIntervalSince1970: 1_000_000),
        notes: String = "",
        aiCareHints: [String] = [],
        aiConfidence: Double? = nil
    ) -> PlantRecord {
        PlantRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            photoIdentifier: photoIdentifier,
            nameEnglish: nameEnglish,
            nameFrench: nameFrench,
            isOutdoor: isOutdoor,
            wateringIntervalDays: wateringIntervalDays,
            checkIntervalDays: checkIntervalDays,
            wateringLogs: wateringLogs,
            lastWateredAt: lastWateredAt,
            lastCheckedAt: lastCheckedAt,
            nextWaterDueAt: nextWaterDueAt,
            nextCheckDueAt: nextCheckDueAt,
            notes: notes,
            aiCareHints: aiCareHints,
            aiConfidence: aiConfidence
        )
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([PlantEntity.self, AppSettingsEntity.self])
        let configuration = ModelConfiguration(
            "PlantKeeperTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    static func makeViewModel(
        plants: [PlantRecord],
        analyzer: any PlantAnalyzing = MockPlantAnalyzer(),
        settingsStore: MockAppSettingsStore = MockAppSettingsStore(),
        notificationScheduler: MockNotificationScheduler = MockNotificationScheduler(),
        locationService: DeviceLocationProviding = MockLocationService(),
        apiKeyValidator: MockOpenAIKeyValidator = MockOpenAIKeyValidator()
    ) async -> PlantListViewModel {
        let store = MockPlantStore(plants: plants)
        let plantService = PlantService(store: store)
        let plantListUseCase = PlantListUseCase(
            plantService: plantService,
            repository: store,
            notificationScheduler: notificationScheduler,
            appSettingsStore: settingsStore
        )
        let plantEditorUseCase = PlantEditorUseCase(repository: store, aiService: analyzer)
        let settingsUseCase = SettingsUseCase(
            appSettingsStore: settingsStore,
            keyStore: MockAPIKeyStore(),
            apiKeyValidator: apiKeyValidator
        )

        return PlantListViewModel(
            plantListUseCase: plantListUseCase,
            plantEditorUseCase: plantEditorUseCase,
            settingsUseCase: settingsUseCase,
            locationService: locationService
        )
    }
}
