import Foundation

enum PlantNameLanguage: String, CaseIterable, Codable, Sendable {
    case english
    case french

    var title: String {
        switch self {
        case .english:
            return "English"
        case .french:
            return "French"
        }
    }
}
