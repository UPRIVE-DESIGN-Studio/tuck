import AppKit

/// Handles clicks on the dot. Left click toggles the bar of tucked items; right click (or
/// ⌃-click) shows a small menu with Settings and Quit.
final class DotController: NSObject {
    private let controller: TuckController
    private let images = ItemImages()
    private let bar = SecondBar()
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
        bar.onSettings = showSettings
        bar.onOpen = { [controller] windowID in
            controller.enqueue {
                // Let the bar fade before something else in the menu bar is pressed.
                try? await Task.sleep(for: .milliseconds(120))
                await controller.open(windowID)
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

    private func showBar() {
        guard let anchor = controller.controls.dot.button?.window?.frame else { return }
        let tucked = controller.scanner.scan().tucked
        let titles = ItemLabel.titles(for: tucked)
        bar.show(entries(tucked, titles: titles, captures: images.cache), under: anchor)

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
