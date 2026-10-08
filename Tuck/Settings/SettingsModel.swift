import AppKit
import Observation
import ServiceManagement

/// State behind the Settings window. Visibility changes are applied right away, one at a time.
@Observable
final class SettingsModel {
    struct Row: Identifiable {
        let id: CGWindowID
        let title: String
        let icon: NSImage?
        let placement: Placement
    }

    private(set) var rows: [Row] = []
    /// Items whose move is queued or running.
    private(set) var pending: Set<CGWindowID> = []
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?
    private(set) var accessibilityGranted = Permissions.isTrusted
    private(set) var screenRecordingGranted = ItemImages.isAllowed

    private(set) var notchHover = Preferences.notchHover
    /// Whether this Mac has a notched screen right now, so the notch option is worth showing.
    private(set) var hasNotch = false

    @ObservationIgnored private let controller: TuckController
    @ObservationIgnored var onNotchHoverChange: (Bool) -> Void = { _ in }

    init(controller: TuckController) {
        self.controller = controller
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
        let items = controller.scanner.scan().items.filter { $0.placement != .pinned }
        let titles = ItemLabel.titles(for: items)
        rows = items.map { Row(id: $0.windowID, title: titles[$0.windowID] ?? "Unknown item", icon: $0.icon, placement: $0.placement) }
    }

    func setHidden(_ hidden: Bool, for id: CGWindowID) {
        guard !pending.contains(id) else { return }
        pending.insert(id)
        controller.enqueue { [weak self, controller] in
            if hidden {
                await controller.hide(id)
            } else {
                await controller.show(id)
            }
            self?.pending.remove(id)
            self?.refresh()
        }
    }

    func setNotchHover(_ enabled: Bool) {
        Preferences.notchHover = enabled
        notchHover = enabled
        onNotchHoverChange(enabled)
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

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }
}
