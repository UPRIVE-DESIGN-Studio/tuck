import AppKit
import QuartzCore

/// A see-through panel over one display's usable area while a window is dragged with ⌃: every
/// drop place in outline, the one under the pointer filled with the accent colour and labelled
/// with the size the window will get. With ⌃⌥ over another window the grid gives way to
/// that window split in two: the dragged window's half filled, the other half outlined with the
/// name of the window that will shrink into it. Clicks pass through it.
final class ZoneOverlay {
    private var panel: NSPanel?
    private var view: ZoneView?
    private var shown: ZoneLayout?

    /// `highlight` is where the dragged window goes, in screen coordinates; nil when nothing is
    /// targeted. `partner` is where the window it splits with goes, and replaces the grid.
    func show(_ layout: ZoneLayout, highlight: CGRect?, label: String?, partner: (frame: CGRect, label: String)? = nil) {
        let (panel, view) = if let panel, let view { (panel, view) } else { make() }
        if shown != layout {
            panel.setFrame(layout.area, display: false)
            view.setCells(layout.cells.map { local($0, in: layout) })
            shown = layout
        }
        view.setHighlight(highlight.map { local($0, in: layout) }, label: label)
        view.setPartner(partner.map { (local($0.frame, in: layout), $0.label) })
        guard !panel.isVisible || panel.alphaValue < 1 else { return }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        shown = nil
        view?.setHighlight(nil, label: nil)
        view?.setPartner(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            // Shown again while fading out: leave it up.
            MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
        }
    }

    private func local(_ rect: CGRect, in layout: ZoneLayout) -> CGRect {
        rect.offsetBy(dx: -layout.area.minX, dy: -layout.area.minY)
    }

    private func make() -> (NSPanel, ZoneView) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        let view = ZoneView()
        panel.contentView = view
        self.panel = panel
        self.view = view
        return (panel, view)
    }
}

private final class ZoneView: NSView {
    /// Space between drawn zones, so neighbours read as separate places.
    private static let gap: CGFloat = 6
    private static let radius: CGFloat = 12

    private var cellLayers: [CALayer] = []
    private let highlight = CALayer()
    private let label = CATextLayer()
    private let partner = CALayer()
    private let partnerLabel = CATextLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        highlight.cornerRadius = Self.radius
        highlight.borderWidth = 2
        highlight.opacity = 0
        highlight.addSublayer(label)

        partner.cornerRadius = Self.radius
        partner.borderWidth = 2
        partner.opacity = 0
        partner.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        partner.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        for text in [label, partnerLabel] {
            text.fontSize = 15
            text.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            text.alignmentMode = .center
            text.truncationMode = .end
            text.foregroundColor = NSColor.white.cgColor
            text.shadowOpacity = 0.4
            text.shadowRadius = 2
            text.shadowOffset = .zero
        }
        partner.addSublayer(partnerLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        label.contentsScale = window?.backingScaleFactor ?? 2
        partnerLabel.contentsScale = label.contentsScale
    }

    func setCells(_ cells: [CGRect]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cellLayers.forEach { $0.removeFromSuperlayer() }
        cellLayers = cells.map { cell in
            let layer = CALayer()
            layer.frame = cell.insetBy(dx: Self.gap, dy: Self.gap)
            layer.cornerRadius = Self.radius
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
            layer.borderWidth = 1
            self.layer?.addSublayer(layer)
            return layer
        }
        layer?.addSublayer(partner)
        layer?.addSublayer(highlight)
        CATransaction.commit()
    }

    /// The other half of a split, or nil to bring the grid back.
    func setPartner(_ zone: (frame: CGRect, label: String)?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        cellLayers.forEach { $0.opacity = zone == nil ? 1 : 0 }
        if let zone {
            CATransaction.setDisableActions(partner.opacity == 0)
            partner.frame = zone.frame.insetBy(dx: Self.gap, dy: Self.gap)
            partner.opacity = 1
            partnerLabel.string = zone.label
            partnerLabel.frame = CGRect(x: 8, y: (partner.bounds.height - 20) / 2, width: partner.bounds.width - 16, height: 20)
        } else {
            partner.opacity = 0
        }
        CATransaction.commit()
    }

    func setHighlight(_ zone: CGRect?, label text: String?) {
        CATransaction.begin()
        guard let zone else {
            highlight.opacity = 0
            CATransaction.commit()
            return
        }
        // Jump into place when appearing; glide between zones after that.
        CATransaction.setDisableActions(highlight.opacity == 0)
        CATransaction.setAnimationDuration(0.12)
        let accent = NSColor.controlAccentColor
        highlight.backgroundColor = accent.withAlphaComponent(0.32).cgColor
        highlight.borderColor = accent.withAlphaComponent(0.95).cgColor
        highlight.frame = zone.insetBy(dx: Self.gap, dy: Self.gap)
        highlight.opacity = 1
        label.string = text
        label.frame = CGRect(x: 0, y: (highlight.bounds.height - 20) / 2, width: highlight.bounds.width, height: 20)
        CATransaction.commit()
    }
}
