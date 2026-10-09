import AppKit
import CoreGraphics

/// Reads status item windows from the window server.
///
/// On macOS 26 every status item window, ours included, is owned by Control Center, so the
/// window list alone says nothing about which app an item belongs to (see `OwnerResolver`).
/// With several displays, every display's menu bar has its own copy of every item, all at the
/// same height; `row(on:)` separates them.
enum WindowList {
    struct Entry: Equatable {
        let windowID: CGWindowID
        let ownerPID: pid_t
        /// CoreGraphics coordinates: top-left origin of the primary display.
        let frame: CGRect
        let isOnScreen: Bool
    }

    private static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

    /// Every status item window, on any display.
    static func allStatusItems() -> [Entry] {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return raw.compactMap { info -> Entry? in
            guard info[kCGWindowLayer as String] as? Int == statusLevel,
                  let entry = entry(from: info), entry.frame.height < 60
            else { return nil }
            return entry
        }
    }

    /// One display's menu bar items, left to right. Items sit edge to edge from the display's right
    /// edge (the Clock) leftwards, hidden ones included, so the row is found by following
    /// neighbours from the right edge. Position alone is not enough: items pushed off one display
    /// can land over another display's menu bar.
    ///
    /// - Parameter screen: the display's frame in CoreGraphics coordinates.
    static func row(on screen: CGRect, in all: [Entry] = allStatusItems()) -> [Entry] {
        let candidates = all.filter { abs($0.frame.minY - screen.minY) < 1 }
        guard var current = candidates
            .filter({ abs($0.frame.maxX - screen.maxX) <= 3 })
            .max(by: { $0.frame.width < $1.frame.width })
        else {
            return candidates.filter { screen.minX <= $0.frame.midX && $0.frame.midX < screen.maxX }
                .sorted { $0.frame.minX < $1.frame.minX }
        }
        var row = [current]
        var seen: Set<CGWindowID> = [current.windowID]
        while let left = candidates.first(where: { !seen.contains($0.windowID) && abs($0.frame.maxX - current.frame.minX) <= 2 }) {
            row.append(left)
            seen.insert(left.windowID)
            current = left
        }
        return row.reversed()
    }

    /// The row that contains `windowID`, on whichever display that is.
    static func row(containing windowID: CGWindowID) -> [Entry] {
        let all = allStatusItems()
        for screen in NSScreen.screens {
            let row = row(on: Coordinates.cgRect(fromCocoa: screen.frame), in: all)
            if row.contains(where: { $0.windowID == windowID }) { return row }
        }
        return []
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
