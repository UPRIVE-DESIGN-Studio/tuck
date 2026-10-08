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
                  let picture = Self.picture(from: image, size: item.frame.size)
            else { continue }
            cache[item.windowID] = picture
        }
        return cache
    }

    /// Turns a capture into something that reads on any background. Monochrome glyphs (most menu
    /// bar icons) become template images, so they take the drawer's colour; colour icons stay as
    /// they are. Blank captures (some off-screen windows) and captures with a solid background
    /// are rejected, and the caller falls back to the app icon.
    static func picture(from image: CGImage, size: CGSize) -> NSImage? {
        guard let stats = PixelStats(image) else { return nil }
        guard stats.visibleFraction > 0.01, stats.opaqueFraction < 0.9 else { return nil }
        let picture = NSImage(cgImage: image, size: size)
        picture.isTemplate = stats.isMonochrome
        return picture
    }
}

/// Coverage and colourfulness of an image, sampled on a grid.
struct PixelStats {
    let visibleFraction: Double
    let opaqueFraction: Double
    let isMonochrome: Bool

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        var samples = 0, visible = 0, opaque = 0, colourful = 0
        let step = max(1, min(width, height) / 24)
        for y in Swift.stride(from: 0, to: height, by: step) {
            for x in Swift.stride(from: 0, to: width, by: step) {
                let pixel = data + (y * width + x) * 4
                let alpha = Int(pixel[3])
                samples += 1
                if alpha > 24 { visible += 1 }
                if alpha > 240 { opaque += 1 }
                guard alpha > 64 else { continue }
                let r = Int(pixel[0]), g = Int(pixel[1]), b = Int(pixel[2])
                if max(r, g, b) - min(r, g, b) > 40 { colourful += 1 }
            }
        }
        visibleFraction = Double(visible) / Double(samples)
        opaqueFraction = Double(opaque) / Double(samples)
        isMonochrome = visible == 0 || Double(colourful) / Double(visible) < 0.08
    }
}
