import SwiftUI
import SwiftData

struct FamilyMembersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query private var memberships: [FamilyMembership]

    @State private var showingAddMember = false
    @State private var memberToEdit: FamilyMember?
    @State private var acceptance = FamilyShareAcceptanceCenter.shared

    var body: some View {
        NavigationStack {
            List {
                FamilySharingSection()

                Section("Profiles") {
                    if members.isEmpty {
                        Text("Add color-coded profiles for the calendar and chores.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members, id: \.id) { member in
                            Button {
                                memberToEdit = member
                            } label: {
                                HStack(spacing: 12) {
                                    MemberAvatar(member: member, size: 44)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(member.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)

                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(member.color)
                                                .frame(width: 10, height: 10)
                                            Text("Calendar color")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteMembers)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tribe")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddMember = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddMember) {
                MemberEditorView()
            }
            .sheet(item: $memberToEdit) { member in
                MemberEditorView(member: member)
            }
            .onChange(of: acceptance.pendingMembership?.id) { _, _ in
                absorbPendingShareAcceptance()
            }
            .alert(
                "Couldn’t join tribe",
                isPresented: Binding(
                    get: { acceptance.errorMessage != nil },
                    set: { if !$0 { acceptance.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { acceptance.errorMessage = nil }
            } message: {
                Text(acceptance.errorMessage ?? "")
            }
        }
    }

    private func absorbPendingShareAcceptance() {
        guard let pending = acceptance.pendingMembership else { return }
        if memberships.isEmpty {
            modelContext.insert(pending)
            try? modelContext.save()
        }
        acceptance.pendingMembership = nil
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            let member = members[index]
            FamilySyncService.shared.noteLocalDeletion(prefix: "member", id: member.id)
            modelContext.delete(member)
        }
    }
}

#Preview {
    FamilyMembersView()
        .modelContainer(for: [FamilyMember.self, FamilyMembership.self], inMemory: true)
}
