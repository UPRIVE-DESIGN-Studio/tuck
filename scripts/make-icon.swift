// Renders Tuck's app icon into the asset catalog: swift scripts/make-icon.swift
import AppKit

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
let output = URL(fileURLWithPath: "Tuck/Resources/Assets.xcassets/AppIcon.appiconset")

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    // macOS icon grid: 824 pt squircle centred in 1024.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(white: 0.36, alpha: 1), NSColor(white: 0.17, alpha: 1)])!.draw(in: squircle, angle: -90)

    // The drawer: hangs from the top edge like the notch peeling down.
    let drawer = NSRect(x: 272 * s, y: 560 * s, width: 480 * s, height: 364 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    let drawerPath = NSBezierPath()
    let r = 90 * s
    drawerPath.move(to: NSPoint(x: drawer.minX - 40 * s, y: drawer.maxY))
    drawerPath.curve(to: NSPoint(x: drawer.minX, y: drawer.maxY - 40 * s),
                     controlPoint1: NSPoint(x: drawer.minX, y: drawer.maxY), controlPoint2: NSPoint(x: drawer.minX, y: drawer.maxY))
    drawerPath.line(to: NSPoint(x: drawer.minX, y: drawer.minY + r))
    drawerPath.curve(to: NSPoint(x: drawer.minX + r, y: drawer.minY),
                     controlPoint1: NSPoint(x: drawer.minX, y: drawer.minY), controlPoint2: NSPoint(x: drawer.minX, y: drawer.minY))
    drawerPath.line(to: NSPoint(x: drawer.maxX - r, y: drawer.minY))
    drawerPath.curve(to: NSPoint(x: drawer.maxX, y: drawer.minY + r),
                     controlPoint1: NSPoint(x: drawer.maxX, y: drawer.minY), controlPoint2: NSPoint(x: drawer.maxX, y: drawer.minY))
    drawerPath.line(to: NSPoint(x: drawer.maxX, y: drawer.maxY - 40 * s))
    drawerPath.curve(to: NSPoint(x: drawer.maxX + 40 * s, y: drawer.maxY),
                     controlPoint1: NSPoint(x: drawer.maxX, y: drawer.maxY), controlPoint2: NSPoint(x: drawer.maxX, y: drawer.maxY))
    drawerPath.close()
    NSColor.black.setFill()
    drawerPath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Three tucked items inside the drawer.
    let dot: CGFloat = 78 * s
    for (index, white) in [CGFloat(1.0), 0.75, 0.5].enumerated() {
        let x = drawer.midX + (CGFloat(index) - 1) * 130 * s - dot / 2
        NSColor(white: white, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: drawer.minY + 100 * s, width: dot, height: dot)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try! render(points * scale).write(to: output.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: output.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icon sizes")
