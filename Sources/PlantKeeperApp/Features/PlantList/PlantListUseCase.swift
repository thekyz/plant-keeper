import Foundation
import PlantKeeperCore

actor PlantListUseCase {
    private let plantService: any PlantServiceType
    private let repository: any PlantStore
    private let notificationScheduler: NotificationScheduling
    private let appSettingsStore: any AppSettingsStoring
    private let urgencyEngine = UrgencyEngine()

    init(
        plantService: any PlantServiceType,
        repository: any PlantStore,
        notificationScheduler: NotificationScheduling,
        appSettingsStore: any AppSettingsStoring
    ) {
        self.plantService = plantService
        self.repository = repository
        self.notificationScheduler = notificationScheduler
        self.appSettingsStore = appSettingsStore
    }

    func configureNotificationsIfNeeded() async throws {
        await notificationScheduler.requestAuthorizationIfNeeded()
        let digestTime = try await appSettingsStore.digestTime()
        await notificationScheduler.scheduleDailyDigest(hour: digestTime.hour, minute: digestTime.minute)
    }

    func seedSimulatorPlantsIfNeeded(now: Date) async throws {
        #if os(iOS) && targetEnvironment(simulator)
        let existing = try await repository.allPlants()
        guard existing.isEmpty else { return }

        let seededPlants = makeSimulatorSeedPlants(now: now)
        for plant in seededPlants {
            try await repository.upsert(plant)
        }
        #endif
    }

    func loadRows(now: Date) async throws -> [PlantRowViewModel] {
        let plants = try await plantService.urgencySortedPlants(now: now)
        let rows = try await buildRows(from: plants, now: now)
        await notificationScheduler.refreshUrgencyNotifications(plants: plants, now: now)
        return rows
    }

    func markWatered(plantID: UUID, at timestamp: Date) async throws {
        try await plantService.recordWatering(plantID: plantID, at: timestamp)
    }

    func addWateringLog(plantID: UUID, at recordedAt: Date, now: Date) async throws {
        try await plantService.addWateringLog(plantID: plantID, at: recordedAt, now: now)
    }

    func updateWateringLog(plantID: UUID, sortedLogIndex: Int, to recordedAt: Date, now: Date) async throws {
        try await plantService.updateWateringLog(plantID: plantID, sortedLogIndex: sortedLogIndex, to: recordedAt, now: now)
    }

    func deleteWateringLog(plantID: UUID, sortedLogIndex: Int, now: Date) async throws {
        try await plantService.deleteWateringLog(plantID: plantID, sortedLogIndex: sortedLogIndex, now: now)
    }

    func snoozeWatering(plantID: UUID, days: Int, now: Date) async throws {
        try await plantService.snoozeWatering(plantID: plantID, days: days, now: now)
    }

    func markChecked(plantID: UUID, at timestamp: Date) async throws {
        try await markChecked(plantID: plantID, at: timestamp, note: nil, photoData: nil)
    }

    func markChecked(plantID: UUID, at timestamp: Date, note: String?, photoData: Data?) async throws {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasObservation = (trimmedNote?.isEmpty == false) || photoData != nil

        if hasObservation, var plant = try await repository.plant(withID: plantID) {
            if let trimmedNote, !trimmedNote.isEmpty {
                plant.notes = appendCheckNote(trimmedNote, to: plant.notes, at: timestamp)
            }
            if let photoData {
                plant.photoIdentifier = try PlantPhotoStore.savePhotoData(photoData, for: plant.id)
            }
            plant.updatedAt = timestamp
            try await repository.upsert(plant)
        }

        try await plantService.recordCheck(plantID: plantID, at: timestamp)
    }

    func deletePlant(plantID: UUID) async throws {
        try await repository.delete(plantID: plantID)
    }

    private func appendCheckNote(_ note: String, to existingNotes: String, at timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let noteEntry = "Check \(formatter.string(from: timestamp)): \(note)"
        let trimmedExisting = existingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExisting.isEmpty else { return noteEntry }
        return "\(trimmedExisting)\n\n\(noteEntry)"
    }

    private func buildRows(from plants: [PlantRecord], now: Date) async throws -> [PlantRowViewModel] {
        var builtRows: [PlantRowViewModel] = []
        builtRows.reserveCapacity(plants.count)

        for plant in plants {
            let urgency = try await plantService.recomputeUrgency(for: plant.id, now: now) ?? urgencyEngine.score(for: plant, now: now)
            builtRows.append(PlantRowViewModel(plant: plant, urgency: urgency))
        }

        return builtRows
    }

    #if os(iOS) && targetEnvironment(simulator)
    private func makeSimulatorSeedPlants(now: Date) -> [PlantRecord] {
        let calendar = Calendar.current
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let inThreeDays = calendar.date(byAdding: .day, value: 3, to: now) ?? now

        return [
            PlantRecord(
                nameEnglish: "Lime Tree",
                nameFrench: "Citronnier vert",
                isOutdoor: true,
                wateringIntervalDays: 3,
                checkIntervalDays: 2,
                lastWateredAt: twoDaysAgo,
                lastCheckedAt: oneDayAgo,
                nextWaterDueAt: now,
                nextCheckDueAt: inThreeDays,
                notes: "Outdoor container citrus."
            ),
            PlantRecord(
                nameEnglish: "Aloe Vera",
                nameFrench: "Aloe vera",
                isOutdoor: false,
                wateringIntervalDays: 10,
                checkIntervalDays: 4,
                lastWateredAt: threeDaysAgo,
                lastCheckedAt: oneDayAgo,
                nextWaterDueAt: calendar.date(byAdding: .day, value: 7, to: now) ?? now,
                nextCheckDueAt: calendar.date(byAdding: .day, value: 2, to: now) ?? now,
                notes: "Keep in bright indirect light."
            ),
            PlantRecord(
                nameEnglish: "Basil",
                nameFrench: "Basilic",
                isOutdoor: false,
                wateringIntervalDays: 2,
                checkIntervalDays: 1,
                lastWateredAt: threeDaysAgo,
                lastCheckedAt: oneDayAgo,
                nextWaterDueAt: oneDayAgo,
                nextCheckDueAt: now,
                notes: "Kitchen herb pot."
            )
        ]
    }
    #endif
}
