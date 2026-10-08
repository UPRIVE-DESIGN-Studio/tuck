import CoreLocation
import CoreWLAN

/// The current Wi‑Fi network name. macOS only reveals it to apps with Location access, so the
/// first call asks for it.
enum WiFi {
    private static let location = CLLocationManager()

    static func currentSSID() -> String? {
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        }
        return CWWiFiClient.shared().interface()?.ssid()
    }
}
