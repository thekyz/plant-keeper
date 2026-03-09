import Foundation
import PlantKeeperCore

struct WateringDateDraft: Identifiable {
    enum Mode {
        case add
        case edit(sortedLogIndex: Int)
    }

    let plantID: UUID
    let plantName: String
    let mode: Mode
    let initialDate: Date

    var id: String {
        switch mode {
        case .add:
            return "\(plantID.uuidString)-add"
        case let .edit(sortedLogIndex):
            return "\(plantID.uuidString)-edit-\(sortedLogIndex)"
        }
    }

    var title: String {
        switch mode {
        case .add: return "Set Watering Date"
        case .edit: return "Edit Watering Date"
        }
    }

    var confirmTitle: String {
        switch mode {
        case .add: return "Save"
        case .edit: return "Update"
        }
    }
}

struct WateringLogsDraft: Identifiable {
    let plantID: UUID
    let plantName: String

    var id: UUID { plantID }
}

struct SnoozeDraft: Identifiable {
    let plantID: UUID
    let plantName: String

    var id: UUID { plantID }
}

struct CheckDraft: Identifiable {
    let plantID: UUID
    let plantName: String

    var id: UUID { plantID }
}

enum ActivePlantSheet: Identifiable {
    case wateringDate(WateringDateDraft)
    case check(CheckDraft)
    case wateringLogs(WateringLogsDraft)

    var id: String {
        switch self {
        case let .wateringDate(draft):
            return "watering-date-\(draft.id)"
        case let .check(draft):
            return "check-\(draft.id.uuidString)"
        case let .wateringLogs(draft):
            return "watering-logs-\(draft.id.uuidString)"
        }
    }
}

@MainActor
final class PlantListViewModel: ObservableObject {
    @Published private(set) var rows: [PlantRowViewModel] = []
    @Published var isPresentingAddPlant = false
    @Published var activeDraft = PlantDraft()
    @Published var draftStatusMessage: String?
    @Published var errorMessage: String?
    @Published var isPresentingSettings = false
    @Published var openAIKeyInput = ""
    @Published var homeLocationNameInput = "Home"
    @Published var homeLatitudeInput = ""
    @Published var homeLongitudeInput = ""
    @Published var isResolvingCurrentLocation = false
    @Published private(set) var editingPlantID: UUID?
    @Published var activeSheet: ActivePlantSheet?
    @Published var activeSnoozeDraft: SnoozeDraft?

    private var editingOriginalPlant: PlantRecord?
    private var didLoadSettings = false
    private var didConfigureNotifications = false
    private var didSeedSimulatorPlants = false
    private var pendingCheckPresentationTask: Task<Void, Never>?

    private let plantListUseCase: PlantListUseCase
    private let plantEditorUseCase: PlantEditorUseCase
    private let settingsUseCase: SettingsUseCase
    private let locationService: DeviceLocationProviding

    init(
        plantListUseCase: PlantListUseCase,
        plantEditorUseCase: PlantEditorUseCase,
        settingsUseCase: SettingsUseCase,
        locationService: DeviceLocationProviding
    ) {
        self.plantListUseCase = plantListUseCase
        self.plantEditorUseCase = plantEditorUseCase
        self.settingsUseCase = settingsUseCase
        self.locationService = locationService
    }

