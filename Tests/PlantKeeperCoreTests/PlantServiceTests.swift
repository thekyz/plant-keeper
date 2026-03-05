import XCTest
@testable import PlantKeeperCore

actor InMemoryPlantStore: PlantStore {
    private var plants: [UUID: PlantRecord]

    init(plants: [PlantRecord] = []) {
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

final class PlantServiceTests: XCTestCase {
    func testRecordWateringUpdatesDates() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let plant = PlantRecord(
            nameEnglish: "Aloe",
            nameFrench: "Aloe",
            isOutdoor: false,
            wateringIntervalDays: 5,
            checkIntervalDays: 2,
            nextWaterDueAt: now,
            nextCheckDueAt: now
        )
        let store = InMemoryPlantStore(plants: [plant])
        let service = PlantService(store: store)

        try await service.recordWatering(plantID: plant.id, at: now)
        let saved = try await store.plant(withID: plant.id)

        XCTAssertEqual(saved?.lastWateredAt, now)
        XCTAssertEqual(saved?.wateringLogs.map(\.timestamp), [now])
        XCTAssertEqual(
            saved?.nextWaterDueAt,
            Calendar.current.date(byAdding: .day, value: 5, to: now)
        )
    }

    func testAddRetroactiveWateringKeepsNewestAsLastWatered() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let plant = PlantRecord(
            nameEnglish: "Pothos",
            nameFrench: "Pothos",
            isOutdoor: false,
            wateringIntervalDays: 4,
            checkIntervalDays: 2,
            nextWaterDueAt: now,
            nextCheckDueAt: now
        )
        let store = InMemoryPlantStore(plants: [plant])
        let service = PlantService(store: store)

        try await service.recordWatering(plantID: plant.id, at: now)
        try await service.addWateringLog(plantID: plant.id, at: yesterday, now: now)

        let saved = try await store.plant(withID: plant.id)
        XCTAssertEqual(saved?.lastWateredAt, now)
        XCTAssertEqual(saved?.wateringLogs.map(\.timestamp), [now, yesterday])
    }

    func testDeleteWateringLogRecomputesLastWateredAndDueDate() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now
        let plant = PlantRecord(
            nameEnglish: "Fern",
            nameFrench: "Fougere",
            isOutdoor: false,
            wateringIntervalDays: 5,
            checkIntervalDays: 2,
            wateringLogs: [WateringLog(timestamp: oneDayAgo), WateringLog(timestamp: threeDaysAgo)],
            lastWateredAt: oneDayAgo,
            nextWaterDueAt: now,
            nextCheckDueAt: now
        )
        let store = InMemoryPlantStore(plants: [plant])
        let service = PlantService(store: store)

        try await service.deleteWateringLog(plantID: plant.id, sortedLogIndex: 0, now: now)

        let saved = try await store.plant(withID: plant.id)
        XCTAssertEqual(saved?.lastWateredAt, threeDaysAgo)
        XCTAssertEqual(saved?.wateringLogs.map(\.timestamp), [threeDaysAgo])
        XCTAssertEqual(
            saved?.nextWaterDueAt,
            Calendar.current.date(byAdding: .day, value: 5, to: threeDaysAgo)
        )
    }

    func testSnoozeWateringMovesNextDueByOneDay() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let dueSoon = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now
        let plant = PlantRecord(
            nameEnglish: "Lily",
            nameFrench: "Lys",
            isOutdoor: false,
            wateringIntervalDays: 3,
            checkIntervalDays: 2,
            nextWaterDueAt: dueSoon,
            nextCheckDueAt: now
        )
        let store = InMemoryPlantStore(plants: [plant])
        let service = PlantService(store: store)

        try await service.snoozeWatering(plantID: plant.id, days: 1, now: now)

        let saved = try await store.plant(withID: plant.id)
        XCTAssertEqual(saved?.lastWateredAt, now)
        XCTAssertEqual(saved?.wateringLogs.map(\.timestamp), [now])
        XCTAssertEqual(
            saved?.nextWaterDueAt,
            Calendar.current.date(byAdding: .day, value: 1, to: dueSoon)
        )
    }

    func testUrgencySortOverdueFirst() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let overdue = PlantRecord(
            nameEnglish: "Mint",
            nameFrench: "Menthe",
            isOutdoor: false,
            wateringIntervalDays: 4,
            checkIntervalDays: 3,
            nextWaterDueAt: now.addingTimeInterval(-7200),
            nextCheckDueAt: now.addingTimeInterval(5000)
        )

        let upcoming = PlantRecord(
            nameEnglish: "Fern",
            nameFrench: "Fougere",
            isOutdoor: false,
            wateringIntervalDays: 4,
            checkIntervalDays: 3,
            nextWaterDueAt: now.addingTimeInterval(7200),
            nextCheckDueAt: now.addingTimeInterval(7200)
        )

        let sorted = UrgencyEngine().sortByUrgency(plants: [upcoming, overdue], now: now)
        XCTAssertEqual(sorted.first?.id, overdue.id)
    }

    func testWeatherAdjustmentsOnlyForOutdoorPlants() {
        let weather = WeatherSnapshot(
            rainMillimeters24h: 8,
            forecastRainMillimeters24h: 4,
            minTemperatureC: 12,
            maxTemperatureC: 21
        )

        let outdoor = PlantRecord(
            nameEnglish: "Rose",
            nameFrench: "Rose",
            isOutdoor: true,
            wateringIntervalDays: 3,
            checkIntervalDays: 1,
            nextWaterDueAt: Date(),
            nextCheckDueAt: Date()
        )

        let indoor = PlantRecord(
            nameEnglish: "Monstera",
            nameFrench: "Monstera",
            isOutdoor: false,
            wateringIntervalDays: 7,
            checkIntervalDays: 3,
            nextWaterDueAt: Date(),
            nextCheckDueAt: Date()
        )

        let adjuster = DefaultWeatherAdjuster()
        XCTAssertEqual(adjuster.adjustment(for: outdoor, weather: weather).daysOffset, 1)
        XCTAssertEqual(adjuster.adjustment(for: indoor, weather: weather).daysOffset, 0)
    }
}
