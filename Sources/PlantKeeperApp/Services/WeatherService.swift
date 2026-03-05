import Foundation
import CoreLocation
import WeatherKit
import PlantKeeperCore

actor PlantWeatherService {
    private let weatherKitService = WeatherService()
    private let settingsStore: AppSettingsStore

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
    }

    func snapshot(forOutdoorPlant plant: PlantRecord) async -> WeatherSnapshot? {
        guard plant.isOutdoor else {
            return nil
        }

        do {
            guard let coords = try await settingsStore.homeCoordinates() else {
                return nil
            }

            let location = CLLocation(latitude: coords.latitude, longitude: coords.longitude)
            let weather = try await weatherKitService.weather(for: location)

            let today = weather.dailyForecast.forecast.first
            let tomorrow = weather.dailyForecast.forecast.dropFirst().first

            return WeatherSnapshot(
                rainMillimeters24h: today?.precipitationAmount.converted(to: .millimeters).value ?? 0,
                forecastRainMillimeters24h: tomorrow?.precipitationAmount.converted(to: .millimeters).value ?? 0,
                minTemperatureC: today?.lowTemperature.converted(to: .celsius).value ?? weather.currentWeather.temperature.converted(to: .celsius).value,
                maxTemperatureC: today?.highTemperature.converted(to: .celsius).value ?? weather.currentWeather.temperature.converted(to: .celsius).value
            )
        } catch {
            return nil
        }
    }
}
