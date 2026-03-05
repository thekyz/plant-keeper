import Foundation
import SwiftData

protocol AppSettingsStoring: Sendable {
    func updateHomeLocation(name: String, latitude: Double?, longitude: Double?) async throws
    func homeCoordinates() async throws -> (name: String, latitude: Double, longitude: Double)?
    func digestTime() async throws -> (hour: Int, minute: Int)
}

actor AppSettingsStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private func loadOrCreate(in context: ModelContext) throws -> AppSettingsEntity {
        let settingsID = AppSettingsEntity.singletonID
        let descriptor = FetchDescriptor<AppSettingsEntity>(
            predicate: #Predicate { $0.id == settingsID }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let created = AppSettingsEntity()
        context.insert(created)
        try context.save()
        return created
    }

    func updateHomeLocation(name: String, latitude: Double?, longitude: Double?) async throws {
        let context = ModelContext(modelContainer)
        let settings = try loadOrCreate(in: context)

        settings.homeLocationName = name
        settings.latitude = latitude
        settings.longitude = longitude
        try context.save()
    }

    func homeCoordinates() async throws -> (name: String, latitude: Double, longitude: Double)? {
        let context = ModelContext(modelContainer)
        let settings = try loadOrCreate(in: context)
        guard let lat = settings.latitude, let lon = settings.longitude else {
            return nil
        }
        return (settings.homeLocationName, lat, lon)
    }

    func digestTime() async throws -> (hour: Int, minute: Int) {
        let context = ModelContext(modelContainer)
        let settings = try loadOrCreate(in: context)
        return (settings.dailyDigestHour, settings.dailyDigestMinute)
    }
}

extension AppSettingsStore: AppSettingsStoring {}
