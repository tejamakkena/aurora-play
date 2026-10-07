import SwiftUI

// MARK: - Heist — types shared by the TV board and the phone controllers
//
// GameLabTV and GameLabController are separate Xcode targets that only see
// their own folder plus Shared/ (see project.yml). HeistControllerView reads
// role, phase, and position live from the server's privateData, so those
// three types have to live here rather than alongside the TV board.

struct GridPos: Hashable, Codable {
    let col: Int
    let row: Int
}

enum HeistPhase: String {
    case guardSets  = "guard_sets"
    case thievesMove = "thieves_move"
    case reveal     = "reveal"

    var label: String {
        switch self {
        case .guardSets:   return "Guard Setting Cameras"
        case .thievesMove: return "Thieves Moving"
        case .reveal:      return "Reveal"
        }
    }
    /// Shared/ compiles into both targets, so it can reference neither
    /// `PhonePlayDesign` nor `ShellTheme`. These are those kits' red, cyan
    /// and yellow by value; if a token moves there, move it here too.
    var color: Color {
        switch self {
        case .guardSets:   return Color(hex: "FF4D6D")
        case .thievesMove: return Color(hex: "38D6F5")
        case .reveal:      return Color(hex: "FFC531")
        }
    }
}

enum HeistRole { case `guard`, thief }
