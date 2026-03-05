import Foundation
import SwiftData
import PlantKeeperCore

struct AppDependencies {
    let plantListUseCase: PlantListUseCase
    let plantEditorUseCase: PlantEditorUseCase
    let settingsUseCase: SettingsUseCase
    let locationService: DeviceLocationProviding

    static func live(container: ModelContainer) -> AppDependencies {
        let repository = SwiftDataPlantRepository(modelContainer: container)
        let settingsStore = AppSettingsStore(modelContainer: container)
        let weatherService = PlantWeatherService(settingsStore: settingsStore)
        let keyStore = KeychainKeyStore()
        let aiService = HybridAIService(
            onDevice: OnDevicePlantAnalyzer(),
            cloud: CloudPlantAnalyzer(keyStore: keyStore),
            keyStore: keyStore
        )
        let service = PlantService(
            store: repository,
            weatherProvider: { plant in
                await weatherService.snapshot(forOutdoorPlant: plant)
            }
        )
        let notificationScheduler = NotificationScheduler()
        let plantListUseCase = PlantListUseCase(
            plantService: service,
            repository: repository,
            notificationScheduler: notificationScheduler,
            appSettingsStore: settingsStore
        )
        let plantEditorUseCase = PlantEditorUseCase(repository: repository, aiService: aiService)
        let settingsUseCase = SettingsUseCase(appSettingsStore: settingsStore, keyStore: keyStore)
        let locationService = DeviceLocationService()

        return AppDependencies(
            plantListUseCase: plantListUseCase,
            plantEditorUseCase: plantEditorUseCase,
            settingsUseCase: settingsUseCase,
            locationService: locationService
        )
    }

    @MainActor
    func makePlantListViewModel() -> PlantListViewModel {
        PlantListViewModel(
            plantListUseCase: plantListUseCase,
            plantEditorUseCase: plantEditorUseCase,
            settingsUseCase: settingsUseCase,
            locationService: locationService
        )
    }
}
