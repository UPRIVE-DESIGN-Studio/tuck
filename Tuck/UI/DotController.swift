import AppKit

/// Handles clicks on the dot. Left click toggles the bar of tucked items; right click (or
/// ⌃-click) shows a small menu with Settings and Quit.
final class DotController: NSObject {
    private let controller: TuckController
    private let images = ItemImages()
    private let bar = SecondBar()
    private let notchSensor = NotchSensor()
    private let showSettings: () -> Void
    private let showOnboarding: () -> Void
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(item("Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Tuck", action: #selector(quit), key: "q"))
        return menu
    }()

    init(controller: TuckController, showSettings: @escaping () -> Void, showOnboarding: @escaping () -> Void) {
        self.controller = controller
        self.showSettings = showSettings
        self.showOnboarding = showOnboarding
        super.init()

        let button = controller.controls.dot.button
        button?.target = self
        button?.action = #selector(dotClicked)
        button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        bar.dotWindow = button?.window
        notchSensor.onHover = { [weak self] notch in self?.showFromNotch(notch) }
        notchSensor.isEnabled = Preferences.notchHover
        bar.onSettings = showSettings
        bar.onOpen = { [controller] windowID, fromNotch in
            controller.enqueue {
                // Let the bar close before something else in the menu bar is pressed.
                try? await Task.sleep(for: .milliseconds(fromNotch ? 200 : 120))
                await controller.open(windowID, at: fromNotch ? .notch : .dot)
            }
        }
    }

    @objc private func dotClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            bar.close()
            showContextMenu()
            return
        }
        guard Permissions.isTrusted else {
            showOnboarding()
            return
        }
        if bar.isVisible {
            bar.close()
        } else {
            showBar()
        }
    }

    /// `tuck://bar`: same as a left click on the dot.
    func toggleBar() {
        if bar.isVisible { bar.close() } else { showBar() }
    }

    /// `tuck://notch`: same as hovering the notch.
    func showFromNotch() {
        guard let notch = NSScreen.screens.lazy.compactMap(NotchSensor.notchRect).first else { return }
        showFromNotch(notch)
    }

    func setNotchHover(_ enabled: Bool) {
        notchSensor.isEnabled = enabled
    }

    private func showFromNotch(_ notch: CGRect) {
        guard Permissions.isTrusted, !bar.isNotchDrawer else { return }
        bar.close()
        showBar(style: .notch(notch))
    }

    private func showBar() {
        guard let anchor = controller.controls.dot.button?.window?.frame else { return }
        showBar(style: .dropdown(anchor: anchor))
    }

    private func showBar(style: SecondBar.Style) {
        let tucked = controller.scanner.scan().tucked
        let titles = ItemLabel.titles(for: tucked)
        bar.show(entries(tucked, titles: titles, captures: images.cache), style: style)

        guard ItemImages.isAllowed, !tucked.isEmpty else { return }
        Task {
            let captures = await images.refresh(tucked)
            bar.update(entries(tucked, titles: titles, captures: captures))
        }
    }

    private func entries(
        _ items: [MenuBarItem], titles: [CGWindowID: String], captures: [CGWindowID: NSImage]
    ) -> [SecondBar.Entry] {
        items.map { item in
            if let capture = captures[item.windowID] {
                return SecondBar.Entry(windowID: item.windowID, title: titles[item.windowID] ?? "", image: capture, isCapture: true)
            }
            let icon = item.icon?.copy() as? NSImage
            icon?.size = NSSize(width: 20, height: 20)
            return SecondBar.Entry(windowID: item.windowID, title: titles[item.windowID] ?? "", image: icon, isCapture: false)
        }
    }

    /// Shows the menu once, then detaches it so the next left click goes back to `dotClicked`.
    private func showContextMenu() {
        let dot = controller.controls.dot
        dot.menu = contextMenu
        dot.button?.performClick(nil)
        dot.menu = nil
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
