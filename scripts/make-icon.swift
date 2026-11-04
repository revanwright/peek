// Draws the app icon at every size macOS needs and saves them into an .iconset folder:
//   swiftc scripts/make-icon.swift -o build/make-icon && build/make-icon build/AppIcon.iconset
//
// Design: a white rounded square, a light gray track ring with a terracotta progress
// arc (about 40% full), and an evenly spaced starburst in the middle.

import AppKit

let terracotta = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)  // #D97757

func drawIcon(in size: CGFloat) {
    let scale = size / 1024
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    // Apple's icon grid: the shape sits inside the canvas with room for its shadow.
    let tile = canvas.insetBy(dx: 100 * scale, dy: 100 * scale)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 28 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    shadow.set()
    NSColor.white.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // A barely-there top-to-bottom shade gives the tile some depth.
    NSGradient(starting: NSColor(white: 1, alpha: 1), ending: NSColor(white: 0.94, alpha: 1))?
        .draw(in: tilePath, angle: -90)

    let center = NSPoint(x: canvas.midX, y: canvas.midY)

    // Track ring and progress arc.
    let ringRadius: CGFloat = 250 * scale
    let ringWidth: CGFloat = 62 * scale
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
    track.lineWidth = ringWidth
    NSColor(white: 0.91, alpha: 1).setStroke()
    track.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: ringRadius, startAngle: 90, endAngle: 90 - 360 * 0.4, clockwise: true)
    arc.lineWidth = ringWidth
    arc.lineCapStyle = .round
    terracotta.setStroke()
    arc.stroke()

    // Starburst: 12 evenly spaced rays with rounded ends.
    let rays = 12
    let inner: CGFloat = 14 * scale
    let outer: CGFloat = 132 * scale
    let burst = NSBezierPath()
    for i in 0..<rays {
        let angle = CGFloat(i) / CGFloat(rays) * 2 * .pi + .pi / 2
        burst.move(to: NSPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        burst.line(to: NSPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
    }
    burst.lineWidth = 34 * scale
    burst.lineCapStyle = .round
    terracotta.setStroke()
    burst.stroke()
}

func savePNG(pixels: Int, to url: URL) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(in: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    savePNG(pixels: points, to: output.appending(path: "icon_\(points)x\(points).png"))
    savePNG(pixels: points * 2, to: output.appending(path: "icon_\(points)x\(points)@2x.png"))
}
print("Saved icon images to \(output.path)")
