import Foundation

// Game Night's data, shared by the TV board and the host's controller.
//
// The TV receives this on `night_state`; each phone receives the same shape
// inside its `private_state` under the `night` key. Both arrive as untyped JSON
// (`[String: Any]`), so `NightState(dict:)` reads defensively: a missing or
// mistyped field falls back to a default rather than failing, because a decode
// failure here would blank the whole screen mid-party.

// MARK: - Reading untyped JSON

private enum JSON {
    static func string(_ d: [String: Any], _ key: String, _ fallback: String = "") -> String {
        d[key] as? String ?? fallback
    }
    static func int(_ d: [String: Any], _ key: String, _ fallback: Int = 0) -> Int {
        d[key] as? Int ?? fallback
    }
    static func bool(_ d: [String: Any], _ key: String, _ fallback: Bool = false) -> Bool {
        d[key] as? Bool ?? fallback
    }
    /// JSON `1.0` can arrive as an Int, so a Double read must accept both.
    static func number(_ d: [String: Any], _ key: String, _ fallback: Double) -> Double {
        if let v = d[key] as? Double { return v }
        if let v = d[key] as? Int { return Double(v) }
        return fallback
    }
    static func dicts(_ d: [String: Any], _ key: String) -> [[String: Any]] {
        (d[key] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }
    static func strings(_ d: [String: Any], _ key: String) -> [String] {
        (d[key] as? [Any] ?? []).compactMap { $0 as? String }
    }
}

// MARK: - Pieces

/// Something the TV should say aloud. `id` increases with every announcement, so
/// the TV can tell a new one from the same one arriving again on the next tick.
struct NightAnnouncement: Equatable {
    let id: Int
    let lines: [String]
    let language: String
    let rate: Float
    let pitch: Float
    /// A voice preview from the setup screen: speak it, but don't report back.
    let preview: Bool

    init?(dict d: [String: Any]?) {
        guard let d, let id = d["id"] as? Int else { return nil }
        self.id = id
        lines = JSON.strings(d, "lines")
        let voice = d["voice"] as? [String: Any] ?? [:]
        language = JSON.string(voice, "language", "en-US")
        rate = Float(JSON.number(voice, "rate", 0.5))
        pitch = Float(JSON.number(voice, "pitch", 1.0))
        preview = JSON.bool(d, "preview")
    }
}

struct NightGameInfo: Equatable {
    let id: String
    let name: String
    let emoji: String
    let blurb: String

    init?(dict d: [String: Any]?) {
        guard let d, let id = d["id"] as? String else { return nil }
        self.id = id
        name = JSON.string(d, "name")
        emoji = JSON.string(d, "emoji", "🎮")
        blurb = JSON.string(d, "blurb")
    }
}

struct NightLineupItem: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    /// "done", "current" or "next".
    let state: String
}

struct NightStanding: Identifiable, Equatable {
    let id: String
    let name: String
    let points: Int
}

struct NightRecap: Equatable {
    let name: String
    let emoji: String
    let winner: String?
    let skipped: Bool
    let results: [NightStanding]

    init?(dict d: [String: Any]?) {
        guard let d else { return nil }
        name = JSON.string(d, "name")
        emoji = JSON.string(d, "emoji", "🎮")
        winner = d["winner"] as? String
        skipped = JSON.bool(d, "skipped")
        results = JSON.dicts(d, "results").map {
            NightStanding(id: JSON.string($0, "name"),
                          name: JSON.string($0, "name"),
                          points: JSON.int($0, "points"))
        }
    }
}

struct NightGuest: Identifiable, Equatable {
    let id: String
    let name: String
    let isHost: Bool
}

/// One selectable thing on the host's setup screen: an occasion, a voice, a
/// Never Have I Ever pack.
struct NightOption: Identifiable, Equatable {
    let id: String
    let title: String
    let emoji: String
    let detail: String
    /// Occasion: asks for a name. Pack: adults only.
    let flag: Bool
}

/// A game the host can queue.
struct NightGameOption: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    let blurb: String
    let minPlayers: Int
    let maxPlayers: Int
}

// MARK: - Host config

/// What the host is choosing. Sent whole on every change, so the TV's welcome
/// screen follows along live and the server never has to merge partial edits.
struct NightConfig: Equatable {
    var occasion = "gathering"
    var honoree = ""
    var voicePack = "party_host"
    /// In play order.
    var games: [String] = []
    var nhiePack = "mix"
    var nhieRounds = 10

    init() {}

    init(dict d: [String: Any]) {
        occasion = JSON.string(d, "occasion", occasion)
        honoree = JSON.string(d, "honoree")
        voicePack = JSON.string(d, "voicePack", voicePack)
        games = JSON.strings(d, "games")
        nhiePack = JSON.string(d, "nhiePack", nhiePack)
        nhieRounds = JSON.int(d, "nhieRounds", nhieRounds)
    }

    var payload: [String: Any] {
        [
            "occasion": occasion,
            "honoree": honoree,
            "voicePack": voicePack,
            "games": games,
            "nhiePack": nhiePack,
            "nhieRounds": nhieRounds,
        ]
    }
}

