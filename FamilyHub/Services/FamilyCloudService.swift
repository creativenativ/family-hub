import CloudKit
import Foundation
import Observation

struct FamilyParticipantInfo: Identifiable, Hashable {
    var id: String
    var displayName: String
    var roleLabel: String
    var acceptanceLabel: String
    var isCurrentUser: Bool
}

enum FamilyCloudError: LocalizedError {
    case iCloudUnavailable
    case alreadyInFamily
    case notInFamily
    case invalidInviteCode
    case emptyFamilyName
    case inviteNotFound
    case missingShareURL
    case shareMissingURL
    case notOwner

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "Sign in to iCloud in Settings to create or join a shared tribe."
        case .alreadyInFamily:
            return "You're already in this tribe."
        case .notInFamily:
            return "You are not in a shared tribe yet."
        case .invalidInviteCode:
            return "Invite codes look like AB3K-9XP2. Check the code and try again."
        case .emptyFamilyName:
            return "Enter a tribe name to create a shared tribe."
        case .inviteNotFound:
            return "No shared tribe found for that invite code."
        case .missingShareURL:
            return "This invite is missing a share link. Ask the owner to create a new invite."
        case .shareMissingURL:
            return "CloudKit did not return a share link. Try creating the tribe again."
        case .notOwner:
            return "Only the tribe owner can do that."
        }
    }
}

@MainActor
@Observable
final class FamilyCloudService {
    static let shared = FamilyCloudService()
    static let containerIdentifier = "iCloud.com.danielschwartzel.familyhub"

    private let rootRecordName = "FamilyRoot"
    private let familyRecordType = "FamilySpace"
    private let inviteRecordType = "FamilyInvite"

    private var container: CKContainer {
        CKContainer(identifier: Self.containerIdentifier)
    }

    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    var isBusy = false
    var lastErrorMessage: String?
    var iCloudAccountStatus: CKAccountStatus = .couldNotDetermine
    var participants: [FamilyParticipantInfo] = []

    var isiCloudAvailable: Bool {
        iCloudAccountStatus == .available
    }

    // MARK: - Account

    func refreshAccountStatus() async {
        do {
            iCloudAccountStatus = try await container.accountStatus()
        } catch {
            iCloudAccountStatus = .couldNotDetermine
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Create

    func createFamily(named name: String, kind: TribeKind = .family) async throws -> FamilyMembership {
        try await ensureiCloud()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FamilyCloudError.emptyFamilyName
        }

        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        let inviteCode = Self.makeInviteCode()
        let zoneName = "Family-\(UUID().uuidString)"
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await privateDB.save(zone)

        let rootID = CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)
        let root = CKRecord(recordType: familyRecordType, recordID: rootID)
        root["name"] = trimmed as CKRecordValue
        root["inviteCode"] = inviteCode as CKRecordValue
        root["createdAt"] = Date() as CKRecordValue
        root["kind"] = kind.rawValue as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "\(trimmed) · Tribe Time" as CKRecordValue
        share.publicPermission = .readWrite

        let saved = try await savePrivateRecords([root, share])
        guard let savedShare = saved.compactMap({ $0 as? CKShare }).first,
              let shareURL = savedShare.url else {
            throw FamilyCloudError.shareMissingURL
        }

        try await savePublicInvite(
            inviteCode: inviteCode,
            familyName: trimmed,
            shareURL: shareURL,
            zoneName: zoneName,
            kind: kind
        )

        let userRecordID = try await container.userRecordID()
        let membership = FamilyMembership(
            familyName: trimmed,
            inviteCode: inviteCode,
            shareURLString: shareURL.absoluteString,
            zoneName: zoneName,
            zoneOwnerName: userRecordID.recordName,
            isOwner: true,
            kind: kind
        )

        await refreshParticipants(for: membership)
        return membership
    }

    // MARK: - Join

