import Foundation

// MARK: - Travel Mode models
//
// Travel Mode: one phone hosts in the car. The passenger operates the phone;
// the driver participates by voice only and never touches it. No TV is
// involved (single-phone V1, no multi-phone join).
//
// Two play styles:
//  - Trivia is client-side: the phone fetches topic-based questions over
//    REST (see TravelQuestions.swift) and runs the round locally, with a
//    bundled offline deck as the never-a-dead-end fallback.
//  - Every other travel game runs its real backend engine in a room the
//    phone hosts itself (one seat per car player, all on this socket — see
//    TravelModeViewModel). Prompts come from the engine's public state.

// The line shown persistently on every travel screen.
enum TravelCopy {
    static let safetyLine = "Driver: voice only — never touch the phone."
    static let entrySubtitle = "Voice-first games for the road"
}

// MARK: - TravelGame

/// The travel-friendly games, in playlist order. Raw values are the backend
/// engine ids (games/native_hub/registry.py); every one of these resolves
/// to a real engine — `trivia`, `most_likely_to`, `wavelength` predate
/// Travel Mode, and `story_chain` / `twenty_questions` / `hot_takes` were
/// built for it in games/native_hub/engines/travel.py.
enum TravelGame: String, CaseIterable, Identifiable {
    case trivia
    case mostLikelyTo    = "most_likely_to"
    case storyChain      = "story_chain"
    case twentyQuestions = "twenty_questions"
    case hotTakes        = "hot_takes"
    case wavelength

    var id: String { rawValue }

    /// The shared GameID enum (ios/Shared/Models/Game.swift) carries the
    /// same ids, including the three Travel Mode cases.
    var gameID: GameID { GameID(rawValue: rawValue)! }

    var displayName: String {
        switch self {
        case .trivia:           return "Trivia"
        case .mostLikelyTo:     return "Most Likely To"
        case .storyChain:       return "Story Chain"
        case .twentyQuestions:  return "20 Questions"
        case .hotTakes:         return "Hot Takes"
        case .wavelength:       return "Wavelength"
        }
    }

    var sfSymbol: String {
        switch self {
        case .trivia:           return "brain.head.profile"
        case .mostLikelyTo:     return "person.2.fill"
        case .storyChain:       return "book.fill"
        case .twentyQuestions:  return "questionmark.circle.fill"
        case .hotTakes:         return "flame.fill"
        case .wavelength:       return "waveform"
        }
    }

    var blurb: String {
        switch self {
        case .trivia:           return "Topic-based questions, read aloud"
        case .mostLikelyTo:     return "Vote who fits — secret ballot"
        case .storyChain:       return "Build a story one sentence at a time"
        case .twentyQuestions:  return "Guess the secret in 20 yes/no questions"
        case .hotTakes:         return "Debate the prompt, 90 seconds each"
        case .wavelength:       return "One clue, then dial the spectrum"
        }
    }

    /// Backend minimum seats. The setup screen enforces this roster size
    /// before a server-hosted game can start.
    var minPlayers: Int {
        switch self {
        case .trivia:           return 2
        case .mostLikelyTo:     return 3
        case .storyChain:       return 2
        case .twentyQuestions:  return 2
        case .hotTakes:         return 2
        case .wavelength:       return 3
        }
    }

    /// Trivia is the only game with a topic picker; it runs client-side.
    var usesTopic: Bool { self == .trivia }

    /// Trivia is client-side; the rest run their engines on the server.
    var isServerHosted: Bool { self != .trivia }
}

// MARK: - Local players & scoring

/// One person in the car. Local to the phone: for server-hosted games each
/// player also gets a room seat (see TravelModeViewModel.seatID(for:)),
/// but scoring here is always the phone's own +1 tally.
/// Index 0 of the roster is the phone operator (host seat).
struct TravelPlayer: Identifiable, Equatable {
    let id: String
    var name: String

    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Trivia questions

/// One multiple-choice question, however it arrived: the travel questions
/// endpoint, the legacy /trivia/generate shape, or the bundled offline deck.
struct TravelQuestion {
    let question: String
    let options: [String]   // exactly 4
    let correctIndex: Int   // 0...3
    let explanation: String?

    /// Defensive parse: accepts the endpoint's keys (`question`, `options`,
    /// `correct_answer`) as well as near-miss variants.
    init?(dict: [String: Any]) {
        let q = (dict["question"] as? String) ?? (dict["text"] as? String) ?? ""
        let opts = (dict["options"] as? [String]) ?? (dict["choices"] as? [String]) ?? []
        guard !q.isEmpty, opts.count == 4 else { return nil }
        let ci: Int?
        if let v = dict["correct_answer"] as? Int { ci = v }
        else if let v = dict["correctIndex"] as? Int { ci = v }
        else if let v = dict["answer"] as? Int { ci = v }
        else { ci = nil }
        guard let correct = ci, (0...3).contains(correct) else { return nil }
        self.question = q
        self.options = opts
        self.correctIndex = correct
        self.explanation = dict["explanation"] as? String
    }

