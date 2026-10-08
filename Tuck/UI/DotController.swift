import AppKit
import KeyboardShortcuts

/// Opens the bar of tucked items: left click on the dot, hovering the notch, or the hotkey.
/// Right click (or ⌃-click) on the dot shows a small menu with Settings and Quit.
final class DotController: NSObject {
    private let controller: TuckController
    private let images = ItemImages()
    let bar = SecondBar()
    private let notchSensor = NotchSensor()
    private let showSettings: () -> Void
    private let showOnboarding: () -> Void
    /// Tucked items in the order the bar shows them, for drag-to-reorder.
    private var shownOrder: [CGWindowID] = []
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
        bar.onSettings = showSettings
        bar.onOpen = { [controller] windowID, click, fromNotch in
            controller.enqueue {
                // Let the bar close before something else in the menu bar is pressed.
                try? await Task.sleep(for: .milliseconds(fromNotch ? 200 : 120))
                await controller.open(windowID, at: fromNotch ? .notch : .dot, click: click)
            }
        }
        bar.onReorder = { [weak self, controller] windowID, index in
            guard let self else { return }
            let order = self.shownOrder
            controller.enqueue {
                await controller.reorder(windowID, to: index, among: order)
                self.refreshBar()
            }
        }
        notchSensor.onHover = { [weak self] notch in self?.showFromNotch(notch) }
        notchSensor.isEnabled = Preferences.notchHover
        KeyboardShortcuts.onKeyUp(for: .openDrawer) { [weak self] in self?.hotkeyPressed() }
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
        if bar.isVisible { bar.close() } else { showUnderDot() }
    }

    /// `tuck://bar`: same as a left click on the dot.
    func toggleBar() {
        if bar.isVisible { bar.close() } else { showUnderDot() }
    }

    /// `tuck://notch`: same as hovering the notch.
    func showFromNotch() {
        guard let notch = NSScreen.screens.lazy.compactMap(NotchSensor.notchRect).first else { return }
        showFromNotch(notch)
    }

    func setNotchHover(_ enabled: Bool) {
        notchSensor.isEnabled = enabled
    }

    private func hotkeyPressed() {
        guard Permissions.isTrusted else { return showOnboarding() }
        if bar.isVisible { return bar.close("hotkey") }
        if controller.menuBarHasNotch, let notch = notchOfMenuBarScreen() {
            show(style: .notch(notch), byKeyboard: true)
        } else {
            showUnderDot(byKeyboard: true)
        }
    }

    private func notchOfMenuBarScreen() -> CGRect? {
        let screen = controller.controls.dot.button?.window?.screen
        return screen.flatMap(NotchSensor.notchRect) ?? NSScreen.screens.lazy.compactMap(NotchSensor.notchRect).first
    }

    private func showFromNotch(_ notch: CGRect) {
        guard Permissions.isTrusted, !bar.isNotchDrawer else { return }
        bar.close()
        show(style: .notch(notch))
    }

    private func showUnderDot(byKeyboard: Bool = false) {
        guard let anchor = controller.controls.dot.button?.window?.frame else { return }
        show(style: .dropdown(anchor: anchor), byKeyboard: byKeyboard)
    }

    private func show(style: SecondBar.Style, byKeyboard: Bool = false) {
        let (tucked, all) = entries(captures: images.cache)
        bar.show(tucked: tucked, all: all, style: style, byKeyboard: byKeyboard)
        refreshCaptures()
    }

    /// Rebuilds the bar's contents after the menu bar changed under it.
    private func refreshBar() {
        let (tucked, all) = entries(captures: images.cache)
        bar.update(tucked: tucked, all: all)
    }

    private func refreshCaptures() {
        guard ItemImages.isAllowed else { return }
        let items = controller.scanner.scan(resolveOwners: false).items
        Task {
            _ = await images.refresh(items)
            refreshBar()
        }
    }

    /// The tucked items (left to right) and every item, as bar entries.
    private func entries(captures: [CGWindowID: NSImage]) -> (tucked: [SecondBar.Entry], all: [SecondBar.Entry]) {
        let snapshot = controller.scanner.scan()
        let titles = ItemLabel.titles(for: snapshot.items)
        func entry(_ item: MenuBarItem) -> SecondBar.Entry {
            if let capture = captures[item.windowID] {
                return SecondBar.Entry(windowID: item.windowID, title: titles[item.windowID] ?? "", image: capture, isCapture: true)
            }
            let icon = item.icon?.copy() as? NSImage
            icon?.size = NSSize(width: 20, height: 20)
            return SecondBar.Entry(windowID: item.windowID, title: titles[item.windowID] ?? "", image: icon, isCapture: false)
        }
        let tucked = snapshot.tucked
        shownOrder = tucked.map(\.windowID)
        return (tucked.map(entry), snapshot.items.map(entry))
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
