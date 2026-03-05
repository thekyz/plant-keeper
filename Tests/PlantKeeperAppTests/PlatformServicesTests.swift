import XCTest
import Foundation
import CoreLocation
@testable import PlantKeeperApp
@testable import PlantKeeperCore

final class PlatformServicesTests: XCTestCase {
    func testLocationServiceErrorDescriptionsAreNonEmpty() {
        let errors: [LocationServiceError] = [
            .servicesDisabled,
            .authorizationDenied,
            .missingUsageDescription,
            .unsupportedRuntime,
            .unableToResolveLocation
        ]

        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }

    func testDeviceLocationServiceRequestCurrentLocationFailsOutsideBundledRuntime() async {
        let service = DeviceLocationService()

        do {
            _ = try await service.requestCurrentLocation()
        } catch {
            let expectedTypes: [LocationServiceError] = [
                .servicesDisabled,
                .unsupportedRuntime,
                .missingUsageDescription,
                .authorizationDenied,
                .unableToResolveLocation
            ]
            let matched = expectedTypes.contains { "\($0)" == "\(error)" }
            XCTAssertTrue(matched, "Unexpected location error: \(error)")
        }
    }

    func testDeviceLocationDelegateEntryPointsAreCallable() {
        let service = DeviceLocationService()
        let manager = CLLocationManager()

        service.locationManagerDidChangeAuthorization(manager)
        service.locationManager(manager, didUpdateLocations: [])
        service.locationManager(manager, didFailWithError: URLError(.timedOut))
    }

    func testNotificationSchedulerMethodsAreCallable() async {
        let scheduler = NotificationScheduler()
        let plant = TestFixture.makePlant()

        await scheduler.requestAuthorizationIfNeeded()
        await scheduler.scheduleDailyDigest(hour: 9, minute: 0)
        await scheduler.refreshUrgencyNotifications(plants: [plant], now: Date())
    }

    func testPlantPhotoStoreSaveAndResolveRelativeAndAbsolutePaths() throws {
        let plantID = UUID()
        let identifier = try PlantPhotoStore.savePhotoData(Data([0xDE, 0xAD, 0xBE, 0xEF]), for: plantID)
        let relativeURL = try XCTUnwrap(PlantPhotoStore.photoURL(for: identifier))
        XCTAssertTrue(FileManager.default.fileExists(atPath: relativeURL.path))

        let absoluteURL = PlantPhotoStore.photoURL(for: relativeURL.path)
        XCTAssertEqual(absoluteURL?.path, relativeURL.path)
        XCTAssertNil(PlantPhotoStore.photoURL(for: nil))
        XCTAssertNil(PlantPhotoStore.photoURL(for: ""))

        try? FileManager.default.removeItem(at: relativeURL)
    }

    func testPlantWeatherServiceReturnsNilForIndoorAndMissingCoordinates() async throws {
        let container = try TestFixture.makeInMemoryContainer()
        let settings = AppSettingsStore(modelContainer: container)
        let service = PlantWeatherService(settingsStore: settings)
        let now = Date()

        let indoorPlant = TestFixture.makePlant(isOutdoor: false, nextWaterDueAt: now, nextCheckDueAt: now)
        let outdoorPlant = TestFixture.makePlant(isOutdoor: true, nextWaterDueAt: now, nextCheckDueAt: now)

        let indoorSnapshot = await service.snapshot(forOutdoorPlant: indoorPlant)
        XCTAssertNil(indoorSnapshot)

        let outdoorSnapshotWithoutHome = await service.snapshot(forOutdoorPlant: outdoorPlant)
        XCTAssertNil(outdoorSnapshotWithoutHome)
    }

    func testSettingsUseCaseErrorDescriptionsArePresent() {
        XCTAssertFalse((SettingsUseCaseError.keychainWriteFailed.errorDescription ?? "").isEmpty)
        XCTAssertFalse((SettingsUseCaseError.keychainDeleteFailed.errorDescription ?? "").isEmpty)
    }
}
