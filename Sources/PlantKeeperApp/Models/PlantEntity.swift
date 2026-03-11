import Foundation
import SwiftData
import PlantKeeperCore

@Model
final class PlantEntity {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var photoIdentifier: String?
    var nameEnglish: String
    var nameFrench: String
    var isOutdoor: Bool
    var wateringIntervalDays: Int
    var checkIntervalDays: Int
    var wateringLogsData: Data?
    var lastWateredAt: Date?
    var lastCheckedAt: Date?
    var nextWaterDueAt: Date
    var nextCheckDueAt: Date
    var notes: String
    var aiCareHintsData: Data?
    var aiConfidence: Double?

    init(from record: PlantRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.photoIdentifier = record.photoIdentifier
        self.nameEnglish = record.nameEnglish
        self.nameFrench = record.nameFrench
        self.isOutdoor = record.isOutdoor
        self.wateringIntervalDays = record.wateringIntervalDays
        self.checkIntervalDays = record.checkIntervalDays
        self.wateringLogsData = Self.encodeWateringLogs(record.wateringLogs)
        self.lastWateredAt = record.lastWateredAt
        self.lastCheckedAt = record.lastCheckedAt
        self.nextWaterDueAt = record.nextWaterDueAt
        self.nextCheckDueAt = record.nextCheckDueAt
        self.notes = record.notes
        self.aiCareHintsData = Self.encodeCareHints(record.aiCareHints)
        self.aiConfidence = record.aiConfidence
    }

    func update(from record: PlantRecord) {
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        photoIdentifier = record.photoIdentifier
        nameEnglish = record.nameEnglish
        nameFrench = record.nameFrench
        isOutdoor = record.isOutdoor
        wateringIntervalDays = record.wateringIntervalDays
        checkIntervalDays = record.checkIntervalDays
        wateringLogsData = Self.encodeWateringLogs(record.wateringLogs)
        lastWateredAt = record.lastWateredAt
        lastCheckedAt = record.lastCheckedAt
        nextWaterDueAt = record.nextWaterDueAt
        nextCheckDueAt = record.nextCheckDueAt
        notes = record.notes
        aiCareHintsData = Self.encodeCareHints(record.aiCareHints)
        aiConfidence = record.aiConfidence
    }

    var asRecord: PlantRecord {
        let decodedLogs = Self.decodeWateringLogs(wateringLogsData)
        let wateringLogs: [WateringLog]
        if decodedLogs.isEmpty, let lastWateredAt {
            wateringLogs = [WateringLog(timestamp: lastWateredAt)]
        } else {
            wateringLogs = decodedLogs
        }

        return PlantRecord(
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
            aiCareHints: Self.decodeCareHints(aiCareHintsData),
            aiConfidence: aiConfidence
        )
    }

    private static func encodeWateringLogs(_ logs: [WateringLog]) -> Data? {
        guard !logs.isEmpty else { return nil }
        return try? JSONEncoder().encode(logs)
    }

    private static func decodeWateringLogs(_ data: Data?) -> [WateringLog] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([WateringLog].self, from: data)) ?? []
    }

    private static func encodeCareHints(_ careHints: [String]) -> Data? {
        guard !careHints.isEmpty else { return nil }
        return try? JSONEncoder().encode(careHints)
    }

    private static func decodeCareHints(_ data: Data?) -> [String] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
