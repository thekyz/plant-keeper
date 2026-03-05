import Foundation
import PlantKeeperCore

struct PlantRowViewModel: Identifiable {
    let plant: PlantRecord
    let urgency: UrgencyScore

    var id: UUID { plant.id }

    var displayName: String {
        plant.nameEnglish.isEmpty ? plant.nameFrench : plant.nameEnglish
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

    var nextDueText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: urgency.effectiveNextDueDate, relativeTo: Date())
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
}
