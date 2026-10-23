import SwiftUI
import SwiftData

/// Adds a newly created or joined tribe to this device.
@MainActor
enum TribeRoster {
    /// A family tribe becomes home when there isn't one yet; anything else is calendar-only here.
    @discardableResult
    static func add(_ membership: FamilyMembership, to modelContext: ModelContext) throws -> FamilyMembership {
        let existing = try modelContext.fetch(FetchDescriptor<FamilyMembership>())
        guard !existing.contains(where: { $0.zoneName == membership.zoneName }) else {
            throw FamilyCloudError.alreadyInFamily
        }
        membership.isHome = membership.kind == .family && FamilyMembership.home(in: existing) == nil
        modelContext.insert(membership)
        try modelContext.save()
        return membership
    }
}

struct TribeComposerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case create = "Create"
        case join = "Join"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var memberships: [FamilyMembership]

    let initialKind: TribeKind?
    let onFinished: (FamilyMembership) -> Void

    @State private var service = FamilyCloudService.shared
    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var kind: TribeKind = .calendar
    @State private var colorHex = MemberColor.blue.hex
    @State private var inviteCode = ""
    @State private var errorMessage: String?

    init(initialKind: TribeKind? = nil, onFinished: @escaping (FamilyMembership) -> Void = { _ in }) {
        self.initialKind = initialKind
        self.onFinished = onFinished
    }

    private var hasHome: Bool {
        FamilyMembership.home(in: memberships) != nil
    }

    private var canSubmit: Bool {
        guard !service.isBusy, service.isiCloudAvailable else { return false }
        switch mode {
        case .create: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .join: return FamilyCloudService.isValidInviteCode(inviteCode)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                switch mode {
                case .create: createSections
                case .join: joinSections
                }

                if !service.isiCloudAvailable {
                    Section {
                        Text("Sign in to iCloud in Settings to create or join tribes.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode == .create ? "New Tribe" : "Join a Tribe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if service.isBusy {
                        ProgressView()
                    } else {
                        Button(mode == .create ? "Create" : "Join") {
                            Task { await submit() }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
            .task { await service.refreshAccountStatus() }
            .onAppear {
                kind = initialKind ?? (hasHome ? .calendar : .family)
            }
            .onChange(of: mode) { _, _ in errorMessage = nil }
        }
    }

    @ViewBuilder
    private var createSections: some View {
        Section("Name") {
            TextField(kind == .family ? "e.g. The Schwartzels" : "e.g. Work, Soccer team, Book club", text: $name)
        }

        Section {
            if hasHome {
                LabeledContent("Type") { Text(TribeKind.calendar.label) }
            } else {
                Picker("Type", selection: $kind) {
                    ForEach(TribeKind.allCases) { Text($0.label).tag($0) }
                }
            }
        } footer: {
            Text(kind == .family
                 ? "Your home tribe shares the calendar, chores, meals, groceries, budget and profiles."
                 : "A tribe calendar shares only events. Invite anyone with Tribe Time — coworkers, a team, friends anywhere.")
        }

        Section("Color") {
            TribeColorRow(selectedHex: $colorHex)
        }
    }

    @ViewBuilder
    private var joinSections: some View {
        Section {
            TextField("AB3K-9XP2", text: $inviteCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        } header: {
            Text("Invite code")
        } footer: {
            Text(hasHome
                 ? "You already have a home tribe, so you'll share only calendar events with this one."
                 : "If this is a home tribe, it becomes yours and shares everything.")
        }

        Section("Color on your wheel") {
            TribeColorRow(selectedHex: $colorHex)
        }
    }

    private func submit() async {
        errorMessage = nil
        do {
            let membership: FamilyMembership
            switch mode {
            case .create:
                membership = try await service.createFamily(named: name, kind: hasHome ? .calendar : kind)
            case .join:
                let code = FamilyCloudService.normalizeInviteCode(inviteCode)
                if memberships.contains(where: { $0.inviteCode.uppercased() == code }) {
                    throw FamilyCloudError.alreadyInFamily
                }
                membership = try await service.joinFamily(inviteCode: code)
            }
            membership.colorHex = colorHex
            try TribeRoster.add(membership, to: modelContext)
            onFinished(membership)
            dismiss()
            _ = try? await FamilySyncService.shared.syncAll(modelContext: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A row of preset colors for a tribe bubble.
struct TribeColorRow: View {
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(MemberColor.allCases) { option in
                let isSelected = option.hex.caseInsensitiveCompare(selectedHex) == .orderedSame
                Button {
                    selectedHex = option.hex
                } label: {
                    Circle()
                        .fill(Color(hex: option.hex) ?? .gray)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay {
                            Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.4 : 0), lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.rawValue.capitalized)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

#if DEBUG
/// Launch with `-seedDemoTribes` to fill the Tribe tab and calendar with sample tribes
/// (handy in the Simulator, which can't create real CloudKit tribes without iCloud).
@MainActor
enum DemoTribes {
    static func seedIfRequested(in modelContext: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedDemoTribes"),
              ((try? modelContext.fetchCount(FetchDescriptor<FamilyMembership>())) ?? 0) == 0
        else { return }

        func tribe(_ name: String, kind: TribeKind, color: MemberColor, unread: Int, home: Bool = false) -> FamilyMembership {
            let tribe = FamilyMembership(
                familyName: name,
                inviteCode: FamilyCloudService.makeInviteCode(),
                shareURLString: "",
                zoneName: "Demo-\(name)",
                zoneOwnerName: "",
                isOwner: true,
                kind: kind
            )
            tribe.isHome = home
            tribe.colorHex = color.hex
            tribe.unreadCount = unread
            modelContext.insert(tribe)
            return tribe
        }

        _ = tribe("The Schwartzels", kind: .family, color: .green, unread: 0, home: true)
        let work = tribe("Work", kind: .calendar, color: .blue, unread: 3)
        let soccer = tribe("Soccer Club", kind: .calendar, color: .orange, unread: 1)
        _ = tribe("Book Club", kind: .calendar, color: .purple, unread: 0)
        _ = tribe("Grandparents", kind: .family, color: .pink, unread: 0)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Int) -> Date {
            calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: dayOffset, to: today)!)!
        }

        let standup = CalendarEvent(title: "Team planning", startDate: at(1, 10), endDate: at(1, 11))
        standup.tribeZoneName = work.zoneName
        let trip = CalendarEvent(title: "Conference trip", startDate: at(3, 0), endDate: at(6, 0), isAllDay: true)
        trip.tribeZoneName = work.zoneName
        let practice = CalendarEvent(title: "Practice", startDate: at(2, 17), endDate: at(2, 18))
        practice.tribeZoneName = soccer.zoneName
        let dinner = CalendarEvent(title: "Family dinner", startDate: at(0, 18), endDate: at(0, 19))
        [standup, trip, practice, dinner].forEach(modelContext.insert)

        // Dad shared the trip from Work into home.
        let tripCopy = CalendarEvent(title: trip.title, startDate: trip.startDate, endDate: trip.endDate, isAllDay: true)
        tripCopy.linkedSourceEventID = trip.id
        tripCopy.linkedSourceZoneName = work.zoneName
        tripCopy.linkedSourceTribeName = work.familyName
        modelContext.insert(tripCopy)

        try? modelContext.save()
    }
}
#endif
