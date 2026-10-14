import AppKit
import ApplicationServices

/// Snapping windows into place: start dragging a window, hold ⌃, and the places it can go light
/// up on the display under the pointer. Let go of the mouse over one and the window fills it.
/// Hold ⌃⌥ instead and the window under the pointer is split with the dragged one (see
/// `WindowSplit`); over empty desktop that falls back to the grid. Let go of the keys first and
/// the drag is an ordinary move.
///
/// A drag is recognised by the window under the press moving along with the pointer, so text
/// selections, sliders and resizes never bring up the zones.
final class WindowZones {
    private struct Drag {
        let window: AXUIElement
        let app: AXUIElement
        /// The window server's number for it. Its frame there follows the drag live, while the
        /// app's Accessibility frame may only catch up when the drag ends.
        let windowID: CGWindowID?
        let resizable: Bool
        /// The window's frame and the pointer when the drag was first seen, CoreGraphics coordinates.
        let startFrame: CGRect
        let startPointer: CGPoint
        var confirmed = false
    }

    /// Another app's window on screen when the drag started; they hold still while it lasts.
    private struct Other {
        let windowID: CGWindowID
        let pid: pid_t
        /// CoreGraphics coordinates.
        let frame: CGRect
        let appName: String
    }

    private enum Tracking {
        case idle
        case pressed(CGPoint)
        case dragging(Drag)
        /// Not a window drag; wait for the next press.
        case ignored
    }

    /// How far the pointer may travel before a window that has not followed it rules the drag out.
    private static let confirmWithin: CGFloat = 40

