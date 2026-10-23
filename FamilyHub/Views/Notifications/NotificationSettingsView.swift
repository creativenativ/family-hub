import SwiftUI
import SwiftData

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var chores: [Chore]
    @Query private var bills: [RecurringBill]
    @Query private var events: [CalendarEvent]

    @State private var preferences = NotificationPreferences.shared
    @State private var isUpdating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose which reminders Tribe Time can send on this device. Individual chores and bills can still turn off their own reminders.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                Section("Notify me about") {
                    ForEach(NotificationCategoryKind.allCases) { kind in
                        Toggle(isOn: binding(for: kind)) {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(kind.title)
                                        .font(.title3.weight(.semibold))
                                    Text(kind.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } icon: {
                                Image(systemName: kind.systemImage)
                                    .font(.title2)
                                    .frame(width: 36, alignment: .center)
                            }
                        }
                        .padding(.vertical, 8)
                        .disabled(isUpdating)
                    }
                }

                if isUpdating {
                    Section {
                        ProgressView("Updating reminders…")
                            .font(.body)
                    }
                }
            }
            .navigationTitle("Notification Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func binding(for kind: NotificationCategoryKind) -> Binding<Bool> {
        switch kind {
        case .chores:
            Binding(
                get: { preferences.choresEnabled },
                set: { newValue in
                    preferences.choresEnabled = newValue
                    Task { await applyChange(kind: .chores, enabled: newValue) }
                }
            )
        case .bills:
            Binding(
                get: { preferences.billsEnabled },
                set: { newValue in
                    preferences.billsEnabled = newValue
                    Task { await applyChange(kind: .bills, enabled: newValue) }
                }
            )
        case .calendarEvents:
            Binding(
                get: { preferences.calendarEventsEnabled },
                set: { newValue in
                    preferences.calendarEventsEnabled = newValue
                    Task { await applyChange(kind: .calendarEvents, enabled: newValue) }
                }
            )
        }
    }

    private func applyChange(kind: NotificationCategoryKind, enabled: Bool) async {
        isUpdating = true
        defer { isUpdating = false }

        if enabled {
            _ = await ChoreReminderService.requestPermission()
        }

        switch kind {
        case .chores:
            if enabled {
                await ChoreReminderService.rescheduleAll(for: chores)
            } else {
                await ChoreReminderService.cancelAllChoreReminders()
            }
        case .bills:
            if enabled {
                await BillScheduleService.rescheduleAll(for: bills)
            } else {
                await BillScheduleService.cancelAllBillReminders()
            }
        case .calendarEvents:
            if enabled {
                await EventReminderService.rescheduleAll(for: events)
            } else {
                await EventReminderService.cancelAllEventReminders()
            }
        }
    }
}
