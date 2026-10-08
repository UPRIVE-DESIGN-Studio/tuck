import AppKit

/// One status item in the menu bar: a window from `WindowList` plus the app that owns it.
struct MenuBarItem: Identifiable {
    struct Owner {
        let pid: pid_t
        let bundleID: String?
        let appName: String
        /// The item's own Accessibility label, e.g. "Wi‑Fi" for a Control Center module.
        let detail: String?
        let element: AXUIElement
    }

    let windowID: CGWindowID
    /// The window server process that hosts the item window (Control Center on macOS 26).
    let hostPID: pid_t
    let frame: CGRect
    let isOnScreen: Bool
    let placement: Placement
    var owner: Owner?

    var id: CGWindowID { windowID }

    var icon: NSImage? {
        guard let pid = owner?.pid else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.icon
    }
}

/// Where an item sits relative to Tuck's own two items:
///
///     [hidden…] [separator] [visible… / overflow…] [dot] [pinned…]
///
/// Overflow items are on the visible side of the separator but macOS could not fit them,
/// which on a notched display means they sit behind the notch.
enum Placement: Equatable {
    case hidden
    case visible
    case overflow
    /// Right of the dot: Clock, Control Center and anything the user dragged there.
    case pinned

    static func of(frame: CGRect, isOnScreen: Bool, separator: CGRect?, dot: CGRect?) -> Placement {
        if let dot, frame.minX >= dot.maxX - 1 { return .pinned }
        if let separator, frame.maxX <= separator.minX + 1 { return .hidden }
        return isOnScreen ? .visible : .overflow
    }

    var isTucked: Bool { self == .hidden || self == .overflow }
}

enum ItemLabel {
    /// Display names for a whole snapshot; an app's own label is added only when it has several items.
    static func titles(for items: [MenuBarItem]) -> [CGWindowID: String] {
        var countPerApp: [pid_t: Int] = [:]
        for item in items { if let pid = item.owner?.pid { countPerApp[pid, default: 0] += 1 } }
        var titles: [CGWindowID: String] = [:]
        for item in items {
            guard let owner = item.owner else {
                titles[item.windowID] = "Unknown item"
                continue
            }
            titles[item.windowID] = title(
                appName: owner.appName, bundleID: owner.bundleID, detail: owner.detail,
                appHasSeveralItems: (countPerApp[owner.pid] ?? 0) > 1
            )
        }
        return titles
    }

    /// Apple's menu bar agents (Control Center, Spotlight, text input…) have unhelpful app names,
    /// so their items are named by their own label instead.
    static func title(appName: String, bundleID: String?, detail: String?, appHasSeveralItems: Bool) -> String {
        if let bundleID, let fixed = fixedNames[bundleID] { return fixed }
        let isSystemAgent = bundleID.map(systemAgents.contains) ?? false
        // Control Center labels carry live state after a comma: "Wi‑Fi, connected, 3 bars".
        let detail = detail?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let detail, !detail.isEmpty, detail != appName else { return appName }
        if isSystemAgent { return detail }
        return appHasSeveralItems ? "\(appName) — \(detail)" : appName
    }

    private static let systemAgents: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.TextInputMenuAgent",
        "com.apple.notificationcenterui",
    ]

    /// Agents whose label is live data (the weather, a keyboard layout) rather than a name.
    private static let fixedNames: [String: String] = [
        "com.apple.weather.menu": "Weather",
        "com.apple.TextInputMenuAgent": "Input Menu",
    ]
}
