import AppKit
import Observation
import ServiceManagement

/// State behind the Settings window. Changes to items are applied right away, one at a time.
@Observable
final class SettingsModel {
    struct Row: Identifiable {
        let key: ItemKey
        let windowID: CGWindowID
        let title: String
        let icon: NSImage?
        let placement: Placement
        let isOnScreen: Bool
        let mode: ItemStore.Mode
        let isAutoTucked: Bool
        let trigger: Trigger?

        var id: ItemKey { key }
    }

    private(set) var rows: [Row] = []
    /// Items whose move is queued or running.
    private(set) var pending: Set<ItemKey> = []
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?
    private(set) var accessibilityGranted = Permissions.isTrusted
    private(set) var screenRecordingGranted = ItemImages.isAllowed
    /// Whether this Mac has a notched screen right now, so notch options are worth showing.
    private(set) var hasNotch = false

    private(set) var notchHover = Preferences.notchHover
    private(set) var autoTuck = Preferences.autoTuck
    private(set) var revealOnPlainDisplays = Preferences.revealOnPlainDisplays
    private(set) var showCount = Preferences.showCount
    private(set) var windowZones = Preferences.windowZones

    private(set) var health: HealthCheck.Report?
    private(set) var isCheckingHealth = false

    @ObservationIgnored let controller: TuckController
    @ObservationIgnored let store: ItemStore
    @ObservationIgnored var onNotchHoverChange: (Bool) -> Void = { _ in }
    /// Something changed that the auto-tucker, separator or dot should react to.
    @ObservationIgnored var onLayoutPreferenceChange: () -> Void = {}

    init(controller: TuckController, store: ItemStore) {
        self.controller = controller
        self.store = store
    }

    func refresh() {
        accessibilityGranted = Permissions.isTrusted
        screenRecordingGranted = ItemImages.isAllowed
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hasNotch = NSScreen.screens.contains { NotchSensor.notchRect(of: $0) != nil }
        guard accessibilityGranted else {
            rows = []
            return
        }
        let items = controller.scanner.scan().items.filter {
            $0.placement != .pinned && $0.key.map { !ItemStore.fixedItems.contains($0.rawValue) } ?? false
        }
        store.adopt(items)
        let titles = ItemLabel.titles(for: items)
        rows = items.compactMap { item -> Row? in
            guard let key = item.key else { return nil }
            return Row(
                key: key, windowID: item.windowID, title: titles[item.windowID] ?? "Unknown item",
                icon: item.icon, placement: item.placement, isOnScreen: item.isOnScreen,
                mode: store.mode(key) ?? .auto, isAutoTucked: store.isAutoTucked(key), trigger: store.trigger(key)
            )
        }
        .sorted { store.rank($0.key) < store.rank($1.key) }
    }

    // MARK: Items

    func setMode(_ mode: ItemStore.Mode, for row: Row) {
        guard !pending.contains(row.key), mode != row.mode else { return }
        let wasHidden = row.placement == .hidden
        store.setMode(mode, for: row.key)
        run(row.key) { [store] controller in
            switch mode {
            case .hide where !wasHidden:
                await controller.hide(row.windowID)
            case .show where wasHidden, .auto where wasHidden:
                await controller.place(row.windowID, rank: store.rank(row.key), ranks: store.rank)
            default:
                break
            }
        }
    }

    /// Drag to reorder: the list is the priority order, and the menu bar follows it.
    func move(from source: IndexSet, to destination: Int) {
        var keys = rows.map(\.key)
        keys.move(fromOffsets: source, toOffset: destination)
        store.setOrder(keys)
        rows.move(fromOffsets: source, toOffset: destination)
        controller.enqueue { [weak self, controller] in
            await controller.arrange(keys)
            self?.refresh()
            self?.onLayoutPreferenceChange()
        }
    }

    func setTrigger(_ trigger: Trigger?, for row: Row) {
        store.setTrigger(trigger, for: row.key)
        refresh()
        onLayoutPreferenceChange()
    }

    private func run(_ key: ItemKey, _ work: @escaping (TuckController) async -> Void) {
        pending.insert(key)
        controller.enqueue { [weak self, controller] in
            await work(controller)
            self?.pending.remove(key)
            self?.refresh()
            self?.onLayoutPreferenceChange()
        }
    }

    // MARK: Preferences

    func setAutoTuck(_ enabled: Bool) {
        Preferences.autoTuck = enabled
        autoTuck = enabled
        onLayoutPreferenceChange()
    }

    func setRevealOnPlainDisplays(_ enabled: Bool) {
        Preferences.revealOnPlainDisplays = enabled
        revealOnPlainDisplays = enabled
        onLayoutPreferenceChange()
    }

    func setShowCount(_ enabled: Bool) {
        Preferences.showCount = enabled
        showCount = enabled
        onLayoutPreferenceChange()
    }

    func setNotchHover(_ enabled: Bool) {
        Preferences.notchHover = enabled
        notchHover = enabled
        onNotchHoverChange(enabled)
    }

    func setWindowZones(_ enabled: Bool) {
        Preferences.windowZones = enabled
        windowZones = enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Backup & health

    func exportSettings() {
        Backup.export(store)
    }

    func importSettings() {
        guard Backup.importFile(into: store) else { return }
        notchHover = Preferences.notchHover
        autoTuck = Preferences.autoTuck
        revealOnPlainDisplays = Preferences.revealOnPlainDisplays
        showCount = Preferences.showCount
        windowZones = Preferences.windowZones
        onNotchHoverChange(notchHover)
        refresh()
        onLayoutPreferenceChange()
    }

    func runHealthCheck() {
        guard !isCheckingHealth else { return }
        isCheckingHealth = true
        controller.enqueue { [weak self, controller] in
            let report = await HealthCheck.run(controller)
            self?.setHealth(report)
            self?.isCheckingHealth = false
        }
    }

    func setHealth(_ report: HealthCheck.Report) {
        health = report
        controller.controls.setWarning(!report.passed)
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }
}