    func joinFamily(inviteCode rawCode: String) async throws -> FamilyMembership {
        try await ensureiCloud()

        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        let inviteCode = Self.normalizeInviteCode(rawCode)
        guard Self.isValidInviteCode(inviteCode) else {
            throw FamilyCloudError.invalidInviteCode
        }

        let inviteID = CKRecord.ID(recordName: Self.publicRecordName(for: inviteCode))
        let invite: CKRecord
        do {
            invite = try await publicDB.record(for: inviteID)
        } catch {
            throw FamilyCloudError.inviteNotFound
        }

        guard let shareURLString = invite["shareURL"] as? String,
              let shareURL = URL(string: shareURLString) else {
            throw FamilyCloudError.missingShareURL
        }

        let familyName = (invite["familyName"] as? String) ?? "Tribe"
        let zoneName = (invite["zoneName"] as? String) ?? ""
        let kind = (invite["kind"] as? String).flatMap(TribeKind.init) ?? .family

        let metadata = try await shareMetadata(for: shareURL)
        _ = try await container.accept(metadata)

        let ownerName = metadata.ownerIdentity.userRecordID?.recordName
            ?? metadata.hierarchicalRootRecordID?.zoneID.ownerName
            ?? CKCurrentUserDefaultName

        let resolvedZoneName = metadata.hierarchicalRootRecordID?.zoneID.zoneName
            ?? zoneName

        let membership = FamilyMembership(
            familyName: familyName,
            inviteCode: inviteCode,
            shareURLString: shareURL.absoluteString,
            zoneName: resolvedZoneName,
            zoneOwnerName: ownerName,
            isOwner: false,
            kind: kind
        )

        await refreshParticipants(for: membership)
        return membership
    }

    func acceptShareMetadata(_ metadata: CKShare.Metadata) async throws -> FamilyMembership {
        try await ensureiCloud()
        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        _ = try await container.accept(metadata)

        let rootID = metadata.hierarchicalRootRecordID
        let zoneID = rootID?.zoneID
        let ownerName = zoneID?.ownerName
            ?? metadata.ownerIdentity.userRecordID?.recordName
            ?? CKCurrentUserDefaultName
        let zoneName = zoneID?.zoneName ?? ""

        var familyName = metadata.share[CKShare.SystemFieldKey.title] as? String ?? "Tribe"
        if familyName.contains("·") {
            familyName = familyName.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) ?? familyName
        }

        var inviteCode = ""
        var kind = TribeKind.family
        if let rootID {
            if let root = try? await sharedDB.record(for: rootID) {
                inviteCode = (root["inviteCode"] as? String) ?? ""
                familyName = (root["name"] as? String) ?? familyName
                kind = (root["kind"] as? String).flatMap(TribeKind.init) ?? .family
            }
        }

        let shareURL = metadata.share.url?.absoluteString ?? ""

