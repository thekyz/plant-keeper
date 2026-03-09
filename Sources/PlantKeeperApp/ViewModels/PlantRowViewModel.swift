import Foundation
import PlantKeeperCore

struct PlantRowViewModel: Identifiable {
    let plant: PlantRecord
    let urgency: UrgencyScore
    let preferredPlantNameLanguage: PlantNameLanguage

    init(
        plant: PlantRecord,
        urgency: UrgencyScore,
        preferredPlantNameLanguage: PlantNameLanguage = .english
    ) {
        self.plant = plant
        self.urgency = urgency
        self.preferredPlantNameLanguage = preferredPlantNameLanguage
    }

    var id: UUID { plant.id }

    var displayName: String {
        switch preferredPlantNameLanguage {
        case .english:
            return preferredName(primary: plant.nameEnglish, fallback: plant.nameFrench)
        case .french:
            return preferredName(primary: plant.nameFrench, fallback: plant.nameEnglish)
        }
    }

    var urgencyBadge: String {
        if urgency.isOverdue {
            return "Overdue"
        }

        let hours = Int(urgency.effectiveNextDueDate.timeIntervalSinceNow / 3600)
        if hours <= 24 {
            return "Due Soon"
        }
        return "On Track"
    }

    var nextWaterText: String {
        relativeText(for: plant.nextWaterDueAt)
    }

    var nextCheckText: String {
        relativeText(for: plant.nextCheckDueAt)
    }

    var wateringLogs: [Date] {
        if !plant.wateringLogs.isEmpty {
            return plant.wateringLogs.map(\.timestamp).sorted(by: >)
        }
        if let lastWateredAt = plant.lastWateredAt {
            return [lastWateredAt]
        }
        return []
    }

    private func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func preferredName(primary: String, fallback: String) -> String {
        if !primary.isEmpty {
            return primary
        }
        return fallback
    }
}
