import Foundation
import CoreLocation
import Combine

struct DayForecast: Identifiable {
    let id = UUID()
    let weekday: String
    let maxTemp: Int
    let symbolName: String
}

@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentTemp: Int?
    @Published var currentSymbol: String = "cloud.fill"
    @Published var forecast: [DayForecast] = []

    private let locationManager = CLLocationManager()
    private var didRequestLocation = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        guard !didRequestLocation else { return }
        didRequestLocation = true
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await self.fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Fall back silently; the widget just won't show weather until location is available.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorized {
            manager.requestLocation()
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max"),
            URLQueryItem(name: "forecast_days", value: "4"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

            currentTemp = Int(response.current.temperature_2m.rounded())
            currentSymbol = Self.symbol(forCode: response.current.weather_code)

            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"

            var days: [DayForecast] = []
            // Skip index 0 (today) to show the upcoming days, like the reference widget.
            for i in 1..<min(response.daily.time.count, 4) {
                let dateString = response.daily.time[i]
                let isoFormatter = DateFormatter()
                isoFormatter.dateFormat = "yyyy-MM-dd"
                let weekday = isoFormatter.date(from: dateString).map { formatter.string(from: $0) } ?? ""
                days.append(DayForecast(
                    weekday: weekday,
                    maxTemp: Int(response.daily.temperature_2m_max[i].rounded()),
                    symbolName: Self.symbol(forCode: response.daily.weather_code[i])
                ))
            }
            forecast = days
        } catch {
            // Network or decoding failure: leave previous values in place.
        }
    }

    private static func symbol(forCode code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
    }
    let current: Current
    let daily: Daily
}
