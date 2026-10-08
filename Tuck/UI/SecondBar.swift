import AppKit

/// The bar of tucked items: one button per item and a gear at the right end. It comes in two
/// looks. Under the dot it is a glass dropdown; from the notch it is a black drawer that grows
/// out of the notch itself. Either way it floats without activating Tuck and closes on Esc or a
/// click outside. The notch drawer also closes once the pointer has left it.
final class SecondBar: NSObject {
    typealias Entry = ItemStrip.Item

    enum Style {
        /// Glass dropdown, right-aligned under the dot. Cocoa screen coordinates.
        case dropdown(anchor: CGRect)
        /// Black drawer growing out of the notch. Cocoa screen coordinates of the notch.
        case notch(CGRect)
    }

    /// Called with the item, how it was clicked, and whether it was clicked in the notch drawer.
    var onOpen: (CGWindowID, ItemStrip.Click, _ fromNotch: Bool) -> Void = { _, _, _ in }
    /// Called with the item and its new index among the tucked items.
    var onReorder: (CGWindowID, Int) -> Void = { _, _ in }
    var onSettings: () -> Void = {}
    /// Builds the shelf shown under the items (now playing, timer, files), or nil for none.
    var makeShelf: (_ onDark: Bool) -> NSView? = { _ in nil }
    /// The bar opened (true) or started closing (false).
    var onVisibilityChange: (Bool) -> Void = { _ in }

    /// The dot's window: clicks there toggle the bar themselves, so the outside-click monitor ignores them.
    weak var dotWindow: NSWindow?

    private var panel: BarPanel?
    private var style: Style?
    private var monitors: [Any] = []
    private var hoverWatch: Task<Void, Never>?
    private var isClosing = false

    /// What the bar shows: the tucked items, or with a search query, matches among all items.
    private var tucked: [Entry] = []
    private var all: [Entry] = []
    private var query = ""
    private var selected: Int?
    private let strip = ItemStrip()
    private let queryLabel = NSTextField(labelWithString: "")

    var isVisible: Bool { (panel?.isVisible ?? false) && !isClosing }
    var isNotchDrawer: Bool {
        if isVisible, case .notch = style { return true }
        return false
    }

    override init() {
        super.init()
        strip.onClick = { [weak self] windowID, click in self?.open(windowID, click) }
        strip.onReorder = { [weak self] windowID, index in self?.onReorder(windowID, index) }
        queryLabel.font = .systemFont(ofSize: 13, weight: .medium)
    }

    /// - Parameter byKeyboard: opened with the hotkey: the first item is selected and the drawer
    ///   stays open until Esc, a click outside, or the hotkey again, wherever the pointer is.
    /// - Parameter peek: open without the pointer there, e.g. when a timer ends; the drawer stays
    ///   this long before closing unless the pointer comes over.
    func show(tucked: [Entry], all: [Entry], style: Style, byKeyboard: Bool = false, peek: Duration? = nil) {
        self.tucked = tucked
        self.all = all
        query = ""
        selected = byKeyboard && !tucked.isEmpty ? 0 : nil

        let panel = panel ?? makePanel()
        self.panel = panel
        // A drawer that is still closing counts as gone: opening again replays the animation.
        let wasVisible = panel.isVisible && !isClosing
        isClosing = false
        self.style = style
        render(animated: !wasVisible)
        if case .notch(let notch) = style, !byKeyboard {
            watchHover(notch: notch, after: peek ?? .zero)
        } else {
            hoverWatch?.cancel()
            hoverWatch = nil
        }
        if !wasVisible {
            installMonitors()
            onVisibilityChange(true)
        }
    }

    /// Swaps in new pictures or a new order, keeping the query and selection.
    func update(tucked: [Entry], all: [Entry]) {
        guard isVisible else { return }
        self.tucked = tucked
        self.all = all
        render(animated: false)
    }

    func close(_ reason: String = "") {
        hoverWatch?.cancel()
        hoverWatch = nil
        removeMonitors()
        guard let panel, panel.isVisible, !isClosing else { return }
        if !reason.isEmpty { Log.info("bar closed: \(reason)") }
        onVisibilityChange(false)
        if case .notch = style, let drawer = panel.contentView as? NotchDrawerView {
            isClosing = true
            drawer.animateClose { [weak self] in
                // A hover may have reopened the drawer while it was closing.
                guard let self, self.isClosing else { return }
                self.isClosing = false
                panel.orderOut(nil)
            }
        } else {
            panel.orderOut(nil)
        }
    }

