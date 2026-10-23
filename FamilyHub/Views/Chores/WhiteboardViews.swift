import SwiftUI
import SwiftData

// MARK: - Marker look

enum Marker {
    /// Dry-erase inks, tuned to the app palette.
    static let inks: [(name: String, hex: String)] = [
        ("Black", "#1F2328"),
        ("Teal", "#005667"),
        ("Green", "#2A3723"),
        ("Red", "#B3261E"),
        ("Brown", "#9A6724"),
    ]
    static let defaultInk = "#1F2328"

    static func color(_ hex: String) -> Color {
        Color(hex: hex.isEmpty ? defaultInk : hex) ?? .black
    }

    static func font(_ size: CGFloat, wide: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(wide ? "MarkerFelt-Wide" : "MarkerFelt-Thin", size: size, relativeTo: style)
    }
}

/// The board stays white in dark mode, like a real whiteboard.
struct WhiteboardSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.995), Color(white: 0.955)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                // Glare from the room lights.
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.7), .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.35)
                    .rotationEffect(.degrees(18))
                    .offset(x: proxy.size.width * 0.55, y: -proxy.size.height * 0.1)
                    .frame(height: proxy.size.height * 1.2)
                    .blendMode(.screen)
                }
                .clipped()
            }
            .overlay {
                // Faint ghosting from old marker.
                Canvas { context, size in
                    let ghost = Color(white: 0.5).opacity(0.05)
                    for index in 0..<6 {
                        let y = size.height * (0.15 + Double(index) * 0.14)
                        var path = Path()
                        path.move(to: CGPoint(x: size.width * 0.12, y: y))
                        path.addQuadCurve(
                            to: CGPoint(x: size.width * 0.78, y: y + 6),
                            control: CGPoint(x: size.width * 0.45, y: y - 10)
                        )
                        context.stroke(path, with: .color(ghost), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    }
                }
            }
            .padding(10)
            .background {
                // Brushed aluminum frame.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.86), Color(white: 0.66), Color(white: 0.8), Color(white: 0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(white: 0.55).opacity(0.6), lineWidth: 1)
                    .padding(10)
            }
    }
}

/// A slightly wonky square, the way people draw checkboxes with a marker.
struct HandDrawnBox: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1.5, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + 0.5, y: rect.maxY - 1.5))
        path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY + 0.5))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 1))
        return path
    }
}

struct HandDrawnCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.5))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.85))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + rect.width * 0.15, y: rect.minY - rect.height * 0.2),
            control: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + rect.height * 0.3)
        )
        return path
    }
}

/// A quick marker line through finished chores.
struct ScribbleStrike: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: rect.minX - 2, y: y + 1))
        path.addCurve(
            to: CGPoint(x: rect.maxX + 3, y: y - 1),
            control1: CGPoint(x: rect.minX + rect.width * 0.35, y: y - 3),
            control2: CGPoint(x: rect.minX + rect.width * 0.65, y: y + 3)
        )
        return path
    }
}

struct MarkerCheckbox: View {
    let isChecked: Bool
    let ink: Color

    var body: some View {
        ZStack {
            HandDrawnBox()
                .stroke(ink.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            if isChecked {
                HandDrawnCheck()
                    .stroke(Marker.color("#2A3723"), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 20, height: 20)
        .padding(4)
        .contentShape(Rectangle())
    }
}

/// A round fridge-style magnet with a member's initial.
struct BoardMagnet: View {
    let label: String
    let color: Color
    var size: CGFloat = 30
    var isSelected = false

    var body: some View {
        Text(label)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(color.contrastingText)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0.75), color], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
                    .shadow(color: .black.opacity(0.3), radius: isSelected ? 4 : 2, y: isSelected ? 3 : 1.5)
            }
            .overlay {
                Circle().strokeBorder(Color.black.opacity(isSelected ? 0.6 : 0), lineWidth: 2)
            }
            .scaleEffect(isSelected ? 1.12 : 1)
    }
}

/// Markers and an eraser sitting on the board's ledge.
struct MarkerTray: View {
    let onPickMarker: (String) -> Void
    let onEraser: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Marker.inks, id: \.hex) { ink in
                Button {
                    onPickMarker(ink.hex)
                } label: {
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(Color(white: 0.96))
                            .frame(width: 30, height: 12)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Marker.color(ink.hex)).frame(width: 6)
                            }
                            .clipShape(Capsule())
                        Capsule()
                            .fill(Marker.color(ink.hex))
                            .frame(width: 18, height: 14)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Write a new chore in \(ink.name.lowercased())")
            }

            Spacer(minLength: 4)

            Button(action: onEraser) {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.25)).frame(width: 40, height: 9)
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.85)).frame(width: 40, height: 6)
                }
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eraser: clear finished chores")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.6)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Dragging items around the board

/// Long-press to pick an item up, then drag it somewhere else on the board.
struct BoardDraggable: ViewModifier {
    let onMoved: (CGSize) -> Void

    @GestureState private var offset: CGSize = .zero
    @GestureState private var isLifted = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isLifted ? 1.06 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.2 : 0), radius: 8, y: 6)
            .offset(offset)
            .zIndex(isLifted ? 10 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isLifted)
            .sensoryFeedback(.selection, trigger: isLifted)
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture())
                    .updating($offset) { value, state, _ in
                        if case .second(true, let drag?) = value { state = drag.translation }
                    }
                    .updating($isLifted) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }
                    .onEnded { value in
                        if case .second(true, let drag?) = value { onMoved(drag.translation) }
                    }
            )
            .accessibilityHint("Touch and hold, then drag to move it on the board.")
    }
}

