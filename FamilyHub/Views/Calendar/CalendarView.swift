import SwiftUI
import SwiftData

enum CalendarSpanSegment {
    case single
    case start
    case middle
    case end
}

/// Name and color of a non-home tribe calendar, for labeling its events.
struct TribeTag {
    let name: String
    let color: Color
}

/// Unified item shown as a color bar on the calendar.
struct CalendarBarItem: Identifiable {
    enum Kind {
        case event
        case chore
    }

    let id: String
    let sourceID: UUID
    let title: String
    let kind: Kind
    let date: Date
    let member: FamilyMember?
    let event: CalendarEvent?
    let chore: Chore?
    let spanSegment: CalendarSpanSegment
    let lane: Int
    let isMultiDay: Bool
    /// Set for events that belong to a tribe calendar other than home.
    var tribe: TribeTag? = nil

    /// Personal color first, then the person, then the tribe, then the theme default.
    @MainActor var color: Color {
        let custom = event?.customColorHex ?? chore?.customColorHex ?? ""
        if let customColor = Color(hex: custom) { return customColor }
        if let member { return member.color }
        if let tribe { return tribe.color }
        return ThemeStore.shared.color(kind == .chore ? .chore : .event)
    }

    /// Name of the tribe a linked copy came from, e.g. "Work".
    var linkedFrom: String? {
        guard let event, event.linkedSourceEventID != nil, !event.linkedSourceTribeName.isEmpty else { return nil }
        return event.linkedSourceTribeName
    }

    var kindLabel: String {
        switch kind {
        case .event: "Event"
        case .chore: "Chore"
        }
    }

