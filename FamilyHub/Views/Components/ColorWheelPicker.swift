import SwiftUI
import UIKit

/// Hue/saturation color wheel plus a brightness gradient slider with a draggable knob.
struct ColorWheelPicker: View {
    @Binding var hex: String

    @State private var hue: Double = 0.58
    @State private var saturation: Double = 0.85
    @State private var brightness: Double = 1.0
    @State private var isSyncingFromBinding = false

    private let wheelSize: CGFloat = 220
    private let knobSize: CGFloat = 28
    private let sliderHeight: CGFloat = 28

    private var selectedColor: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private var fullBrightColor: Color {
        Color(hue: hue, saturation: saturation, brightness: 1)
    }

    var body: some View {
        VStack(spacing: 20) {
            wheel
            brightnessSlider
            previewRow
        }
        .onAppear {
            apply(hex: hex)
        }
        .onChange(of: hex) { _, newValue in
            guard !isSyncingFromBinding else { return }
            apply(hex: newValue)
        }
    }

    private var wheel: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: Self.hueSpectrum),
                        center: .center
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, .white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: wheelSize / 2
                    )
                )

            Circle()
                .fill(Color.black.opacity(1 - brightness))
                .blendMode(.multiply)
                .allowsHitTesting(false)

            Circle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)

            wheelKnob
        }
        .frame(width: wheelSize, height: wheelSize)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    updateHueSaturation(at: value.location, in: CGSize(width: wheelSize, height: wheelSize))
                }
        )
        .accessibilityLabel("Color wheel")
        .accessibilityValue(hex)
    }

    private var wheelKnob: some View {
        let radius = saturation * (wheelSize / 2 - knobSize / 2)
        let angle = hue * 2 * Double.pi - Double.pi / 2
        let x = cos(angle) * radius
        let y = sin(angle) * radius

        return Circle()
            .fill(selectedColor)
            .frame(width: knobSize, height: knobSize)
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }

    private var brightnessSlider: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let travel = max(width - sliderHeight, 1)
            let knobX = CGFloat(brightness) * travel + sliderHeight / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: hue, saturation: saturation, brightness: 0.05),
                                fullBrightColor,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                Circle()
                    .fill(selectedColor)
                    .frame(width: sliderHeight, height: sliderHeight)
                    .overlay {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .position(x: knobX, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let normalized = (value.location.x - sliderHeight / 2) / travel
                        brightness = min(max(Double(normalized), 0.08), 1)
                        commitHex()
                    }
            )
        }
        .frame(height: sliderHeight)
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(brightness * 100)) percent")
    }

    private var previewRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selectedColor)
                .frame(width: 44, height: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Selected color")
                    .font(.subheadline.weight(.medium))
                Text(hex.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func updateHueSaturation(at location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        let maxRadius = size.width / 2 - knobSize / 2

        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }

        hue = angle / (2 * .pi)
        saturation = min(max(distance / maxRadius, 0), 1)
        commitHex()
    }

    private func apply(hex: String) {
        guard let components = ColorHSB.from(hex: hex) else { return }
        let nextHue = components.hue
        let nextSat = components.saturation
        let nextBright = max(components.brightness, 0.08)
        // Avoid fighting in-progress drags when hex round-trips to an equivalent color.
        if abs(nextHue - hue) < 0.0001,
           abs(nextSat - saturation) < 0.0001,
           abs(nextBright - brightness) < 0.0001 {
            return
        }
        hue = nextHue
        saturation = nextSat
        brightness = nextBright
    }

    private func commitHex() {
        let next = ColorHSB(hue: hue, saturation: saturation, brightness: brightness).hexString
        guard next.caseInsensitiveCompare(hex) != .orderedSame else { return }
        isSyncingFromBinding = true
        hex = next
        Task { @MainActor in
            isSyncingFromBinding = false
        }
    }

    private static let hueSpectrum: [Color] = (0...12).map { step in
        Color(hue: Double(step) / 12, saturation: 1, brightness: 1)
    }
}

private struct ColorHSB {
    var hue: Double
    var saturation: Double
    var brightness: Double

    var hexString: String {
        let color = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    static func from(hex: String) -> ColorHSB? {
        guard let color = UIColor(hex: hex) else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return nil
        }
        return ColorHSB(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness))
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let rgb = UInt64(sanitized, radix: 16) else { return nil }
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var hex = MemberColor.blue.hex
        var body: some View {
            Form {
                Section("Calendar Color") {
                    ColorWheelPicker(hex: $hex)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    return PreviewHost()
}
