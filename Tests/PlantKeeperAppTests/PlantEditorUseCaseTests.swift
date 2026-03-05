import XCTest
@testable import PlantKeeperApp
@testable import PlantKeeperCore

final class PlantEditorUseCaseTests: XCTestCase {
    func testAnalyzePhotoDelegatesToAnalyzer() async throws {
        let expected = AIAnalysisResult(
            nameEnglish: "Rose",
            nameFrench: "Rose FR",
            confidence: 0.8,
            suggestedWateringIntervalDays: 4,
            suggestedCheckIntervalDays: 2,
            careHints: ["Sun"]
        )
        let useCase = PlantEditorUseCase(
            repository: MockPlantStore(),
            aiService: MockPlantAnalyzer(result: expected)
        )

        let result = try await useCase.analyzePhoto(Data([0x01]))

        XCTAssertEqual(result, expected)
    }

    func testMakeDraftCopiesPlantFields() async {
        let plant = TestFixture.makePlant(
            nameEnglish: "Aloe",
            nameFrench: "Aloe Vera",
            isOutdoor: true,
            wateringIntervalDays: 9,
            checkIntervalDays: 3,
            notes: "Needs sun",
            aiConfidence: 0.44
        )
        let useCase = PlantEditorUseCase(repository: MockPlantStore(), aiService: MockPlantAnalyzer())

        let draft = await useCase.makeDraft(from: plant)

        XCTAssertEqual(draft.nameEnglish, "Aloe")
        XCTAssertEqual(draft.nameFrench, "Aloe Vera")
        XCTAssertTrue(draft.isOutdoor)
        XCTAssertEqual(draft.wateringIntervalDays, 9)
        XCTAssertEqual(draft.checkIntervalDays, 3)
        XCTAssertEqual(draft.notes, "Needs sun")
        XCTAssertEqual(draft.aiConfidence, 0.44)
    }

    func testSaveDraftCreatesNewRecordForNewPlant() async throws {
        let store = MockPlantStore()
        let useCase = PlantEditorUseCase(repository: store, aiService: MockPlantAnalyzer())
        var draft = PlantDraft()
        draft.nameEnglish = "Mint"
        draft.nameFrench = "Menthe"
        draft.wateringIntervalDays = 5
        draft.checkIntervalDays = 2

        try await useCase.saveDraft(draft, editingID: nil, original: nil)

        let upserted = await store.upsertedPlantIDs
        XCTAssertEqual(upserted.count, 1)
        let saved = try await store.plant(withID: upserted[0])
        XCTAssertEqual(saved?.nameEnglish, "Mint")
        XCTAssertEqual(saved?.wateringIntervalDays, 5)
        XCTAssertEqual(saved?.checkIntervalDays, 2)
    }

    func testSaveDraftEditingPreservesOriginalIdentityAndScheduleWhenIntervalsUnchanged() async throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let lastWatered = Date(timeIntervalSince1970: 200)
        let lastChecked = Date(timeIntervalSince1970: 300)
        let nextWater = Date(timeIntervalSince1970: 400)
        let nextCheck = Date(timeIntervalSince1970: 500)

        let original = TestFixture.makePlant(
            id: id,
            createdAt: createdAt,
            updatedAt: Date(timeIntervalSince1970: 350),
            photoIdentifier: "old.jpg",
            nameEnglish: "Original",
            nameFrench: "Original FR",
            wateringIntervalDays: 7,
            checkIntervalDays: 4,
            lastWateredAt: lastWatered,
            lastCheckedAt: lastChecked,
            nextWaterDueAt: nextWater,
            nextCheckDueAt: nextCheck
        )
        let store = MockPlantStore(plants: [original])
        let useCase = PlantEditorUseCase(repository: store, aiService: MockPlantAnalyzer())
        var draft = PlantDraft()
        draft.nameEnglish = "Edited"
        draft.nameFrench = "Edited FR"
        draft.wateringIntervalDays = original.wateringIntervalDays
        draft.checkIntervalDays = original.checkIntervalDays
        draft.notes = "Updated note"

        try await useCase.saveDraft(draft, editingID: id, original: original)

        let saved = try await store.plant(withID: id)
        XCTAssertEqual(saved?.id, id)
        XCTAssertEqual(saved?.createdAt, createdAt)
        XCTAssertEqual(saved?.lastWateredAt, lastWatered)
        XCTAssertEqual(saved?.lastCheckedAt, lastChecked)
        XCTAssertEqual(saved?.photoIdentifier, "old.jpg")
        XCTAssertEqual(saved?.nextWaterDueAt, nextWater)
        XCTAssertEqual(saved?.nextCheckDueAt, nextCheck)
        XCTAssertEqual(saved?.nameEnglish, "Edited")
    }

    func testSaveDraftEditingRecomputesScheduleWhenIntervalsChange() async throws {
        let id = UUID()
        let lastWatered = Date(timeIntervalSince1970: 10_000)
        let lastChecked = Date(timeIntervalSince1970: 20_000)
        let original = TestFixture.makePlant(
            id: id,
            wateringIntervalDays: 7,
            checkIntervalDays: 3,
            lastWateredAt: lastWatered,
            lastCheckedAt: lastChecked,
            nextWaterDueAt: Date(timeIntervalSince1970: 30_000),
            nextCheckDueAt: Date(timeIntervalSince1970: 40_000)
        )
        let store = MockPlantStore(plants: [original])
        let useCase = PlantEditorUseCase(repository: store, aiService: MockPlantAnalyzer())
        var draft = PlantDraft()
        draft.nameEnglish = "Edited"
        draft.nameFrench = "Edited FR"
        draft.wateringIntervalDays = 2
        draft.checkIntervalDays = 5

        try await useCase.saveDraft(draft, editingID: id, original: original)

        let saved = try await store.plant(withID: id)
        XCTAssertEqual(
            saved?.nextWaterDueAt,
            Calendar.current.date(byAdding: .day, value: 2, to: lastWatered)
        )
        XCTAssertEqual(
            saved?.nextCheckDueAt,
            Calendar.current.date(byAdding: .day, value: 5, to: lastChecked)
        )
    }

    func testSaveDraftPersistsPhotoDataAndWritesIdentifier() async throws {
        let store = MockPlantStore()
        let useCase = PlantEditorUseCase(repository: store, aiService: MockPlantAnalyzer())
        var draft = PlantDraft()
        draft.nameEnglish = "Photo Plant"
        draft.photoData = Data([0x01, 0x02, 0x03, 0x04])

        try await useCase.saveDraft(draft, editingID: nil, original: nil)

        let ids = await store.upsertedPlantIDs
        guard let saved = try await store.plant(withID: ids[0]) else {
            XCTFail("Missing saved record.")
            return
        }
        XCTAssertNotNil(saved.photoIdentifier)

        if let url = PlantPhotoStore.photoURL(for: saved.photoIdentifier) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url)
        }
    }
}
