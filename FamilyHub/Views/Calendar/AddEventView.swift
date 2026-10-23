import SwiftUI
import SwiftData

struct AddEventView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let selectedDate: Date
    let members: [FamilyMember]

    @State private var title = ""
    @State private var notes = ""
    @State private var location = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay = false
    @State private var selectedMember: FamilyMember?

    init(selectedDate: Date, members: [FamilyMember]) {
        self.selectedDate = selectedDate
        self.members = members
        let defaultStart = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let defaultEnd = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        _startDate = State(initialValue: defaultStart)
        _endDate = State(initialValue: defaultEnd)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Details") {
                    TextField("Title", text: $title)
                    TextField("Location", text: $location)
                    Toggle("All Day", isOn: $isAllDay)

                    if !isAllDay {
                        DatePicker("Starts", selection: $startDate)
                        DatePicker("Ends", selection: $endDate)
                    } else {
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                        DatePicker("Ends", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section("Assign To") {
                    if members.isEmpty {
                        Text("Add tribe members in the Tribe tab to assign events.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        memberAssignmentGrid
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEvent() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var memberAssignmentGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
            assignmentOption(
                title: "Everyone",
                isSelected: selectedMember == nil,
                color: .gray
            ) {
                selectedMember = nil
            }

            ForEach(members, id: \.id) { member in
                assignmentOption(
                    title: member.name,
                    isSelected: selectedMember?.id == member.id,
                    color: member.color,
                    member: member
                ) {
                    selectedMember = member
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
                    Image(systemName: "person.3.fill")
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

    private func saveEvent() {
        let eventStart: Date
        let eventEnd: Date

        if isAllDay {
            eventStart = startDate.startOfDay
            let lastDay = max(endDate.startOfDay, eventStart)
            eventEnd = Calendar.current.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        } else {
            eventStart = startDate
            eventEnd = max(endDate, startDate)
        }

        let event = CalendarEvent(
            title: title.trimmingCharacters(in: .whitespaces),
            startDate: eventStart,
            endDate: eventEnd,
            isAllDay: isAllDay,
            notes: notes,
            location: location,
            assignedMember: selectedMember
        )
        modelContext.insert(event)
        Task {
            _ = await ChoreReminderService.requestPermission()
            await EventReminderService.scheduleReminder(for: event)
        }
        dismiss()
    }
}
