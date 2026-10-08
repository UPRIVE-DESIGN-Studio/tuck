import Foundation

/// Small user preferences, stored in UserDefaults.
enum Preferences {
    private enum Key {
        static let notchHover = "notchHover"
    }

    /// Hovering the notch opens the drawer of tucked items. On by default.
    static var notchHover: Bool {
        get { UserDefaults.standard.object(forKey: Key.notchHover) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.notchHover) }
    }
}
