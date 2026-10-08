import Foundation

/// Small user preferences, stored in UserDefaults.
enum Preferences {
    private enum Key {
        static let notchHover = "notchHover"
        static let autoTuck = "autoTuck"
        static let revealOnPlainDisplays = "revealOnPlainDisplays"
        static let showCount = "showCount"
    }

    /// Hovering the notch opens the drawer of tucked items. On by default.
    static var notchHover: Bool {
        get { bool(Key.notchHover, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.notchHover) }
    }

    /// Tuck the least important items when the notch would cover something. On by default.
    static var autoTuck: Bool {
        get { bool(Key.autoTuck, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.autoTuck) }
    }

    /// On a display without a notch, show hidden items in the menu bar too. On by default.
    static var revealOnPlainDisplays: Bool {
        get { bool(Key.revealOnPlainDisplays, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.revealOnPlainDisplays) }
    }

    /// Show how many items are out of sight next to the dot. On by default.
    static var showCount: Bool {
        get { bool(Key.showCount, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.showCount) }
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
