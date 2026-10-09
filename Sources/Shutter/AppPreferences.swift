import Foundation

/* App-level preferences. Same UserDefaults caveat as the rest of the app:
   `swift run` and the bundled app use different defaults domains. */
enum AppPreferences {
    static let changed = Notification.Name("Shutter.PreferencesChanged")

    private static let hideMenuBarIconKey = "pref.hideMenuBarIcon"
    private static let followsAmbientLightKey = "pref.followsAmbientLight"
    private static let darkBelowLuxKey = "pref.darkBelowLux"

    static var isMenuBarIconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hideMenuBarIconKey) }
        set { set(newValue, forKey: hideMenuBarIconKey) }
    }

    static var followsAmbientLight: Bool {
        get { UserDefaults.standard.bool(forKey: followsAmbientLightKey) }
        set { set(newValue, forKey: followsAmbientLightKey) }
    }

    /* The light (lux, as the sensor reports it) below which Dark Mode turns
       on. The sensor sits behind the display glass and reads low: 15–75 in
       a lit room at night, single digits with only a screen on. */
    static let darkBelowLuxRange: ClosedRange<Double> = 1...100
    static let defaultDarkBelowLux = 10.0

    static var darkBelowLux: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: darkBelowLuxKey)
            guard stored > 0 else { return defaultDarkBelowLux }
            return min(max(stored, darkBelowLuxRange.lowerBound), darkBelowLuxRange.upperBound)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: darkBelowLuxKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    private static func set(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
