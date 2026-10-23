import SwiftUI
import SwiftData

struct VoiceMemoBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceMemo.createdAt, order: .reverse) private var memos: [VoiceMemo]
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]

    let selectedDate: Date

    @State private var showingRecordSheet = false
    @State private var memoToSchedule: VoiceMemo?
    @State private var audioController = VoiceMemoAudioController()
    @State private var filteredMemberID: UUID?
    @State private var filterRole: MemoFilterRole = .involved

    private var filteredMemos: [VoiceMemo] {
        guard let filteredMemberID else { return memos }
        return memos.filter { memo in
            switch filterRole {
            case .involved:
                return memo.fromMember?.id == filteredMemberID || memo.toMember?.id == filteredMemberID
            case .from:
                return memo.fromMember?.id == filteredMemberID
            case .to:
                return memo.toMember?.id == filteredMemberID
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Voice Memos", systemImage: "waveform")
                    .font(.headline)

                Spacer()

                Button {
                    showingRecordSheet = true
                } label: {
                    Label("Record", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(members.count < 2)
            }

            if members.count < 2 {
                Text("Add at least two tribe members to leave voice messages for each other.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !members.isEmpty {
                personFilterBar

                if filteredMemberID != nil {
                    roleFilterBar
                }
            }

            if memos.isEmpty {
                emptyBoard
            } else if filteredMemos.isEmpty {
                filteredEmptyBoard
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredMemos, id: \.id) { memo in
                        VoiceMemoRow(
                            memo: memo,
                            audioController: audioController,
                            onSchedule: { memoToSchedule = memo },
                            onDelete: { deleteMemo(memo) }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 16)
        .sheet(isPresented: $showingRecordSheet) {
            RecordVoiceMemoView(members: members)
        }
        .sheet(item: $memoToSchedule) { memo in
            ScheduleFromMemoView(memo: memo, selectedDate: selectedDate, members: members)
        }
        .onDisappear {
            audioController.stopPlayback()
            audioController.cancelRecording()
        }
    }

    private var personFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    title: "Everyone",
                    isSelected: filteredMemberID == nil,
                    color: .accentColor
                ) {
                    filteredMemberID = nil
                    filterRole = .involved
                }

                ForEach(members, id: \.id) { member in
                    Button {
                        if filteredMemberID == member.id {
                            filteredMemberID = nil
                            filterRole = .involved
                        } else {
                            filteredMemberID = member.id
                        }
                    } label: {
                        MemberChip(
                            member: member,
                            isSelected: filteredMemberID == member.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var roleFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(MemoFilterRole.allCases) { role in
                filterChip(
                    title: role.label,
                    isSelected: filterRole == role,
                    color: members.first(where: { $0.id == filteredMemberID })?.color ?? .accentColor
                ) {
                    filterRole = role
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func filterChip(title: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? color.opacity(0.22) : Color(.systemBackground))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? color : Color.clear, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var emptyBoard: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No voice memos yet")
                .font(.subheadline.weight(.medium))
            Text("Leave a message for a tribe member, then schedule it to the calendar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var filteredEmptyBoard: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No memos for this filter")
                .font(.subheadline.weight(.medium))
            Text("Try Everyone, or switch between Involved, From, and To.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func deleteMemo(_ memo: VoiceMemo) {
        if audioController.currentlyPlayingID == memo.id {
            audioController.stopPlayback()
        }
        modelContext.delete(memo)
    }
}

enum MemoFilterRole: String, CaseIterable, Identifiable {
    case involved
    case from
    case to

    var id: String { rawValue }

    var label: String {
        switch self {
        case .involved: "Involved"
        case .from: "From"
        case .to: "To"
        }
    }
}

struct VoiceMemoRow: View {
    @Bindable var memo: VoiceMemo
    let audioController: VoiceMemoAudioController
    let onSchedule: () -> Void
    let onDelete: () -> Void

    private var isPlayingThis: Bool {
        audioController.isPlaying && audioController.currentlyPlayingID == memo.id
    }

    private var accentColor: Color {
        memo.toMember?.color ?? memo.fromMember?.color ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let from = memo.fromMember {
                        MemberAvatar(member: from, size: 28, showColorRing: false)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let to = memo.toMember {
                        MemberAvatar(member: to, size: 28, showColorRing: false)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(memo.title.isEmpty ? "Voice message" : memo.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text(routeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if !memo.isHeard {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        audioController.togglePlayback(data: memo.audioData, memoID: memo.id)
                        memo.isHeard = true
                    } label: {
                        Image(systemName: isPlayingThis ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(accentColor)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.tertiarySystemFill))
                                Capsule()
                                    .fill(accentColor)
                                    .frame(width: geo.size.width * (isPlayingThis ? audioController.playbackProgress : 0))
                            }
                        }
                        .frame(height: 4)

                        Text(memo.formattedDuration)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if memo.isScheduled {
                        Label("Scheduled", systemImage: "calendar.badge.checkmark")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                    } else {
                        Button("Schedule", action: onSchedule)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var routeLabel: String {
        let from = memo.fromMember?.name ?? "Someone"
        let to = memo.toMember?.name ?? "Tribe"
        let date = memo.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(from) → \(to) · \(date)"
    }
}

struct RecordVoiceMemoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let members: [FamilyMember]

    @State private var audioController = VoiceMemoAudioController()
    @State private var fromMember: FamilyMember?
    @State private var toMember: FamilyMember?
    @State private var title = ""
    @State private var recordedData: Data?
    @State private var recordedDuration: TimeInterval = 0
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    memberPicker(selection: $fromMember, excluding: toMember)
                }

                Section("To") {
                    memberPicker(selection: $toMember, excluding: fromMember)
                }

                Section("Label (optional)") {
                    TextField("e.g. Soccer practice reminder", text: $title)
                }

                Section("Recording") {
                    VStack(spacing: 16) {
                        Text(timeLabel)
                            .font(.title.monospacedDigit())
                            .frame(maxWidth: .infinity)

                        if permissionDenied {
                            Text("Microphone access is required. Enable it in Settings.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if let error = audioController.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        HStack(spacing: 20) {
                            if audioController.isRecording {
                                Button {
                                    finishRecording()
                                } label: {
                                    Label("Stop", systemImage: "stop.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                }
                            } else if recordedData != nil {
                                Button {
                                    recordedData = nil
                                    recordedDuration = 0
                                    startRecording()
                                } label: {
                                    Label("Re-record", systemImage: "mic.circle.fill")
                                        .font(.title2)
                                }

                                Button {
                                    if let data = recordedData {
                                        audioController.togglePlayback(data: data, memoID: previewID)
                                    }
                                } label: {
                                    Image(systemName: audioController.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.title2)
                                }
                            } else {
                                Button {
                                    startRecording()
                                } label: {
                                    Label("Hold to speak — tap to start", systemImage: "mic.circle.fill")
                                        .font(.title2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Voice Memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        audioController.cancelRecording()
                        audioController.stopPlayback()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { saveMemo() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if fromMember == nil { fromMember = members.first }
                if toMember == nil { toMember = members.dropFirst().first }
            }
            .onDisappear {
                audioController.cancelRecording()
                audioController.stopPlayback()
            }
        }
    }

    private let previewID = UUID()

    private var canSave: Bool {
        recordedData != nil && fromMember != nil && toMember != nil && fromMember?.id != toMember?.id
    }

    private var timeLabel: String {
        let seconds: TimeInterval
        if audioController.isRecording {
            seconds = audioController.recordingElapsed
        } else {
            seconds = recordedDuration
        }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func memberPicker(selection: Binding<FamilyMember?>, excluding: FamilyMember?) -> some View {
        Picker("Member", selection: selection) {
            ForEach(members.filter { $0.id != excluding?.id }, id: \.id) { member in
                Text(member.name).tag(member as FamilyMember?)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func startRecording() {
        Task {
            let granted = await audioController.requestPermission()
            await MainActor.run {
                guard granted else {
                    permissionDenied = true
                    return
                }
                permissionDenied = false
                do {
                    try audioController.startRecording()
                } catch {
                    audioController.errorMessage = "Couldn't start recording."
                }
            }
        }
    }

    private func finishRecording() {
        audioController.stopPlayback()
        if let result = audioController.stopRecording() {
            recordedData = result.data
            recordedDuration = result.duration
        }
    }

    private func saveMemo() {
        guard let data = recordedData,
              let from = fromMember,
              let to = toMember else { return }

        let memo = VoiceMemo(
            title: title.trimmingCharacters(in: .whitespaces),
            audioData: data,
            durationSeconds: recordedDuration,
            fromMember: from,
            toMember: to
        )
        modelContext.insert(memo)
        dismiss()
    }
}

struct ScheduleFromMemoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var memo: VoiceMemo
    let selectedDate: Date
    let members: [FamilyMember]

    @State private var title: String
    @State private var eventDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isAllDay = false
    @State private var assignedMember: FamilyMember?

    init(memo: VoiceMemo, selectedDate: Date, members: [FamilyMember]) {
        self.memo = memo
        self.selectedDate = selectedDate
        self.members = members
        let defaultTitle = memo.title.isEmpty
            ? "Task from \(memo.fromMember?.name ?? "Tribe")"
            : memo.title
        _title = State(initialValue: defaultTitle)
        _eventDate = State(initialValue: selectedDate)
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let end = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: end)
        _assignedMember = State(initialValue: memo.toMember)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    Toggle("All Day", isOn: $isAllDay)
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                    if !isAllDay {
                        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Assign To") {
                    Picker("Tribe Member", selection: $assignedMember) {
                        Text("Everyone").tag(nil as FamilyMember?)
                        ForEach(members, id: \.id) { member in
                            Text(member.name).tag(member as FamilyMember?)
                        }
                    }
                }

                if let from = memo.fromMember, let to = memo.toMember {
                    Section("From Voice Memo") {
                        Text("\(from.name) left this for \(to.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Schedule to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Event") { scheduleEvent() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func scheduleEvent() {
        let start: Date
        let end: Date
        if isAllDay {
            start = eventDate.startOfDay
            end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        } else {
            let day = eventDate.startOfDay
            let startComponents = Calendar.current.dateComponents([.hour, .minute], from: startTime)
            let endComponents = Calendar.current.dateComponents([.hour, .minute], from: endTime)
            start = Calendar.current.date(bySettingHour: startComponents.hour ?? 9, minute: startComponents.minute ?? 0, second: 0, of: day) ?? day
            end = Calendar.current.date(bySettingHour: endComponents.hour ?? 10, minute: endComponents.minute ?? 0, second: 0, of: day) ?? day
        }

        let event = CalendarEvent(
            title: title.trimmingCharacters(in: .whitespaces),
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            notes: "Scheduled from voice memo",
            assignedMember: assignedMember
        )
        modelContext.insert(event)
        memo.scheduledEventID = event.id
        memo.isHeard = true
        dismiss()
    }
}
