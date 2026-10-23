import SwiftUI
import SwiftData
import UserNotifications

/// Chores as a family whiteboard: chores and room headings written in marker,
/// moved around by touch-and-hold, with member magnets to filter.
struct ChoresView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Chore.dueDate) private var chores: [Chore]
    @Query(sort: \BoardNote.createdAt) private var notes: [BoardNote]
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query private var memberships: [FamilyMembership]

    @State private var showingAddChore = false
    @State private var newChoreInk = ""
    @State private var selectedMemberID: UUID?
    @State private var notificationsAllowed = true
    @State private var choreToInspect: Chore?
    @State private var noteToEdit: BoardNote?
    @State private var noteDraft = ""
    @State private var addingNote = false
    @State private var confirmErase = false
    @State private var boardMessage: String?

    private var finishedOneTimeChores: [Chore] {
        chores.filter { $0.isCompleted && $0.frequency == .once }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        board(width: proxy.size.width)
                    }
                    .frame(height: boardHeight(for: boardWidth) * boardWidth + 20)
                    .padding(.horizontal, 12)

                    MarkerTray(
                        onPickMarker: { ink in
                            newChoreInk = ink
                            showingAddChore = true
                        },
                        onEraser: { confirmErase = true }
                    )
                    .padding(.top, -6)

                    Text("Touch and hold a chore or heading to move it. Tap a marker to write a new chore.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                }
                .padding(.top, 4)
            }
            .navigationTitle("Chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !notificationsAllowed && !members.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task { await requestNotifications() }
                        } label: {
                            Image(systemName: "bell.badge")
                        }
                        .accessibilityLabel("Enable chore reminders")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            newChoreInk = ""
                            showingAddChore = true
                        } label: {
                            Label("New chore", systemImage: "square.and.pencil")
                        }
                        Button {
                            noteDraft = ""
                            addingNote = true
                        } label: {
                            Label("Add heading", systemImage: "textformat")
                        }
                        Button {
                            let added = ChoreBoardStarter.addMissing(existing: chores, existingNotes: notes, modelContext: modelContext)
                            boardMessage = added == 0 ? "All the common chores are already on the board." : "Added \(added) common chores."
                        } label: {
                            Label("Add common chores", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddChore) {
                AddChoreView(
                    members: members,
                    initialMember: members.first(where: { $0.id == selectedMemberID }),
                    markerColorHex: newChoreInk
                )
            }
            .sheet(item: $choreToInspect) { chore in
                ChoreDetailView(chore: chore)
            }
            .alert("Edit heading", isPresented: Binding(
                get: { noteToEdit != nil },
                set: { if !$0 { noteToEdit = nil } }
            )) {
                TextField("Heading", text: $noteDraft)
                Button("Save") {
                    let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { noteToEdit?.text = text }
                    noteToEdit = nil
                }
                Button("Erase", role: .destructive) {
                    if let noteToEdit { modelContext.delete(noteToEdit) }
                    noteToEdit = nil
                }
                Button("Cancel", role: .cancel) { noteToEdit = nil }
            }
            .alert("Add heading", isPresented: $addingNote) {
                TextField("e.g. Garage", text: $noteDraft)
                Button("Add") { addNote() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Headings label areas of the board, like rooms.")
            }
            .confirmationDialog("Erase finished chores?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase \(finishedOneTimeChores.count) finished", role: .destructive) { eraseFinished() }
                    .disabled(finishedOneTimeChores.isEmpty)
            } message: {
                Text(finishedOneTimeChores.isEmpty
                     ? "Nothing to erase. Repeating chores reset on their own when they're done."
                     : "Removes crossed-off one-time chores from the board.")
            }
            .alert(boardMessage ?? "", isPresented: Binding(
                get: { boardMessage != nil },
                set: { if !$0 { boardMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
            .task {
                ChoreBoardStarter.seedIfNeeded(chores: chores, notes: notes, memberships: memberships, modelContext: modelContext)
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

    // MARK: - Board

    /// Width the board is laid out against; the GeometryReader reports the real one.
    @State private var boardWidth: CGFloat = 360

    /// Board height in width units: tall enough for the lowest item, at least a portrait board.
    private func boardHeight(for width: CGFloat) -> Double {
        let lowestChore = positions.values.map(\.y).max() ?? 0
        let lowestNote = notes.map(\.boardY).max() ?? 0
        return max(1.5, max(lowestChore, lowestNote) + 0.22)
    }

    private var positions: [UUID: CGPoint] {
        BoardLayout.positions(for: chores, notes: notes)
    }

    private func board(width: CGFloat) -> some View {
        let height = boardHeight(for: width)
        let inner = width - 20 // inside the frame
        let positions = positions

        return ZStack(alignment: .topLeading) {
            WhiteboardSurface()

            ZStack(alignment: .topLeading) {
                boardHeader(width: inner)

                ForEach(notes, id: \.id) { note in
                    BoardHeading(note: note)
                        .frame(width: inner * BoardLayout.itemWidth, alignment: .leading)
                        .onTapGesture {
                            noteDraft = note.text
                            noteToEdit = note
                        }
                        .boardDraggable { move(note, by: $0, inner: inner, height: height) }
                        .offset(x: note.boardX * inner, y: note.boardY * inner)
                }

                ForEach(chores, id: \.id) { chore in
                    let point = positions[chore.id] ?? .zero
                    BoardChoreItem(
                        chore: chore,
                        isDimmed: selectedMemberID != nil && chore.assignedMember?.id != selectedMemberID,
                        onToggle: { toggle(chore) },
                        onOpen: { choreToInspect = chore }
                    )
                    .frame(width: inner * BoardLayout.itemWidth, alignment: .leading)
                    .boardDraggable { move(chore, from: point, by: $0, inner: inner, height: height) }
                    .offset(x: point.x * inner, y: point.y * inner)
                }
            }
            .padding(10)
        }
        .frame(width: width, height: height * inner + 20)
        .onAppear { boardWidth = inner }
        .onChange(of: width) { _, _ in boardWidth = inner }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: chores.map(\.boardY))
    }

    private func boardHeader(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(Marker.font(32, wide: true, relativeTo: .largeTitle))
                    .foregroundStyle(Marker.color("#B3261E"))
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                    .font(Marker.font(17, relativeTo: .subheadline))
                    .foregroundStyle(Marker.color(Marker.defaultInk).opacity(0.75))
            }

            if !members.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button {
                            selectedMemberID = nil
                        } label: {
                            VStack(spacing: 2) {
                                BoardMagnet(label: "★", color: Color(hex: "#B78819") ?? .yellow, isSelected: selectedMemberID == nil)
                                Text("All").font(Marker.font(13))
                            }
                        }
                        .buttonStyle(.plain)

                        ForEach(members, id: \.id) { member in
                            Button {
                                selectedMemberID = selectedMemberID == member.id ? nil : member.id
                            } label: {
                                VStack(spacing: 2) {
                                    BoardMagnet(
                                        label: String(member.name.prefix(1)).uppercased(),
                                        color: member.color,
                                        isSelected: selectedMemberID == member.id
                                    )
                                    Text(member.name).font(Marker.font(13)).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Show \(member.name)'s chores")
                        }
                    }
                    .foregroundStyle(Marker.color(Marker.defaultInk))
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Actions

    private func move(_ chore: Chore, from point: CGPoint, by translation: CGSize, inner: CGFloat, height: Double) {
        chore.boardX = BoardLayout.clamp(x: point.x + translation.width / inner)
        chore.boardY = BoardLayout.clamp(y: point.y + translation.height / inner, boardHeight: height + 0.3)
        chore.touchForSync()
    }

    private func move(_ note: BoardNote, by translation: CGSize, inner: CGFloat, height: Double) {
        note.boardX = BoardLayout.clamp(x: note.boardX + translation.width / inner)
        note.boardY = BoardLayout.clamp(y: note.boardY + translation.height / inner, boardHeight: height + 0.3)
        note.modifiedAt = Date()
    }

    private func addNote() {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Start new headings below everything else; they can be dragged anywhere.
        let lowest = max(positions.values.map(\.y).max() ?? 0, notes.map(\.boardY).max() ?? 0)
        modelContext.insert(BoardNote(text: text, boardX: BoardLayout.columns[0], boardY: max(lowest + 0.14, BoardLayout.firstRow)))
    }

    private func toggle(_ chore: Chore) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if chore.isCompleted {
                chore.isCompleted = false
                chore.completedAt = nil
                chore.touchForSync()
                Task { await ChoreReminderService.scheduleReminder(for: chore) }
            } else {
                chore.markComplete()
                Task { await ChoreReminderService.cancelReminder(for: chore.id) }
            }
        }
        // Repeating chores show the check for a moment, then reset for next time.
        guard chore.isCompleted, chore.frequency != .once else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard chore.isCompleted else { return }
            withAnimation { chore.resetForNextOccurrence() }
            await ChoreReminderService.scheduleReminder(for: chore)
        }
    }

    private func eraseFinished() {
        for chore in finishedOneTimeChores {
            Task { await ChoreReminderService.cancelReminder(for: chore.id) }
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

/// One chore written on the board.
private struct BoardChoreItem: View {
    let chore: Chore
    let isDimmed: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    private var ink: Color { Marker.color(chore.markerColorHex) }

    private var isOverdue: Bool {
        !chore.isCompleted && chore.dueDate < Date().startOfDay
    }

    private var dueText: String {
        if isOverdue { return "overdue!" }
        if Calendar.current.isDateInToday(chore.dueDate) { return "today" }
        if Calendar.current.isDateInTomorrow(chore.dueDate) { return "tomorrow" }
        return chore.dueDate.formatted(.dateTime.weekday(.abbreviated))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Button(action: onToggle) {
                MarkerCheckbox(isChecked: chore.isCompleted, ink: ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chore.isCompleted ? "Mark \(chore.title) not done" : "Mark \(chore.title) done")

            VStack(alignment: .leading, spacing: 0) {
                Text(chore.title)
                    .font(Marker.font(18, relativeTo: .body))
                    .foregroundStyle(ink.opacity(chore.isCompleted ? 0.55 : 1))
                    // One line keeps every item the same height so neighbors never overlap.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .overlay {
                        if chore.isCompleted {
                            ScribbleStrike()
                                .stroke(ink.opacity(0.8), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        }
                    }

                HStack(spacing: 4) {
                    Text(chore.frequency == .once ? dueText : "\(chore.frequency.label.lowercased()) · \(dueText)")
                        .foregroundStyle(isOverdue ? Marker.color("#B3261E") : ink.opacity(0.6))
                    if !chore.components.isEmpty {
                        Text("· \(chore.completedComponentCount)/\(chore.components.count)")
                            .foregroundStyle(ink.opacity(0.6))
                    }
                }
                .font(Marker.font(12, relativeTo: .caption))
                .lineLimit(1)
            }
            .padding(.top, 3)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens steps and details")

            if let member = chore.assignedMember {
                BoardMagnet(label: String(member.name.prefix(1)).uppercased(), color: member.color, size: 20)
                    .padding(.top, 4)
                    .accessibilityLabel("Assigned to \(member.name)")
            }
        }
        .opacity(isDimmed ? 0.22 : 1)
    }
}

/// A room heading written on the board.
private struct BoardHeading: View {
    let note: BoardNote

    var body: some View {
        Text(note.text)
            .font(Marker.font(21, wide: true, relativeTo: .title3))
            .foregroundStyle(Marker.color(note.colorHex))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.bottom, 3)
            .overlay(alignment: .bottomLeading) {
                ScribbleStrike()
                    .stroke(Marker.color(note.colorHex).opacity(0.7), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(height: 4)
                    .offset(y: 2)
            }
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Tap to rename or erase. Touch and hold to move.")
    }
}

#Preview {
    ChoresView()
        .modelContainer(for: [Chore.self, FamilyMember.self, BoardNote.self, FamilyMembership.self], inMemory: true)
}