    func loadPlants() async {
        do {
            if !didLoadSettings {
                try await loadSettings()
                didLoadSettings = true
            }
            if !didConfigureNotifications {
                try await plantListUseCase.configureNotificationsIfNeeded()
                didConfigureNotifications = true
            }
            if !didSeedSimulatorPlants {
                try await plantListUseCase.seedSimulatorPlantsIfNeeded(now: Date())
                didSeedSimulatorPlants = true
            }
            rows = try await plantListUseCase.loadRows(now: Date())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSettings() async {
        do {
            let formData = SettingsFormData(
                openAIKey: openAIKeyInput,
                homeLocationName: homeLocationNameInput,
                homeLatitude: homeLatitudeInput,
                homeLongitude: homeLongitudeInput
            )
            try await settingsUseCase.saveFormData(formData)
            isPresentingSettings = false
            await loadPlants()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentSettings() async {
        do {
            try await loadSettings()
            isPresentingSettings = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startNewPlantDraft() {
        activeDraft = PlantDraft()
        editingPlantID = nil
        editingOriginalPlant = nil
        draftStatusMessage = nil
        isPresentingAddPlant = true
    }

    func useCurrentLocationForHome() async {
        isResolvingCurrentLocation = true
        defer { isResolvingCurrentLocation = false }

        do {
            let coordinate = try await locationService.requestCurrentLocation()
            homeLatitudeInput = String(format: "%.6f", coordinate.latitude)
            homeLongitudeInput = String(format: "%.6f", coordinate.longitude)
            if homeLocationNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || homeLocationNameInput == "Home" {
                homeLocationNameInput = "Current Location"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPlantFromDraft() async {
        do {
            try await plantEditorUseCase.saveDraft(activeDraft, editingID: editingPlantID, original: editingOriginalPlant)
            resetDraftState()
            await loadPlants()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func analyzePhotoAndPrefill(_ data: Data) async {
        do {
            let result = try await plantEditorUseCase.analyzePhoto(data)
            if result.identifiesPlant {
                activeDraft.applyAI(result)
                draftStatusMessage = nil
            } else {
                activeDraft.aiConfidence = result.confidence
                draftStatusMessage = "Photo saved, but plant identification needs an OpenAI API key in Settings."
            }
        } catch {
            draftStatusMessage = nil
            errorMessage = "Photo captured, but AI analysis failed."
        }
    }

    func cancelDraft() {
        resetDraftState()
    }

    func markWatered(plantID: UUID) async {
        do {
            try await plantListUseCase.markWatered(plantID: plantID, at: Date())
            await loadPlants()
        } catch {
            errorMessage = "Failed to mark as watered. Please retry."
        }
    }

    func snoozeWateringOneDay(plantID: UUID) async {
        do {
            try await plantListUseCase.snoozeWatering(plantID: plantID, days: 1, now: Date())
            await loadPlants()
        } catch {
            errorMessage = "Failed to snooze watering. Please retry."
        }
    }

    func requestSnooze(plantID: UUID) {
        guard let row = rows.first(where: { $0.id == plantID }) else { return }
        activeSnoozeDraft = SnoozeDraft(plantID: plantID, plantName: row.displayName)
    }

    func confirmSnooze(from draft: SnoozeDraft) async {
        activeSnoozeDraft = nil
        await snoozeWateringOneDay(plantID: draft.plantID)
    }

    func requestCheck(plantID: UUID) {
        guard let row = rows.first(where: { $0.id == plantID }) else { return }
        let draft = CheckDraft(plantID: plantID, plantName: row.displayName)
        pendingCheckPresentationTask?.cancel()
        pendingCheckPresentationTask = Task { @MainActor [draft] in
            defer { pendingCheckPresentationTask = nil }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, activeSheet == nil else { return }
            activeSheet = .check(draft)
        }
    }

    func confirmCheckAllGood(from draft: CheckDraft) async {
        activeSheet = nil

        do {
            try await plantListUseCase.markChecked(plantID: draft.plantID, at: Date())
            await loadPlants()
        } catch {
            errorMessage = "Failed to save check. Please retry."
        }
    }

    func saveCheckObservation(from draft: CheckDraft, note: String, photoData: Data?) async {
        activeSheet = nil

        do {
            try await plantListUseCase.markChecked(
                plantID: draft.plantID,
                at: Date(),
                note: note,
                photoData: photoData
            )
            await loadPlants()
        } catch {
            errorMessage = "Failed to save check. Please retry."
        }
    }

    func saveWateringDate(from draft: WateringDateDraft, selectedDate: Date) async {
        do {
            switch draft.mode {
            case .add:
                try await plantListUseCase.addWateringLog(plantID: draft.plantID, at: selectedDate, now: Date())
            case let .edit(sortedLogIndex):
                try await plantListUseCase.updateWateringLog(
                    plantID: draft.plantID,
                    sortedLogIndex: sortedLogIndex,
                    to: selectedDate,
                    now: Date()
                )
            }

            activeSheet = nil
            await loadPlants()
        } catch {
            errorMessage = "Failed to save watering date. Please retry."
        }
    }

    func deleteWateringLog(plantID: UUID, sortedLogIndex: Int) async {
        do {
            try await plantListUseCase.deleteWateringLog(plantID: plantID, sortedLogIndex: sortedLogIndex, now: Date())
            await loadPlants()
        } catch {
            errorMessage = "Failed to delete watering log. Please retry."
        }
    }

    func handleOverflowAction(_ action: OverflowAction, plantID: UUID) async {
        do {
            switch action {
            case .setWateringDate:
                guard let row = rows.first(where: { $0.id == plantID }) else { return }
                activeSheet = .wateringDate(WateringDateDraft(
                    plantID: plantID,
                    plantName: row.displayName,
                    mode: .add,
                    initialDate: Date()
                ))
            case .wateringLogs:
                guard let row = rows.first(where: { $0.id == plantID }) else { return }
                activeSheet = .wateringLogs(WateringLogsDraft(plantID: row.id, plantName: row.displayName))
            case .markChecked:
                try await plantListUseCase.markChecked(plantID: plantID, at: Date())
                await loadPlants()
            case .edit:
                guard let target = rows.first(where: { $0.id == plantID }) else { return }
                editingPlantID = plantID
                editingOriginalPlant = target.plant
                activeDraft = await plantEditorUseCase.makeDraft(from: target.plant)
                draftStatusMessage = nil
                isPresentingAddPlant = true
            case .delete:
                try await plantListUseCase.deletePlant(plantID: plantID)
                await loadPlants()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSettings() async throws {
        let formData = try await settingsUseCase.loadFormData()
        openAIKeyInput = formData.openAIKey
        homeLocationNameInput = formData.homeLocationName
        homeLatitudeInput = formData.homeLatitude
        homeLongitudeInput = formData.homeLongitude
    }

    private func resetDraftState() {
        activeDraft = PlantDraft()
        editingPlantID = nil
        editingOriginalPlant = nil
        draftStatusMessage = nil
        isPresentingAddPlant = false
    }
}
