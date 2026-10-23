import Foundation
import SwiftData

enum ChoreFrequency: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekly, biweekly, monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .once: "One-time"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        }
    }
}

struct ChoreComponent: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var detail: String
    var isCompleted: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        isCompleted: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }
}

@Model
final class Chore {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var dueDate: Date = Date()
    var frequencyRaw: String = ChoreFrequency.weekly.rawValue
    var isCompleted: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false
    var remindersEnabled: Bool = true
    var componentsData: Data = Data()
    /// Personal color override on the calendar ("" = default).
    var customColorHex: String = ""
    /// Position on the chore whiteboard as fractions of the board's width (both axes); -1 = not placed yet.
    var boardX: Double = -1
    var boardY: Double = -1
    /// Marker color the chore is written in on the whiteboard ("" = default ink).
    var markerColorHex: String = ""

    var assignedMember: FamilyMember?

    init(
        title: String,
        dueDate: Date = Date(),
        frequency: ChoreFrequency = .weekly,
        notes: String = "",
        assignedMember: FamilyMember? = nil,
        remindersEnabled: Bool = true,
        components: [ChoreComponent] = []
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.frequencyRaw = frequency.rawValue
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
        self.assignedMember = assignedMember
        self.remindersEnabled = remindersEnabled && assignedMember != nil
        self.componentsData = (try? JSONEncoder().encode(components)) ?? Data()
    }

    var frequency: ChoreFrequency {
        get { ChoreFrequency(rawValue: frequencyRaw) ?? .weekly }
        set { frequencyRaw = newValue.rawValue }
    }

    var components: [ChoreComponent] {
        get {
            let decoded = (try? JSONDecoder().decode([ChoreComponent].self, from: componentsData)) ?? []
            return decoded.sorted { $0.sortOrder < $1.sortOrder }
        }
        set {
            var ordered = newValue
            for index in ordered.indices {
                ordered[index].sortOrder = index
            }
            componentsData = (try? JSONEncoder().encode(ordered)) ?? Data()
            touchForSync()
        }
    }

    var completedComponentCount: Int {
        components.filter(\.isCompleted).count
    }

    func touchForSync() {
        modifiedAt = Date()
    }

    func markComplete() {
        isCompleted = true
        completedAt = Date()
        var updated = components
        for index in updated.indices {
            updated[index].isCompleted = true
        }
        components = updated
        touchForSync()
    }

    func resetForNextOccurrence() {
        isCompleted = false
        completedAt = nil
        dueDate = nextDueDate(from: dueDate, frequency: frequency)
        var updated = components
        for index in updated.indices {
            updated[index].isCompleted = false
        }
        components = updated
        touchForSync()
    }

    func toggleComponent(id: UUID) {
        var updated = components
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isCompleted.toggle()
        components = updated

        if !updated.isEmpty, updated.allSatisfy(\.isCompleted), !isCompleted {
            isCompleted = true
            completedAt = Date()
            touchForSync()
        } else if isCompleted, updated.contains(where: { !$0.isCompleted }) {
            isCompleted = false
            completedAt = nil
            touchForSync()
        }
    }

    private func nextDueDate(from date: Date, frequency: ChoreFrequency) -> Date {
        let calendar = Calendar.current
        switch frequency {
        case .once: return date
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .biweekly: return calendar.date(byAdding: .weekOfYear, value: 2, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
}
