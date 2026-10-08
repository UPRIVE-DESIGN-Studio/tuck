import AppKit

/// A row of menu bar item pictures that can be clicked, ⌥-clicked, right-clicked, dragged to
/// reorder, and walked with the arrow keys. Draws its own cells so a drag can slide them around.
final class ItemStrip: NSView, NSViewToolTipOwner {
    struct Item: Equatable {
        let windowID: CGWindowID
        let title: String
        let image: NSImage?
        /// True when `image` is a capture of the real item rather than its app icon.
        let isCapture: Bool
    }

    enum Click {
        case primary
        /// Right-click (or ⌃-click): many items show extra options.
        case secondary
        /// ⌥-click: many items show a different, more detailed menu.
        case alternate
    }

    var onClick: (CGWindowID, Click) -> Void = { _, _ in }
    /// The item and its new index in `items`.
    var onReorder: (CGWindowID, Int) -> Void = { _, _ in }

    var items: [Item] = [] {
        didSet {
            guard items != oldValue else { return }
            prepareImages()
            invalidateIntrinsicContentSize()
            needsDisplay = true
            updateToolTips()
        }
    }

    var selectedIndex: Int? {
        didSet { needsDisplay = true }
    }

    var canReorder = true
    /// White in the notch drawer, label colour on glass.
    var tint: NSColor = .labelColor {
        didSet { prepareImages() }
    }

    private static let height: CGFloat = 30
    private static let iconCell: CGFloat = 30
    private static let spacing: CGFloat = 2

    private var images: [NSImage?] = []
    private var hoveredIndex: Int? {
        didSet { if hoveredIndex != oldValue { needsDisplay = true } }
    }
    private var pressedIndex: Int?
    private var pressLocation: CGPoint = .zero
    private var dragOffset: CGFloat?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let widths = items.map(Self.cellWidth)
        let total = widths.reduce(0, +) + Self.spacing * CGFloat(max(0, widths.count - 1))
        return NSSize(width: max(total, 1), height: Self.height)
    }

    private static func cellWidth(_ item: Item) -> CGFloat {
        item.isCapture ? max(Self.iconCell, (item.image?.size.width ?? 0) + 4) : Self.iconCell
    }

    private func cellFrames() -> [CGRect] {
        var x: CGFloat = 0
        return items.map { item in
            let width = Self.cellWidth(item)
            defer { x += width + Self.spacing }
            return CGRect(x: x, y: 0, width: width, height: Self.height)
        }
    }

    private func prepareImages() {
        images = items.map { item in
            guard let image = item.image else {
                return NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: nil)
                    .map { Self.tinted($0, tint) }
            }
            return image.isTemplate ? Self.tinted(image, tint) : image
        }
        needsDisplay = true
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        var frames = cellFrames()
        // While dragging, the picked-up cell follows the pointer and the others close the gap.
        if let pressed = pressedIndex, let offset = dragOffset {
            let target = targetIndex(for: pressed, offset: offset, frames: frames)
            frames = reorderedFrames(frames, moving: pressed, to: target)
            frames[pressed].origin.x = cellFrames()[pressed].minX + offset
        }
        for (index, frame) in frames.enumerated() {
            if index == hoveredIndex || index == selectedIndex || index == pressedIndex {
                tint.withAlphaComponent(index == selectedIndex ? 0.22 : 0.12).setFill()
                NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 2), xRadius: 7, yRadius: 7).fill()
            }
            guard let image = images[index] else { continue }
            let size = fitted(image.size, in: items[index].isCapture ? CGSize(width: frame.width - 4, height: 22) : CGSize(width: 20, height: 20))
            let rect = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height, 1.5)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Where the dragged cell would drop: past the centre of a neighbour means swapping with it.
    private func targetIndex(for index: Int, offset: CGFloat, frames: [CGRect]) -> Int {
        let center = frames[index].midX + offset
        var target = index
        for (other, frame) in frames.enumerated() where other != index {
            if other < index && center < frame.midX { target = min(target, other) }
            if other > index && center > frame.midX { target = max(target, other) }
        }
        return target
    }

    private func reorderedFrames(_ frames: [CGRect], moving index: Int, to target: Int) -> [CGRect] {
        guard index != target else { return frames }
        var order = Array(frames.indices)
        order.remove(at: index)
        order.insert(index, at: target)
        var result = frames
        var x: CGFloat = 0
        for cell in order {
            result[cell].origin.x = x
            x += frames[cell].width + Self.spacing
        }
        return result
    }

    private func index(at point: CGPoint) -> Int? {
        cellFrames().firstIndex { $0.contains(point) }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseMoved(with event: NSEvent) {
        hoveredIndex = index(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = index(at: point) else { return }
        if event.modifierFlags.contains(.control) {
            onClick(items[index].windowID, .secondary)
            return
        }
        pressedIndex = index
        pressLocation = point
        dragOffset = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard canReorder, pressedIndex != nil else { return }
        let dx = convert(event.locationInWindow, from: nil).x - pressLocation.x
        if dragOffset != nil || abs(dx) > 4 {
            dragOffset = dx
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressedIndex = nil
            dragOffset = nil
            needsDisplay = true
        }
        guard let pressed = pressedIndex else { return }
        if let offset = dragOffset {
            let target = targetIndex(for: pressed, offset: offset, frames: cellFrames())
            if target != pressed { onReorder(items[pressed].windowID, target) }
            return
        }
        onClick(items[pressed].windowID, event.modifierFlags.contains(.option) ? .alternate : .primary)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else { return }
        onClick(items[index].windowID, .secondary)
    }

    // MARK: Tooltips & accessibility

    private func updateToolTips() {
        removeAllToolTips()
        for (index, frame) in cellFrames().enumerated() {
            addToolTip(frame, owner: self, userData: UnsafeMutableRawPointer(bitPattern: index + 1))
        }
        setAccessibilityLabel(items.map(\.title).joined(separator: ", "))
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let data else { return "" }
        let index = Int(bitPattern: data) - 1
        return items.indices.contains(index) ? items[index].title : ""
    }
}
