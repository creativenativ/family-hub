import SwiftUI
import SwiftData

struct AddChoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let members: [FamilyMember]
    var initialMember: FamilyMember? = nil

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate = Date()
    @State private var frequency: ChoreFrequency = .weekly
    @State private var selectedMember: FamilyMember?
    @State private var remindersEnabled = true
    @State private var draftComponents: [DraftChoreComponent] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Chore") {
                    TextField("Title", text: $title)
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    Picker("Repeats", selection: $frequency) {
                        ForEach(ChoreFrequency.allCases) { freq in
                            Text(freq.label).tag(freq)
                        }
                    }
                }

                Section {
                    if members.isEmpty {
                        Text("Add tribe members in the Tribe tab to assign chores to their slots.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        memberAssignmentGrid
                    }
                } header: {
                    Text("Assign To Member Slot")
                } footer: {
                    Text("Assigned chores appear in that person’s chore slot.")
                }

                if selectedMember != nil {
                    Section {
                        Toggle("Reminder notification", isOn: $remindersEnabled)
                    } header: {
                        Text("Remind \(selectedMember?.name ?? "Member")")
                    } footer: {
                        Text("Sends a reminder on this device at 8:00 AM on the due date for \(selectedMember?.name ?? "the assigned member").")
                    }
                }

                Section {
                    if draftComponents.isEmpty {
                        Text("Break the chore into steps with instructions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach($draftComponents) { $component in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Step title", text: $component.title)
                            TextField("Instructions / details", text: $component.detail, axis: .vertical)
                                .lineLimit(2...4)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        draftComponents.remove(atOffsets: offsets)
                    }

                    Button {
                        draftComponents.append(DraftChoreComponent())
                    } label: {
                        Label("Add step", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Steps & instructions")
                } footer: {
                    Text("Double-tap a chore later to review and check off each step.")
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("New Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChore() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                selectedMember = initialMember
                if initialMember != nil {
                    remindersEnabled = true
                }
            }
        }
    }

    private var memberAssignmentGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
            assignmentOption(
                title: "Unassigned",
                isSelected: selectedMember == nil,
                color: .gray
            ) {
                selectedMember = nil
                remindersEnabled = false
            }

            ForEach(members, id: \.id) { member in
                assignmentOption(
                    title: member.name,
                    isSelected: selectedMember?.id == member.id,
                    color: member.color,
                    member: member
                ) {
                    selectedMember = member
                    remindersEnabled = true
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func assignmentOption(
        title: String,
        isSelected: Bool,
        color: Color,
        member: FamilyMember? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let member {
                    MemberAvatar(member: member, size: 28, showColorRing: false)
                } else {
                    Image(systemName: "person.slash")
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(isSelected ? color.opacity(0.2) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? color : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func saveChore() {
        let components = draftComponents
            .map {
                ChoreComponent(
                    title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    detail: $0.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.title.isEmpty }
            .enumerated()
            .map { index, component in
                ChoreComponent(
                    id: component.id,
                    title: component.title,
                    detail: component.detail,
                    sortOrder: index
                )
            }

        let chore = Chore(
            title: title.trimmingCharacters(in: .whitespaces),
            dueDate: dueDate,
            frequency: frequency,
            notes: notes,
            assignedMember: selectedMember,
            remindersEnabled: remindersEnabled && selectedMember != nil,
            components: components
        )
        modelContext.insert(chore)

        Task {
            if chore.remindersEnabled {
                _ = await ChoreReminderService.requestPermission()
                await ChoreReminderService.scheduleReminder(for: chore)
            }
        }

        dismiss()
    }
}

private struct DraftChoreComponent: Identifiable {
    let id = UUID()
    var title = ""
    var detail = ""
}
