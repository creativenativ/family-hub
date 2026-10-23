import Foundation
import SwiftData

/// Local cache of the CloudKit family hub this device belongs to.
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

    init(
        familyName: String,
        inviteCode: String,
        shareURLString: String,
        zoneName: String,
        zoneOwnerName: String,
        isOwner: Bool
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
    }

    var shareURL: URL? {
        URL(string: shareURLString)
    }

    var formattedInviteCode: String {
        inviteCode.uppercased()
    }
}
