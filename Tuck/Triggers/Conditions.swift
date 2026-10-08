import AppKit
import IOKit.ps

/// Live readings that triggers are checked against.
enum Conditions {
    struct Power: Equatable {
        let onBattery: Bool
        /// 0…100, nil on a Mac without a battery.
        let percent: Int?
    }

    static func power() -> Power {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return Power(onBattery: false, percent: nil) }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = source == kIOPMBatteryPowerKey
        var percent: Int?
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            percent = current * 100 / max
        }
        return Power(onBattery: onBattery, percent: percent)
    }

    static var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Whether a Focus is on, read from Control Center's Focus menu bar item. With Focus off
    /// its label is just "Focus"; with one on, the label or value names the Focus. Needs the
    /// Focus item in the menu bar (System Settings › Menu Bar › Focus).
    static func focusIsOn(_ items: [MenuBarItem]) -> Bool? {
        guard let item = items.first(where: { $0.owner?.identifier == "com.apple.menuextra.focusmode" }),
              let element = item.owner?.element
        else { return nil }
        if let value = AX.attribute(element, kAXValueAttribute) {
            if let number = value as? NSNumber { return number.boolValue }
            if let text = value as? String { return !text.isEmpty }
        }
        return AX.string(element, kAXDescriptionAttribute)?.contains(",") ?? false
    }
}
