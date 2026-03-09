import XCTest
import SwiftData
@testable import PlantKeeperApp
@testable import PlantKeeperCore

final class PersistenceAndModelTests: XCTestCase {
    func testAppSettingsEntityDefaults() async throws {
        let container = try TestFixture.makeInMemoryContainer()
        let store = AppSettingsStore(modelContainer: container)

        let initialCoordinates = try await store.homeCoordinates()
        XCTAssertNil(initialCoordinates)
        let digest = try await store.digestTime()
        XCTAssertEqual(digest.hour, 9)
        XCTAssertEqual(digest.minute, 0)

        let context = ModelContext(container)
        let settingsID = AppSettingsEntity.singletonID
        let descriptor = FetchDescriptor<AppSettingsEntity>(
            predicate: #Predicate { $0.id == settingsID }
        )
        let entity = try XCTUnwrap(context.fetch(descriptor).first)

        XCTAssertEqual(entity.id, AppSettingsEntity.singletonID)
        XCTAssertEqual(entity.homeLocationName, "Home")
        XCTAssertNil(entity.latitude)
        XCTAssertNil(entity.longitude)
        XCTAssertEqual(entity.dailyDigestHour, 9)
        XCTAssertEqual(entity.dailyDigestMinute, 0)
    }

    func testPlantEntityRoundTripWithWateringLogs() {
        let logA = WateringLog(timestamp: Date(timeIntervalSince1970: 10))
        let logB = WateringLog(timestamp: Date(timeIntervalSince1970: 20))
        let record = TestFixture.makePlant(
            wateringLogs: [logA, logB],
            lastWateredAt: logB.timestamp,
            notes: "notes"
        )

        let entity = PlantEntity(from: record)
        let mapped = entity.asRecord

        XCTAssertEqual(mapped.id, record.id)
        XCTAssertEqual(mapped.wateringLogs, [logA, logB])
        XCTAssertEqual(mapped.lastWateredAt, logB.timestamp)
        XCTAssertEqual(mapped.notes, "notes")
    }

    func testPlantEntityUsesLegacyLastWateredAsFallbackLogWhenDecodingEmptyLogs() {
        let lastWatered = Date(timeIntervalSince1970: 99)
        let record = TestFixture.makePlant(
            wateringLogs: [],
            lastWateredAt: lastWatered
        )
        let entity = PlantEntity(from: record)
        entity.wateringLogsData = nil

        let mapped = entity.asRecord

        XCTAssertEqual(mapped.wateringLogs, [WateringLog(timestamp: lastWatered)])
    }

    func testPlantEntityUpdateFromRecord() {
        let initial = TestFixture.makePlant(nameEnglish: "Before")
        let entity = PlantEntity(from: initial)
        let updated = TestFixture.makePlant(
            id: initial.id,
            nameEnglish: "After",
            nameFrench: "Apres",
            isOutdoor: true,
            wateringIntervalDays: 9,
            checkIntervalDays: 5,
            notes: "updated",
            aiConfidence: 0.5
        )

        entity.update(from: updated)

        XCTAssertEqual(entity.nameEnglish, "After")
        XCTAssertEqual(entity.nameFrench, "Apres")
        XCTAssertTrue(entity.isOutdoor)
        XCTAssertEqual(entity.wateringIntervalDays, 9)
        XCTAssertEqual(entity.checkIntervalDays, 5)
        XCTAssertEqual(entity.notes, "updated")
        XCTAssertEqual(entity.aiConfidence, 0.5)
    }

    func testAppSettingsStoreCRUD() async throws {
        let container = try TestFixture.makeInMemoryContainer()
        let defaultsSuiteName = "PersistenceAndModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        let store = AppSettingsStore(modelContainer: container, userDefaults: defaults)
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let initialCoordinates = try await store.homeCoordinates()
        XCTAssertNil(initialCoordinates)
        let digest = try await store.digestTime()
        XCTAssertEqual(digest.hour, 9)
        XCTAssertEqual(digest.minute, 0)

        try await store.updateHomeLocation(name: "Garden", latitude: 50.85, longitude: 4.35)
        try await store.updatePreferredPlantNameLanguage(.french)
        let coords = try await store.homeCoordinates()
        let preferredPlantNameLanguage = try await store.preferredPlantNameLanguage()

        XCTAssertEqual(coords?.name, "Garden")
        XCTAssertEqual(coords?.latitude, 50.85)
        XCTAssertEqual(coords?.longitude, 4.35)
        XCTAssertEqual(preferredPlantNameLanguage, .french)
    }

    func testSwiftDataPlantRepositoryUpsertFetchAndDelete() async throws {
        let container = try TestFixture.makeInMemoryContainer()
        let repository = SwiftDataPlantRepository(modelContainer: container)
        let plant = TestFixture.makePlant(nameEnglish: "RepoPlant")

        try await repository.upsert(plant)
        var all = try await repository.allPlants()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.nameEnglish, "RepoPlant")
        let fetched = try await repository.plant(withID: plant.id)
        XCTAssertEqual(fetched?.id, plant.id)

        var updated = plant
        updated.nameEnglish = "Updated"
        try await repository.upsert(updated)
        all = try await repository.allPlants()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.nameEnglish, "Updated")

        try await repository.delete(plantID: plant.id)
        let deleted = try await repository.plant(withID: plant.id)
        XCTAssertNil(deleted)
        let remaining = try await repository.allPlants()
        XCTAssertTrue(remaining.isEmpty)
    }

    @MainActor
    func testAppDependenciesLiveFactoryAndViewModelBuilder() throws {
        let container = try TestFixture.makeInMemoryContainer()
        let dependencies = AppDependencies.live(container: container)

        XCTAssertNotNil(dependencies.plantListUseCase)
        XCTAssertNotNil(dependencies.plantEditorUseCase)
        XCTAssertNotNil(dependencies.settingsUseCase)
        XCTAssertNotNil(dependencies.locationService)

        let viewModel = dependencies.makePlantListViewModel()
        XCTAssertNotNil(viewModel)
    }
}