    var subtitle: String {
        switch kind {
        case .event:
            guard let event else { return kindLabel }
            if event.isAllDay {
                if isMultiDay {
                    return "\(event.startDate.formatted(date: .abbreviated, time: .omitted)) – \(event.lastInclusiveDay.formatted(date: .abbreviated, time: .omitted))"
                }
                return "All day"
            }
            return "\(event.startDate.formattedTime()) – \(event.endDate.formattedTime())"
        case .chore:
            return "Chore · \(chore?.frequency.label ?? "")"
        }
    }
}

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
    @Query(sort: \Chore.dueDate) private var chores: [Chore]
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query private var memberships: [FamilyMembership]

    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var showingAddEvent = false
    @State private var showingImportEmail = false
    @State private var filteredMemberIDs: Set<UUID> = []
    @State private var itemToColor: CalendarBarItem?
    @AppStorage("Calendar.showChores") private var showsChores = true

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let maxBarsPerCell = 3

    /// Precomputed bars for every day in the visible month grid.
    private var barsByDay: [Date: [CalendarBarItem]] {
        CalendarSpanLayout.build(
            events: filteredEvents,
            chores: filteredChores,
            monthDays: monthDays.compactMap { $0 },
            tribeTags: tribeTags
        )
    }

    private var homeTribe: FamilyMembership? { FamilyMembership.home(in: memberships) }
    private var otherTribes: [FamilyMembership] {
        FamilyMembership.extras(in: memberships).sorted {
            $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedAscending
        }
    }

    private var tribeTags: [String: TribeTag] {
        Dictionary(otherTribes.map { ($0.zoneName, TribeTag(name: $0.familyName, color: $0.color)) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Tribe calendars currently switched on ("" = home).
    private var visibleZoneKeys: Set<String> {
        var keys = Set(otherTribes.filter(\.showOnCalendar).map(\.zoneName))
        if homeTribe?.showOnCalendar ?? true { keys.insert("") }
        return keys
    }

    private var showsHomeItems: Bool { visibleZoneKeys.contains("") }

    private var filteredEvents: [CalendarEvent] {
        let visible = visibleZoneKeys
        let shownIDs = Set(events.filter { visible.contains($0.tribeZoneName) }.map(\.id))
        return events.filter { event in
            guard visible.contains(event.tribeZoneName) else { return false }
            // A shared copy is redundant when its original is on screen too.
            if let sourceID = event.linkedSourceEventID, shownIDs.contains(sourceID) { return false }
            guard !filteredMemberIDs.isEmpty else { return true }
            guard let memberID = event.assignedMember?.id else { return true }
            return filteredMemberIDs.contains(memberID)
        }
    }

    private var filteredChores: [Chore] {
        chores.filter { chore in
            guard showsChores, showsHomeItems, !chore.isCompleted else { return false }
            guard !filteredMemberIDs.isEmpty else { return true }
            guard let memberID = chore.assignedMember?.id else { return true }
            return filteredMemberIDs.contains(memberID)
        }
    }

    private var itemsForSelectedDate: [CalendarBarItem] {
        let items = barsByDay[selectedDate.startOfDay] ?? []
        // Deduplicate multi-day segments for the detail list (one row per source)
        var seen = Set<UUID>()
        return items.filter { seen.insert($0.sourceID).inserted }
            .sorted { $0.date < $1.date }
    }

    private var monthDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday
        else { return [] }

        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 0

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                days.append(date)
            }
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !otherTribes.isEmpty {
                        tribeFilterBar
                        Divider()
                    }

                    if !members.isEmpty && showsHomeItems {
                        memberFilterBar
                        Divider()
                    }

                    monthHeader
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                    weekdayHeader
                        .padding(.horizontal, 8)

                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                            if let day {
                                DayBoxCell(
                                    date: day,
                                    isSelected: day.isSameDay(as: selectedDate),
                                    isToday: day.isSameDay(as: Date()),
                                    isCurrentMonth: day.isSameMonth(as: displayedMonth),
                                    bars: barsByDay[day.startOfDay] ?? [],
                                    maxBars: maxBarsPerCell,
                                    onTap: {
                                        selectedDate = day
                                    },
                                    onDoubleTap: {
                                        selectedDate = day
                                        showingAddEvent = true
                                    }
                                )
                            } else {
                                Color.clear
                                    .aspectRatio(0.72, contentMode: .fit)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)

                    Divider()

                    dayDetailPanel

                    Divider()
                        .padding(.top, 8)

                    VoiceMemoBoardView(selectedDate: selectedDate)
                        .padding(.top, 12)
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingAddEvent = true
                        } label: {
                            Label("New Event", systemImage: "plus")
                        }
                        Button {
                            showingImportEmail = true
                        } label: {
                            Label("Import from Email", systemImage: "envelope.badge")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventView(selectedDate: selectedDate, members: members, tribes: memberships)
            }
            .sheet(item: $itemToColor) { item in
                ItemColorSheet(
                    title: item.title,
                    currentHex: item.event?.customColorHex ?? item.chore?.customColorHex ?? ""
                ) { hex in
                    item.event?.customColorHex = hex ?? ""
                    item.chore?.customColorHex = hex ?? ""
                }
            }
            .sheet(isPresented: $showingImportEmail) {
                ImportEmailView(members: members, referenceDate: selectedDate)
            }
            .task {
                await EventReminderService.rescheduleAll(
                    for: events.filter { $0.notificationsEnabled && $0.endDate >= Date().startOfDay }
                )
            }
        }
    }

    // MARK: - Month header

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }

            Spacer()

            Text(displayedMonth.formattedMonthYear())
                .font(.title2.weight(.semibold))

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Day detail

    private var dayDetailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !itemsForSelectedDate.isEmpty {
                    Text("\(itemsForSelectedDate.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if itemsForSelectedDate.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Nothing scheduled")
                        .font(.subheadline.weight(.medium))
                    Text("Tap + to add an event. Chores due this day also appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ForEach(itemsForSelectedDate) { item in
                        CalendarBarRow(item: item)
                            .contextMenu {
                                if let event = item.event {
                                    shareMenu(for: event)
                                }
                                Button {
                                    itemToColor = item
                                } label: {
                                    Label("Color…", systemImage: "paintpalette")
                                }
                                Button("Delete", role: .destructive) {
                                    deleteItem(item)
                                }
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    private func deleteItem(_ item: CalendarBarItem) {
        if let event = item.event {
            FamilySyncService.shared.noteLocalDeletion(prefix: "event", id: event.id)
            Task { await EventReminderService.cancelReminder(for: event.id) }
            modelContext.delete(event)
        } else if let chore = item.chore {
            FamilySyncService.shared.noteLocalDeletion(prefix: "chore", id: chore.id)
            Task { await ChoreReminderService.cancelReminder(for: chore.id) }
            modelContext.delete(chore)
        }
    }

    // MARK: - Sharing between tribes

    /// Tribes this event could be shared into: every calendar except its own.
    private func shareTargets(for event: CalendarEvent) -> [(key: String, name: String)] {
        var targets: [(key: String, name: String)] = []
        if !event.tribeZoneName.isEmpty {
            targets.append(("", homeTribe?.familyName ?? "My calendar"))
        }
        for tribe in otherTribes where tribe.zoneName != event.tribeZoneName {
            targets.append((tribe.zoneName, tribe.familyName))
        }
        return targets
    }

    @ViewBuilder
    private func shareMenu(for event: CalendarEvent) -> some View {
        let targets = shareTargets(for: event)
        if !targets.isEmpty {
            Menu {
                ForEach(targets, id: \.key) { target in
                    let alreadyShared = events.contains {
                        $0.linkedSourceEventID == event.id && $0.tribeZoneName == target.key
                    }
                    Button {
                        share(event, toZoneKey: target.key)
                    } label: {
                        Label(target.name, systemImage: alreadyShared ? "checkmark" : "calendar.badge.plus")
                    }
                    .disabled(alreadyShared)
                }
            } label: {
                Label("Share to…", systemImage: "arrowshape.turn.up.right")
            }
        }
    }

    /// Puts a linked copy of `event` on another tribe calendar. Only that one event is shared;
    /// the copy keeps following the original's time and details.
    private func share(_ event: CalendarEvent, toZoneKey zoneKey: String) {
        let sourceTribe = event.tribeZoneName.isEmpty
            ? homeTribe
            : memberships.first { $0.zoneName == event.tribeZoneName }
        let copy = CalendarEvent(
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            notes: event.notes,
            location: event.location,
            assignedMember: zoneKey.isEmpty ? event.assignedMember : nil,
            notificationsEnabled: event.notificationsEnabled
        )
        copy.tribeZoneName = zoneKey
        copy.linkedSourceEventID = event.id
        copy.linkedSourceZoneName = sourceTribe?.zoneName ?? ""
        copy.linkedSourceTribeName = sourceTribe?.familyName ?? "My calendar"
        modelContext.insert(copy)
    }

    // MARK: - Filter bar

    private var tribeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tribeChip(
                    name: homeTribe?.familyName ?? "My calendar",
                    color: homeTribe?.color ?? .green,
                    systemImage: "house.fill",
                    isOn: showsHomeItems
                ) {
                    homeTribe?.showOnCalendar.toggle()
                }
                .disabled(homeTribe == nil)

                ForEach(otherTribes, id: \.id) { tribe in
                    tribeChip(
                        name: tribe.familyName,
                        color: tribe.color,
                        systemImage: "calendar",
                        isOn: tribe.showOnCalendar
                    ) {
                        tribe.showOnCalendar.toggle()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    private func tribeChip(
        name: String,
        color: Color,
        systemImage: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(name, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? .white : .primary)
                .background(isOn ? color : Color(.secondarySystemBackground))
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(color, lineWidth: isOn ? 0 : 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "Shown" : "Hidden")
    }

    private var memberFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    filteredMemberIDs.removeAll()
                } label: {
                    Text("Everyone")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(filteredMemberIDs.isEmpty ? Color.themeAccent.opacity(0.2) : Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(filteredMemberIDs.isEmpty ? Color.themeAccent : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)

                ForEach(members, id: \.id) { member in
                    Button {
                        toggleFilter(for: member)
                    } label: {
                        MemberChip(
                            member: member,
                            isSelected: filteredMemberIDs.contains(member.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Helpers

    private func toggleFilter(for member: FamilyMember) {
        if filteredMemberIDs.contains(member.id) {
            filteredMemberIDs.remove(member.id)
        } else {
            filteredMemberIDs.insert(member.id)
        }
    }

    private func shiftMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newMonth
            if !selectedDate.isSameMonth(as: displayedMonth) {
                selectedDate = displayedMonth.startOfMonth
            }
        }
    }
}

// MARK: - Span layout

enum CalendarSpanLayout {
    static func build(
        events: [CalendarEvent],
        chores: [Chore],
        monthDays: [Date],
        tribeTags: [String: TribeTag] = [:]
    ) -> [Date: [CalendarBarItem]] {
        let calendar = Calendar.current
        var result: [Date: [CalendarBarItem]] = [:]
        for day in monthDays {
            result[day.startOfDay] = []
        }

        // Sort longer spans first so lanes stay stable across days
        let sortedEvents = events.sorted { lhs, rhs in
            let lStart = lhs.startDate.startOfDay
            let rStart = rhs.startDate.startOfDay
            if lStart != rStart { return lStart < rStart }
            return lhs.dayCount > rhs.dayCount
        }

        var laneEndDates: [Date] = [] // lane index → busy until this day (inclusive)

        for event in sortedEvents {
            let days = event.inclusiveDays.filter { result[$0] != nil }
            guard let first = days.first, let last = days.last else { continue }

            let lane = assignLane(
                start: first,
                end: last,
                laneEndDates: &laneEndDates
            )

            let multi = days.count > 1
            for day in days {
                let segment: CalendarSpanSegment
                if !multi {
                    segment = .single
                } else if day == first {
                    segment = .start
                } else if day == last {
                    segment = .end
                } else {
                    segment = .middle
                }

                let item = CalendarBarItem(
                    id: "\(event.id.uuidString)-\(day.timeIntervalSince1970)",
                    sourceID: event.id,
                    title: event.title,
                    kind: .event,
                    date: event.startDate,
                    member: event.assignedMember,
                    event: event,
                    chore: nil,
                    spanSegment: segment,
                    lane: lane,
                    isMultiDay: multi,
                    tribe: tribeTags[event.tribeZoneName]
                )
                result[day, default: []].append(item)
            }
        }

        for chore in chores {
            let day = chore.dueDate.startOfDay
            guard result[day] != nil else { continue }
            let lane = assignLane(start: day, end: day, laneEndDates: &laneEndDates)
            let item = CalendarBarItem(
                id: "\(chore.id.uuidString)-\(day.timeIntervalSince1970)",
                sourceID: chore.id,
                title: chore.title,
                kind: .chore,
                date: chore.dueDate,
                member: chore.assignedMember,
                event: nil,
                chore: chore,
                spanSegment: .single,
                lane: lane,
                isMultiDay: false
            )
            result[day, default: []].append(item)
        }

        // Sort each day by lane so bars align across the week
        for day in result.keys {
            result[day]?.sort { lhs, rhs in
                if lhs.lane != rhs.lane { return lhs.lane < rhs.lane }
                return lhs.date < rhs.date
            }
        }

        return result
    }

    private static func assignLane(start: Date, end: Date, laneEndDates: inout [Date]) -> Int {
        for index in laneEndDates.indices {
            // Lane free if previous occupancy ends before this start
            if laneEndDates[index] < start {
                laneEndDates[index] = end
                return index
            }
        }
        laneEndDates.append(end)
        return laneEndDates.count - 1
    }
}

private extension CalendarEvent {
    var lastInclusiveDay: Date {
        let calendar = Calendar.current
        let start = startDate.startOfDay
        var end = endDate.startOfDay

        // All-day and midnight endings are typically exclusive
        if isAllDay || (endDate == end && endDate > startDate) {
            end = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        }
        if end < start { end = start }
        return end
    }

    var dayCount: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: startDate.startOfDay, to: lastInclusiveDay).day ?? 0
        return days + 1
    }

    var inclusiveDays: [Date] {
        let calendar = Calendar.current
        let start = startDate.startOfDay
        let end = lastInclusiveDay
        var days: [Date] = []
        var cursor = start
        while cursor <= end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }
}

// MARK: - Day box

struct DayBoxCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let bars: [CalendarBarItem]
    let maxBars: Int
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var visibleBars: [CalendarBarItem] {
        Array(bars.prefix(maxBars))
    }

    private var overflowCount: Int {
        max(0, bars.count - maxBars)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dayNumber)
                .font(.system(size: 20, weight: isToday || isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(dayNumberColor)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
                .accessibilityLabel("\(dayNumber)")

            VStack(spacing: 2) {
                ForEach(visibleBars) { item in
                    spanningBar(item)
                }

                if overflowCount > 0 {
                    Text("+\(overflowCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .aspectRatio(0.72, contentMode: .fit)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(boxBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2.5 : (isToday ? 1.5 : 0.5))
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .onTapGesture {
            onTap()
        }
        .opacity(isCurrentMonth ? 1 : 0.35)
        .zIndex(1) // let spanning bars draw above neighboring cell edges
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to add an event")
        .accessibilityAction(named: "Add Event") {
            onDoubleTap()
        }
    }

    @ViewBuilder
    private func spanningBar(_ item: CalendarBarItem) -> some View {
        let showTitle = item.spanSegment == .single || item.spanSegment == .start

        RoundedRectangle(cornerRadius: cornerRadius(for: item.spanSegment), style: .continuous)
            .fill(item.color)
            .frame(height: 7)
            .overlay(alignment: .leading) {
                if showTitle {
                    Text(item.title)
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(item.color.contrastingText)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius(for: item.spanSegment), style: .continuous))
            .padding(.leading, leadingPad(for: item.spanSegment))
            .padding(.trailing, trailingPad(for: item.spanSegment))
            // Bridge the 4pt grid gap so multi-day bars look continuous
            .padding(.leading, item.spanSegment == .middle || item.spanSegment == .end ? -2 : 0)
            .padding(.trailing, item.spanSegment == .middle || item.spanSegment == .start ? -2 : 0)
    }

    private func cornerRadius(for segment: CalendarSpanSegment) -> CGFloat {
        switch segment {
        case .single: 3
        case .start: 3
        case .middle: 0
        case .end: 3
        }
    }

    private func leadingPad(for segment: CalendarSpanSegment) -> CGFloat {
        switch segment {
        case .single, .start: 4
        case .middle, .end: 0
        }
    }

    private func trailingPad(for segment: CalendarSpanSegment) -> CGFloat {
        switch segment {
        case .single, .end: 4
        case .middle, .start: 0
        }
    }

    // The app accent is white in light mode, so selection uses the primary color.
    private var dayNumberColor: Color {
        .primary
    }

    private var boxBackground: Color {
        if isSelected {
            return ThemeStore.shared.color(.today).opacity(0.14)
        }
        return Color(.secondarySystemBackground)
    }

    private var borderColor: Color {
        if isSelected || isToday { return ThemeStore.shared.color(.today) }
        return Color(.separator)
    }
}

// MARK: - Detail row (color bar)

struct CalendarBarRow: View {
    let item: CalendarBarItem

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(item.color)
                .frame(width: 6)

            HStack(spacing: 10) {
                if let member = item.member {
                    MemberAvatar(member: member, size: 28, showColorRing: false)
                } else {
                    Image(systemName: item.kind == .chore ? "checklist" : "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 6) {
                        Text(item.kindLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.color.opacity(0.2))
                            .foregroundStyle(item.color)
                            .clipShape(Capsule())

                        if item.isMultiDay {
                            Text("Multi-day")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }

                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if item.tribe != nil || item.linkedFrom != nil {
                        HStack(spacing: 6) {
                            if let tribe = item.tribe {
                                Label(tribe.name, systemImage: "calendar")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(tribe.color)
                            }
                            if let source = item.linkedFrom {
                                Label("From \(source)", systemImage: "link")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let member = item.member {
                        Text(member.name)
                            .font(.caption)
                            .foregroundStyle(member.color)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.vertical, 8)
            .padding(.trailing, 8)
        }
        .background(item.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: [CalendarEvent.self, FamilyMember.self, Chore.self], inMemory: true)
}

