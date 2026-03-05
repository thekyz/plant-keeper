import Foundation

public struct WeatherSnapshot: Equatable, Sendable {
    public var rainMillimeters24h: Double
    public var forecastRainMillimeters24h: Double
    public var minTemperatureC: Double
    public var maxTemperatureC: Double

    public init(
        rainMillimeters24h: Double,
        forecastRainMillimeters24h: Double,
        minTemperatureC: Double,
        maxTemperatureC: Double
    ) {
        self.rainMillimeters24h = rainMillimeters24h
        self.forecastRainMillimeters24h = forecastRainMillimeters24h
        self.minTemperatureC = minTemperatureC
        self.maxTemperatureC = maxTemperatureC
    }
}

public protocol WeatherAdjusting: Sendable {
    func adjustment(for plant: PlantRecord, weather: WeatherSnapshot?) -> WeatherAdjustment
}

public struct DefaultWeatherAdjuster: WeatherAdjusting {
    public init() {}

    public func adjustment(for plant: PlantRecord, weather: WeatherSnapshot?) -> WeatherAdjustment {
        guard plant.isOutdoor, let weather else {
            return .init(daysOffset: 0)
        }

        var daysOffset = 0
        var reasons: [String] = []

        if weather.rainMillimeters24h + weather.forecastRainMillimeters24h >= 10 {
            daysOffset += 1
            reasons.append("Rain easing watering urgency")
        }

        if weather.maxTemperatureC >= 30 {
            daysOffset -= 1
            reasons.append("Heat increasing watering urgency")
        }

        if weather.minTemperatureC <= 5 {
            daysOffset += 1
            reasons.append("Cold reducing watering urgency")
        }

        return .init(daysOffset: max(-1, min(2, daysOffset)), reasons: reasons)
    }
}

public protocol PlantStore: Sendable {
    func allPlants() async throws -> [PlantRecord]
    func upsert(_ plant: PlantRecord) async throws
    func delete(plantID: UUID) async throws
    func plant(withID id: UUID) async throws -> PlantRecord?
}

public protocol PlantServiceType: Sendable {
    func recordWatering(plantID: UUID, at timestamp: Date) async throws
    func addWateringLog(plantID: UUID, at recordedAt: Date, now: Date) async throws
    func updateWateringLog(plantID: UUID, sortedLogIndex: Int, to recordedAt: Date, now: Date) async throws
    func deleteWateringLog(plantID: UUID, sortedLogIndex: Int, now: Date) async throws
    func snoozeWatering(plantID: UUID, days: Int, now: Date) async throws
    func recordCheck(plantID: UUID, at timestamp: Date) async throws
    func recomputeUrgency(for plantID: UUID, now: Date) async throws -> UrgencyScore?
    func urgencySortedPlants(now: Date) async throws -> [PlantRecord]
}

