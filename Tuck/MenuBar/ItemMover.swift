import AppKit
import CoreGraphics

/// Moves and clicks other apps' menu bar items by posting mouse events addressed to the item's
/// window. A move is the same ⌘-drag a person would do by hand; because the events name the
/// window directly, it also works for items that are off-screen or behind the notch.
final class ItemMover {
    enum Destination: CustomStringConvertible {
        case leftOf(CGWindowID)
        case rightOf(CGWindowID)

        var target: CGWindowID {
            switch self {
            case .leftOf(let id), .rightOf(let id): id
            }
        }

        func dropPoint(in frame: CGRect) -> CGPoint {
            switch self {
            case .leftOf: CGPoint(x: frame.minX, y: frame.midY)
            case .rightOf: CGPoint(x: frame.maxX, y: frame.midY)
            }
        }

        /// True when the item is the target's direct neighbour on the requested side. Checked by
        /// order rather than exact edges, because the hidden section shifts while it settles.
        func isSatisfied(by windowID: CGWindowID, in row: [WindowList.Entry]) -> Bool {
            guard let index = row.firstIndex(where: { $0.windowID == windowID }) else { return false }
            switch self {
            case .leftOf(let target): return index + 1 < row.count && row[index + 1].windowID == target
            case .rightOf(let target): return index > 0 && row[index - 1].windowID == target
            }
        }

        var description: String {
            switch self {
            case .leftOf(let id): "left of \(id)"
            case .rightOf(let id): "right of \(id)"
            }
        }
    }

    /// Where synthetic events are injected. Kept switchable (`tuck://route/<name>`) because the
    /// right answer has changed between macOS releases.
    enum Route: String {
        case session, pid, hid
    }

    var route: Route = .session

    /// Undocumented event field that carries the target window ID.
    private static let windowIDField = CGEventField(rawValue: 0x33)!

    /// - Parameter landed: an extra success test on the item's new frame, for destinations whose
    ///   own frame the window server reports late (the collapsed separator).
    func move(
        _ windowID: CGWindowID, to destination: Destination, landed: ((CGRect) -> Bool)? = nil
    ) async -> Bool {
        await Cursor.hidden { await moveWithVisibleCursor(windowID, to: destination, landed: landed) }
    }

    private func moveWithVisibleCursor(
        _ windowID: CGWindowID, to destination: Destination, landed: ((CGRect) -> Bool)?
    ) async -> Bool {
        for attempt in 1...4 {
            guard let item = WindowList.entry(for: windowID),
                  let target = WindowList.entry(for: destination.target)
            else {
                Log.error("move \(windowID): window gone")
                return false
            }
            if destination.isSatisfied(by: windowID, in: row(at: item.frame.minY)) { return true }

            permitSyntheticEvents()
            let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
            let end = destination.dropPoint(in: target.frame)
            Log.info("move \(windowID) from \(item.frame) → \(destination) target \(target.frame), down \(start) up \(end)")
            post(mouseEvent(.leftMouseDown, at: start, window: item.windowID, pid: item.ownerPID, flags: .maskCommand))
            try? await Task.sleep(for: .milliseconds(40))
            post(mouseEvent(.leftMouseUp, at: end, window: target.windowID, pid: item.ownerPID, flags: []))

            let before = item.frame
            let done = await waitUntil(timeout: .milliseconds(500)) {
                if destination.isSatisfied(by: windowID, in: self.row(at: before.minY)) { return true }
                guard let landed, let now = WindowList.frame(of: windowID), now != before else { return false }
                return landed(now)
            }
            if done {
                Log.info("moved \(windowID) \(destination) (attempt \(attempt), route \(route.rawValue))")
                return true
            }
            let near = row(at: item.frame.minY).prefix(4).map { "\($0.windowID)@\(Int($0.frame.minX))+\(Int($0.frame.width))" }
            Log.info("move \(windowID) \(destination) attempt \(attempt) did not land; row starts \(near)")
        }
        Log.error("move \(windowID) \(destination) failed")
        return false
    }

    /// Fallback for items without an Accessibility element; `AX.press` is preferred.
    func click(_ windowID: CGWindowID, button: CGMouseButton = .left) async -> Bool {
        await Cursor.hidden { await clickWithVisibleCursor(windowID, button: button) }
    }

    private func clickWithVisibleCursor(_ windowID: CGWindowID, button: CGMouseButton) async -> Bool {
        guard let item = WindowList.entry(for: windowID) else { return false }

        let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let (down, up): (CGEventType, CGEventType) = switch button {
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.leftMouseDown, .leftMouseUp)
        }
        permitSyntheticEvents()
        post(mouseEvent(down, at: point, window: windowID, pid: item.ownerPID, flags: [], button: button, clickState: 1))
        try? await Task.sleep(for: .milliseconds(30))
        post(mouseEvent(up, at: point, window: windowID, pid: item.ownerPID, flags: [], button: button, clickState: 1))
        Log.info("clicked \(windowID) at \(point) (route \(route.rawValue))")
        return true
    }

    private func row(at menuBarTop: CGFloat) -> [WindowList.Entry] {
        WindowList.statusItems(menuBarTop: menuBarTop)
    }

    // MARK: Events

    private func mouseEvent(
        _ type: CGEventType, at point: CGPoint, window: CGWindowID, pid: pid_t,
        flags: CGEventFlags, button: CGMouseButton = .left, clickState: Int64? = nil
    ) -> CGEvent? {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        else { return nil }
        event.flags = flags
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        event.setIntegerValueField(Self.windowIDField, value: Int64(window))
        if let clickState {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        return event
    }

    private func post(_ event: CGEvent?) {
        guard let event else {
            Log.error("could not create event")
            return
        }
        switch route {
        case .session: event.post(tap: .cgSessionEventTap)
        case .hid: event.post(tap: .cghidEventTap)
        case .pid: event.postToPid(pid_t(event.getIntegerValueField(.eventTargetUnixProcessID)))
        }
    }

    /// Without this, the window server drops synthetic mouse events for a short while after
    /// real input, and during drags.
    private func permitSyntheticEvents() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let all: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source.setLocalEventsFilterDuringSuppressionState(all, state: .eventSuppressionStateRemoteMouseDrag)
        source.setLocalEventsFilterDuringSuppressionState(all, state: .eventSuppressionStateSuppressionInterval)
        source.localEventsSuppressionInterval = 0
    }
}

/// Polls `condition` every 20 ms until it is true or `timeout` passes.
func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
