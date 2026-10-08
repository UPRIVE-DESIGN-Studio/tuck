import AppKit

/// The extended bar that drops down under the dot: one button per tucked item, a gear at the
/// right end. It floats without activating Tuck, and closes on Esc or any click outside it.
final class SecondBar: NSObject {
    struct Entry {
        let windowID: CGWindowID
        let title: String
        let image: NSImage?
        /// True when `image` is a capture of the real item rather than its app icon.
        let isCapture: Bool
    }

    var onOpen: (CGWindowID) -> Void = { _ in }
    var onSettings: () -> Void = {}

    private var panel: BarPanel?
    private var monitors: [Any] = []
    /// The dot's window: clicks there toggle the bar themselves, so the outside-click monitor ignores them.
    weak var dotWindow: NSWindow?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// - Parameter anchor: the dot's frame in Cocoa screen coordinates.
    func show(_ entries: [Entry], under anchor: CGRect) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let glass = NSGlassEffectView()
        glass.cornerRadius = 14
        glass.contentView = makeContent(entries)
        panel.contentView = glass

        let size = glass.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? anchor
        var origin = CGPoint(x: anchor.maxX + 6 - size.width, y: anchor.minY - 6 - size.height)
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - 8 - size.width)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
            installMonitors()
        }
    }

    /// Swaps in new pictures without moving the bar, e.g. when captures arrive.
    func update(_ entries: [Entry]) {
        guard let panel, panel.isVisible, let glass = panel.contentView as? NSGlassEffectView else { return }
        let right = panel.frame.maxX
        glass.contentView = makeContent(entries)
        let size = glass.fittingSize
        panel.setFrame(CGRect(x: right - size.width, y: panel.frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    func close(_ reason: String = "") {
        if panel?.isVisible == true, !reason.isEmpty { Log.info("bar closed: \(reason)") }
        removeMonitors()
        panel?.orderOut(nil)
    }

    // MARK: Building

    private func makePanel() -> BarPanel {
        let panel = BarPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.onCancel = { [weak self] in self?.close("cancel") }
        return panel
    }

    private func makeContent(_ entries: [Entry]) -> NSView {
        var views: [NSView] = []
        if entries.isEmpty {
            let label = NSTextField(labelWithString: "Nothing tucked away")
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 12)
            views.append(label)
        }
        for entry in entries {
            views.append(itemButton(entry))
        }

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        views.append(divider)

        let gear = NSButton(
            image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Tuck Settings")!,
            target: self, action: #selector(openSettings)
        )
        gear.isBordered = false
        gear.contentTintColor = .secondaryLabelColor
        gear.toolTip = "Tuck Settings"
        gear.translatesAutoresizingMaskIntoConstraints = false
        gear.widthAnchor.constraint(equalToConstant: 26).isActive = true
        views.append(gear)

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 8)
        stack.setCustomSpacing(8, after: views[views.count - 3])
        stack.setCustomSpacing(6, after: divider)
        stack.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return stack
    }

    private func itemButton(_ entry: Entry) -> NSButton {
        let button = ItemButton(windowID: entry.windowID)
        button.image = entry.image ?? NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.toolTip = entry.title
        button.setAccessibilityLabel(entry.title)
        button.target = self
        button.action = #selector(itemClicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        let width = entry.isCapture ? (entry.image?.size.width ?? 30) : 30
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: entry.isCapture ? 26 : 20),
        ])
        return button
    }

    // MARK: Actions

    @objc private func itemClicked(_ sender: ItemButton) {
        close()
        onOpen(sender.windowID)
    }

    @objc private func openSettings() {
        close()
        onSettings()
    }

    // MARK: Dismissal

    private func installMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close("global click") }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.panel && event.window !== self.dotWindow { self.close("local click") }
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}

private final class ItemButton: NSButton {
    let windowID: CGWindowID

    init(windowID: CGWindowID) {
        self.windowID = windowID
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Takes key status without activating Tuck, so Esc reaches it.
private final class BarPanel: NSPanel {
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}
