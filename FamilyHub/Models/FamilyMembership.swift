import Foundation
import SwiftData
import SwiftUI

/// What a shared tribe holds. Stored on the CloudKit root record and the public invite.
enum TribeKind: String, Codable, CaseIterable, Identifiable {
    /// A household: calendar plus chores, meals, groceries, budget, profiles and the rest.
    case family
    /// A shared calendar only, e.g. a work team or sports club.
    case calendar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .family: "Home tribe"
        case .calendar: "Tribe calendar"
        }
    }
}

/// Local cache of one CloudKit tribe this device belongs to.
/// One family-kind membership can be the device's home tribe; every other membership
/// shares calendar events only.
@Model
final class FamilyMembership {
    var id: UUID = UUID()
    var familyName: String = ""
    var inviteCode: String = ""
    var shareURLString: String = ""
    var rootRecordName: String = "FamilyRoot"
    var zoneName: String = ""
    /// CloudKit zone owner user record name (for shared DB lookups).
    var zoneOwnerName: String = ""
    var isOwner: Bool = false
    var joinedAt: Date = Date()
    var kindRaw: String = TribeKind.family.rawValue
    var isHome: Bool = false
    /// Bubble and calendar color on this device.
    var colorHex: String = ""
    var showOnCalendar: Bool = true
    /// Events that arrived from other members since this tribe was last opened.
    var unreadCount: Int = 0
    var lastActivityAt: Date = Date()

    init(
        familyName: String,
        inviteCode: String,
        shareURLString: String,
        zoneName: String,
        zoneOwnerName: String,
        isOwner: Bool,
        kind: TribeKind = .family
    ) {
        self.id = UUID()
        self.familyName = familyName
        self.inviteCode = inviteCode
        self.shareURLString = shareURLString
        self.rootRecordName = "FamilyRoot"
        self.zoneName = zoneName
        self.zoneOwnerName = zoneOwnerName
        self.isOwner = isOwner
        self.joinedAt = Date()
        self.kindRaw = kind.rawValue
        self.isHome = false
        self.colorHex = Self.defaultColorHex(for: zoneName)
        self.showOnCalendar = true
        self.unreadCount = 0
        self.lastActivityAt = Date()
    }

    var kind: TribeKind {
        get { TribeKind(rawValue: kindRaw) ?? .family }
        set { kindRaw = newValue.rawValue }
    }

    var shareURL: URL? {
        URL(string: shareURLString)
    }

    var formattedInviteCode: String {
        inviteCode.uppercased()
    }

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    /// Value stored in `CalendarEvent.tribeZoneName` for this tribe's events.
    /// Home events use "" so data created before joining any tribe belongs to home.
    var eventZoneKey: String {
        isHome ? "" : zoneName
    }

    var initials: String {
        let words = familyName.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    static func home(in memberships: [FamilyMembership]) -> FamilyMembership? {
        memberships.first { $0.isHome }
    }

    static func extras(in memberships: [FamilyMembership]) -> [FamilyMembership] {
        memberships
            .filter { !$0.isHome }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Before multiple tribes, the single membership was implicitly home. Mark it explicitly, once.
    @MainActor
    static func migrateHomeIfNeeded(in modelContext: ModelContext) {
        let key = "Tribes.homeMigrated"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard let all = try? modelContext.fetch(FetchDescriptor<FamilyMembership>()),
              !all.contains(where: \.isHome),
              let oldest = all.filter({ $0.kind == .family }).min(by: { $0.joinedAt < $1.joinedAt })
        else { return }
        oldest.isHome = true
        if oldest.colorHex.isEmpty {
            oldest.colorHex = MemberColor.green.hex
        }
        try? modelContext.save()
    }

    private static func defaultColorHex(for seed: String) -> String {
        let palette = MemberColor.allCases.map(\.hex)
        let sum = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}
