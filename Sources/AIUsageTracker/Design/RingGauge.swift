import SwiftUI

/// A circular progress ring in the style of the macOS Batteries widget.
/// Shared by the dropdown and (later) the desktop widget.
struct RingGauge: View {
    let percent: Double
    let level: UsageLevel
    var diameter: CGFloat = 78
    var lineWidth: CGFloat = 8

    var body: some View {
        let fraction = min(max(percent, 0), 100) / 100

        ZStack {
            Circle()
                .stroke(Theme.trackFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(level.color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(percent.rounded()))%")
                .font(.system(size: diameter * 0.25, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: percent))
        }
        .frame(width: diameter, height: diameter)
        .animation(.smooth(duration: 0.6), value: percent)
        .accessibilityElement()
        .accessibilityLabel("\(Int(percent)) percent used")
    }
}
