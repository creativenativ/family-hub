import Foundation
import SwiftData

@Model
final class VoiceMemo {
    var id: UUID = UUID()
    var title: String = ""
    var audioData: Data = Data()
    var durationSeconds: Double = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false
    var isHeard: Bool = false
    var scheduledEventID: UUID?

    var fromMember: FamilyMember?
    var toMember: FamilyMember?

    init(
        title: String = "",
        audioData: Data,
        durationSeconds: Double,
        fromMember: FamilyMember? = nil,
        toMember: FamilyMember? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.audioData = audioData
        self.durationSeconds = durationSeconds
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
        self.isHeard = false
        self.scheduledEventID = nil
        self.fromMember = fromMember
        self.toMember = toMember
    }

    var formattedDuration: String {
        let total = Int(durationSeconds.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var isScheduled: Bool {
        scheduledEventID != nil
    }
}