        let membership = FamilyMembership(
            familyName: familyName,
            inviteCode: inviteCode,
            shareURLString: shareURL,
            zoneName: zoneName,
            zoneOwnerName: ownerName,
            isOwner: false,
            kind: kind
        )
        await refreshParticipants(for: membership)
        return membership
    }

    // MARK: - Participants / leave

    func refreshParticipants(for membership: FamilyMembership) async {
        do {
            let share = try await fetchShare(for: membership)
            let currentUser = try? await container.userRecordID()
            participants = share.participants.map { participant in
                let name = Self.displayName(for: participant)
                let userRecordName = participant.userIdentity.userRecordID?.recordName
                return FamilyParticipantInfo(
                    id: userRecordName ?? name,
                    displayName: name,
                    roleLabel: Self.roleLabel(participant.role),
                    acceptanceLabel: Self.acceptanceLabel(participant.acceptanceStatus),
                    isCurrentUser: userRecordName != nil && userRecordName == currentUser?.recordName
                )
            }
        } catch {
            participants = []
            lastErrorMessage = error.localizedDescription
        }
    }

    func leaveFamily(_ membership: FamilyMembership) async throws {
        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        if membership.isOwner {
            try await deleteFamilyAsOwner(membership)
        } else {
            let zoneID = CKRecordZone.ID(
                zoneName: membership.zoneName,
                ownerName: membership.zoneOwnerName
            )
            try await sharedDB.deleteRecordZone(withID: zoneID)
        }
        participants = []
    }

    // MARK: - Helpers

    private func deleteFamilyAsOwner(_ membership: FamilyMembership) async throws {
        let zoneID = CKRecordZone.ID(
            zoneName: membership.zoneName,
            ownerName: CKCurrentUserDefaultName
        )

        if let share = try? await fetchShare(for: membership) {
            let delete = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [share.recordID])
            delete.database = privateDB
            delete.savePolicy = .changedKeys
            try await run(delete)
        }

        try await privateDB.deleteRecordZone(withID: zoneID)

        let inviteID = CKRecord.ID(recordName: Self.publicRecordName(for: membership.inviteCode))
        _ = try? await publicDB.deleteRecord(withID: inviteID)
    }

    private func fetchShare(for membership: FamilyMembership) async throws -> CKShare {
        let zoneID: CKRecordZone.ID
        let database: CKDatabase
        if membership.isOwner {
            zoneID = CKRecordZone.ID(zoneName: membership.zoneName, ownerName: CKCurrentUserDefaultName)
            database = privateDB
        } else {
            zoneID = CKRecordZone.ID(zoneName: membership.zoneName, ownerName: membership.zoneOwnerName)
            database = sharedDB
        }

        let rootID = CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)
        let root = try await database.record(for: rootID)
        guard let shareRef = root.share else {
            throw FamilyCloudError.missingShareURL
        }
        let shareRecord = try await database.record(for: shareRef.recordID)
        guard let share = shareRecord as? CKShare else {
            throw FamilyCloudError.missingShareURL
        }
        return share
    }

    private func savePublicInvite(
        inviteCode: String,
        familyName: String,
        shareURL: URL,
        zoneName: String,
        kind: TribeKind
    ) async throws {
        let recordID = CKRecord.ID(recordName: Self.publicRecordName(for: inviteCode))
        let record = CKRecord(recordType: inviteRecordType, recordID: recordID)
        record["inviteCode"] = inviteCode as CKRecordValue
        record["familyName"] = familyName as CKRecordValue
        record["shareURL"] = shareURL.absoluteString as CKRecordValue
        record["zoneName"] = zoneName as CKRecordValue
        record["kind"] = kind.rawValue as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        _ = try await publicDB.save(record)
    }

    private func savePrivateRecords(_ records: [CKRecord]) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .allKeys
            operation.isAtomic = true
            var saved: [CKRecord] = []
            operation.perRecordSaveBlock = { _, result in
                if case .success(let record) = result {
                    saved.append(record)
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success:
                    continuation.resume(returning: saved)
                }
            }
            privateDB.add(operation)
        }
    }

    private func run(_ operation: CKModifyRecordsOperation) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            privateDB.add(operation)
        }
    }

    private func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            var metadata: CKShare.Metadata?
            operation.perShareMetadataResultBlock = { _, result in
                if case .success(let value) = result {
                    metadata = value
                }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success:
                    if let metadata {
                        continuation.resume(returning: metadata)
                    } else {
                        continuation.resume(throwing: FamilyCloudError.inviteNotFound)
                    }
                }
            }
            container.add(operation)
        }
    }

    private func ensureiCloud() async throws {
        let status = try await container.accountStatus()
        iCloudAccountStatus = status
        guard status == .available else {
            throw FamilyCloudError.iCloudUnavailable
        }
    }

    static func makeInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        func part(_ count: Int) -> String {
            String((0..<count).map { _ in alphabet.randomElement()! })
        }
        return "\(part(4))-\(part(4))"
    }

    static func normalizeInviteCode(_ raw: String) -> String {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count == 8 else { return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        let left = cleaned.prefix(4)
        let right = cleaned.suffix(4)
        return "\(left)-\(right)"
    }

    static func isValidInviteCode(_ code: String) -> Bool {
        let normalized = normalizeInviteCode(code)
        let parts = normalized.split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 4 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return normalized.replacingOccurrences(of: "-", with: "")
            .unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func publicRecordName(for inviteCode: String) -> String {
        normalizeInviteCode(inviteCode).replacingOccurrences(of: "-", with: "")
    }

    private static func displayName(for participant: CKShare.Participant) -> String {
        let identity = participant.userIdentity
        if let nameComponents = identity.nameComponents {
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: nameComponents)
            if !formatted.isEmpty { return formatted }
        }
        if let email = identity.lookupInfo?.emailAddress { return email }
        if let phone = identity.lookupInfo?.phoneNumber { return phone }
        if participant.role == .owner { return "Owner" }
        return "Tribe member"
    }

    private static func roleLabel(_ role: CKShare.ParticipantRole) -> String {
        // Every role other than owner reads as "Member", including roles added in newer iOS versions.
        role == .owner ? "Owner" : "Member"
    }

    private static func acceptanceLabel(_ status: CKShare.ParticipantAcceptanceStatus) -> String {
        switch status {
        case .accepted: "Joined"
        case .pending: "Invited"
        case .removed: "Removed"
        case .unknown: "Unknown"
        @unknown default: "Unknown"
        }
    }
}
