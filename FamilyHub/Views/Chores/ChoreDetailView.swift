import SwiftUI
import SwiftData

struct ChoreDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var chore: Chore

    @State private var showingAddStep = false
    @State private var newStepTitle = ""
    @State private var newStepDetail = ""

    private var isOverdue: Bool {
        !chore.isCompleted && chore.dueDate < Date().startOfDay
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(chore.title)
                            .font(.title2.weight(.semibold))
                            .strikethrough(chore.isCompleted)

                        HStack(spacing: 8) {
                            Label(chore.dueDate.formatted(), systemImage: "calendar")
                                .foregroundStyle(isOverdue ? .red : .secondary)
                            Text(chore.frequency.label)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                        .font(.subheadline)

                        if let member = chore.assignedMember {
                            HStack(spacing: 8) {
                                MemberAvatar(member: member, size: 28, showColorRing: false)
                                Text(member.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(member.color)
                            }
                        }

                        if !chore.notes.isEmpty {
                            Text(chore.notes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if chore.components.isEmpty {
                        Text("No steps yet. Add the first one below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(chore.components) { component in
                            Button {
                                toggleStep(component.id)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: component.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(component.isCompleted ? .green : .secondary)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(component.title)
                                            .font(.body.weight(.semibold))
                                            .strikethrough(component.isCompleted)
                                            .foregroundStyle(component.isCompleted ? .secondary : .primary)
                                            .multilineTextAlignment(.leading)

                                        if !component.detail.isEmpty {
                                            Text(component.detail)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteComponents)

                        Text("\(chore.completedComponentCount) of \(chore.components.count) steps done")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        newStepTitle = ""
                        newStepDetail = ""
                        showingAddStep = true
                    } label: {
                        Label("Add step", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Steps & instructions")
                } footer: {
                    Text("Tap a step to mark it done. Completing every step marks the chore complete. Double-tap a chore in the list to open this screen.")
                }
            }
            .navigationTitle("Chore Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddStep) {
                NavigationStack {
                    Form {
                        Section("Step") {
                            TextField("Title", text: $newStepTitle)
                            TextField("Instructions / details", text: $newStepDetail, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }
                    .navigationTitle("Add Step")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingAddStep = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") { addStep() }
                                .disabled(newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func toggleStep(_ id: UUID) {
        let wasCompleted = chore.isCompleted
        chore.toggleComponent(id: id)

        if chore.isCompleted && !wasCompleted {
            Task { await ChoreReminderService.cancelReminder(for: chore.id) }
            if chore.frequency != .once {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard chore.isCompleted else { return }
                    chore.resetForNextOccurrence()
                    await ChoreReminderService.scheduleReminder(for: chore)
                }
            }
        } else if !chore.isCompleted && wasCompleted {
            Task { await ChoreReminderService.scheduleReminder(for: chore) }
        }
    }

    private func addStep() {
        let title = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var updated = chore.components
        updated.append(
            ChoreComponent(
                title: title,
                detail: newStepDetail.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: updated.count
            )
        )
        chore.components = updated
        showingAddStep = false
    }

    private func deleteComponents(at offsets: IndexSet) {
        var updated = chore.components
        updated.remove(atOffsets: offsets)
        chore.components = updated
    }
}
