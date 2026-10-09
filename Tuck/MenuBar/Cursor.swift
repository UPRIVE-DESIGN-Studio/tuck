import CoreGraphics
import Darwin

/// Hides the pointer while synthetic drags run, then puts it back where it was. Moving a menu bar
/// item only works through the session event stream, which drags the real pointer along.
enum Cursor {
    private static var allowedInBackground = false

    /// Seconds since the mouse last moved or a button was pressed.
    static var idleSeconds: Double {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
    }

    /// Automatic moves wait for a still mouse: they hide and warp the pointer, which would fight
    /// a hand on the mouse.
    static var isStill: Bool { idleSeconds >= 1.5 }

    static func location() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Runs `work` with the pointer hidden and restores its position afterwards.
    static func hidden<T>(_ work: () async -> T) async -> T {
        let start = location()
        allowHidingInBackground()
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            CGWarpMouseCursorPosition(start)
            // A warp normally freezes the mouse for a quarter second; re-associating lifts that.
            CGAssociateMouseAndMouseCursorPosition(1)
            CGDisplayShowCursor(CGMainDisplayID())
        }
        return await work()
    }

    /// An app that is not frontmost may only hide the pointer once it sets the window server
    /// connection property "SetsCursorInBackground". There is no public API for this.
    private static func allowHidingInBackground() {
        guard !allowedInBackground else { return }
        allowedInBackground = true
        typealias MainConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainSymbol = dlsym(skyLight, "SLSMainConnectionID"),
              let setSymbol = dlsym(skyLight, "SLSSetConnectionProperty")
        else {
            Log.error("cannot hide the pointer in the background: SkyLight symbols missing")
            return
        }
        let main = unsafeBitCast(mainSymbol, to: MainConnection.self)
        let set = unsafeBitCast(setSymbol, to: SetProperty.self)
        let connection = main()
        _ = set(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
