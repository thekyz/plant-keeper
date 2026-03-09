import XCTest
@testable import PlantKeeperApp
@testable import PlantKeeperCore

private actor FixedUrgencyPlantService: PlantServiceType {
    let plants: [PlantRecord]
    let urgencyByID: [UUID: UrgencyScore]
    private(set) var recordedChecks: [(UUID, Date)] = []
    private(set) var recordedWaterings: [(UUID, Date)] = []
    private(set) var snoozed: [(UUID, Int, Date)] = []

    init(plants: [PlantRecord], urgencyByID: [UUID: UrgencyScore]) {
        self.plants = plants
        self.urgencyByID = urgencyByID
    }

    func recordWatering(plantID: UUID, at timestamp: Date) async throws {
        recordedWaterings.append((plantID, timestamp))
    }

    func addWateringLog(plantID: UUID, at recordedAt: Date, now: Date) async throws {
        recordedWaterings.append((plantID, recordedAt))
    }

    func updateWateringLog(plantID: UUID, sortedLogIndex: Int, to recordedAt: Date, now: Date) async throws {
        recordedWaterings.append((plantID, recordedAt))
    }

    func deleteWateringLog(plantID: UUID, sortedLogIndex: Int, now: Date) async throws {}

    func snoozeWatering(plantID: UUID, days: Int, now: Date) async throws {
        snoozed.append((plantID, days, now))
    }

    func recordCheck(plantID: UUID, at timestamp: Date) async throws {
        recordedChecks.append((plantID, timestamp))
    }

    func recomputeUrgency(for plantID: UUID, now: Date) async throws -> UrgencyScore? {
        urgencyByID[plantID]
    }

    func urgencySortedPlants(now: Date) async throws -> [PlantRecord] {
        plants
    }
}

final class PlantListUseCaseTests: XCTestCase {
    func testConfigureNotificationsIfNeededUsesDigestTime() async throws {
        let plant = TestFixture.makePlant()
        let service = PlantService(store: MockPlantStore(plants: [plant]))
        let scheduler = MockNotificationScheduler()
        let settings = MockAppSettingsStore(digest: (7, 45))
        let useCase = PlantListUseCase(
            plantService: service,
            repository: MockPlantStore(plants: [plant]),
            notificationScheduler: scheduler,
            appSettingsStore: settings
        )

        try await useCase.configureNotificationsIfNeeded()

        let requested = await scheduler.requestedAuthorization
        let digest = await scheduler.scheduledDigest
        XCTAssertTrue(requested)
        XCTAssertEqual(digest?.hour, 7)
        XCTAssertEqual(digest?.minute, 45)
    }

