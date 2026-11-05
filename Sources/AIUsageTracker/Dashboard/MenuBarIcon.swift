import AppKit

/// Draws the menu bar item: a small progress ring, optionally followed by the percentage.
///
/// Menu bar items are normally single-color, so to keep the ring colored this is drawn
/// as a regular image. The text and ring track are drawn at display time in the menu
/// bar's own colors, so they stay readable on light, dark, and tinted menu bars.
enum MenuBarIcon {
    /// - Parameters:
    ///   - percent: Current usage, or nil when there's no reading yet (shows an empty ring).
    ///   - showsPercent: Adds the number next to the ring.
    static func image(percent: Double?, showsPercent: Bool) -> NSImage {
        let height: CGFloat = 18
        let ringSize: CGFloat = showsPercent ? 14 : 16
        let text = showsPercent ? (percent.map { "\(Int($0.rounded()))%" } ?? "—") : nil
        let gap: CGFloat = text != nil ? 5 : 0
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let textWidth = text.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) } ?? 0
        let width = ringSize + gap + textWidth

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let ringRect = NSRect(x: 0, y: (height - ringSize) / 2, width: ringSize, height: ringSize)
            drawRing(in: ringRect, percent: percent, lineWidth: showsPercent ? 2.5 : 3)

            if let text {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor.labelColor,
                ]
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: NSPoint(x: ringSize + gap, y: (height - size.height) / 2), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = percent.map { "Claude usage \(Int($0.rounded())) percent" } ?? "Peek"
        return image
    }

    private static func drawRing(in rect: NSRect, percent: Double?, lineWidth: CGFloat) {
        let inset = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let center = NSPoint(x: inset.midX, y: inset.midY)
        let radius = inset.width / 2

        let track = NSBezierPath(ovalIn: inset)
        track.lineWidth = lineWidth
        NSColor.labelColor.withAlphaComponent(0.25).setStroke()
        track.stroke()

        guard let percent else { return }
        let fraction = min(max(percent, 0), 100) / 100
        guard fraction > 0 else { return }
        // Start at 12 o'clock and fill clockwise.
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        UsageLevel(percent: percent).nsColor.setStroke()
        arc.stroke()
    }
}
