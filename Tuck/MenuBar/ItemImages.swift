import AppKit
import ScreenCaptureKit

/// Pictures of the real menu bar items, so the bar under the dot looks like the menu bar itself.
/// Needs Screen Recording; without it the bar shows app icons instead.
final class ItemImages {
    private(set) var cache: [CGWindowID: NSImage] = [:]

    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Captures the given items and returns the ones that produced a non-empty picture.
    func refresh(_ items: [MenuBarItem]) async -> [CGWindowID: NSImage] {
        guard Self.isAllowed, !items.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return cache }

        for item in items {
            guard let window = content.windows.first(where: { $0.windowID == item.windowID }) else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int(item.frame.width * scale)
            config.height = Int(item.frame.height * scale)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                  !Self.isBlank(image)
            else { continue }
            cache[item.windowID] = NSImage(cgImage: image, size: item.frame.size)
        }
        return cache
    }

    /// Off-screen windows sometimes come back fully transparent.
    private static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
        let length = CFDataGetLength(data)
        let stride = max(4, length / 4096 / 4 * 4)
        for offset in Swift.stride(from: 3, to: length, by: stride) where bytes[offset] > 8 {
            return false
        }
        return true
    }
}
