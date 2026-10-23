import SwiftUI
import SwiftData
import UIKit

struct ImportEmailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let members: [FamilyMember]
    let referenceDate: Date

    @State private var emailText = ""
    @State private var parsedEvents: [ParsedEmailEvent] = []
    @State private var assignedMember: FamilyMember?
    @State private var didParse = false
    @State private var showingTips = false
    @State private var showingQueuedConfirmation = false
    @State private var queuedCount = 0

    private var selectedCount: Int {
        parsedEvents.filter(\.isSelected).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EmailBodyInput(text: $emailText, minHeight: 140)
                        .font(.body)

                    HStack {
                        Button("Paste") {
                            if let pasted = UIPasteboard.general.string {
                                emailText = pasted
                            }
                        }

                        Spacer()

                        Button("Scan Email") {
                            parseEmail()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(emailText.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                    }
                } header: {
                    Text("Email Content")
                } footer: {
                    Text("Detected items are sent to Notifications for approval — nothing is added to the calendar until you approve.")
                }

                if !members.isEmpty {
                    Section("Suggest Assign To") {
                        Picker("Tribe Member", selection: $assignedMember) {
                            Text("Everyone").tag(nil as FamilyMember?)
                            ForEach(members, id: \.id) { member in
                                Text(member.name).tag(member as FamilyMember?)
                            }
                        }
                    }
                }

                if didParse {
                    Section {
                        if parsedEvents.isEmpty {
                            Text("No appointments or deliveries found. Try including the full email body with dates.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($parsedEvents) { $event in
                                ParsedEventRow(event: $event)
                            }
                        }
                    } header: {
                        Text("Detected (\(selectedCount) selected)")
                    } footer: {
                        Text("Selected items go to the Notifications panel (bell, top left) for approval.")
                    }
                }

                Section {
                    Button {
                        showingTips = true
                    } label: {
                        Label("How to import from Mail", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Import Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send for Approval") { queueSelectedEvents() }
                        .disabled(selectedCount == 0)
                }
            }
            .alert("Import from Mail", isPresented: $showingTips) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("""
                1. Open the email in Mail or Gmail
                2. Copy the message text
                3. Paste here and tap Scan Email
                4. Tap Send for Approval
                5. Tap the bell (top left) and Approve or Decline each item

                Nothing is added to the calendar until you approve it.
                """)
            }
            .alert("Sent for Approval", isPresented: $showingQueuedConfirmation) {
                Button("OK") { dismiss() }
            } message: {
                Text("\(queuedCount) item\(queuedCount == 1 ? "" : "s") ready in Notifications (bell, top left). Approve them there to add to the calendar.")
            }
        }
    }

    private func parseEmail() {
        parsedEvents = EmailEventParser.parse(emailText, referenceDate: referenceDate)
        didParse = true
    }

    private func queueSelectedEvents() {
        let snippet = String(emailText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        var count = 0

        for event in parsedEvents where event.isSelected {
            let pending = PendingEmailImport(
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                location: event.location,
                notes: event.notes,
                category: event.category,
                sourceSnippet: snippet,
                suggestedMember: assignedMember
            )
            modelContext.insert(pending)
            count += 1
        }

        queuedCount = count
        showingQueuedConfirmation = true
    }
}

private struct EmailBodyInput: View {
    @Binding var text: String
    var minHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Paste dentist confirmations, Amazon delivery emails, practice schedules…")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
            }
            TextField("", text: $text, axis: .vertical)
                .lineLimit(6...14)
        }
        .frame(minHeight: minHeight, alignment: .topLeading)
    }
}

struct ParsedEventRow: View {
    @Binding var event: ParsedEmailEvent

    var body: some View {
        Toggle(isOn: $event.isSelected) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: event.category.icon)
                        .foregroundStyle(Color.themeAccent)
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                }

                HStack(spacing: 8) {
                    Text(event.category.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.themeAccent.opacity(0.15))
                        .clipShape(Capsule())

                    if event.isAllDay {
                        Text(event.startDate.formatted(date: .abbreviated, time: .omitted) + " · All day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(event.startDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .tint(.themeAccent)
    }
}

#Preview {
    ImportEmailView(members: [], referenceDate: Date())
}
