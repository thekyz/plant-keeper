import Foundation
import SwiftData

@Model
final class AppSettingsEntity {
    static let singletonID = UUID(uuidString: "E2E55E3D-9B5D-4D5A-9061-3DF7B7D65845")!

    @Attribute(.unique) var id: UUID
    var homeLocationName: String
    var latitude: Double?
    var longitude: Double?
    var dailyDigestHour: Int
    var dailyDigestMinute: Int

    init(
        id: UUID = AppSettingsEntity.singletonID,
        homeLocationName: String = "Home",
        latitude: Double? = nil,
        longitude: Double? = nil,
        dailyDigestHour: Int = 9,
        dailyDigestMinute: Int = 0
    ) {
        self.id = id
        self.homeLocationName = homeLocationName
        self.latitude = latitude
        self.longitude = longitude
        self.dailyDigestHour = dailyDigestHour
        self.dailyDigestMinute = dailyDigestMinute
    }
}
