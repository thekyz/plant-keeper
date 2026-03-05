import Foundation
import CoreLocation

enum LocationServiceError: LocalizedError {
    case servicesDisabled
    case authorizationDenied
    case missingUsageDescription
    case unsupportedRuntime
    case unableToResolveLocation

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "Location services are disabled on this device."
        case .authorizationDenied:
            return "Location permission denied. Enable it in system settings."
        case .missingUsageDescription:
            return "Missing NSLocationWhenInUseUsageDescription in Info.plist."
        case .unsupportedRuntime:
            return "Current location is unavailable in this runtime. Launch the bundled app from Xcode to use location services."
        case .unableToResolveLocation:
            return "Unable to get your current location."
        }
    }
}

protocol DeviceLocationProviding {
    func requestCurrentLocation() async throws -> CLLocationCoordinate2D
}

final class DeviceLocationService: NSObject, DeviceLocationProviding {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() async throws -> CLLocationCoordinate2D {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationServiceError.servicesDisabled
        }

        #if os(macOS)
        guard isBundledAppRuntime else {
            throw LocationServiceError.unsupportedRuntime
        }
        #endif

        #if os(iOS) || os(macOS)
        guard hasLocationUsageDescription else {
            throw LocationServiceError.missingUsageDescription
        }
        #endif

        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return try await requestLocationValue()
        case .notDetermined:
            try await requestAuthorizationIfNeeded()
            return try await requestLocationValue()
        case .restricted, .denied:
            throw LocationServiceError.authorizationDenied
        @unknown default:
            throw LocationServiceError.unableToResolveLocation
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.authorizationContinuation = continuation
                    self.manager.requestWhenInUseAuthorization()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 12_000_000_000)
                self.authorizationContinuation = nil
                throw LocationServiceError.unableToResolveLocation
            }

            let _: Void = try await group.next()!
            group.cancelAll()
            return
        }
    }

    private func requestLocationValue() async throws -> CLLocationCoordinate2D {
        try await withThrowingTaskGroup(of: CLLocationCoordinate2D.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.locationContinuation = continuation
                    self.manager.requestLocation()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 12_000_000_000)
                self.locationContinuation = nil
                throw LocationServiceError.unableToResolveLocation
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private var hasLocationUsageDescription: Bool {
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String else {
            return false
        }
        return !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isBundledAppRuntime: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }
}

extension DeviceLocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationContinuation = nil
            continuation.resume()
        case .restricted, .denied:
            authorizationContinuation = nil
            continuation.resume(throwing: LocationServiceError.authorizationDenied)
        case .notDetermined:
            break
        @unknown default:
            authorizationContinuation = nil
            continuation.resume(throwing: LocationServiceError.unableToResolveLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil

        if let coordinate = locations.first?.coordinate {
            continuation.resume(returning: coordinate)
        } else {
            continuation.resume(throwing: LocationServiceError.unableToResolveLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(throwing: error)
            return
        }

        if let continuation = authorizationContinuation {
            authorizationContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}
