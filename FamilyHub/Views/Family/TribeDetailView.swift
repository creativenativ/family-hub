import SwiftUI
import SwiftData

struct TribeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var tribe: FamilyMembership

    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]

    @State private var service = FamilyCloudService.shared
    @State private var syncService = FamilySyncService.shared
    @State private var confirmLeave = false
    @State private var showingInviteComposer = false
    @State private var actionMessage: String?

    private var upcoming: [CalendarEvent] {
        let key = tribe.eventZoneKey
        let now = Date()
        return events.filter { $0.tribeZoneName == key && $0.endDate >= now }.prefix(5).map { $0 }
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    TribeBubble(tribe: tribe, size: 96, isHome: tribe.isHome)
                    Text(tribe.isHome ? "Home tribe · shares everything" : "Tribe calendar · shares events only")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("On this device") {
                TribeColorRow(selectedHex: $tribe.colorHex)
                Toggle("Show on my calendar", isOn: $tribe.showOnCalendar)
            }

            Section("Coming up") {
                if upcoming.isEmpty {
                    Text("No upcoming events")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(upcoming, id: \.id) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                            Text(event.isAllDay
                                 ? event.startDate.formatted(date: .abbreviated, time: .omitted)
                                 : event.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            inviteSection

            if !service.participants.isEmpty {
                Section("Members") {
                    ForEach(service.participants) { participant in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(participant.displayName)
                                Text("\(participant.roleLabel) · \(participant.acceptanceLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if participant.isCurrentUser {
                                Text("You")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                if syncService.isSyncing {
                    ProgressView("Syncing…")
                } else if let lastSyncAt = syncService.lastSyncAt {
                    LabeledContent("Last sync") {
                        Text(lastSyncAt, style: .relative)
                    }
                }
                Button("Sync now") {
                    Task { await syncNow() }
                }
                .disabled(syncService.isSyncing)
            } footer: {
                if let message = actionMessage ?? syncService.tribeErrors[tribe.zoneName] {
                    Text(message)
                }
            }

            Section {
                Button(tribe.isOwner ? "Delete tribe for everyone" : "Leave tribe", role: .destructive) {
                    confirmLeave = true
                }
            }
        }
        .navigationTitle(tribe.familyName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tribe.unreadCount = 0
            await service.refreshParticipants(for: tribe)
        }
        .sheet(isPresented: $showingInviteComposer) {
            FamilyInviteComposerView(preselectedMembershipID: tribe.id)
        }
        .alert(tribe.isOwner ? "Delete \(tribe.familyName)?" : "Leave \(tribe.familyName)?", isPresented: $confirmLeave) {
            Button(tribe.isOwner ? "Delete" : "Leave", role: .destructive) {
                Task { await leave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(leaveMessage)
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        Section {
            if !tribe.inviteCode.isEmpty {
                HStack {
                    Text(tribe.formattedInviteCode)
                        .font(.title2.monospaced().weight(.semibold))
                    Spacer()
                    Button {
                        UIPasteboard.general.string = tribe.formattedInviteCode
                        actionMessage = "Invite code copied."
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy invite code")
                }
            }

            if let url = tribe.shareURL {
                ShareLink(item: url, subject: Text(tribe.familyName), message: Text(shareMessage)) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                showingInviteComposer = true
            } label: {
                Label("Invite by text or email", systemImage: "person.crop.circle.badge.plus")
            }
        } header: {
            Text("Invite")
        } footer: {
            Text("Anyone with Tribe Time and an Apple ID can join with this code.")
        }
    }

    private var shareMessage: String {
        """
        Join "\(tribe.familyName)" on Tribe Time.
        Invite code: \(tribe.formattedInviteCode)
        Or open this link on your iPhone with Tribe Time installed.
        """
    }

    private var leaveMessage: String {
        switch (tribe.isOwner, tribe.isHome) {
        case (true, true): "This deletes the shared tribe and invite code for everyone. Your data stays on this device."
        case (true, false): "This deletes this tribe calendar and its events for everyone."
        case (false, true): "You'll stop sharing with this tribe. Your data stays on this device."
        case (false, false): "Its events will be removed from your calendar. Events you shared from it stay as your own."
        }
    }

    private func syncNow() async {
        do {
            _ = try await syncService.syncAll(modelContext: modelContext)
            actionMessage = "Synced."
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func leave() async {
        do {
            try await service.leaveFamily(tribe)
            if tribe.isHome {
                try syncService.detachLocalDataFromFamily(modelContext: modelContext)
            } else {
                try syncService.detachTribeCalendar(tribe, modelContext: modelContext)
            }
            modelContext.delete(tribe)
            try modelContext.save()
            dismiss()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}
