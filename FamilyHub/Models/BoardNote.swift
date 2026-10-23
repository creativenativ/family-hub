import Foundation
import SwiftData

/// A heading written on the chore whiteboard, e.g. "Kitchen". Shared with the home tribe.
@Model
final class BoardNote {
    var id: UUID = UUID()
    var text: String = ""
    /// Position on the board, as fractions of the board's width (both axes).
    var boardX: Double = 0
    var boardY: Double = 0
    var colorHex: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false

    init(text: String, boardX: Double, boardY: Double, colorHex: String = "") {
        self.id = UUID()
        self.text = text
        self.boardX = boardX
        self.boardY = boardY
        self.colorHex = colorHex
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
    }
}
