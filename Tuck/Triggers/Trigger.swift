import Foundation

/// A condition that brings a tucked item into the menu bar while it holds.
enum Trigger: Codable, Equatable, Hashable {
    /// While this app is in front.
    case appFrontmost(bundleID: String)
    /// While running on battery.
    case onBattery
    /// While the battery is below this percentage.
    case batteryBelow(percent: Int)
    /// While connected to this Wi‑Fi network.
    case wifi(ssid: String)
    /// While a Focus is on.
    case focus
    /// When the item's icon changes (sync started, VPN dropped): the notch drawer peeks open.
    case appearanceChanges

    var summary: String {
        switch self {
        case .appFrontmost(let bundleID): "While \(AppName.of(bundleID)) is in front"
        case .onBattery: "While on battery"
        case .batteryBelow(let percent): "While battery is below \(percent) %"
        case .wifi(let ssid): "While on Wi‑Fi “\(ssid)”"
        case .focus: "While a Focus is on"
        case .appearanceChanges: "Peek when its icon changes"
        }
    }
}

enum AppName {
    static func of(_ bundleID: String) -> String {
        guard let url = NSWorkspaceProxy.urlForApplication(bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