    func testLoadRowsBuildsViewModelsAndRefreshesNotifications() async throws {
        let now = Date(timeIntervalSince1970: 5_000)
        let plantA = TestFixture.makePlant(id: UUID(), nameEnglish: "A")
        let plantB = TestFixture.makePlant(id: UUID(), nameEnglish: "B")
        let urgencyA = UrgencyEngine().score(for: plantA, now: now)
        let urgencyB = UrgencyEngine().score(for: plantB, now: now)
        let service = FixedUrgencyPlantService(plants: [plantA, plantB], urgencyByID: [
            plantA.id: urgencyA,
            plantB.id: urgencyB
        ])
        let scheduler = MockNotificationScheduler()
        let useCase = PlantListUseCase(
            plantService: service,
            repository: MockPlantStore(plants: [plantA, plantB]),
            notificationScheduler: scheduler,
            appSettingsStore: MockAppSettingsStore()
        )

        let rows = try await useCase.loadRows(now: now, preferredPlantNameLanguage: .english)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.id)), Set([plantA.id, plantB.id]))
        let refreshed = await scheduler.refreshedPayload
        XCTAssertEqual(refreshed?.count, 2)
        XCTAssertEqual(refreshed?.now, now)
    }

    func testMarkWateredAndSnoozeAreForwardedToPlantService() async throws {
        let plant = TestFixture.makePlant()
        let urgency = UrgencyEngine().score(for: plant, now: Date())
        let service = FixedUrgencyPlantService(plants: [plant], urgencyByID: [plant.id: urgency])
        let useCase = PlantListUseCase(
            plantService: service,
            repository: MockPlantStore(plants: [plant]),
            notificationScheduler: MockNotificationScheduler(),
            appSettingsStore: MockAppSettingsStore()
        )
        let timestamp = Date(timeIntervalSince1970: 3_000)

        try await useCase.markWatered(plantID: plant.id, at: timestamp)
        try await useCase.snoozeWatering(plantID: plant.id, days: 1, now: timestamp)

        let recordedWaterings = await service.recordedWaterings
        let snoozed = await service.snoozed
        XCTAssertEqual(recordedWaterings.first?.0, plant.id)
        XCTAssertEqual(recordedWaterings.first?.1, timestamp)
        XCTAssertEqual(snoozed.first?.0, plant.id)
        XCTAssertEqual(snoozed.first?.1, 1)
    }

    func testMarkCheckedWithoutObservationStillRecordsCheck() async throws {
        let plant = TestFixture.makePlant()
        let urgency = UrgencyEngine().score(for: plant, now: Date())
        let service = FixedUrgencyPlantService(plants: [plant], urgencyByID: [plant.id: urgency])
        let store = MockPlantStore(plants: [plant])
        let useCase = PlantListUseCase(
            plantService: service,
            repository: store,
            notificationScheduler: MockNotificationScheduler(),
            appSettingsStore: MockAppSettingsStore()
        )
        let timestamp = Date(timeIntervalSince1970: 6_000)

        try await useCase.markChecked(plantID: plant.id, at: timestamp)

        let checks = await service.recordedChecks
        XCTAssertEqual(checks.count, 1)
        XCTAssertEqual(checks[0].0, plant.id)
        XCTAssertEqual(checks[0].1, timestamp)
        let upsertedIDs = await store.upsertedPlantIDs
        XCTAssertEqual(upsertedIDs.count, 0)
    }

    func testMarkCheckedWithNoteAndPhotoAppendsObservationAndPersistsPhoto() async throws {
        let plant = TestFixture.makePlant(
            nameEnglish: "ObservationPlant",
            notes: "Existing note"
        )
        let urgency = UrgencyEngine().score(for: plant, now: Date())
        let service = FixedUrgencyPlantService(plants: [plant], urgencyByID: [plant.id: urgency])
        let store = MockPlantStore(plants: [plant])
        let useCase = PlantListUseCase(
            plantService: service,
            repository: store,
            notificationScheduler: MockNotificationScheduler(),
            appSettingsStore: MockAppSettingsStore()
        )
        let timestamp = Date(timeIntervalSince1970: 8_000)

        try await useCase.markChecked(
            plantID: plant.id,
            at: timestamp,
            note: "  looks healthy  ",
            photoData: Data([0x0A, 0x0B])
        )

        let saved = try await store.plant(withID: plant.id)
        XCTAssertNotNil(saved?.photoIdentifier)
        XCTAssertTrue(saved?.notes.contains("Existing note") == true)
        XCTAssertTrue(saved?.notes.contains("looks healthy") == true)
        XCTAssertEqual(saved?.updatedAt, timestamp)
        let checks = await service.recordedChecks
        XCTAssertEqual(checks.count, 1)

        if let url = PlantPhotoStore.photoURL(for: saved?.photoIdentifier) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testDeletePlantDeletesFromRepository() async throws {
        let plant = TestFixture.makePlant()
        let service = PlantService(store: MockPlantStore(plants: [plant]))
        let store = MockPlantStore(plants: [plant])
        let useCase = PlantListUseCase(
            plantService: service,
            repository: store,
            notificationScheduler: MockNotificationScheduler(),
            appSettingsStore: MockAppSettingsStore()
        )

        try await useCase.deletePlant(plantID: plant.id)

        let deleted = await store.deletedPlantIDs
        XCTAssertEqual(deleted, [plant.id])
    }
}