extension View {
    func boardDraggable(onMoved: @escaping (CGSize) -> Void) -> some View {
        modifier(BoardDraggable(onMoved: onMoved))
    }
}

// MARK: - Layout

enum BoardLayout {
    /// Board coordinates are fractions of the board's width on both axes,
    /// so a board looks the same on every screen size.
    static let itemWidth = 0.44
    static let columns: [Double] = [0.04, 0.52]
    static let firstRow = 0.40
    static let rowHeight = 0.10
    static let headerBottom = 0.30

    /// Places chores that haven't been put anywhere yet into the first free slots.
    static func positions(for chores: [Chore], notes: [BoardNote]) -> [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        var taken: [CGPoint] = notes.map { CGPoint(x: $0.boardX, y: $0.boardY) }
        for chore in chores where chore.boardX >= 0 && chore.boardY >= 0 {
            let point = CGPoint(x: chore.boardX, y: chore.boardY)
            result[chore.id] = point
            taken.append(point)
        }

        var row = 0
        for chore in chores.sorted(by: { $0.createdAt < $1.createdAt }) where result[chore.id] == nil {
            while true {
                let column = columns[row % columns.count]
                let y = firstRow + Double(row / columns.count) * rowHeight
                row += 1
                let candidate = CGPoint(x: column, y: y)
                let isFree = !taken.contains { abs($0.x - candidate.x) < 0.3 && abs($0.y - candidate.y) < rowHeight * 0.8 }
                if isFree {
                    result[chore.id] = candidate
                    taken.append(candidate)
                    break
                }
            }
        }
        return result
    }

    static func clamp(x: Double) -> Double { min(max(x, 0.01), 1 - itemWidth) }
    static func clamp(y: Double, boardHeight: Double) -> Double { min(max(y, headerBottom), boardHeight - 0.08) }
}

// MARK: - Starter chores

/// The usual indoor chores, grouped by room, for a fresh board.
@MainActor
enum ChoreBoardStarter {
    private struct Group {
        let heading: String
        let x: Double
        let y: Double
        let ink: String
        let chores: [(String, ChoreFrequency)]
    }

    private static let groups: [Group] = [
        Group(heading: "Kitchen", x: 0.04, y: 0.34, ink: "#005667", chores: [
            ("Do the dishes", .daily), ("Wipe counters", .daily), ("Empty dishwasher", .daily),
            ("Take out trash", .weekly), ("Clean fridge", .monthly),
        ]),
        Group(heading: "Living areas", x: 0.52, y: 0.34, ink: "#2A3723", chores: [
            ("Vacuum floors", .weekly), ("Mop floors", .weekly), ("Dust surfaces", .weekly),
            ("Tidy living room", .daily), ("Water plants", .weekly),
        ]),
        Group(heading: "Bathroom", x: 0.04, y: 0.93, ink: "#005667", chores: [
            ("Scrub toilet", .weekly), ("Clean sink & mirror", .weekly),
            ("Clean shower & tub", .weekly), ("Swap out towels", .weekly),
        ]),
        Group(heading: "Bedrooms", x: 0.52, y: 0.93, ink: "#9A6724", chores: [
            ("Make beds", .daily), ("Change sheets", .biweekly), ("Put away clothes", .daily),
        ]),
        Group(heading: "Laundry", x: 0.04, y: 1.42, ink: "#2A3723", chores: [
            ("Wash laundry", .weekly), ("Fold & put away", .weekly),
        ]),
        Group(heading: "Around the house", x: 0.52, y: 1.42, ink: "#1F2328", chores: [
            ("Wipe switches & handles", .monthly), ("Clean windows", .monthly),
        ]),
    ]

    static var allTitles: [String] { groups.flatMap { $0.chores.map(\.0) } }

    /// Fills an empty board once per device. Joiners get the owner's board through sync instead.
    static func seedIfNeeded(chores: [Chore], notes: [BoardNote], memberships: [FamilyMembership], modelContext: ModelContext) {
        let key = "ChoreBoard.seeded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let home = FamilyMembership.home(in: memberships)
        guard chores.isEmpty, notes.isEmpty, home == nil || home?.isOwner == true else { return }
        UserDefaults.standard.set(true, forKey: key)
        addMissing(existing: chores, existingNotes: notes, modelContext: modelContext)
    }

    /// Adds any starter chores (and their headings) not already on the board. Returns how many chores were added.
    @discardableResult
    static func addMissing(existing: [Chore], existingNotes: [BoardNote], modelContext: ModelContext) -> Int {
        let haveChores = Set(existing.map { $0.title.lowercased() })
        let haveNotes = Set(existingNotes.map { $0.text.lowercased() })
        let today = Calendar.current.startOfDay(for: Date())
        var added = 0

        for group in groups {
            let missing = group.chores.filter { !haveChores.contains($0.0.lowercased()) }
            guard !missing.isEmpty else { continue }
            if !haveNotes.contains(group.heading.lowercased()) {
                modelContext.insert(BoardNote(text: group.heading, boardX: group.x, boardY: group.y))
            }
            for (index, item) in group.chores.enumerated() where !haveChores.contains(item.0.lowercased()) {
                let spread = item.1 == .daily ? 0 : (index * 2) % 7
                let due = Calendar.current.date(byAdding: .day, value: spread, to: today) ?? today
                let chore = Chore(title: item.0, dueDate: due, frequency: item.1, remindersEnabled: false)
                chore.boardX = group.x
                chore.boardY = group.y + 0.09 + Double(index) * BoardLayout.rowHeight * 0.95
                chore.markerColorHex = group.ink
                modelContext.insert(chore)
                added += 1
            }
        }
        return added
    }
}
