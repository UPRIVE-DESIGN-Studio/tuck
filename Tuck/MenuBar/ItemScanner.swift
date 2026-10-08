import AppKit
import ApplicationServices

/// Builds the current list of menu bar items and classifies them against Tuck's control items.
final class ItemScanner {
    struct Snapshot {
        /// Other apps' items, left to right. Tuck's own items are excluded.
        var items: [MenuBarItem]
        var dot: WindowList.Entry?
        var separator: WindowList.Entry?

        var tucked: [MenuBarItem] { items.filter { $0.placement.isTucked } }
        var hasHidden: Bool { items.contains { $0.placement == .hidden } }

        func item(_ windowID: CGWindowID) -> MenuBarItem? {
            items.first { $0.windowID == windowID }
        }
    }

    private let controls: ControlItems
    private let resolver = OwnerResolver()
    private var dotWindowID: CGWindowID?
    private var separatorWindowID: CGWindowID?

    init(controls: ControlItems) {
        self.controls = controls
    }

    func scan(resolveOwners: Bool = true) -> Snapshot {
        let dotFrame = controls.dotFrame
        let separatorFrame = controls.separatorFrame
        let menuBarTop = dotFrame?.minY ?? 0
        let entries = WindowList.statusItems(menuBarTop: menuBarTop)

        // Window IDs stay the same for the item's lifetime, but the window server reports a new
        // frame a beat after AppKit does, so match by frame only until the ID is known.
        let dot = entries.first { $0.windowID == dotWindowID } ?? entries.first { dotFrame.map($0.frame.matches) ?? false }
        let separator = entries.first { $0.windowID == separatorWindowID }
            ?? entries.first { separatorFrame.map($0.frame.matches) ?? false }
        if let dot { dotWindowID = dot.windowID }
        if let separator { separatorWindowID = separator.windowID }
        let owners = resolveOwners && Permissions.isTrusted ? resolver.owners(for: entries) : [:]

        var items: [MenuBarItem] = []
        for entry in entries where entry.windowID != dot?.windowID && entry.windowID != separator?.windowID {
            let placement = Placement.of(
                frame: entry.frame, isOnScreen: entry.isOnScreen,
                separator: separator?.frame, dot: dot?.frame
            )
            items.append(MenuBarItem(
                windowID: entry.windowID, hostPID: entry.ownerPID, frame: entry.frame,
                isOnScreen: entry.isOnScreen, placement: placement, owner: owners[entry.windowID]
            ))
        }
        return Snapshot(items: items, dot: dot, separator: separator)
    }
}

/// Finds the app behind each item window by matching window frames with the children of every
/// app's `AXExtrasMenuBar`. Needed because on macOS 26 all item windows belong to Control Center.
final class OwnerResolver {
    /// Apps known to have menu bar items; asked first, so a scan usually ends after a handful.
    private var knownOwners: [pid_t] = []
    /// Apps without menu bar items, skipped until an app launches or a few minutes pass.
    private var withoutExtras: [pid_t: Date] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var launchObserver: NSObjectProtocol?

    init() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.withoutExtras.removeAll() }
        }
    }

    func owners(for entries: [WindowList.Entry]) -> [CGWindowID: MenuBarItem.Owner] {
        let started = Date.now
        var result: [CGWindowID: MenuBarItem.Owner] = [:]
        var queried = 0

        let running = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != ownPID }
        let known = Set(knownOwners)
        let ordered = running.filter { known.contains($0.processIdentifier) }
            + running.filter { !known.contains($0.processIdentifier) }
        var owners: [pid_t] = []

        for app in ordered {
            if result.count == entries.count { break }
            let pid = app.processIdentifier
            if let since = withoutExtras[pid], since.timeIntervalSinceNow > -300 { continue }

            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.15)
            queried += 1
            guard let bar = AX.attribute(element, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
                withoutExtras[pid] = .now
                continue
            }
            let name = app.localizedName ?? app.bundleIdentifier ?? "pid \(pid)"
            for child in AX.children(bar as! AXUIElement) {
                // The Accessibility frame is a few points narrower than the item window and sits inside it.
                guard let frame = AX.frame(child), frame.width > 0,
                      let match = entries.first(where: { $0.frame.minX <= frame.midX && frame.midX < $0.frame.maxX })
                else { continue }
                let detail = AX.string(child, kAXDescriptionAttribute) ?? AX.string(child, kAXTitleAttribute)
                result[match.windowID] = MenuBarItem.Owner(
                    pid: pid, bundleID: app.bundleIdentifier, appName: name, detail: detail, element: child
                )
                owners.append(pid)
            }
        }
        knownOwners = Array(Set(owners))

        let ms = Int(Date.now.timeIntervalSince(started) * 1000)
        if ms > 100 { Log.info("owner scan took \(ms) ms over \(queried) apps") }
        return result
    }
}

extension CGRect {
    /// Same position and width within a point; heights differ between AX and the window server.
    func matches(_ other: CGRect) -> Bool {
        abs(minX - other.minX) <= 1 && abs(width - other.width) <= 1
    }
}
