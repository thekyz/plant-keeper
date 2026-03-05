import Foundation
import SwiftData
import PlantKeeperCore

actor SwiftDataPlantRepository: PlantStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func allPlants() async throws -> [PlantRecord] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlantEntity>(sortBy: [SortDescriptor(\PlantEntity.createdAt)])
        return try context.fetch(descriptor).map(\.asRecord)
    }

    func upsert(_ plant: PlantRecord) async throws {
        let context = ModelContext(modelContainer)
        let plantID = plant.id
        let descriptor = FetchDescriptor<PlantEntity>(predicate: #Predicate { $0.id == plantID })

        if let existing = try context.fetch(descriptor).first {
            existing.update(from: plant)
        } else {
            let entity = PlantEntity(from: plant)
            context.insert(entity)
        }

        try context.save()
    }

    func delete(plantID: UUID) async throws {
        let context = ModelContext(modelContainer)
        let targetID = plantID
        let descriptor = FetchDescriptor<PlantEntity>(predicate: #Predicate { $0.id == targetID })

        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            try context.save()
        }
    }

    func plant(withID id: UUID) async throws -> PlantRecord? {
        let context = ModelContext(modelContainer)
        let targetID = id
        let descriptor = FetchDescriptor<PlantEntity>(predicate: #Predicate { $0.id == targetID })
        return try context.fetch(descriptor).first?.asRecord
    }
}
