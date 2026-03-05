import Foundation

public struct WeatherAdjustment: Equatable, Sendable {
    public var daysOffset: Int
    public var reasons: [String]

    public init(daysOffset: Int = 0, reasons: [String] = []) {
        self.daysOffset = daysOffset
        self.reasons = reasons
    }
}

public struct UrgencyScore: Equatable, Sendable {
    public let plantID: UUID
    public let effectiveNextDueDate: Date
    public let isOverdue: Bool
    public let overdueMinutes: Int
    public let weatherAdjustment: WeatherAdjustment
    public let rankValue: Double

    public init(
        plantID: UUID,
        effectiveNextDueDate: Date,
        isOverdue: Bool,
        overdueMinutes: Int,
        weatherAdjustment: WeatherAdjustment,
        rankValue: Double
    ) {
        self.plantID = plantID
        self.effectiveNextDueDate = effectiveNextDueDate
        self.isOverdue = isOverdue
        self.overdueMinutes = overdueMinutes
        self.weatherAdjustment = weatherAdjustment
        self.rankValue = rankValue
    }
}

public struct UrgencyEngine {
    public init() {}

    public func score(for plant: PlantRecord, now: Date, weatherAdjustment: WeatherAdjustment = .init()) -> UrgencyScore {
        let baseDue = min(plant.nextWaterDueAt, plant.nextCheckDueAt)
        let effectiveDue = Calendar.current.date(byAdding: .day, value: weatherAdjustment.daysOffset, to: baseDue) ?? baseDue

        let overdueInterval = now.timeIntervalSince(effectiveDue)
        let overdueMinutes = max(0, Int(overdueInterval / 60.0))
        let isOverdue = overdueMinutes > 0

        // Lower rank value = higher urgency.
        let rankValue = effectiveDue.timeIntervalSince(now)

        return UrgencyScore(
            plantID: plant.id,
            effectiveNextDueDate: effectiveDue,
            isOverdue: isOverdue,
            overdueMinutes: overdueMinutes,
            weatherAdjustment: weatherAdjustment,
            rankValue: rankValue
        )
    }

    public func sortByUrgency(
        plants: [PlantRecord],
        now: Date,
        weatherProvider: (PlantRecord) -> WeatherAdjustment = { _ in .init() }
    ) -> [PlantRecord] {
        plants.sorted { lhs, rhs in
            let lhsScore = score(for: lhs, now: now, weatherAdjustment: weatherProvider(lhs))
            let rhsScore = score(for: rhs, now: now, weatherAdjustment: weatherProvider(rhs))

            if lhsScore.isOverdue != rhsScore.isOverdue {
                return lhsScore.isOverdue && !rhsScore.isOverdue
            }
            if lhsScore.effectiveNextDueDate != rhsScore.effectiveNextDueDate {
                return lhsScore.effectiveNextDueDate < rhsScore.effectiveNextDueDate
            }
            if lhs.aiConfidence != rhs.aiConfidence {
                return (lhs.aiConfidence ?? 0.0) > (rhs.aiConfidence ?? 0.0)
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
