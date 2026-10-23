import SwiftUI
import SwiftData

struct FamilySharingSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var memberships: [FamilyMembership]

    @State private var service = FamilyCloudService.shared
    @State private var syncService = FamilySyncService.shared
    @State private var showingCreate = false
    @State private var showingJoin = false
    @State private var familyName = ""
    @State private var inviteCode = ""
    @State private var confirmLeave = false
    @State private var actionMessage: String?
    @State private var showingInviteComposer = false
    @State private var sheetError: String?

    private var membership: FamilyMembership? {
        memberships.first
    }

    var body: some View {
        Section {
            if let membership {
                activeFamilyContent(membership)
            } else {
                emptyFamilyContent
            }
        } header: {
            Text("Shared Tribe")
        } footer: {
            Text(footerText)
        }
        .task {
            await service.refreshAccountStatus()
            if let membership {
                await service.refreshParticipants(for: membership)
                await runSync(for: membership, messageOnSuccess: nil)
            }
        }
        .alert("Leave Shared Tribe?", isPresented: $confirmLeave) {
            Button("Leave", role: .destructive) {
                Task { await leaveCurrentFamily() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                membership?.isOwner == true
                    ? "This deletes the shared tribe and invite code for everyone."
                    : "You’ll stop seeing this shared tribe on this device."
            )
        }
        .sheet(isPresented: $showingCreate) {
            createSheet
        }
        .sheet(isPresented: $showingJoin) {
            joinSheet
        }
        .sheet(isPresented: $showingInviteComposer) {
            FamilyInviteComposerView()
        }
    }

    private var footerText: String {
        if let actionMessage { return actionMessage }
        if let syncError = syncService.lastErrorMessage { return syncError }
        if let summary = syncService.lastResultSummary { return summary }
        if !service.isiCloudAvailable {
            return "Sign in to iCloud in Settings to create or join a shared tribe."
        }
        return "Events, chores, recipes, and profiles sync across everyone in the shared tribe."
    }

    @ViewBuilder
    private func activeFamilyContent(_ membership: FamilyMembership) -> some View {
        LabeledContent("Tribe") {
            Text(membership.familyName)
        }

        LabeledContent("Your role") {
            Text(membership.isOwner ? "Owner" : "Member")
        }

        if !membership.inviteCode.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Invite code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(membership.formattedInviteCode)
                        .font(.title2.monospaced().weight(.semibold))
                    Spacer()
                    Button {
                        UIPasteboard.general.string = membership.formattedInviteCode
                        actionMessage = "Invite code copied."
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        if let url = membership.shareURL {
            ShareLink(item: url, subject: Text(membership.familyName), message: Text(shareMessage(for: membership))) {
                Label("Share invite link", systemImage: "square.and.arrow.up")
            }
        }

        Button {
            showingInviteComposer = true
        } label: {
            Label("Invite by text or email", systemImage: "person.crop.circle.badge.plus")
        }

        if syncService.isSyncing || service.isBusy {
            ProgressView(syncService.isSyncing ? "Syncing tribe data…" : "Working…")
        } else if let lastSyncAt = syncService.lastSyncAt {
            LabeledContent("Last sync") {
                Text(lastSyncAt, style: .relative)
            }
        }

        if !service.participants.isEmpty {
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

        Button("Sync now") {
            Task { await runSync(for: membership, messageOnSuccess: "Tribe data synced.") }
        }
        .disabled(syncService.isSyncing)

        Button("Refresh members") {
            Task { await service.refreshParticipants(for: membership) }
        }

        Button(membership.isOwner ? "Delete shared tribe" : "Leave shared tribe", role: .destructive) {
            confirmLeave = true
        }
    }

    private var emptyFamilyContent: some View {
        Group {
            if service.isBusy {
                ProgressView("Connecting to iCloud…")
            }

            Button {
                familyName = ""
                showingCreate = true
            } label: {
                Label("Create shared tribe", systemImage: "house.fill")
            }
            .disabled(!service.isiCloudAvailable || service.isBusy)

            Button {
                inviteCode = ""
                showingJoin = true
            } label: {
                Label("Join with invite code", systemImage: "person.badge.plus")
            }
            .disabled(!service.isiCloudAvailable || service.isBusy)
        }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("Tribe name") {
                    TextField("e.g. The Schwartzels", text: $familyName)
                }
                Section {
                    Text("You’ll get an invite code to share. Relatives join with their own Apple ID.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let sheetError {
                    Section {
                        Text(sheetError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Create Tribe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createFamily() }
                    }
                    .disabled(familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isBusy)
                }
            }
            .onAppear { sheetError = nil }
        }
        .presentationDetents([.medium])
    }

    private var joinSheet: some View {
        NavigationStack {
            Form {
                Section("Invite code") {
                    TextField("AB3K-9XP2", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }
                if let sheetError {
                    Section {
                        Text(sheetError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Join Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingJoin = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task { await joinFamily() }
                    }
                    .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isBusy)
                }
            }
            .onAppear { sheetError = nil }
        }
        .presentationDetents([.medium])
    }

    private func shareMessage(for membership: FamilyMembership) -> String {
        """
        Join our tribe on Tribe Time.
        Invite code: \(membership.formattedInviteCode)
        Or open this link on your iPhone with Tribe Time installed.
        """
    }

    private func createFamily() async {
        guard memberships.isEmpty else {
            sheetError = FamilyCloudError.alreadyInFamily.localizedDescription
            return
        }
        do {
            let created = try await service.createFamily(named: familyName)
            modelContext.insert(created)
            try modelContext.save()
            showingCreate = false
            actionMessage = "Shared tribe created. Share your invite code."
            await runSync(for: created, messageOnSuccess: nil)
        } catch {
            sheetError = error.localizedDescription
        }
    }

    private func joinFamily() async {
        guard memberships.isEmpty else {
            sheetError = FamilyCloudError.alreadyInFamily.localizedDescription
            return
        }
        do {
            let joined = try await service.joinFamily(inviteCode: inviteCode)
            modelContext.insert(joined)
            try modelContext.save()
            showingJoin = false
            actionMessage = "Joined \(joined.familyName)."
            await runSync(for: joined, messageOnSuccess: "Downloaded shared tribe data.")
        } catch {
            sheetError = error.localizedDescription
        }
    }

    private func leaveCurrentFamily() async {
        guard let membership else { return }
        do {
            try await service.leaveFamily(membership)
            try syncService.detachLocalDataFromFamily(modelContext: modelContext)
            modelContext.delete(membership)
            try modelContext.save()
            actionMessage = "Left the shared tribe."
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func runSync(for membership: FamilyMembership, messageOnSuccess: String?) async {
        do {
            _ = try await syncService.syncNow(membership: membership, modelContext: modelContext)
            if let messageOnSuccess {
                actionMessage = messageOnSuccess
            }
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}
