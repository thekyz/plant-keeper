import Foundation
import PlantKeeperCore

struct PlantDraft {
    var photoData: Data?
    var photoIdentifier: String?
    var nameEnglish: String = ""
    var nameFrench: String = ""
    var isOutdoor: Bool = false
    var wateringIntervalDays: Int = 7
    var checkIntervalDays: Int = 3
    var notes: String = ""
    var aiCareHints: [String] = []
    var aiConfidence: Double?

    mutating func applyAI(_ result: AIAnalysisResult) {
        if nameEnglish.isEmpty { nameEnglish = result.nameEnglish }
        if nameFrench.isEmpty { nameFrench = result.nameFrench }
        wateringIntervalDays = result.suggestedWateringIntervalDays
        checkIntervalDays = result.suggestedCheckIntervalDays
        aiCareHints = result.careHints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        aiConfidence = result.confidence
    }

    func makeRecord(existingID: UUID? = nil, now: Date = Date()) -> PlantRecord {
        let nextWater = Calendar.current.date(byAdding: .day, value: wateringIntervalDays, to: now) ?? now
        let nextCheck = Calendar.current.date(byAdding: .day, value: checkIntervalDays, to: now) ?? now

        return PlantRecord(
            id: existingID ?? UUID(),
            createdAt: now,
            updatedAt: now,
            photoIdentifier: photoIdentifier,
            nameEnglish: nameEnglish,
            nameFrench: nameFrench,
            isOutdoor: isOutdoor,
            wateringIntervalDays: wateringIntervalDays,
            checkIntervalDays: checkIntervalDays,
            nextWaterDueAt: nextWater,
            nextCheckDueAt: nextCheck,
            notes: notes,
            aiCareHints: aiCareHints,
            aiConfidence: aiConfidence
        )
    }
}