    private var tracking: Tracking = .idle
    private var drop: CGRect?
    /// The window being split and where it goes, CoreGraphics coordinates.
    private var partnerDrop: (window: AXUIElement, frame: CGRect)?
    private var others: [Other] = []
    /// Accessibility elements of `others` looked up so far; nil for one that cannot be resized.
    private var elements: [CGWindowID: AXUIElement?] = [:]
    private var monitor: Any?
    private let overlay = ZoneOverlay()

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let keys = Keys(event.modifierFlags)
            MainActor.assumeIsolated { self?.handle(type, keys: keys) }
        }
    }

    /// What the held modifier keys ask for.
    private enum Keys {
        case none, grid, split

        init(_ flags: NSEvent.ModifierFlags) {
            self = !flags.contains(.control) ? .none : flags.contains(.option) ? .split : .grid
        }
    }

    private func handle(_ type: NSEvent.EventType, keys: Keys) {
        switch type {
        case .leftMouseDown:
            finish()
            tracking = Preferences.windowZones && Permissions.isTrusted ? .pressed(NSEvent.mouseLocation) : .ignored
        case .leftMouseDragged:
            dragged(keys: keys)
        case .leftMouseUp:
            released(keys: keys)
        case .flagsChanged:
            update(keys: keys)
        default:
            break
        }
    }

    private func dragged(keys: Keys) {
        switch tracking {
        case .pressed(let point):
            let drag = Self.drag(at: point)
            Log.info("zones: drag from \(point): \(drag.map { "window \($0.windowID.map(String.init) ?? "?") \($0.startFrame)" } ?? "not a window")")
            tracking = drag.map(Tracking.dragging) ?? .ignored
        case .dragging(var drag) where !drag.confirmed:
            let pointer = Self.global(NSEvent.mouseLocation)
            let travelled = hypot(pointer.x - drag.startPointer.x, pointer.y - drag.startPointer.y)
            guard travelled >= 4, let frame = drag.windowID.flatMap(WindowList.frame(of:)) ?? AX.frame(drag.window) else { return }
            let moved = hypot(frame.minX - drag.startFrame.minX, frame.minY - drag.startFrame.minY)
            if frame.size == drag.startFrame.size && moved >= 2 {
                drag.confirmed = true
                others = drag.windowID.map(Self.otherWindows) ?? []
                Log.info("zones: window follows the pointer; \(others.count) other windows")
                tracking = .dragging(drag)
                update(keys: keys)
            } else if travelled > Self.confirmWithin {
                Log.info("zones: window stayed at \(frame) while the pointer moved \(Int(travelled)); not a window drag")
                tracking = .ignored
            }
        case .dragging:
            update(keys: keys)
        default:
            break
        }
    }

    /// Shows or moves the zones for the pointer's position, or hides them without ⌃.
    private func update(keys: Keys) {
        guard keys != .none, case .dragging(let drag) = tracking, drag.confirmed else {
            drop = nil
            partnerDrop = nil
            overlay.hide()
            return
        }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { return }
        let layout = ZoneLayout(area: screen.visibleFrame)
        if keys == .split, drag.resizable, let (split, other, window) = split(at: pointer, in: layout) {
            drop = split.mine
            partnerDrop = (window, Self.global(split.theirs))
            overlay.show(
                layout, highlight: split.mine, label: "\(Int(split.mine.width)) × \(Int(split.mine.height))",
                partner: (split.theirs, other.appName)
            )
            return
        }
        partnerDrop = nil
        let zone = layout.target(for: pointer)
        drop = zone.flatMap { ZoneLayout.dropFrame(in: $0, windowSize: drag.startFrame.size, resizable: drag.resizable) }
        let label = drop.map { "\(Int($0.width)) × \(Int($0.height))" }
        overlay.show(layout, highlight: drop == nil ? nil : zone, label: label)
    }

    private func released(keys: Keys) {
        defer { finish() }
        guard keys != .none, case .dragging(let drag) = tracking, drag.confirmed, let drop else { return }
        let target = Self.global(drop)
        let partner = partnerDrop
        Log.info("zones: snapping window to \(target)\(partner.map { ", sharing with a window going to \($0.frame)" } ?? "")")
        // The window server finishes its own move on release; land after it, not under it.
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            if let partner { AX.setFrame(partner.window, partner.frame) }
            Self.place(drag.window, app: drag.app, at: target)
        }
    }

    private func finish() {
        tracking = .idle
        drop = nil
        partnerDrop = nil
        others = []
        elements = [:]
        overlay.hide()
    }

    /// A split of the frontmost other window under the pointer, when it can be resized.
    private func split(at pointer: CGPoint, in layout: ZoneLayout) -> (WindowSplit, Other, AXUIElement)? {
        guard let other = others.first(where: { Self.cocoa($0.frame).contains(pointer) }),
              let split = WindowSplit.offer(Self.cocoa(other.frame).intersection(layout.area), at: pointer),
              let window = element(for: other)
        else { return nil }
        return (split, other, window)
    }

    private func element(for other: Other) -> AXUIElement? {
        if let known = elements[other.windowID] { return known }
        let found = Self.resizableWindow(of: other.pid, at: other.frame)
        elements.updateValue(found, forKey: other.windowID)
        return found
    }

    // MARK: Accessibility

    /// The window under a press, if it is one Tuck can move: an ordinary window or dialog of
    /// another app, not full screen.
    private static func drag(at point: CGPoint) -> Drag? {
        let pointer = global(point)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(pointer.x), Float(pointer.y), &hit) == .success,
              let hit
        else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }

        let window: AXUIElement
        if AX.string(hit, kAXRoleAttribute) == kAXWindowRole {
            window = hit
        } else if let parent = AX.attribute(hit, kAXWindowAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() {
            window = parent as! AXUIElement
        } else {
            return nil
        }
        AXUIElementSetMessagingTimeout(window, 0.25)
        let subrole = AX.string(window, kAXSubroleAttribute)
        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole,
              AX.attribute(window, "AXFullScreen") as? Bool != true
        else { return nil }
        // Prefer the window server's frame: by now the window may already have moved there.
        let windowID = windowID(of: pid, under: pointer)
        guard let frame = windowID.flatMap(WindowList.frame(of:)) ?? AX.frame(window) else { return nil }

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
        return Drag(
            window: window, app: AXUIElementCreateApplication(pid), windowID: windowID,
            resizable: settable.boolValue,
            startFrame: frame, startPointer: global(NSEvent.mouseLocation)
        )
    }

    /// The frontmost ordinary window of `pid` under the pointer, by the window server's list.
    private static func windowID(of pid: pid_t, under pointer: CGPoint) -> CGWindowID? {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.lazy.compactMap { info -> CGWindowID? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.insetBy(dx: -8, dy: -8).contains(pointer)
            else { return nil }
            return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }.first
    }

    /// Other apps' ordinary windows on screen, front to back, leaving out the dragged one.
    private static func otherWindows(excluding dragged: CGWindowID) -> [Other] {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { info in
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value, number != dragged,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  (info[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 100, frame.height >= 100
            else { return nil }
            return Other(windowID: number, pid: pid, frame: frame, appName: info[kCGWindowOwnerName as String] as? String ?? "")
        }
    }

    /// The Accessibility element for another app's window at `frame`, if its size can be set.
    private static func resizableWindow(of pid: pid_t, at frame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let windows = AX.attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.first { window in
            guard let found = AX.frame(window),
                  abs(found.minX - frame.minX) <= 2, abs(found.minY - frame.minY) <= 2,
                  abs(found.width - frame.width) <= 2, abs(found.height - frame.height) <= 2
            else { return false }
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
            return settable.boolValue
        }
    }

    /// Moves and resizes the window. Apps with enhanced accessibility (set by VoiceOver and some
    /// tools) animate every change, so that is switched off for the move. A window that stays
    /// larger than the zone is centred on it instead.
    private static func place(_ window: AXUIElement, app: AXUIElement, at target: CGRect) {
        let enhanced = "AXEnhancedUserInterface" as CFString
        let wasEnhanced = AX.attribute(app, enhanced as String) as? Bool == true
        if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanFalse) }
        defer { if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanTrue) } }

        AX.setFrame(window, target)
        guard let landed = AX.frame(window),
              landed.width > target.width + 2 || landed.height > target.height + 2
        else { return }
        let centred = CGRect(
            x: (target.midX - landed.width / 2).rounded(), y: max(target.minY, (target.midY - landed.height / 2).rounded()),
            width: landed.width, height: landed.height
        )
        Log.info("zones: window kept \(landed.size), centring")
        AX.setFrame(window, centred)
    }

    // MARK: Coordinates

    /// Cocoa screen coordinates (bottom-left origin) to CoreGraphics global ones (top-left of the
    /// primary display), which Accessibility uses.
    private static func global(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    private static func global(_ rect: CGRect) -> CGRect {
        Coordinates.cgRect(fromCocoa: rect)
    }

    /// The same flip the other way.
    private static func cocoa(_ rect: CGRect) -> CGRect {
        Coordinates.cgRect(fromCocoa: rect)
    }

    private static var primaryHeight: CGFloat { Coordinates.primaryHeight }
}
