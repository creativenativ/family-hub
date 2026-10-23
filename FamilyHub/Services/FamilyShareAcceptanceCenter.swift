import CloudKit
import SwiftUI
import SwiftData
import UIKit

final class FamilyHubAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await FamilyShareAcceptanceCenter.shared.handle(metadata: cloudKitShareMetadata)
        }
    }
}

@MainActor
@Observable
final class FamilyShareAcceptanceCenter {
    static let shared = FamilyShareAcceptanceCenter()

    var pendingMembership: FamilyMembership?
    var errorMessage: String?

    func handle(metadata: CKShare.Metadata) async {
        do {
            let membership = try await FamilyCloudService.shared.acceptShareMetadata(metadata)
            pendingMembership = membership
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
