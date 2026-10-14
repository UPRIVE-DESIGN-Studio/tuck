import AppKit
import ApplicationServices
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TuckController?
    private var autoTucker: AutoTucker?
    private var triggers: TriggerEngine?
    private let windowZones = WindowZones()
    private let store = ItemStore()
    private var dot: DotController?
    private var settingsWindow: WindowHost?
    private var permissionPoll: Task<Void, Never>?

    private lazy var onboardingWindow = WindowHost(title: "Welcome to Tuck") {
        OnboardingView()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app; keep the host inert.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let controller = TuckController()
        self.controller = controller
        let autoTucker = AutoTucker(controller: controller, store: store)
        self.autoTucker = autoTucker
        autoTucker.onCountChange = { count in
            controller.controls.setCount(Preferences.showCount ? count : 0)
        }
        let settings = SettingsModel(controller: controller, store: store)
        settings.onLayoutPreferenceChange = { [weak self] in
            controller.enqueue { await controller.settleSeparator() }
            autoTucker.schedule(enforceModes: true)
            self?.triggers?.check()
        }
        let dot = DotController(
            controller: controller,
            showSettings: { [weak self] in self?.settingsWindow?.show() },
            showOnboarding: { [weak self] in self?.showOnboarding() }
        )
        self.dot = dot
        settingsWindow = WindowHost(title: "Tuck Settings") { SettingsView(model: settings, shelf: dot.shelf) }
        let triggers = TriggerEngine(controller: controller, store: store) { [weak dot] in dot?.peek() }
        self.triggers = triggers
        autoTucker.exempt = { [weak triggers] in triggers?.shownByTrigger ?? [] }
        settings.onNotchHoverChange = { [weak self] in self?.dot?.setNotchHover($0) }
        windowZones.start()
        Log.info("launched; trusted=\(Permissions.isTrusted)")

        // Status item windows get their frames a moment after creation.
        controller.enqueue {
            try? await Task.sleep(for: .milliseconds(500))
            await controller.settleSeparator()
            // The first owner scan asks every running app; do it now rather than on the first click.
            if Permissions.isTrusted { self.store.adopt(controller.scanner.scan().items) }
            autoTucker.start()
            triggers.start()
            await self.checkHealthAfterSystemUpdate(controller, settings: settings)
        }

        if !Permissions.isTrusted {
            showOnboarding()
        }
    }

    /// After a macOS update (or on the very first launch), checks that hiding and moving still work.
    private func checkHealthAfterSystemUpdate(_ controller: TuckController, settings: SettingsModel) async {
        let key = "lastCheckedSystem"
        guard Permissions.isTrusted, UserDefaults.standard.string(forKey: key) != HealthCheck.systemVersion else { return }
        let report = await HealthCheck.run(controller)
        settings.setHealth(report)
        UserDefaults.standard.set(HealthCheck.systemVersion, forKey: key)
    }

    /// Shows the permission explainer and polls once a second until access is granted.
    private func showOnboarding() {
        onboardingWindow.show()
        guard permissionPoll == nil else { return }
        permissionPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if Permissions.isTrusted {
                    Log.info("accessibility granted")
                    if let items = self.controller?.scanner.scan().items { self.store.adopt(items) }
                    self.onboardingWindow.close()
                    self.permissionPoll = nil
                    return
                }
            }
        }
    }

    // MARK: tuck:// URLs (scripting and debugging)

    /// `tuck://dump`, `tuck://hide/<window>`, `tuck://show/<window>`, `tuck://open/<window>`,
    /// `tuck://click/<window>`, `tuck://press/<window>`, `tuck://route/<session|pid|hid>`,
    /// `tuck://separator/<idle|collapsed|expanded>`. Window IDs are the ones `dump` logs.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller else { return }
        for url in urls where url.scheme == "tuck" {
            let command = url.host() ?? ""
            let argument = url.pathComponents.dropFirst().first ?? ""
            let windowID = CGWindowID(argument) ?? 0
            Log.info("url: \(url.absoluteString)")
            switch command {
            case "bar": dot?.toggleBar()
            case "notch": dot?.showFromNotch()
            case "peek": dot?.peek()
            case "snapshot":
                let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Tuck-bar.png")
                Log.info("snapshot: \(dot?.bar.snapshot(to: url) == true ? url.path : "nothing open")")
            case "mode":
                // tuck://mode/<window>/<show|auto|hide>
                let parts = url.pathComponents.dropFirst()
                guard let raw = parts.dropFirst().first, let mode = ItemStore.Mode(rawValue: raw),
                      let item = controller.scanner.scan().item(windowID), let key = item.key else { break }
                let wasHidden = item.placement == .hidden
                store.setMode(mode, for: key)
                controller.enqueue { [store] in
                    if mode == .hide && !wasHidden { await controller.hide(windowID) }
                    if mode != .hide && wasHidden { await controller.place(windowID, rank: store.rank(key), ranks: store.rank) }
                }
                autoTucker?.schedule(after: .seconds(1), enforceModes: true)
            case "trigger":
                // tuck://trigger/<window>/<none|battery|below-<n>|focus|appearance|app-<bundle id>>
                guard let raw = url.pathComponents.dropFirst(2).first,
                      let key = controller.scanner.scan().item(windowID)?.key else { break }
                let trigger: Trigger? = switch raw {
                case "battery": .onBattery
                case "focus": .focus
                case "appearance": .appearanceChanges
                case let value where value.hasPrefix("below-"): Int(value.dropFirst(6)).map { .batteryBelow(percent: $0) }
                case let value where value.hasPrefix("app-"): .appFrontmost(bundleID: String(value.dropFirst(4)))
                default: nil
                }
                store.setTrigger(trigger, for: key)
                triggers?.check()
            case "resetdot": controller.controls.resetDotPosition()
            case "health":
                controller.enqueue {
                    let report = await HealthCheck.run(controller)
                    controller.controls.setWarning(!report.passed)
                }
            case "state": Log.info("state: \(controller.debugState)")
            case "settings": settingsWindow?.show()
            case "dump": dump(controller.scanner.scan(), controller: controller)
            case "axdump": axDump()
            case "ax":
                // tuck://ax/<window>: every attribute of one item's Accessibility element
                guard let element = controller.scanner.scan().item(windowID)?.owner?.element else { break }
                var names: CFArray?
                AXUIElementCopyAttributeNames(element, &names)
                let lines = ((names as? [String]) ?? []).map { "  \($0) = \(AX.attribute(element, $0).map { "\($0)" } ?? "nil")" }
                Log.info("ax \(windowID):\n" + lines.joined(separator: "\n"))
            case "hide": controller.enqueue { await controller.hide(windowID) }
            case "show": controller.enqueue { await controller.show(windowID) }
            case "open":
                let query = url.query() ?? ""
                let spot: TuckController.OpenSpot = query.contains("at=notch") ? .notch : .dot
                let click: ItemStrip.Click = query.contains("click=secondary") ? .secondary
                    : query.contains("click=alternate") ? .alternate : .primary
                controller.enqueue { await controller.open(windowID, at: spot, click: click) }
            case "move":
                // tuck://move/<window>?leftOf=<window> or ?rightOf=<window>
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let left = query.first { $0.name == "leftOf" }?.value.flatMap { CGWindowID($0) }
                let right = query.first { $0.name == "rightOf" }?.value.flatMap { CGWindowID($0) }
                if let left {
                    controller.enqueue { await controller.relocate(windowID, to: .leftOf(left)) }
                } else if let right {
                    controller.enqueue { await controller.relocate(windowID, to: .rightOf(right)) }
                }
            case "click": controller.enqueue { _ = await controller.mover.click(windowID) }
            case "press":
                if let element = controller.scanner.scan().item(windowID)?.owner?.element {
                    Log.info("AXPress \(windowID): \(AX.press(element))")
                }
            case "route":
                if let route = ItemMover.Route(rawValue: argument) { controller.mover.route = route }
            case "separator":
                switch argument {
                case "idle": controller.controls.apply(.idle)
                case "collapsed": controller.controls.apply(.collapsed)
                case "expanded": controller.controls.apply(.expanded)
                default: break
                }
            default: Log.error("unknown command \(command)")
            }
        }
    }

    private func axDump() {
        var lines = ["--- axdump"]
        for app in NSWorkspace.shared.runningApplications {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.15)
            var names: CFArray?
            AXUIElementCopyAttributeNames(element, &names)
            let attributes = (names as? [String]) ?? []
            guard let bar = AX.attribute(element, "AXExtrasMenuBar") else {
                if attributes.contains("AXExtrasMenuBar") { lines.append("\(app.localizedName ?? "?") lists AXExtrasMenuBar but read failed") }
                continue
            }
            let children = AX.children(bar as! AXUIElement)
            lines.append("\(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "-")] pid \(app.processIdentifier): \(children.count) children")
            for child in children {
                lines.append("   frame \(AX.frame(child) ?? .null) role \(AX.string(child, kAXRoleAttribute) ?? "-") title “\(AX.string(child, kAXTitleAttribute) ?? "")” desc “\(AX.string(child, kAXDescriptionAttribute) ?? "")” id \(AX.string(child, "AXIdentifier") ?? "-")")
            }
        }
        Log.info(lines.joined(separator: "\n"))
    }

    private func dump(_ snapshot: ItemScanner.Snapshot, controller: TuckController) {
        var lines = ["--- dump: separator \(controller.controls.separatorState)"]
        if let screen = NSScreen.screens.first {
            lines.append("screen \(screen.frame) notch \(screen.auxiliaryTopLeftArea?.maxX ?? 0)…\(screen.auxiliaryTopRightArea?.minX ?? 0)")
        }
        lines.append("dot \(snapshot.dot.map { "\($0.windowID) \($0.frame)" } ?? "missing")")
        lines.append("separator \(snapshot.separator.map { "\($0.windowID) \($0.frame)" } ?? "missing")")
        for item in snapshot.items {
            let owner = item.owner.map { "\($0.appName) [\($0.bundleID ?? "-")] “\($0.detail ?? "")”" } ?? "UNRESOLVED"
            lines.append("\(item.windowID) x=\(Int(item.frame.minX)) w=\(Int(item.frame.width)) on=\(item.isOnScreen) \(item.placement) host=\(item.hostPID) \(owner)")
        }
        Log.info(lines.joined(separator: "\n"))
    }
}