/// Everything the host's setup screen offers. Only sent to the host, and only
/// while the night is still being set up.
struct NightSetup: Equatable {
    var config = NightConfig()
    var catalog: [NightGameOption] = []
    var occasions: [NightOption] = []
    var voicePacks: [NightOption] = []
    var nhiePacks: [NightOption] = []
    var roundChoices: [Int] = [10]
    var guestCount = 0

    init?(dict d: [String: Any]) {
        guard let config = d["config"] as? [String: Any] else { return nil }
        self.config = NightConfig(dict: config)
        catalog = JSON.dicts(d, "catalog").map {
            NightGameOption(id: JSON.string($0, "id"), name: JSON.string($0, "name"),
                            emoji: JSON.string($0, "emoji", "🎮"),
                            blurb: JSON.string($0, "blurb"),
                            minPlayers: JSON.int($0, "minPlayers", 1),
                            maxPlayers: JSON.int($0, "maxPlayers", 20))
        }
        occasions = JSON.dicts(d, "occasions").map {
            NightOption(id: JSON.string($0, "id"), title: JSON.string($0, "label"),
                        emoji: JSON.string($0, "emoji"), detail: JSON.string($0, "nameLabel"),
                        flag: JSON.bool($0, "needsName"))
        }
        voicePacks = JSON.dicts(d, "voicePacks").map {
            NightOption(id: JSON.string($0, "id"), title: JSON.string($0, "name"),
                        emoji: JSON.string($0, "emoji"), detail: JSON.string($0, "blurb"),
                        flag: false)
        }
        nhiePacks = JSON.dicts(d, "nhiePacks").map {
            NightOption(id: JSON.string($0, "id"), title: JSON.string($0, "name"),
                        emoji: JSON.string($0, "emoji"), detail: JSON.string($0, "blurb"),
                        flag: JSON.bool($0, "adult"))
        }
        let rounds = (d["nhieRoundChoices"] as? [Any] ?? []).compactMap { $0 as? Int }
        roundChoices = rounds.isEmpty ? [10] : rounds
        guestCount = JSON.int(d, "guestCount")
    }
}

// MARK: - The night

struct NightState: Equatable {
    /// setup, welcome, lineup, intro, playing, interlude, finale, done.
    var phase = "setup"
    var roomCode = ""
    var title = "Game Night"
    var cheer = ""
    var occasion = "gathering"
    var occasionLabel = ""
    var emoji = "🎉"
    var honoree = ""
    var voiceName = ""
    var voiceEmoji = ""
    var gameIndex = 0
    var gameCount = 0
    var currentGame: NightGameInfo?
    var lineup: [NightLineupItem] = []
    var standings: [NightStanding] = []
    var lastGame: NightRecap?

    // TV channel only.
    var announce: NightAnnouncement?
    var hostName: String?
    var guests: [NightGuest] = []

    // Phone only.
    var isHost = false
    var playing = false
    /// A guest who arrived mid-game and sits it out.
    var spectating = false
    var setup: NightSetup?

    init() {}

    init(dict d: [String: Any]) {
        phase = JSON.string(d, "phase", phase)
        roomCode = JSON.string(d, "roomCode")
        title = JSON.string(d, "title", title)
        cheer = JSON.string(d, "cheer")
        occasion = JSON.string(d, "occasion", occasion)
        occasionLabel = JSON.string(d, "occasionLabel")
        emoji = JSON.string(d, "emoji", emoji)
        honoree = JSON.string(d, "honoree")
        let voice = d["voicePack"] as? [String: Any] ?? [:]
        voiceName = JSON.string(voice, "name")
        voiceEmoji = JSON.string(voice, "emoji")
        gameIndex = JSON.int(d, "gameIndex")
        gameCount = JSON.int(d, "gameCount")
        currentGame = NightGameInfo(dict: d["currentGame"] as? [String: Any])
        lineup = JSON.dicts(d, "lineup").map {
            NightLineupItem(id: JSON.string($0, "id"), name: JSON.string($0, "name"),
                            emoji: JSON.string($0, "emoji", "🎮"),
                            state: JSON.string($0, "state", "next"))
        }
        standings = JSON.dicts(d, "standings").map {
            NightStanding(id: JSON.string($0, "id"), name: JSON.string($0, "name"),
                          points: JSON.int($0, "points"))
        }
        lastGame = NightRecap(dict: d["lastGame"] as? [String: Any])
        announce = NightAnnouncement(dict: d["announce"] as? [String: Any])
        hostName = d["hostName"] as? String
        guests = JSON.dicts(d, "guests").map {
            NightGuest(id: JSON.string($0, "id"), name: JSON.string($0, "name"),
                       isHost: JSON.bool($0, "isHost"))
        }
        isHost = JSON.bool(d, "isHost")
        playing = JSON.bool(d, "playing")
        spectating = JSON.bool(d, "spectating")
        setup = NightSetup(dict: d)
    }
}
