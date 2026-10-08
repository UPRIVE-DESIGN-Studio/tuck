import AppKit
import SwiftUI

/// Owns one NSWindow showing a SwiftUI view. Re-shows the existing window if already open.
///
/// Deliberately not generic over the view: Swift 6.2.4's optimizer crashes on the deinit of a
/// generic main-actor class in Release builds.
final class WindowHost {
    private let title: String
    private let makeController: () -> NSViewController
    private var window: NSWindow?

    init<Content: View>(title: String, content: @escaping () -> Content) {
        self.title = title
        self.makeController = {
            let controller = NSHostingController(rootView: content())
            controller.sizingOptions = [.preferredContentSize]
            return controller
        }
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: makeController())
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }
}