    /// `tuck://snapshot`: renders the open bar to a PNG, for checking the layout without
    /// Screen Recording.
    func snapshot(to url: URL) -> Bool {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    // MARK: Rendering

    private var shown: [Entry] {
        guard !query.isEmpty else { return tucked }
        return all.filter { $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private func render(animated: Bool) {
        guard let panel, let style else { return }
        let entries = shown
        if let index = selected { selected = entries.isEmpty ? nil : min(index, entries.count - 1) }

        switch style {
        case .dropdown(let anchor):
            let glass = NSGlassEffectView()
            glass.cornerRadius = 14
            glass.contentView = content(entries, onDark: false)
            panel.contentView = glass
            panel.hasShadow = true
            panel.setFrame(dropdownFrame(size: glass.fittingSize, anchor: anchor), display: true)
            if animated { fadeIn(panel) }

        case .notch(let notch):
            let drawer = NotchDrawerView(notch: notch.size, content: content(entries, onDark: true))
            panel.contentView = drawer
            panel.hasShadow = false
            panel.alphaValue = 1
            panel.setFrame(notchFrame(size: drawer.fittingSize, notch: notch), display: true)
            if animated {
                panel.makeKeyAndOrderFront(nil)
                drawer.animateOpen()
            } else {
                drawer.showOpen()
            }
        }
    }

    private func content(_ entries: [Entry], onDark: Bool) -> NSView {
        strip.removeFromSuperview()
        strip.tint = onDark ? .white : .labelColor
        strip.items = entries
        strip.selectedIndex = selected
        strip.canReorder = query.isEmpty

        var views: [NSView] = []
        if !query.isEmpty {
            queryLabel.stringValue = "⌕ \(query)"
            queryLabel.textColor = onDark ? .white : .labelColor
            views.append(queryLabel)
        }
        if entries.isEmpty {
            let label = NSTextField(labelWithString: query.isEmpty ? "Nothing tucked away" : "No match")
            label.textColor = onDark ? NSColor.white.withAlphaComponent(0.6) : .secondaryLabelColor
            label.font = .systemFont(ofSize: 12)
            views.append(label)
        } else {
            views.append(strip)
        }

        let divider = NSBox()
        divider.boxType = .custom
        divider.borderWidth = 0
        divider.fillColor = onDark ? NSColor.white.withAlphaComponent(0.2) : .separatorColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 18),
        ])
        views.append(divider)

        let gear = NSButton(
            image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Tuck Settings")!,
            target: self, action: #selector(openSettings)
        )
        gear.isBordered = false
        gear.contentTintColor = onDark ? NSColor.white.withAlphaComponent(0.7) : .secondaryLabelColor
        gear.toolTip = "Tuck Settings"
        gear.translatesAutoresizingMaskIntoConstraints = false
        gear.widthAnchor.constraint(equalToConstant: 26).isActive = true
        views.append(gear)

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.setCustomSpacing(8, after: views[views.count - 3])
        row.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let column = NSStackView(views: [row])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 6
        column.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 2, right: 8)
        if query.isEmpty, let shelf = makeShelf(onDark) {
            column.addArrangedSubview(shelf)
        }
        return column
    }

    // MARK: Keyboard

    /// Arrows move the selection, Return opens it (⌥Return as ⌥-click), Esc closes, typing searches.
    fileprivate func handleKey(_ event: NSEvent) -> Bool {
        let entries = shown
        switch event.keyCode {
        case 53: // Esc: clear the search first, then close
            if query.isEmpty { close("escape") } else { query = ""; render(animated: false) }
        case 123: // ←
            selected = max(0, (selected ?? entries.count) - 1)
            strip.selectedIndex = selected
        case 124: // →
            selected = min(entries.count - 1, (selected ?? -1) + 1)
            strip.selectedIndex = selected
        case 36, 76: // Return, Enter
            guard let index = selected ?? (entries.isEmpty ? nil : 0), entries.indices.contains(index) else { return true }
            open(entries[index].windowID, event.modifierFlags.contains(.option) ? .alternate : .primary)
        case 51: // Delete
            guard !query.isEmpty else { return true }
            query.removeLast()
            selected = query.isEmpty ? nil : 0
            render(animated: false)
        default:
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty,
                  event.modifierFlags.isDisjoint(with: [.command, .control]),
                  characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.whitespaces).contains($0) })
            else { return false }
            query += characters
            selected = 0
            render(animated: false)
        }
        return true
    }

    // MARK: Actions

    private func open(_ windowID: CGWindowID, _ click: ItemStrip.Click) {
        let fromNotch = isNotchDrawer
        close()
        onOpen(windowID, click, fromNotch)
    }

    @objc private func openSettings() {
        close()
        onSettings()
    }

    // MARK: Geometry & animation

    private func dropdownFrame(size: CGSize, anchor: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? anchor
        var origin = CGPoint(x: anchor.maxX + 6 - size.width, y: anchor.minY - 6 - size.height)
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - 8 - size.width)
        return CGRect(origin: origin, size: size)
    }

    /// Centred on the notch, top edge flush with the top of the screen.
    private func notchFrame(size: CGSize, notch: CGRect) -> CGRect {
        CGRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height, width: size.width, height: size.height)
    }

    private func fadeIn(_ panel: NSPanel) {
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    /// Closes the notch drawer once the pointer has been outside both the drawer and the notch
    /// for a moment, so slipping off the edge briefly does not snap it shut.
    private func watchHover(notch: CGRect, after delay: Duration = .zero) {
        hoverWatch?.cancel()
        hoverWatch = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            var outsideSince: ContinuousClock.Instant?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, let panel = self.panel else { return }
                let pointer = NSEvent.mouseLocation
                let inside = panel.frame.insetBy(dx: -6, dy: -6).contains(pointer)
                    || notch.insetBy(dx: -2, dy: -2).contains(pointer)
                if inside {
                    outsideSince = nil
                } else if let since = outsideSince {
                    if ContinuousClock.now - since > .milliseconds(350) {
                        self.close("pointer left the notch")
                        return
                    }
                } else {
                    outsideSince = .now
                }
            }
        }
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
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        return panel
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

