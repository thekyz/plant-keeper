import Foundation
import PlantKeeperCore

actor PlantEditorUseCase {
    private let repository: any PlantStore
    private let aiService: any PlantAnalyzing

    init(repository: any PlantStore, aiService: any PlantAnalyzing) {
        self.repository = repository
        self.aiService = aiService
    }

    func saveDraft(_ draft: PlantDraft, editingID: UUID?, original: PlantRecord?) async throws {
        var record = draft.makeRecord(existingID: editingID)
        if let original {
            record.createdAt = original.createdAt
            record.lastWateredAt = original.lastWateredAt
            record.lastCheckedAt = original.lastCheckedAt
            record.photoIdentifier = original.photoIdentifier
            applyEditedSchedule(into: &record, original: original, now: Date())
        }

        if let photoData = draft.photoData {
            record.photoIdentifier = try PlantPhotoStore.savePhotoData(photoData, for: record.id)
        }

        try await repository.upsert(record)
    }

    func analyzePhoto(_ data: Data) async throws -> AIAnalysisResult {
        try await aiService.analyzePhotoData(data)
    }

    nonisolated func photoData(for draft: PlantDraft) throws -> Data? {
        if let photoData = draft.photoData {
            return photoData
        }

        guard
            let photoURL = PlantPhotoStore.photoURL(for: draft.photoIdentifier),
            FileManager.default.fileExists(atPath: photoURL.path)
        else {
            return nil
        }

        return try Data(contentsOf: photoURL)
    }

    func makeDraft(from plant: PlantRecord) -> PlantDraft {
        var draft = PlantDraft()
        draft.photoIdentifier = plant.photoIdentifier
        draft.nameEnglish = plant.nameEnglish
        draft.nameFrench = plant.nameFrench
        draft.isOutdoor = plant.isOutdoor
        draft.wateringIntervalDays = plant.wateringIntervalDays
        draft.checkIntervalDays = plant.checkIntervalDays
        draft.notes = plant.notes
        draft.aiCareHints = plant.aiCareHints
        draft.aiConfidence = plant.aiConfidence
        return draft
    }

    private func applyEditedSchedule(into edited: inout PlantRecord, original: PlantRecord, now: Date) {
        if edited.wateringIntervalDays == original.wateringIntervalDays {
            edited.nextWaterDueAt = original.nextWaterDueAt
        } else {
            let anchor = original.lastWateredAt ?? now
            edited.nextWaterDueAt = Calendar.current.date(byAdding: .day, value: edited.wateringIntervalDays, to: anchor) ?? anchor
        }

        if edited.checkIntervalDays == original.checkIntervalDays {
            edited.nextCheckDueAt = original.nextCheckDueAt
        } else {
            let anchor = original.lastCheckedAt ?? now
            edited.nextCheckDueAt = Calendar.current.date(byAdding: .day, value: edited.checkIntervalDays, to: anchor) ?? anchor
        }
    }
}
