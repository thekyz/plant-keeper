import Foundation

public struct WateringLog: Equatable, Sendable, Codable {
    public var timestamp: Date

    public init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

public struct PlantRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var photoIdentifier: String?
    public var nameEnglish: String
    public var nameFrench: String
    public var isOutdoor: Bool
    public var wateringIntervalDays: Int
    public var checkIntervalDays: Int
    public var wateringLogs: [WateringLog]
    public var lastWateredAt: Date?
    public var lastCheckedAt: Date?
    public var nextWaterDueAt: Date
    public var nextCheckDueAt: Date
    public var notes: String
    public var aiCareHints: [String]
    public var aiConfidence: Double?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        photoIdentifier: String? = nil,
        nameEnglish: String,
        nameFrench: String,
        isOutdoor: Bool,
        wateringIntervalDays: Int,
        checkIntervalDays: Int,
        wateringLogs: [WateringLog] = [],
        lastWateredAt: Date? = nil,
        lastCheckedAt: Date? = nil,
        nextWaterDueAt: Date,
        nextCheckDueAt: Date,
        notes: String = "",
        aiCareHints: [String] = [],
        aiConfidence: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.photoIdentifier = photoIdentifier
        self.nameEnglish = nameEnglish
        self.nameFrench = nameFrench
        self.isOutdoor = isOutdoor
        self.wateringIntervalDays = max(1, wateringIntervalDays)
        self.checkIntervalDays = max(1, checkIntervalDays)
        self.wateringLogs = wateringLogs
        self.lastWateredAt = lastWateredAt ?? wateringLogs.map(\.timestamp).max()
        self.lastCheckedAt = lastCheckedAt
        self.nextWaterDueAt = nextWaterDueAt
        self.nextCheckDueAt = nextCheckDueAt
        self.notes = notes
        self.aiCareHints = aiCareHints
        self.aiConfidence = aiConfidence
    }
}