/// Fully black and shaped like the notch grown taller and wider: flush with the top of the
/// screen, flaring into it with small concave corners, rounded at the bottom. It opens by
/// morphing out of the exact notch outline, so it looks like the notch itself peels down.
private final class NotchDrawerView: NSView {
    /// The concave fillets where the drawer meets the top edge of the screen.
    private static let ear: CGFloat = 8
    private static let bottomRadius: CGFloat = 20
    /// The hardware notch's own bottom corner radius, roughly.
    private static let notchRadius: CGFloat = 9

    private let notch: CGSize
    private let row: NSView
    private let shape = CAShapeLayer()

    init(notch: CGSize, content row: NSView) {
        self.notch = notch
        self.row = row
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.mask = shape

        row.wantsLayer = true
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: notch.height + 2),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            widthAnchor.constraint(greaterThanOrEqualTo: row.widthAnchor, constant: 2 * Self.ear + 28),
            widthAnchor.constraint(greaterThanOrEqualToConstant: notch.width + 2 * Self.ear + 36),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        shape.frame = bounds
        if shape.animationKeys() == nil {
            shape.path = isOpen ? openPath : notchPath
        }
    }

    private var isOpen = true

    func showOpen() {
        isOpen = true
        shape.removeAllAnimations()
        shape.path = openPath
        row.layer?.opacity = 1
    }

    func animateOpen() {
        layoutSubtreeIfNeeded()
        isOpen = true
        let spring = CASpringAnimation(keyPath: "path")
        spring.fromValue = notchPath
        spring.toValue = openPath
        spring.mass = 1
        spring.stiffness = 260
        spring.damping = 24
        spring.duration = spring.settlingDuration
        shape.path = openPath
        shape.add(spring, forKey: "open")

        // The row rides down with the bottom edge and fades in as it clears the notch.
        guard let rowLayer = row.layer else { return }
        let slide = CASpringAnimation(keyPath: "transform.translation.y")
        slide.fromValue = notch.height
        slide.toValue = 0
        slide.mass = 1
        slide.stiffness = 260
        slide.damping = 24
        slide.duration = slide.settlingDuration
        rowLayer.add(slide, forKey: "slide")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.beginTime = CACurrentMediaTime() + 0.05
        fade.duration = 0.18
        fade.fillMode = .backwards
        rowLayer.opacity = 1
        rowLayer.add(fade, forKey: "fade")
    }

    func animateClose(completion: @escaping @MainActor () -> Void) {
        isOpen = false
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        let shrink = CABasicAnimation(keyPath: "path")
        shrink.fromValue = shape.presentation()?.path ?? openPath
        shrink.toValue = notchPath
        shrink.duration = 0.2
        shrink.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.9, 0.6)
        shape.path = notchPath
        shape.add(shrink, forKey: "close")

        if let rowLayer = row.layer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = rowLayer.presentation()?.opacity ?? 1
            fade.toValue = 0
            fade.duration = 0.1
            rowLayer.opacity = 0
            rowLayer.add(fade, forKey: "fade")
        }
        CATransaction.commit()
    }

    // MARK: Shapes

    private var openPath: CGPath {
        Self.path(width: bounds.width - 2 * Self.ear, height: bounds.height, ear: Self.ear,
                  radius: Self.bottomRadius, in: bounds)
    }

    private var notchPath: CGPath {
        Self.path(width: notch.width, height: notch.height, ear: 0, radius: Self.notchRadius, in: bounds)
    }

    /// Both shapes use the same sequence of path elements, so Core Animation can morph one into
    /// the other point by point. Layer coordinates: origin bottom-left.
    private static func path(width: CGFloat, height: CGFloat, ear: CGFloat, radius: CGFloat, in bounds: CGRect) -> CGPath {
        let left = bounds.midX - width / 2
        let right = bounds.midX + width / 2
        let top = bounds.maxY
        let bottom = top - height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left - ear, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top - ear), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom + radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom + radius), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: top - ear))
        path.addQuadCurve(to: CGPoint(x: right + ear, y: top), control: CGPoint(x: right, y: top))
        path.closeSubpath()
        return path
    }
}

/// Takes key status without activating Tuck, so the keyboard reaches it.
private final class BarPanel: NSPanel {
    var onKey: (NSEvent) -> Bool = { _ in false }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !onKey(event) { super.keyDown(with: event) }
    }
}
