import Foundation

/// Small user preferences, stored in UserDefaults.
enum Preferences {
    private enum Key {
        static let notchHover = "notchHover"
        static let autoTuck = "autoTuck"
        static let revealOnPlainDisplays = "revealOnPlainDisplays"
        static let showCount = "showCount"
        static let shelfNowPlaying = "shelfNowPlaying"
        static let shelfTimer = "shelfTimer"
        static let shelfFiles = "shelfFiles"
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

    /// While a display without a notch is connected, show Hide items in the menu bar too.
    /// Off by default: Hide means hidden everywhere.
    static var revealOnPlainDisplays: Bool {
        get { bool(Key.revealOnPlainDisplays, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: Key.revealOnPlainDisplays) }
    }

    /// Show how many items are out of sight next to the dot. On by default.
    static var showCount: Bool {
        get { bool(Key.showCount, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.showCount) }
    }

    /// Shelf sections in the drawer. All on by default.
    static var shelfNowPlaying: Bool {
        get { bool(Key.shelfNowPlaying, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.shelfNowPlaying) }
    }

    static var shelfTimer: Bool {
        get { bool(Key.shelfTimer, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.shelfTimer) }
    }

    static var shelfFiles: Bool {
        get { bool(Key.shelfFiles, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.shelfFiles) }
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