    init(question: String, options: [String], correctIndex: Int, explanation: String? = nil) {
        self.question = question
        self.options = options
        self.correctIndex = correctIndex
        self.explanation = explanation
    }
}

// MARK: - create_room payload

/// Mirrors the TV's SoloRoomPayload pattern: the shared CreateRoomPayload
/// stays exactly what the join flow sends; travel adds its own fields.
///
/// `topic` is forward-compatible: today's server ignores unknown
/// create_room keys, but a future backend can read it to seed the room's
/// question pool for topic trivia without any client change.
struct TravelCreateRoomPayload: Encodable {
    let gameID: String
    let hostName: String
    let hostID: String
    let solo: Bool
    let topic: String?
}

// MARK: - Offline trivia deck
//
// Bundled fallback so Travel Mode trivia never dead-ends: if the topic
// endpoint reports its offline pack OR the request fails outright (no
// signal on the road is the normal case, not the exception), play
// continues on these. General knowledge, family-friendly, TTS-safe.

enum TravelOfflineQuestions {
    static let deck: [TravelQuestion] = [
        .init(question: "Which planet is known as the Red Planet?",
              options: ["Venus", "Mars", "Jupiter", "Mercury"], correctIndex: 1),
        .init(question: "How many continents are there on Earth?",
              options: ["Five", "Six", "Seven", "Eight"], correctIndex: 2),
        .init(question: "What is the largest ocean on Earth?",
              options: ["Atlantic", "Indian", "Arctic", "Pacific"], correctIndex: 3),
        .init(question: "Which animal is the tallest in the world?",
              options: ["Elephant", "Giraffe", "Ostrich", "Kangaroo"], correctIndex: 1),
        .init(question: "How many days are in a leap year?",
              options: ["365", "366", "364", "367"], correctIndex: 1),
        .init(question: "What is the capital of France?",
              options: ["London", "Berlin", "Paris", "Madrid"], correctIndex: 2),
        .init(question: "Which instrument has 88 keys?",
              options: ["Guitar", "Violin", "Piano", "Flute"], correctIndex: 2),
        .init(question: "What do you call a baby frog?",
              options: ["Tadpole", "Froglet", "Polliwog", "Cub"], correctIndex: 0),
        .init(question: "Which is the fastest land animal?",
              options: ["Lion", "Cheetah", "Greyhound", "Horse"], correctIndex: 1),
        .init(question: "How many colors are in a rainbow?",
              options: ["Six", "Seven", "Eight", "Five"], correctIndex: 1),
        .init(question: "What is the hardest natural substance on Earth?",
              options: ["Gold", "Iron", "Diamond", "Quartz"], correctIndex: 2),
        .init(question: "Which country invented paper?",
              options: ["Egypt", "Greece", "India", "China"], correctIndex: 3),
        .init(question: "What is the largest desert in the world?",
              options: ["Sahara", "Gobi", "Antarctic", "Kalahari"], correctIndex: 2),
        .init(question: "How many legs does a spider have?",
              options: ["Six", "Eight", "Ten", "Four"], correctIndex: 1),
        .init(question: "Which planet has the most moons?",
              options: ["Jupiter", "Saturn", "Uranus", "Neptune"], correctIndex: 1),
        .init(question: "What is the main ingredient in guacamole?",
              options: ["Tomato", "Avocado", "Onion", "Pepper"], correctIndex: 1),
        .init(question: "Which ocean is the Bermuda Triangle in?",
              options: ["Pacific", "Indian", "Atlantic", "Arctic"], correctIndex: 2),
        .init(question: "How many players are on a soccer team on the field?",
              options: ["Nine", "Ten", "Eleven", "Twelve"], correctIndex: 2),
        .init(question: "What is the capital of Japan?",
              options: ["Kyoto", "Osaka", "Tokyo", "Hiroshima"], correctIndex: 2),
        .init(question: "Which gas do plants absorb from the air?",
              options: ["Oxygen", "Nitrogen", "Carbon dioxide", "Helium"], correctIndex: 2),
        .init(question: "What is the currency of the United Kingdom?",
              options: ["Euro", "Dollar", "Pound", "Franc"], correctIndex: 2),
        .init(question: "Which bird cannot fly but swims well?",
              options: ["Ostrich", "Penguin", "Emu", "Kiwi"], correctIndex: 1),
        .init(question: "How many strings does a standard guitar have?",
              options: ["Four", "Five", "Six", "Seven"], correctIndex: 2),
        .init(question: "What is the tallest mountain in the world?",
              options: ["K2", "Everest", "Kilimanjaro", "Denali"], correctIndex: 1),
    ]
}
