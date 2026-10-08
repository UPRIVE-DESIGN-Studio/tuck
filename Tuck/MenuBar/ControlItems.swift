import AppKit

/// Tuck's own two status items: the dot (always visible, opens the dropdown) and the separator.
/// Everything left of the separator is the hidden section. Collapsing it stretches the separator
/// so wide that those items are pushed off the left edge of the screen.
final class ControlItems {
    enum SeparatorState {
        /// Nothing is hidden: zero width, invisible.
        case idle
        /// Hidden items are pushed off-screen.
        case collapsed
        /// Hidden items are on screen, with a thin divider marking the boundary.
        case expanded
    }

    private enum Key {
        static let dot = "TuckDot"
        static let separator = "TuckSeparator"
        static func position(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }
    }

    /// macOS caps a status item's width at about 5000 pt; anything this large pushes past every screen.
    private static let collapsedLength: CGFloat = 10_000

    let dot: NSStatusItem
    let separator: NSStatusItem
    private(set) var separatorState: SeparatorState = .idle

    init() {
        Self.seedPositions()

        dot = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dot.autosaveName = Key.dot
        dot.behavior = []
        dot.button?.image = Self.dotImage
        dot.button?.setAccessibilityLabel("Tuck")

        separator = NSStatusBar.system.statusItem(withLength: 0)
        separator.autosaveName = Key.separator
        separator.behavior = []
        separator.button?.image = Self.dividerImage
        separator.button?.imagePosition = .imageOnly
        separator.button?.setAccessibilityLabel("Tuck separator")
        apply(.idle)
    }

    /// First launch only: the dot goes right next to the Clock and Control Center, where the notch
    /// can never cover it; the separator goes to the far left, so nothing starts out hidden.
    /// After that, macOS remembers wherever the items end up.
    private static func seedPositions() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.position(Key.dot)) == nil {
            defaults.set(0, forKey: Key.position(Key.dot))
        }
        if defaults.object(forKey: Key.position(Key.separator)) == nil {
            defaults.set(10_000, forKey: Key.position(Key.separator))
        }
    }

    /// Puts the dot back next to the Clock and Control Center without dragging it: dragging
    /// Tuck's own item sends the events to Tuck itself. macOS re-reads the saved position
    /// when an item is shown again.
    func resetDotPosition() {
        UserDefaults.standard.set(0, forKey: Key.position(Key.dot))
        dot.isVisible = false
        UserDefaults.standard.set(0, forKey: Key.position(Key.dot))
        dot.isVisible = true
        Log.info("dot position reset")
    }

    func apply(_ state: SeparatorState) {
        separatorState = state
        switch state {
        case .idle:
            separator.length = 0
            separator.button?.image = nil
        case .collapsed:
            separator.length = Self.collapsedLength
            separator.button?.image = nil
        case .expanded:
            separator.length = 12
            separator.button?.image = Self.dividerImage
        }
    }

    /// Shows `count` next to the dot, or the plain dot for zero.
    func setCount(_ count: Int) {
        guard count != shownCount else { return }
        shownCount = count
        updateDotImage()
    }

    /// A failed health check shows "!" next to the dot until the next check passes.
    func setWarning(_ warning: Bool) {
        guard warning != showsWarning else { return }
        showsWarning = warning
        updateDotImage()
    }

    private var shownCount = 0
    private var showsWarning = false

    private func updateDotImage() {
        if showsWarning {
            dot.button?.image = Self.dotImage(label: "!")
        } else {
            dot.button?.image = shownCount > 0 ? Self.dotImage(label: shownCount > 99 ? "99+" : "\(shownCount)") : Self.dotImage
        }
    }

    /// Dot frame in CoreGraphics coordinates.
    var dotFrame: CGRect? { cgFrame(of: dot) }
    var separatorFrame: CGRect? { cgFrame(of: separator) }

    private func cgFrame(of item: NSStatusItem) -> CGRect? {
        guard let window = item.button?.window else { return nil }
        return Coordinates.cgRect(fromCocoa: window.frame)
    }

    // MARK: Images

    private static let dotImage: NSImage = {
        let image = NSImage(size: NSSize(width: 12, height: 16), flipped: false) { rect in
            let diameter: CGFloat = 7
            let circle = NSRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: circle).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    private static func dotImage(label: String) -> NSImage {
        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        let textSize = text.size()
        let image = NSImage(size: NSSize(width: 7 + 3 + ceil(textSize.width), height: 16), flipped: false) { rect in
            let diameter: CGFloat = 7
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: rect.midY - diameter / 2, width: diameter, height: diameter)).fill()
            text.draw(at: NSPoint(x: diameter + 3, y: rect.midY - textSize.height / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static let dividerImage: NSImage = {
        let image = NSImage(size: NSSize(width: 2, height: 16), flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 2), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
