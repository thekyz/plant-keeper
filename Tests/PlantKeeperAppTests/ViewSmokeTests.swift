import XCTest
import SwiftUI
@testable import PlantKeeperApp
@testable import PlantKeeperCore

final class ViewSmokeTests: XCTestCase {
    @MainActor
    func testPlantListViewBodyRendersWithRowsAndSheetStates() async {
        let plant = TestFixture.makePlant(id: UUID(), nameEnglish: "Body Plant")
        let viewModel = await TestFixture.makeViewModel(plants: [plant])
        await viewModel.loadPlants()

        let view = PlantListView(viewModel: viewModel)
        _ = view.body

        viewModel.activeSheet = .wateringDate(
            WateringDateDraft(
                plantID: plant.id,
                plantName: "Body Plant",
                mode: .add,
                initialDate: Date()
            )
        )
        _ = view.body

        viewModel.activeSheet = .check(CheckDraft(plantID: plant.id, plantName: "Body Plant"))
        _ = view.body

        viewModel.activeSheet = .wateringLogs(WateringLogsDraft(plantID: plant.id, plantName: "Body Plant"))
        _ = view.body

        viewModel.activeSnoozeDraft = SnoozeDraft(plantID: plant.id, plantName: "Body Plant")
        viewModel.errorMessage = "Example error"
        _ = view.body
    }

    @MainActor
    func testPlantRowViewBodyRendersAndActionClosuresAreCallable() {
        let row = PlantRowViewModel(
            plant: TestFixture.makePlant(nameEnglish: "Row Plant"),
            urgency: UrgencyEngine().score(for: TestFixture.makePlant(nameEnglish: "Row Plant"), now: Date())
        )

        var watered = false
        var checked = false
        var snoozed = false
        var action: OverflowAction?

        let view = PlantRowView(
            row: row,
            onWatered: { watered = true },
            onCheck: { checked = true },
            onSnooze: { snoozed = true },
            onAction: { action = $0 }
        )

        _ = view.body
        view.onWatered()
        view.onCheck()
        view.onSnooze()
        view.onAction(.edit)

        XCTAssertTrue(watered)
        XCTAssertTrue(checked)
        XCTAssertTrue(snoozed)
        XCTAssertEqual(action, .edit)
    }

    @MainActor
    func testAddPlantFlowViewBodyRenders() async {
        let viewModel = await TestFixture.makeViewModel(plants: [])
        viewModel.startNewPlantDraft()
        viewModel.activeDraft.nameEnglish = "Draft Plant"

        let view = AddPlantFlowView(viewModel: viewModel)
        _ = view.body
    }

    @MainActor
    func testSettingsViewBodyRenders() async {
        let viewModel = await TestFixture.makeViewModel(plants: [])
        viewModel.isResolvingCurrentLocation = true

        let view = SettingsView(viewModel: viewModel)
        _ = view.body
    }

    @MainActor
    func testCheckInSheetViewBodyRendersAndCallbacksAreCallable() {
        var markGoodCalled = false
        var savedNote: String?
        var savedPhotoData: Data?
        var cancelled = false

        let view = CheckInSheetView(
            plantName: "Check Plant",
            onMarkGood: { markGoodCalled = true },
            onSaveNote: { note, photoData in
                savedNote = note
                savedPhotoData = photoData
            },
            onCancel: { cancelled = true }
        )

        _ = view.body
        view.onMarkGood()
        view.onSaveNote("note", Data([0x01]))
        view.onCancel()

        XCTAssertTrue(markGoodCalled)
        XCTAssertEqual(savedNote, "note")
        XCTAssertEqual(savedPhotoData, Data([0x01]))
        XCTAssertTrue(cancelled)
    }

    @MainActor
    func testWateringDateAndLogsSheetViewsRenderAllBranches() {
        let plantID = UUID()
        let draft = WateringDateDraft(
            plantID: plantID,
            plantName: "Water Plant",
            mode: .add,
            initialDate: Date()
        )
        var savedDate: Date?
        var cancelled = false
        let dateView = WateringDateSheetView(
            draft: draft,
            onSave: { savedDate = $0 },
            onCancel: { cancelled = true }
        )
        _ = dateView.body
        dateView.onSave(Date(timeIntervalSince1970: 123))
        dateView.onCancel()
        XCTAssertNotNil(savedDate)
        XCTAssertTrue(cancelled)

        var deletedIndex: Int?
        var closed = false
        let emptyLogsView = WateringLogsSheetView(
            plantName: "Water Plant",
            plantID: plantID,
            wateringLogs: [],
            onSaveDraft: { _, _ in },
            onDeleteLog: { deletedIndex = $0 },
            onClose: { closed = true }
        )
        _ = emptyLogsView.body
        emptyLogsView.onDeleteLog(1)
        emptyLogsView.onClose()
        XCTAssertEqual(deletedIndex, 1)
        XCTAssertTrue(closed)

        let nonEmptyLogsView = WateringLogsSheetView(
            plantName: "Water Plant",
            plantID: plantID,
            wateringLogs: [Date(), Date().addingTimeInterval(-3600)],
            onSaveDraft: { _, _ in },
            onDeleteLog: { _ in },
            onClose: {}
        )
        _ = nonEmptyLogsView.body
    }

    @MainActor
    func testSmallSharedViewsRender() {
        var tapped = false
        let settingsButton = SettingsButton(action: { tapped = true }, compact: true)
        _ = settingsButton.body
        settingsButton.action()
        XCTAssertTrue(tapped)

        let header = AppBrandHeaderView()
        _ = header.body

        let camera = CameraCaptureView(onImageData: { _ in })
        _ = camera.body
    }
}
