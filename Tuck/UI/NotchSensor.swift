import AppKit

/// An invisible window exactly behind the notch on each notched screen. The pointer can move
/// there even though no pixels exist, so hovering it for a moment opens the drawer. Being behind
/// the notch, the window can never be seen and covers nothing clickable.
final class NotchSensor {
    var onHover: (_ notch: CGRect) -> Void = { _ in }

    /// How long the pointer must rest in the notch, so sweeping across the menu bar does not trigger it.
    private let dwell: Duration = .milliseconds(200)
    private var windows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            rebuild()
        }
    }

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    /// The notch in Cocoa screen coordinates: the gap between the two usable top areas.
    static func notchRect(of screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX
        else { return nil }
        let height = screen.safeAreaInsets.top
        return CGRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
    }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard isEnabled else { return }
        for screen in NSScreen.screens {
            guard let notch = Self.notchRect(of: screen) else { continue }
            windows.append(makeWindow(covering: notch))
        }
        Log.info("notch sensor: \(windows.count) notch(es)")
    }

    private func makeWindow(covering notch: CGRect) -> NSWindow {
        let window = NSPanel(contentRect: notch, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.isOpaque = false
        // Not fully clear: the window server lets the pointer pass through fully transparent windows.
        window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = SensorView(frame: CGRect(origin: .zero, size: notch.size))
        view.onEnter = { [weak self] in self?.pointerEntered(notch) }
        window.contentView = view
        window.orderFrontRegardless()
        return window
    }

    private var pending: Task<Void, Never>?

    private func pointerEntered(_ notch: CGRect) {
        pending?.cancel()
        pending = Task { [weak self, dwell] in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled, notch.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) else { return }
            self?.onHover(notch)
        }
    }
}

private final class SensorView: NSView {
    var onEnter: () -> Void = {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter()
    }
}
