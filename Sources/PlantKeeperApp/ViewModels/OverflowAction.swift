import Foundation

enum OverflowAction: String, CaseIterable, Identifiable {
    case setWateringDate
    case wateringLogs
    case markChecked
    case edit
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setWateringDate: return "Set Watering Date"
        case .wateringLogs: return "Watering Logs"
        case .markChecked: return "Mark Checked"
        case .edit: return "Edit"
        case .delete: return "Delete"
        }
    }
}
