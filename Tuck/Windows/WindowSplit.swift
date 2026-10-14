import CoreGraphics

/// Sharing another window's place with the dragged one: the pointer over a window splits it in
/// two, the dragged window taking the side the pointer leans to and the other window keeping
/// the rest. Cocoa coordinates.
struct WindowSplit: Equatable {
    /// Where the dragged window goes.
    let mine: CGRect
    /// What the window underneath shrinks to.
    let theirs: CGRect

    /// No split that would leave either window smaller than this.
    static let smallestHalf = CGSize(width: 240, height: 160)

    /// Left or right when the pointer leans sideways, top or bottom when it leans up or down.
    static func offer(_ window: CGRect, at point: CGPoint) -> WindowSplit? {
        guard !window.isEmpty, window.contains(point) else { return nil }
        let across = (point.x - window.midX) / (window.width / 2)
        let up = (point.y - window.midY) / (window.height / 2)
        return abs(across) >= abs(up) ? sideBySide(window, mineLeft: across < 0) : stacked(window, mineOnTop: up > 0)
    }

    private static func sideBySide(_ window: CGRect, mineLeft: Bool) -> WindowSplit? {
        guard window.width / 2 >= smallestHalf.width else { return nil }
        let middle = (window.minX + window.width / 2).rounded()
        let left = CGRect(x: window.minX, y: window.minY, width: middle - window.minX, height: window.height)
        let right = CGRect(x: middle, y: window.minY, width: window.maxX - middle, height: window.height)
        return mineLeft ? WindowSplit(mine: left, theirs: right) : WindowSplit(mine: right, theirs: left)
    }

    private static func stacked(_ window: CGRect, mineOnTop: Bool) -> WindowSplit? {
        guard window.height / 2 >= smallestHalf.height else { return nil }
        let middle = (window.minY + window.height / 2).rounded()
        let bottom = CGRect(x: window.minX, y: window.minY, width: window.width, height: middle - window.minY)
        let top = CGRect(x: window.minX, y: middle, width: window.width, height: window.maxY - middle)
        return mineOnTop ? WindowSplit(mine: top, theirs: bottom) : WindowSplit(mine: bottom, theirs: top)
    }
}
