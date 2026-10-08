import AppKit

/// One status item in the menu bar: a window from `WindowList` plus the app that owns it.
struct MenuBarItem: Identifiable {
    struct Owner {
        let pid: pid_t
        let bundleID: String?
        let appName: String
        /// The item's own Accessibility label, e.g. "Wi‑Fi" for a Control Center module.
        let detail: String?
        /// `AXIdentifier`, e.g. "com.apple.menuextra.wifi". Only some apps set one.
        let identifier: String?
        let element: AXUIElement
    }

    let windowID: CGWindowID
    /// The window server process that hosts the item window (Control Center on macOS 26).
    let hostPID: pid_t
    let frame: CGRect
    let isOnScreen: Bool
    let placement: Placement
    var owner: Owner?
    /// Stable identity across app relaunches and reboots; nil until the owner is known.
    var key: ItemKey?

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
    /// Right of the separator, whether or not macOS found room for it.
    var isVisibleSide: Bool { self == .visible || self == .overflow }
}

/// Identifies an item across relaunches: window IDs change every time an app starts, so items
/// are keyed by app plus the item's Accessibility identifier, or its position among that app's
/// items when it has none.
struct ItemKey: Hashable, Codable, Comparable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(bundleID: String, qualifier: String) {
        rawValue = "\(bundleID)|\(qualifier)"
    }

    var bundleID: String { String(rawValue.prefix { $0 != "|" }) }
    var description: String { rawValue }

    static func < (lhs: ItemKey, rhs: ItemKey) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Keys for a whole snapshot, in the order given (left to right).
    static func keys(for owners: [(bundleID: String?, identifier: String?)]) -> [ItemKey?] {
        var seen: [String: Int] = [:]
        return owners.map { owner in
            guard let bundleID = owner.bundleID else { return nil }
            if let identifier = owner.identifier { return ItemKey(bundleID: bundleID, qualifier: identifier) }
            let index = seen[bundleID, default: 0]
            seen[bundleID] = index + 1
            return ItemKey(bundleID: bundleID, qualifier: "#\(index)")
        }
    }
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
