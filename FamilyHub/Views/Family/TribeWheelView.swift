import SwiftUI

/// Home tribe in the middle, every other tribe calendar orbiting it as a bubble.
/// Drag anywhere on the wheel to spin it; a flick keeps it turning for a moment.
struct TribeWheelView: View {
    let home: FamilyMembership?
    let others: [FamilyMembership]
    let onSelect: (FamilyMembership) -> Void
    let onSelectEmptyHome: () -> Void
    let onAdd: () -> Void

    @State private var rotation: Double = 0
    @State private var dragStartRotation: Double?
    @State private var dragStartAngle: Double = 0

    private let centerSize: CGFloat = 100

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let slots = others.count + 1 // + the add bubble
            let bubble = bubbleSize(side: side, slots: slots)
            // Leave room for each bubble's name label below it.
            let radius = side / 2 - bubble / 2 - 18

            ZStack {
                Circle()
                    .strokeBorder(Color(.separator).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                centerBubble
                    .position(center)

                ForEach(Array(others.enumerated()), id: \.element.id) { index, tribe in
                    Button { onSelect(tribe) } label: {
                        TribeBubble(tribe: tribe, size: bubble)
                    }
                    .buttonStyle(BubbleButtonStyle())
                    .position(position(index: index, slots: slots, radius: radius, center: center))
                }

                Button(action: onAdd) {
                    AddTribeBubble(size: bubble)
                }
                .buttonStyle(BubbleButtonStyle())
                .position(position(index: others.count, slots: slots, radius: radius, center: center))
                .accessibilityLabel("Add a tribe calendar")
            }
            .contentShape(Rectangle())
            .gesture(spinGesture(center: center))
        }
        .frame(height: 390)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: others.map(\.id))
    }

    @ViewBuilder
    private var centerBubble: some View {
        if let home {
            Button { onSelect(home) } label: {
                TribeBubble(tribe: home, size: centerSize, isHome: true)
            }
            .buttonStyle(BubbleButtonStyle())
        } else {
            Button(action: onSelectEmptyHome) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                        Circle()
                            .strokeBorder(ThemeStore.shared.accentGradient, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        Image(systemName: "house.fill")
                            .font(.title)
                            .foregroundStyle(ThemeStore.shared.accentGradient)
                    }
                    .frame(width: centerSize, height: centerSize)
                    Text("Set up home")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(BubbleButtonStyle())
        }
    }

    private func bubbleSize(side: CGFloat, slots: Int) -> CGFloat {
        let ring = (side / 2 - 50) * 2 * .pi
        return min(68, max(40, ring / CGFloat(max(slots, 1)) * 0.55))
    }

    private func position(index: Int, slots: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = rotation + (2 * .pi * Double(index) / Double(max(slots, 1))) - .pi / 2
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }

    private func angle(of point: CGPoint, around center: CGPoint) -> Double {
        atan2(Double(point.y - center.y), Double(point.x - center.x))
    }

    private func spinGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragStartRotation == nil {
                    dragStartRotation = rotation
                    dragStartAngle = angle(of: value.startLocation, around: center)
                }
                let delta = angle(of: value.location, around: center) - dragStartAngle
                rotation = (dragStartRotation ?? rotation) + delta
            }
            .onEnded { value in
                let predicted = angle(of: value.predictedEndLocation, around: center)
                var fling = predicted - angle(of: value.location, around: center)
                // Take the short way around the atan2 seam.
                if fling > .pi { fling -= 2 * .pi }
                if fling < -.pi { fling += 2 * .pi }
                dragStartRotation = nil
                withAnimation(.easeOut(duration: 0.9)) {
                    rotation += fling * 1.5
                }
            }
    }
}

struct TribeBubble: View {
    let tribe: FamilyMembership
    let size: CGFloat
    var isHome = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tribe.color.opacity(0.75), tribe.color],
                            center: UnitPoint(x: 0.3, y: 0.25),
                            startRadius: 0,
                            endRadius: size * 0.8
                        )
                    )
                    .overlay {
                        // Glossy highlight so it reads as a bubble.
                        Circle()
                            .fill(.white.opacity(0.35))
                            .frame(width: size * 0.32, height: size * 0.22)
                            .blur(radius: size * 0.04)
                            .offset(x: -size * 0.16, y: -size * 0.22)
                    }
                    .overlay {
                        VStack(spacing: 0) {
                            Image(systemName: isHome ? "house.fill" : "calendar")
                                .font(.system(size: size * 0.2, weight: .semibold))
                            if size >= 56 {
                                Text(tribe.initials)
                                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .frame(width: size, height: size)
                    .shadow(color: tribe.color.opacity(0.35), radius: 8, y: 4)

                if tribe.unreadCount > 0 {
                    ThemeBadge(count: tribe.unreadCount)
                        .offset(x: 4, y: -2)
                }
            }

            Text(tribe.familyName)
                .font(isHome ? .subheadline.weight(.semibold) : .caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: max(size + 24, 72))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tribe.familyName)\(tribe.unreadCount > 0 ? ", \(tribe.unreadCount) new" : "")")
    }
}

private struct AddTribeBubble: View {
    let size: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                Circle()
                    .strokeBorder(ThemeStore.shared.accentGradient, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                Image(systemName: "plus")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(ThemeStore.shared.accentGradient)
            }
            .frame(width: size, height: size)
            Text("Add")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct BubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
