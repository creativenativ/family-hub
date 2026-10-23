import SwiftUI
import UIKit

/// A part of the app whose color can be customized in Settings.
enum ThemeRole: String, CaseIterable, Identifiable, Codable {
    case accent
    case accentEnd
    case badge
    case badgeEnd
    case today
    case event
    case chore

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accent: "Buttons & highlights"
        case .accentEnd: "Gradient blend"
        case .badge: "Notification bubbles"
        case .badgeEnd: "Bubble blend"
        case .today: "Today & selected day"
        case .event: "Events"
        case .chore: "Chores"
        }
    }

    var detail: String {
        switch self {
        case .accent: "Buttons, switches, the selected tab and links."
        case .accentEnd: "Second color in buttons and bubbles that use a gradient."
        case .badge: "Unread counts and alert bubbles."
        case .badgeEnd: "Second color in notification bubbles."
        case .today: "The outline around today and the day you pick."
        case .event: "Events with no person or tribe color."
        case .chore: "Chores with no person assigned."
        }
    }

    static let general: [ThemeRole] = [.accent, .accentEnd, .badge, .badgeEnd]
    static let calendar: [ThemeRole] = [.today, .event, .chore]
}

struct ThemePreset: Identifiable {
    let id: String
    let name: String
    let colors: [ThemeRole: String]

    static let hearth = ThemePreset(id: "hearth", name: "Hearth", colors: [
        .accent: "#005667", .accentEnd: "#2A3723",
        .badge: "#B78819", .badgeEnd: "#9A6724",
        .today: "#005667", .event: "#243F46", .chore: "#9A6724",
    ])
    static let lagoon = ThemePreset(id: "lagoon", name: "Lagoon & Brass", colors: [
        .accent: "#005667", .accentEnd: "#243F46",
        .badge: "#B78819", .badgeEnd: "#9A6724",
        .today: "#243F46", .event: "#005667", .chore: "#B78819",
    ])
    static let sage = ThemePreset(id: "sage", name: "Sage Kitchen", colors: [
        .accent: "#2A3723", .accentEnd: "#0C0A08",
        .badge: "#DCBC98", .badgeEnd: "#B9BBA8",
        .today: "#2A3723", .event: "#2A3723", .chore: "#B9BBA8",
    ])
    static let classic = ThemePreset(id: "classic", name: "Classic", colors: [
        .accent: "#007AFF", .accentEnd: "#5AC8FA",
        .badge: "#FF3B30", .badgeEnd: "#FF2D55",
        .today: "#007AFF", .event: "#8E8E93", .chore: "#8E8E93",
    ])

    static let all: [ThemePreset] = [.hearth, .lagoon, .sage, .classic]
}

/// The app's color theme. Read colors from `ThemeStore.shared` inside a view's body and the
/// view updates when the theme changes.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    /// Colors offered in pickers: both inspiration palettes, then the classic set.
    static let swatches: [String] = [
        "#243F46", "#005667", "#B78819", "#9A6724", "#2F302A",
        "#0C0A08", "#2A3723", "#B9BBA8", "#E8E5DD", "#DCBC98",
    ] + MemberColor.allCases.map(\.hex)

    private(set) var presetID: String
    private(set) var hexes: [ThemeRole: String]

    private init() {
        let defaults = UserDefaults.standard
        presetID = defaults.string(forKey: "Theme.preset") ?? ThemePreset.hearth.id
        let stored = (defaults.dictionary(forKey: "Theme.colors") as? [String: String]) ?? [:]
        var hexes = ThemePreset.hearth.colors
        for (key, value) in stored {
            if let role = ThemeRole(rawValue: key) { hexes[role] = value }
        }
        self.hexes = hexes
        applyUIKitAppearance()
    }

    var presetName: String {
        ThemePreset.all.first { $0.id == presetID }?.name ?? "Custom"
    }

    // MARK: Colors

    func hex(_ role: ThemeRole) -> String {
        hexes[role] ?? ThemePreset.hearth.colors[role] ?? "#005667"
    }

    func color(_ role: ThemeRole) -> Color {
        Color(uiColor: Self.adaptive(hex(role)))
    }

    var accent: Color { color(.accent) }

    var accentGradient: LinearGradient {
        LinearGradient(colors: [color(.accent), color(.accentEnd)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var badgeGradient: LinearGradient {
        LinearGradient(colors: [color(.badge), color(.badgeEnd)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Readable text on top of the notification bubble colors.
    var badgeText: Color {
        Self.prefersDarkText(on: hex(.badge)) ? Color(hex: "#0C0A08") ?? .black : .white
    }

    // MARK: Changing the theme

    func apply(_ preset: ThemePreset) {
        hexes = preset.colors
        presetID = preset.id
        persist()
    }

    func set(_ role: ThemeRole, hex: String) {
        hexes[role] = hex.uppercased()
        presetID = ThemePreset.all.first { $0.colors == hexes }?.id ?? "custom"
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(presetID, forKey: "Theme.preset")
        defaults.set(Dictionary(uniqueKeysWithValues: hexes.map { ($0.key.rawValue, $0.value) }), forKey: "Theme.colors")
        applyUIKitAppearance()
    }

    /// UIKit-drawn pieces SwiftUI can't style directly (tab bar badges).
    private func applyUIKitAppearance() {
        let badge = Self.adaptive(hex(.badge))
        let text: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor(badgeText)]
        let appearance = UITabBarAppearance()
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            for state in [item.normal, item.selected] {
                state.badgeBackgroundColor = badge
                state.badgeTextAttributes = text
            }
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBarItem.appearance().badgeColor = badge
    }

    // MARK: Helpers

    /// Very dark colors get lifted in dark mode so they stay visible on black.
    nonisolated static func adaptive(_ hex: String) -> UIColor {
        let base = UIColor(themeHex: hex) ?? .systemTeal
        return UIColor { traits in
            guard traits.userInterfaceStyle == .dark, luminance(of: base) < 0.18 else { return base }
            return base.blended(with: .white, amount: 0.38)
        }
    }

    nonisolated static func prefersDarkText(on hex: String) -> Bool {
        guard let color = UIColor(themeHex: hex) else { return false }
        return luminance(of: color) > 0.55
    }

    nonisolated static func luminance(of color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }
}

extension Color {
    /// The theme's accent; use in place of `Color.accentColor`.
    @MainActor static var themeAccent: Color { ThemeStore.shared.accent }

    /// Black or white, whichever reads better on this color.
    var contrastingText: Color {
        ThemeStore.luminance(of: UIColor(self)) > 0.55 ? .black : .white
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((min(max(r, 0), 1) * 255).rounded()),
                      Int((min(max(g, 0), 1) * 255).rounded()),
                      Int((min(max(b, 0), 1) * 255).rounded()))
    }
}

extension UIColor {
    convenience init?(themeHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            alpha: a1
        )
    }
}

/// A notification count bubble in the theme's badge gradient.
struct ThemeBadge: View {
    let count: Int
    var maximum = 99

    var body: some View {
        let theme = ThemeStore.shared
        Text(count > maximum ? "\(maximum)+" : "\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(theme.badgeText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.badgeGradient))
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
    }
}
