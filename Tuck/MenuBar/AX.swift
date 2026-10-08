import ApplicationServices
import CoreGraphics

/// Thin typed wrappers over the Accessibility C API.
enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) as? String, !value.isEmpty else { return nil }
        return value
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    /// Frame in CoreGraphics global coordinates (top-left origin of the primary display).
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    /// Presses an element. For a menu bar item that opens a menu, the call does not return until
    /// the menu closes, so the timeout is short: the menu stays open, we just stop waiting.
    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.25)
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        return result == .success || result == .cannotComplete
    }
}
