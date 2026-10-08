import AppKit
import CoreGraphics

/// Reads status item windows from the window server.
///
/// On macOS 26 every status item window, ours included, is owned by Control Center, so the
/// window list alone says nothing about which app an item belongs to (see `OwnerResolver`).
enum WindowList {
    struct Entry: Equatable {
        let windowID: CGWindowID
        let ownerPID: pid_t
        /// CoreGraphics coordinates: top-left origin of the primary display.
        let frame: CGRect
        let isOnScreen: Bool
    }

    private static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

    /// Every status item window in the menu bar whose top edge is at `menuBarTop`, left to right.
    static func statusItems(menuBarTop: CGFloat) -> [Entry] {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return raw.compactMap { info -> Entry? in
            guard info[kCGWindowLayer as String] as? Int == statusLevel,
                  let entry = entry(from: info),
                  abs(entry.frame.minY - menuBarTop) < 1,
                  entry.frame.height < 60
            else { return nil }
            return entry
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Looked up in the full list: on macOS 26 `.optionIncludingWindow` returns nothing for item windows.
    static func entry(for windowID: CGWindowID) -> Entry? {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
              let info = raw.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID })
        else { return nil }
        return entry(from: info)
    }

    static func frame(of windowID: CGWindowID) -> CGRect? {
        entry(for: windowID)?.frame
    }

    /// IDs of all on-screen windows above the menu bar level (menus, popovers, panels).
    static func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }
        return Set(raw.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int ?? 0) != statusLevel else { return nil }
            return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
    }

    private static func entry(from info: [String: Any]) -> Entry? {
        guard let number = info[kCGWindowNumber as String] as? NSNumber,
              let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { return nil }
        let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
        return Entry(windowID: number.uint32Value, ownerPID: pid.int32Value, frame: frame, isOnScreen: onScreen)
    }
}

/// Cocoa (bottom-left origin) ↔ CoreGraphics (top-left origin) conversion.
enum Coordinates {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func cgRect(fromCocoa rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
