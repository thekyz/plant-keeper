import XCTest
@testable import PlantKeeperApp
@testable import PlantKeeperCore

final class PlantDraftAndRowModelTests: XCTestCase {
    func testPlantDraftApplyAIFillsEmptyNamesAndIntervals() {
        var draft = PlantDraft()
        let result = AIAnalysisResult(
            nameEnglish: "Monstera",
            nameFrench: "Monstera FR",
            confidence: 0.91,
            suggestedWateringIntervalDays: 6,
            suggestedCheckIntervalDays: 2,
            careHints: ["Bright light"]
        )

        draft.applyAI(result)

        XCTAssertEqual(draft.nameEnglish, "Monstera")
        XCTAssertEqual(draft.nameFrench, "Monstera FR")
        XCTAssertEqual(draft.wateringIntervalDays, 6)
        XCTAssertEqual(draft.checkIntervalDays, 2)
        XCTAssertEqual(draft.aiConfidence, 0.91)
    }

    func testPlantDraftApplyAIDoesNotOverwriteExistingNames() {
        var draft = PlantDraft()
        draft.nameEnglish = "Existing EN"
        draft.nameFrench = "Existing FR"

        draft.applyAI(
            AIAnalysisResult(
                nameEnglish: "New EN",
                nameFrench: "New FR",
                confidence: 0.2,
                suggestedWateringIntervalDays: 10,
                suggestedCheckIntervalDays: 5,
                careHints: []
            )
        )

        XCTAssertEqual(draft.nameEnglish, "Existing EN")
        XCTAssertEqual(draft.nameFrench, "Existing FR")
        XCTAssertEqual(draft.wateringIntervalDays, 10)
        XCTAssertEqual(draft.checkIntervalDays, 5)
    }

    func testPlantDraftMakeRecordUsesProvidedIDAndDates() {
        let now = Date(timeIntervalSince1970: 1_234_567)
        let id = UUID()
        var draft = PlantDraft()
        draft.nameEnglish = "Aloe"
        draft.nameFrench = "Aloe"
        draft.isOutdoor = true
        draft.wateringIntervalDays = 9
        draft.checkIntervalDays = 4
        draft.notes = "Test note"
        draft.aiConfidence = 0.7

        let record = draft.makeRecord(existingID: id, now: now)

        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.createdAt, now)
        XCTAssertEqual(record.updatedAt, now)
        XCTAssertEqual(record.nameEnglish, "Aloe")
        XCTAssertEqual(record.notes, "Test note")
        XCTAssertEqual(record.aiConfidence, 0.7)
        XCTAssertEqual(
            record.nextWaterDueAt,
            Calendar.current.date(byAdding: .day, value: 9, to: now)
        )
        XCTAssertEqual(
            record.nextCheckDueAt,
            Calendar.current.date(byAdding: .day, value: 4, to: now)
        )
    }

    func testOverflowActionTitlesCoverAllCases() {
        let titles = Dictionary(uniqueKeysWithValues: OverflowAction.allCases.map { ($0, $0.title) })
        XCTAssertEqual(titles[.setWateringDate], "Set Watering Date")
        XCTAssertEqual(titles[.wateringLogs], "Watering Logs")
        XCTAssertEqual(titles[.markChecked], "Mark Checked")
        XCTAssertEqual(titles[.edit], "Edit")
        XCTAssertEqual(titles[.delete], "Delete")
        XCTAssertEqual(Set(OverflowAction.allCases.map(\.id)).count, OverflowAction.allCases.count)
    }

    func testPlantRowViewModelComputesDisplayNameUrgencyAndLogs() {
        let now = Date()
        let dueSoon = now.addingTimeInterval(3600)
        let older = now.addingTimeInterval(-8_000)
        let newer = now.addingTimeInterval(-4_000)
        let plant = TestFixture.makePlant(
            nameEnglish: "",
            nameFrench: "Ficus FR",
            wateringLogs: [WateringLog(timestamp: older), WateringLog(timestamp: newer)],
            lastWateredAt: newer,
            nextWaterDueAt: dueSoon,
            nextCheckDueAt: dueSoon
        )
        let urgency = UrgencyEngine().score(for: plant, now: now)
        let row = PlantRowViewModel(plant: plant, urgency: urgency)

        XCTAssertEqual(row.displayName, "Ficus FR")
        XCTAssertEqual(row.urgencyBadge, "Due Soon")
        XCTAssertEqual(row.wateringLogs, [newer, older])
        XCTAssertFalse(row.nextDueText.isEmpty)
    }

    func testPlantRowViewModelHandlesFallbackWateringLogAndOverdueBadge() {
        let now = Date()
        let lastWatered = now.addingTimeInterval(-86_400)
        let plant = TestFixture.makePlant(
            lastWateredAt: lastWatered,
            nextWaterDueAt: now.addingTimeInterval(-60),
            nextCheckDueAt: now.addingTimeInterval(3600)
        )
        let urgency = UrgencyEngine().score(for: plant, now: now)
        let row = PlantRowViewModel(plant: plant, urgency: urgency)

        XCTAssertEqual(row.urgencyBadge, "Overdue")
        XCTAssertEqual(row.wateringLogs, [lastWatered])
    }
}
