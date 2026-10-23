import SwiftUI
import SwiftData

struct FamilyMembersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query private var memberships: [FamilyMembership]
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]

    @State private var showingAddMember = false
    @State private var memberToEdit: FamilyMember?
    @State private var selectedTribe: FamilyMembership?
    @State private var composerKind: TribeKind?
    @State private var showingComposer = false
    @State private var acceptance = FamilyShareAcceptanceCenter.shared

    private var home: FamilyMembership? { FamilyMembership.home(in: memberships) }
    private var others: [FamilyMembership] { FamilyMembership.extras(in: memberships) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TribeWheelView(
                        home: home,
                        others: others,
                        onSelect: { selectedTribe = $0 },
                        onSelectEmptyHome: { openComposer(kind: .family) },
                        onAdd: { openComposer(kind: nil) }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Spin the wheel to browse your tribes. Tap + to start or join a tribe calendar with anyone who uses Tribe Time.")
                }

                if !memberships.isEmpty {
                    Section("Tribes") {
                        ForEach([home].compactMap { $0 } + others, id: \.id) { tribe in
                            Button {
                                selectedTribe = tribe
                            } label: {
                                TribeThreadRow(tribe: tribe, nextEvent: nextEvent(for: tribe))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
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
                } header: {
                    Text(home.map { "\($0.familyName) profiles" } ?? "Profiles")
                } footer: {
                    if let summary = FamilySyncService.shared.lastResultSummary {
                        Text(summary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tribe")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingAddMember = true
                        } label: {
                            Label("New profile", systemImage: "person.badge.plus")
                        }
                        Button {
                            openComposer(kind: nil)
                        } label: {
                            Label("New or join tribe", systemImage: "circle.hexagongrid.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(item: $selectedTribe) { tribe in
                TribeDetailView(tribe: tribe)
            }
            .sheet(isPresented: $showingAddMember) {
                MemberEditorView()
            }
            .sheet(item: $memberToEdit) { member in
                MemberEditorView(member: member)
            }
            .sheet(isPresented: $showingComposer) {
                TribeComposerView(initialKind: composerKind)
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

    private func openComposer(kind: TribeKind?) {
        composerKind = kind
        showingComposer = true
    }

    private func nextEvent(for tribe: FamilyMembership) -> CalendarEvent? {
        let key = tribe.eventZoneKey
        let now = Date()
        return events.first { $0.tribeZoneName == key && $0.endDate >= now }
    }

    private func absorbPendingShareAcceptance() {
        guard let pending = acceptance.pendingMembership else { return }
        acceptance.pendingMembership = nil
        do {
            let added = try TribeRoster.add(pending, to: modelContext)
            selectedTribe = added
            Task { _ = try? await FamilySyncService.shared.syncAll(modelContext: modelContext) }
        } catch {
            acceptance.errorMessage = error.localizedDescription
        }
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            let member = members[index]
            FamilySyncService.shared.noteLocalDeletion(prefix: "member", id: member.id)
            modelContext.delete(member)
        }
    }
}

/// One tribe in the list under the wheel, styled like a message thread.
private struct TribeThreadRow: View {
    let tribe: FamilyMembership
    let nextEvent: CalendarEvent?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tribe.color)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: tribe.isHome ? "house.fill" : "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(tribe.familyName)
                        .font(.body.weight(tribe.unreadCount > 0 ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(tribe.lastActivityAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if tribe.unreadCount > 0 {
                        Text("\(tribe.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.red))
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var preview: String {
        guard let nextEvent else {
            return tribe.isHome ? "Home tribe" : "No upcoming events"
        }
        let when = nextEvent.isAllDay
            ? nextEvent.startDate.formatted(.dateTime.weekday(.abbreviated).month().day())
            : nextEvent.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "Next: \(nextEvent.title) · \(when)"
    }
}

#Preview {
    FamilyMembersView()
        .modelContainer(for: [FamilyMember.self, FamilyMembership.self, CalendarEvent.self], inMemory: true)
}