public actor PlantService: PlantServiceType {
    private let store: PlantStore
    private let urgencyEngine: UrgencyEngine
    private let weatherAdjuster: WeatherAdjusting
    private let weatherProvider: @Sendable (PlantRecord) async -> WeatherSnapshot?

    public init(
        store: PlantStore,
        urgencyEngine: UrgencyEngine = .init(),
        weatherAdjuster: WeatherAdjusting = DefaultWeatherAdjuster(),
        weatherProvider: @escaping @Sendable (PlantRecord) async -> WeatherSnapshot? = { _ in nil }
    ) {
        self.store = store
        self.urgencyEngine = urgencyEngine
        self.weatherAdjuster = weatherAdjuster
        self.weatherProvider = weatherProvider
    }

    public func recordWatering(plantID: UUID, at timestamp: Date) async throws {
        try await addWateringLog(plantID: plantID, at: timestamp, now: timestamp)
    }

    public func addWateringLog(plantID: UUID, at recordedAt: Date, now: Date) async throws {
        guard var plant = try await store.plant(withID: plantID) else { return }

        var logs = normalizedWateringLogs(for: plant)
        logs.append(WateringLog(timestamp: recordedAt))
        applyWateringLogs(logs, to: &plant, now: now)

        try await store.upsert(plant)
    }

    public func updateWateringLog(plantID: UUID, sortedLogIndex: Int, to recordedAt: Date, now: Date) async throws {
        guard var plant = try await store.plant(withID: plantID) else { return }

        var logs = normalizedWateringLogs(for: plant)
        let sorted = logs.sorted(by: { $0.timestamp > $1.timestamp })
        guard sorted.indices.contains(sortedLogIndex) else { return }

        let target = sorted[sortedLogIndex]
        guard let sourceIndex = logs.firstIndex(where: { $0.timestamp == target.timestamp }) else { return }
        logs[sourceIndex].timestamp = recordedAt

        applyWateringLogs(logs, to: &plant, now: now)
        try await store.upsert(plant)
    }

    public func deleteWateringLog(plantID: UUID, sortedLogIndex: Int, now: Date) async throws {
        guard var plant = try await store.plant(withID: plantID) else { return }

        var logs = normalizedWateringLogs(for: plant)
        let sorted = logs.sorted(by: { $0.timestamp > $1.timestamp })
        guard sorted.indices.contains(sortedLogIndex) else { return }

        let target = sorted[sortedLogIndex]
        guard let sourceIndex = logs.firstIndex(where: { $0.timestamp == target.timestamp }) else { return }
        logs.remove(at: sourceIndex)

        applyWateringLogs(logs, to: &plant, now: now)
        try await store.upsert(plant)
    }

    public func snoozeWatering(plantID: UUID, days: Int, now: Date) async throws {
        guard var plant = try await store.plant(withID: plantID) else { return }

        var logs = normalizedWateringLogs(for: plant)
        logs.append(WateringLog(timestamp: now))
        let sortedLogs = logs.sorted(by: { $0.timestamp > $1.timestamp })
        plant.wateringLogs = sortedLogs
        plant.lastWateredAt = sortedLogs.first?.timestamp

        let baseline = max(plant.nextWaterDueAt, now)
        plant.nextWaterDueAt = Calendar.current.date(byAdding: .day, value: days, to: baseline) ?? baseline
        plant.updatedAt = now
        try await store.upsert(plant)
    }

    public func recordCheck(plantID: UUID, at timestamp: Date) async throws {
        guard var plant = try await store.plant(withID: plantID) else { return }
        plant.lastCheckedAt = timestamp
        plant.nextCheckDueAt = Calendar.current.date(byAdding: .day, value: plant.checkIntervalDays, to: timestamp) ?? timestamp
        plant.updatedAt = timestamp
        try await store.upsert(plant)
    }

    public func recomputeUrgency(for plantID: UUID, now: Date) async throws -> UrgencyScore? {
        guard let plant = try await store.plant(withID: plantID) else { return nil }
        let snapshot = await weatherProvider(plant)
        let adjustment = weatherAdjuster.adjustment(for: plant, weather: snapshot)
        return urgencyEngine.score(for: plant, now: now, weatherAdjustment: adjustment)
    }

    public func urgencySortedPlants(now: Date) async throws -> [PlantRecord] {
        let plants = try await store.allPlants()
        var adjustmentMap: [UUID: WeatherAdjustment] = [:]

        for plant in plants {
            let snapshot = await weatherProvider(plant)
            adjustmentMap[plant.id] = weatherAdjuster.adjustment(for: plant, weather: snapshot)
        }

        return urgencyEngine.sortByUrgency(plants: plants, now: now) { plant in
            adjustmentMap[plant.id] ?? .init()
        }
    }

    private func normalizedWateringLogs(for plant: PlantRecord) -> [WateringLog] {
        if !plant.wateringLogs.isEmpty {
            return plant.wateringLogs
        }
        guard let legacyLastWateredAt = plant.lastWateredAt else {
            return []
        }
        return [WateringLog(timestamp: legacyLastWateredAt)]
    }

    private func applyWateringLogs(_ logs: [WateringLog], to plant: inout PlantRecord, now: Date) {
        let sortedLogs = logs.sorted(by: { $0.timestamp > $1.timestamp })
        plant.wateringLogs = sortedLogs

        if let latest = sortedLogs.first?.timestamp {
            plant.lastWateredAt = latest
            plant.nextWaterDueAt = Calendar.current.date(byAdding: .day, value: plant.wateringIntervalDays, to: latest) ?? latest
        } else {
            plant.lastWateredAt = nil
            plant.nextWaterDueAt = now
        }

        plant.updatedAt = now
    }
}
