import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @AppStorage("Calendar.showChores") private var showsChoresOnCalendar = true

    var body: some View {
        let theme = ThemeStore.shared
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ThemePreset.all) { preset in
                                PresetCard(preset: preset, isSelected: theme.presetID == preset.id) {
                                    withAnimation(.easeInOut(duration: 0.25)) { theme.apply(preset) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Theme")
                } footer: {
                    Text(theme.presetID == "custom" ? "You've customized your colors." : "Pick a starting point, then fine-tune any color below.")
                }

                Section("App colors") {
                    ForEach(ThemeRole.general) { role in
                        NavigationLink {
                            ThemeColorPickerView(role: role)
                        } label: {
                            ThemeRoleRow(role: role)
                        }
                    }
                }

                Section {
                    Toggle("Show chores on calendar", isOn: $showsChoresOnCalendar)
                    ForEach(ThemeRole.calendar) { role in
                        NavigationLink {
                            ThemeColorPickerView(role: role)
                        } label: {
                            ThemeRoleRow(role: role)
                        }
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Long-press any event or chore on the calendar to give it its own color. People and tribes keep the colors set on their profiles.")
                }

                Section("App icon") {
                    AppIconPicker()
                }

                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                }

                Section {
                    Button("Reset colors to Hearth", role: .destructive) {
                        confirmReset = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset all colors?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { theme.apply(.hearth) }
            }
        }
        .tint(theme.accent)
    }
}

private struct PresetCard: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void

    private func swatch(_ role: ThemeRole) -> Color {
        Color(hex: preset.colors[role] ?? "#000000") ?? .black
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [swatch(.accent), swatch(.accentEnd)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    HStack(spacing: -6) {
                        ForEach([ThemeRole.badge, .event, .chore], id: \.self) { role in
                            Circle()
                                .fill(swatch(role))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                        }
                    }
                    .padding(8)
                }
                .frame(width: 118, height: 74)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2.5)
                }

                HStack(spacing: 4) {
                    Text(preset.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ThemeRoleRow: View {
    let role: ThemeRole

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ThemeStore.shared.color(role))
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
            Text(role.label)
        }
    }
}

/// Palette swatches plus the system picker for anything else.
struct ThemeColorPickerView: View {
    let role: ThemeRole

    var body: some View {
        let theme = ThemeStore.shared
        Form {
            Section {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.color(role))
                    .frame(height: 64)
                    .overlay {
                        Text(theme.hex(role))
                            .font(.headline.monospaced())
                            .foregroundStyle(theme.color(role).contrastingText)
                    }
            } footer: {
                Text(role.detail)
            }

            Section("Palette") {
                SwatchGrid(selectedHex: theme.hex(role)) { hex in
                    theme.set(role, hex: hex)
                }
            }

            Section {
                ColorPicker(
                    "Any color…",
                    selection: Binding(
                        get: { Color(hex: theme.hex(role)) ?? .black },
                        set: { theme.set(role, hex: $0.hexString) }
                    ),
                    supportsOpacity: false
                )
            }
        }
        .navigationTitle(role.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A grid of the theme swatches with a checkmark on the current one.
struct SwatchGrid: View {
    let selectedHex: String?
    let onPick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
            ForEach(ThemeStore.swatches, id: \.self) { hex in
                let isSelected = selectedHex?.caseInsensitiveCompare(hex) == .orderedSame
                let color = Color(hex: hex) ?? .gray
                Button {
                    onPick(hex)
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(color.contrastingText)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hex)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AppIconPicker: View {
    private struct Option: Identifiable {
        let id: String
        let name: String
        /// nil = the primary icon.
        let iconName: String?
        let preview: String
    }

    private let options = [
        Option(id: "hearth", name: "Hearth", iconName: nil, preview: "IconPreviewHearth"),
        Option(id: "brass", name: "Brass", iconName: "AppIconBrass", preview: "IconPreviewBrass"),
        Option(id: "linen", name: "Linen", iconName: "AppIconLinen", preview: "IconPreviewLinen"),
        Option(id: "midnight", name: "Midnight", iconName: "AppIconMidnight", preview: "IconPreviewMidnight"),
        Option(id: "sage", name: "Sage", iconName: "AppIconSage", preview: "IconPreviewSage"),
    ]

    @State private var current = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(options) { option in
                    let isSelected = current == option.iconName
                    Button {
                        choose(option)
                    } label: {
                        VStack(spacing: 6) {
                            Image(option.preview)
                                .resizable()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(isSelected ? Color.primary : Color(.separator), lineWidth: isSelected ? 2.5 : 0.5)
                                }
                            Text(option.name)
                                .font(.caption2.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.name) icon")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func choose(_ option: Option) {
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "This device can't change the app icon."
            return
        }
        UIApplication.shared.setAlternateIconName(option.iconName) { error in
            Task { @MainActor in
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    current = option.iconName
                    errorMessage = nil
                }
            }
        }
    }
}

/// Picks a personal color for one calendar item. Passing nil restores the default.
struct ItemColorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let currentHex: String
    let onPick: (String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SwatchGrid(selectedHex: currentHex.isEmpty ? nil : currentHex) { hex in
                        onPick(hex)
                        dismiss()
                    }
                } footer: {
                    Text("Only you see this color.")
                }
                Section {
                    ColorPicker(
                        "Any color…",
                        selection: Binding(
                            get: { Color(hex: currentHex) ?? ThemeStore.shared.color(.event) },
                            set: { onPick($0.hexString) }
                        ),
                        supportsOpacity: false
                    )
                    if !currentHex.isEmpty {
                        Button("Use default color") {
                            onPick(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
