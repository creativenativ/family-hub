import SwiftUI
import SwiftData

enum FamilyInviteChannel: String, CaseIterable, Identifiable {
    case text, email

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: "Text message"
        case .email: "Email"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "message.fill"
        case .email: "envelope.fill"
        }
    }
}

struct FamilyInviteComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query private var memberships: [FamilyMembership]

    @State private var selectedMembershipID: UUID?
    @State private var selectedMemberID: UUID?
    @State private var channel: FamilyInviteChannel = .text
    @State private var recipientContact = ""
    @State private var errorMessage: String?

    private var selectedMembership: FamilyMembership? {
        if let selectedMembershipID {
            return memberships.first { $0.id == selectedMembershipID }
        }
        return memberships.first
    }

    private var selectedMember: FamilyMember? {
        guard let selectedMemberID else { return nil }
        return members.first { $0.id == selectedMemberID }
    }

    private var canSend: Bool {
        guard selectedMembership != nil else { return false }
        let contact = recipientContact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contact.isEmpty else { return false }
        switch channel {
        case .email: return contact.contains("@")
        case .text: return sanitizedPhone(contact).count >= 7
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if memberships.isEmpty {
                        Text("Create a shared tribe first, then invite people to its calendar.")
                            .foregroundStyle(.secondary)
                    } else if memberships.count == 1, let only = memberships.first {
                        LabeledContent("Tribe calendar") {
                            Text(only.familyName)
                        }
                    } else {
                        Picker("Tribe calendar", selection: $selectedMembershipID) {
                            ForEach(memberships, id: \.id) { hub in
                                Text(hub.familyName).tag(Optional(hub.id))
                            }
                        }
                    }
                } header: {
                    Text("Which calendar?")
                } footer: {
                    Text("Choose which shared tribe calendar this invite opens.")
                }

                Section {
                    Picker("Invite for", selection: $selectedMemberID) {
                        Text("Whole tribe / someone new").tag(UUID?.none)
                        ForEach(members, id: \.id) { member in
                            Text(member.name).tag(Optional(member.id))
                        }
                    }

                    if let member = selectedMember {
                        HStack(spacing: 10) {
                            MemberAvatar(member: member, size: 36, showColorRing: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                    .font(.body.weight(.medium))
                                Text("Invite is addressed to this profile")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Tribe member")
                }

                Section {
                    Picker("Send by", selection: $channel) {
                        ForEach(FamilyInviteChannel.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch channel {
                    case .text:
                        TextField("Phone number", text: $recipientContact)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    case .email:
                        TextField("Email address", text: $recipientContact)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.emailAddress)
                    }
                } header: {
                    Text("Send invite")
                } footer: {
                    Text("Opens Messages or Mail with the invite code and link filled in so you can send it in one tap.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        sendInvite()
                    } label: {
                        Label(
                            channel == .text ? "Open Messages" : "Open Mail",
                            systemImage: channel.systemImage
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSend)
                }
            }
            .navigationTitle("Invite to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if selectedMembershipID == nil {
                    selectedMembershipID = memberships.first?.id
                }
                applyMemberContactDefaults()
            }
            .onChange(of: selectedMemberID) { _, _ in
                applyMemberContactDefaults()
            }
            .onChange(of: channel) { _, _ in
                applyMemberContactDefaults(forceReplace: true)
            }
        }
        .presentationDetents([.large, .medium])
    }

    private func applyMemberContactDefaults(forceReplace: Bool = false) {
        guard let member = selectedMember else { return }
        let current = recipientContact.trimmingCharacters(in: .whitespacesAndNewlines)
        switch channel {
        case .text:
            if forceReplace || current.isEmpty || current.contains("@") {
                recipientContact = member.invitePhone
            }
        case .email:
            if forceReplace || current.isEmpty || !current.contains("@") {
                recipientContact = member.inviteEmail
            }
        }
    }

    private func sendInvite() {
        guard let membership = selectedMembership else {
            errorMessage = "Create or select a tribe calendar first."
            return
        }

        let contact = recipientContact.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = inviteBody(for: membership, member: selectedMember)
        let subject = "Join \(membership.familyName) on Tribe Time"

        switch channel {
        case .text:
            let phone = sanitizedPhone(contact)
            guard phone.count >= 7 else {
                errorMessage = "Enter a valid phone number."
                return
            }
            guard let url = makeMessageURL(scheme: "sms", path: phone, subject: nil, body: body) else {
                errorMessage = "Couldn't open Messages."
                return
            }
            openURL(url)
            dismiss()

        case .email:
            guard contact.contains("@") else {
                errorMessage = "Enter a valid email address."
                return
            }
            guard let url = makeMessageURL(scheme: "mailto", path: contact, subject: subject, body: body) else {
                errorMessage = "Couldn't open Mail."
                return
            }
            openURL(url)
            dismiss()
        }
    }

    /// Builds sms:/mailto: URLs with a fully percent-encoded body so CloudKit share links
    /// that contain `?` are not truncated by URLComponents.queryItems.
    private func makeMessageURL(scheme: String, path: String, subject: String?, body: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")

        var query: [String] = []
        if let subject,
           let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed) {
            query.append("subject=\(encodedSubject)")
        }
        guard let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        query.append("body=\(encodedBody)")

        var components = URLComponents()
        components.scheme = scheme
        components.path = path
        components.percentEncodedQuery = query.joined(separator: "&")
        return components.url
    }

    private func inviteBody(for membership: FamilyMembership, member: FamilyMember?) -> String {
        let greeting: String
        if let member {
            greeting = "Hi \(member.name),"
        } else {
            greeting = "Hi,"
        }

        var lines = [
            greeting,
            "",
            "You're invited to the \(membership.familyName) tribe calendar in Tribe Time.",
            "",
            "Invite code: \(membership.formattedInviteCode)",
        ]

        if let url = membership.shareURL {
            lines.append("Invite link: \(url.absoluteString)")
        }

        lines.append(contentsOf: [
            "",
            "1. Install Tribe Time on your iPhone",
            "2. Open the Tribe tab",
            "3. Tap Join with invite code (or open the link)",
            "",
            "Use your own Apple ID — you'll stay in sync with the shared tribe calendar.",
        ])

        return lines.joined(separator: "\n")
    }

    private func sanitizedPhone(_ raw: String) -> String {
        let allowed = Set("+0123456789")
        return String(raw.filter { allowed.contains($0) })
    }
}
