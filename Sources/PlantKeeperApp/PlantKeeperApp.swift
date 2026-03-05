import SwiftUI
import SwiftData

@main
@MainActor
struct PlantKeeperApp: App {
    private let modelContainer: ModelContainer
    private let dependencies: AppDependencies
    private let plantListViewModel: PlantListViewModel

    init() {
        do {
            modelContainer = try Self.makeModelContainer()
            dependencies = AppDependencies.live(container: modelContainer)
            plantListViewModel = dependencies.makePlantListViewModel()
        } catch {
            fatalError("Failed to start app: \(error)")
        }
    }

    private static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([PlantEntity.self, AppSettingsEntity.self])
        let cloudConfiguration = ModelConfiguration(
            "PlantKeeper",
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [cloudConfiguration])
        } catch {
            // Fall back to local persistence when CloudKit capability is unavailable.
            let localConfiguration = ModelConfiguration("PlantKeeper", schema: schema)
            return try ModelContainer(for: schema, configurations: [localConfiguration])
        }
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            PlantListView(viewModel: plantListViewModel)
                .frame(
                    minWidth: 430,
                    idealWidth: 430,
                    maxWidth: 430,
                    minHeight: 840,
                    idealHeight: 840,
                    maxHeight: 840
                )
                .modelContainer(modelContainer)
            #else
            PlantListView(viewModel: plantListViewModel)
                .dynamicTypeSize(.small ... .xxLarge)
                .modelContainer(modelContainer)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 430, height: 840)
        .windowResizability(.contentSize)
        #endif
    }
}
