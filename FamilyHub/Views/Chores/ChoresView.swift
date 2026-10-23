import SwiftUI
import SwiftData
import UserNotifications

struct ChoresView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Chore.dueDate) private var chores: [Chore]
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]

    @State private var showingAddChore = false
    @State private var showCompleted = false
    @State private var selectedMemberID: UUID?
    @State private var preselectedMember: FamilyMember?
    @State private var notificationsAllowed = false
    @State private var choreToInspect: Chore?

    private var visibleChores: [Chore] {
        chores.filter { showCompleted || !$0.isCompleted }
    }

    private var filteredChores: [Chore] {
        guard let selectedMemberID else { return visibleChores }
        return visibleChores.filter { $0.assignedMember?.id == selectedMemberID }
    }

    private var unassignedChores: [Chore] {
        visibleChores.filter { $0.assignedMember == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if !members.isEmpty {
                    Section {
                        memberSlotPicker
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowBackground(Color.clear)
                    }

                    if !notificationsAllowed {
                        Section {
                            Button {
                                Task { await requestNotifications() }
                            } label: {
                                Label("Enable chore reminders", systemImage: "bell.badge")
                            }
                        } footer: {
                            Text("Reminders notify this device for the assigned tribe member’s chores (8:00 AM on the due date).")
                        }
                    }
                }

                if selectedMemberID == nil {
                    everyoneSlots
                } else if let member = members.first(where: { $0.id == selectedMemberID }) {
                    memberSlotSection(member: member, chores: filteredChores)
                }

                if filteredChores.isEmpty && (selectedMemberID != nil || (unassignedChores.isEmpty && members.allSatisfy { choresFor($0).isEmpty })) {
                    Section {
                        ContentUnavailableView(
                            selectedMemberID == nil ? "No Chores" : "Empty Slot",
                            systemImage: "checklist",
                            description: Text(selectedMemberID == nil
                                ? "Add a chore and assign it to a tribe member"
                                : "No chores assigned to this person yet")
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Chores")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        preselectedMember = members.first(where: { $0.id == selectedMemberID })
                        showingAddChore = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Toggle("Show done", isOn: $showCompleted)
                        .toggleStyle(.button)
                }
            }
            .sheet(isPresented: $showingAddChore) {
                AddChoreView(
                    members: members,
                    initialMember: preselectedMember
                )
            }
            .sheet(item: $choreToInspect) { chore in
                ChoreDetailView(chore: chore)
            }
            .task {
                await refreshNotificationStatus()
                await ChoreReminderService.rescheduleAll(for: chores.filter { !$0.isCompleted })
            }
            .onChange(of: chores.count) { _, _ in
                Task {
                    await ChoreReminderService.rescheduleAll(for: chores.filter { !$0.isCompleted })
                }
            }
        }
    }

    // MARK: - Member picker

    private var memberSlotPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selectedMemberID = nil
                } label: {
                    Text("Everyone")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedMemberID == nil ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(selectedMemberID == nil ? Color.accentColor : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)

                ForEach(members, id: \.id) { member in
                    Button {
                        selectedMemberID = member.id
                    } label: {
                        HStack(spacing: 6) {
                            MemberChip(
                                member: member,
                                isSelected: selectedMemberID == member.id
                            )
                            let count = choresFor(member).filter { !$0.isCompleted }.count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(member.color)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Slots

    @ViewBuilder
    private var everyoneSlots: some View {
        if !unassignedChores.isEmpty {
            Section {
                ForEach(unassignedChores, id: \.id) { chore in
                    ChoreRow(chore: chore, onComplete: completeChore) {
                        choreToInspect = chore
                    }
                }
                .onDelete { offsets in deleteChores(from: unassignedChores, at: offsets) }
            } header: {
                Label("Unassigned", systemImage: "person.slash")
            }
        }

        ForEach(members, id: \.id) { member in
            let memberChores = choresFor(member)
            if !memberChores.isEmpty || selectedMemberID == member.id {
                memberSlotSection(member: member, chores: memberChores)
            }
        }
    }

    private func memberSlotSection(member: FamilyMember, chores memberChores: [Chore]) -> some View {
        Section {
            if memberChores.isEmpty {
                Text("No chores in \(member.name)’s slot")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(memberChores, id: \.id) { chore in
                    ChoreRow(chore: chore, onComplete: completeChore) {
                        choreToInspect = chore
                    }
                }
                .onDelete { offsets in deleteChores(from: memberChores, at: offsets) }
            }
        } header: {
            HStack(spacing: 8) {
                MemberAvatar(member: member, size: 22, showColorRing: false)
                Text("\(member.name)’s Chores")
                Spacer()
                let openCount = memberChores.filter { !$0.isCompleted }.count
                if openCount > 0 {
                    Text("\(openCount) open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if memberChores.contains(where: { $0.remindersEnabled && !$0.isCompleted }) {
                Text("Reminders set for assigned chores on this device.")
            }
        }
    }

    private func choresFor(_ member: FamilyMember) -> [Chore] {
        visibleChores.filter { $0.assignedMember?.id == member.id }
    }

    // MARK: - Actions

    private func completeChore(_ chore: Chore) {
        if chore.isCompleted {
            chore.isCompleted = false
            chore.completedAt = nil
            chore.touchForSync()
            Task { await ChoreReminderService.scheduleReminder(for: chore) }
        } else {
            chore.markComplete()
            Task { await ChoreReminderService.cancelReminder(for: chore.id) }
            if chore.frequency != .once {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard chore.isCompleted else { return }
                    chore.resetForNextOccurrence()
                    await ChoreReminderService.scheduleReminder(for: chore)
                }
            }
        }
    }

    private func deleteChores(from list: [Chore], at offsets: IndexSet) {
        for index in offsets {
            let chore = list[index]
            Task { await ChoreReminderService.cancelReminder(for: chore.id) }
            FamilySyncService.shared.noteLocalDeletion(prefix: "chore", id: chore.id)
            modelContext.delete(chore)
        }
    }

    private func requestNotifications() async {
        notificationsAllowed = await ChoreReminderService.requestPermission()
        if notificationsAllowed {
            await ChoreReminderService.rescheduleAll(for: chores.filter { !$0.isCompleted })
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsAllowed = true
        default:
            notificationsAllowed = false
        }
    }
}

struct ChoreRow: View {
    @Bindable var chore: Chore
    let onComplete: (Chore) -> Void
    let onOpenDetails: () -> Void

    private var isOverdue: Bool {
        !chore.isCompleted && chore.dueDate < Date().startOfDay
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onComplete(chore)
            } label: {
                Image(systemName: chore.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chore.isCompleted ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(chore.title)
                    .strikethrough(chore.isCompleted)
                    .foregroundStyle(chore.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    Text(chore.dueDate.formatted())
                        .font(.caption)
                        .foregroundStyle(isOverdue ? .red : .secondary)

                    Text(chore.frequency.label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())

                    if !chore.components.isEmpty {
                        Text("\(chore.completedComponentCount)/\(chore.components.count) steps")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if chore.remindersEnabled && chore.assignedMember != nil && !chore.isCompleted {
                        Label("Reminder", systemImage: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                if let member = chore.assignedMember {
                    HStack(spacing: 4) {
                        MemberAvatar(member: member, size: 18, showColorRing: false)
                        Text(member.name)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(member.color)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(member.color.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onOpenDetails()
            }
            .accessibilityHint("Double tap to view steps and instructions")
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ChoresView()
        .modelContainer(for: [Chore.self, FamilyMember.self], inMemory: true)
}
