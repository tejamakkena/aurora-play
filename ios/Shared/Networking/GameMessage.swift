import Foundation
import CoreGraphics

// All Socket.IO events flow through these typed messages.

// MARK: - Outbound (client → server)

enum ClientEvent: String {
    case joinRoom       = "join_room"
    case createRoom     = "create_room"
    case playerReady    = "player_ready"
    case gameAction     = "game_action"    // generic per-game payload
    case startGame      = "start_game"
    case beginGame      = "begin_game"     // host (or TV) lifts the rules gate
    case leaveRoom      = "leave_room"
    case addBot         = "add_bot"          // TV or host, lobby only
    case removeBot      = "remove_bot"
    case setContentPack = "set_content_pack" // question language (Trivia/KBC)
    case setTopic       = "set_topic"        // free-text quiz topic (lobby)
    case setCustomQuestions = "set_custom_questions" // make-your-own quiz
    // Game Night (TV or host, between games)
    case startNight     = "start_night"
    case nextGame       = "next_game"
    case endNight       = "end_night"
    // Teams mode (TV or host; a phone may move itself)
    case setTeams       = "set_teams"
    case moveToTeam     = "move_to_team"
    case clearTeams     = "clear_teams"
    // Voice quizmaster (TV speaks, one phone listens)
    case claimMic       = "claim_mic"       // phone -> server: I hold the mic
    case voiceState      = "voice_state"     // TV/mic -> room: ask/listen/lock/grade
    case voiceTranscript = "voice_transcript" // mic phone -> room: partial/final
    case voiceVerdict    = "voice_verdict"   // mic/TV -> room: grading result
}

// MARK: - Inbound (server → client)

enum ServerEvent: String {
    case roomJoined     = "room_joined"
    case roomUpdated    = "room_updated"
    case gameStarted    = "game_started"
    case gameBegun      = "game_begun"     // rules gate lifted, engine started
    case gameState      = "game_state"     // board update for TV
    case privateState   = "private_state"  // private data for phone only
    case gameEnded      = "game_ended"
    case error          = "error"
    // Voice quizmaster
    case micReassigned  = "mic_reassigned"
    case voiceState      = "voice_state"
    case voiceTranscript = "voice_transcript"
    case voiceVerdict    = "voice_verdict"
}

// MARK: - Payloads

struct JoinRoomPayload: Encodable {
    let roomCode: String
    let playerName: String
    let playerID: String
    let isTV: Bool         // TV app sends true; phone sends false
}

struct CreateRoomPayload: Encodable {
    let gameID: String
    let hostName: String
    let hostID: String
}

struct GameActionPayload: Encodable {
    let roomCode: String
    let playerID: String
    let action: String          // e.g. "answer", "bet", "move"
    let data: [String: AnyCodable]
}

struct RoomJoinedResponse: Decodable {
    let room: Room
    let playerID: String
}

struct GameStateResponse: Decodable {
    let roomCode: String
    let boardState: [String: AnyCodable]   // TV renders this
}

struct PrivateStateResponse: Decodable {
    let roomCode: String
    let playerID: String
    let privateData: [String: AnyCodable]  // only sent to that phone
}

struct ErrorResponse: Decodable {
    let message: String
    let code: String?
}

// MARK: - Voice quizmaster payloads

struct ClaimMicPayload: Encodable {
    let roomCode: String
    let playerID: String
}

struct VoiceStatePayload: Encodable {
    let roomCode: String
    let state: String        // ask | listen | lock | grade
    let questionID: String
}

struct VoiceTranscriptPayload: Encodable {
    let roomCode: String
    let playerID: String
    let text: String
    let isFinal: Bool
    let confidence: Double
}

struct VoiceVerdictPayload: Encodable {
    let roomCode: String
    let correct: Bool?
    let text: String
}

struct MicReassignedResponse: Decodable {
    let roomCode: String
    let playerID: String
    let playerName: String
}

struct VoiceStateResponse: Decodable {
    let roomCode: String
    let state: String
    let questionID: String
}

struct VoiceTranscriptResponse: Decodable {
    let roomCode: String
    let playerID: String
    let text: String
    let isFinal: Bool
    let confidence: Double
}

struct VoiceVerdictResponse: Decodable {
    let roomCode: String
    let correct: Bool?
    let text: String
}

// MARK: - AnyCodable helper (encode/decode arbitrary JSON values)

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)   { value = v; return }
        if let v = try? container.decode(Int.self)    { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(String.self) { value = v; return }
        if let v = try? container.decode([AnyCodable].self) {
            value = v.map(\.value); return
        }
        if let v = try? container.decode([String: AnyCodable].self) {
            value = v.mapValues(\.value); return
        }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:               try container.encode(v)
        case let v as Int:                try container.encode(v)
        case let v as Double:             try container.encode(v)
        // CGFloat/Float are not Double at runtime; without these a touch
        // coordinate or slider value silently went out as null.
        case let v as CGFloat:            try container.encode(Double(v))
        case let v as Float:              try container.encode(Double(v))
        case let v as String:             try container.encode(v)
        case let v as [Any]:
            try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]:
            try container.encode(v.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
