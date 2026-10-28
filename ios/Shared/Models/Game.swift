import Foundation

/// Everything the apps need to know about one game.
///
/// Declared as a single table rather than nine parallel switch statements: with
/// forty-one games that shape becomes unmaintainable, and the old
/// `hasPrivateInfo` switch had a `default:` arm that silently answered `false`
/// for any newly added case. One exhaustive switch means the compiler catches a
/// missing game, and every field has to be stated deliberately.
struct GameMeta {
    let displayName: String
    let emoji: String
    let category: GameCategory
    let minPlayers: Int
    let maxPlayers: Int
    /// The phone shows something the TV must never display.
    let hasPrivateInfo: Bool
    let phoneInputStyle: PhoneInputStyle
    /// Fully playable with the Siri Remote, no phone required.
    let supportsRemote: Bool
    /// Works with zero phones connected — the TV starts it on its own.
    let soloPlayable: Bool
}

enum GameID: String, Codable, CaseIterable {

    // MARK: Originals
    case trivia        = "trivia"
    case poker         = "poker"
    case tambola       = "tambola"
    case mafia         = "mafia"
    case heist         = "heist"
    case stockPanic    = "stock_panic"
    case mindMeld      = "mind_meld"
    case hotGrid       = "hot_grid"
    case speedSculptor = "speed_sculptor"
    case pong          = "pong"
    case connectFour   = "connect4"
    case chess         = "chess"
    case snakeLadder   = "snake_ladder"
    case roulette      = "roulette"
    case rajaMantri    = "raja_mantri"
    case memory        = "memory"
    case digitGuess    = "digit_guess"

    // MARK: Party — everyone plays at once, scales to a full room
    case bluffIt       = "bluff_it"
    case lastTap       = "last_tap"
    case herd          = "herd"
    case emojiMovie    = "emoji_movie"
    case npat          = "npat"
    case antakshari    = "antakshari"
    case neverHaveIEver = "never_have_i_ever"

    // MARK: Mid group — roles, deduction and negotiation
    case cipherGrid        = "cipher_grid"
    case oddOneOut         = "odd_one_out"
    case sealedAuction     = "sealed_auction"
    case wavelength        = "wavelength"
    case kbc               = "kbc"
    case bollywoodCharades = "bollywood_charades"

    // MARK: Duel and co-op
    case defuse      = "defuse"
    case battleship  = "battleship"
    case airHockey   = "air_hockey"
    case heistEscape = "heist_escape"
    case ludo        = "ludo"
    case carrom      = "carrom"
    case teenPatti   = "teen_patti"

    // MARK: Solo — Siri Remote only, no phone needed
    case neonSnake    = "neon_snake"
    case twenty48     = "twenty48"
    case brickBreaker = "brick_breaker"
    case simonSays    = "simon_says"
    case atlas        = "atlas"

    // MARK: Co-op arcade
    case blastRunners = "blast_runners"

    // MARK: Game Night -- hosts a whole evening of the games above
    case gameNight = "game_night"

    var meta: GameMeta {
        switch self {

        // ---- Originals -------------------------------------------------
        case .trivia:
            return .init(displayName: "Trivia", emoji: "🧠", category: .knowledge,
                         minPlayers: 2, maxPlayers: 10, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .poker:
            return .init(displayName: "Poker", emoji: "🃏", category: .casino,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: true,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .tambola:
            return .init(displayName: "Tambola", emoji: "🎱", category: .casino,
                         minPlayers: 2, maxPlayers: 20, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .mafia:
            return .init(displayName: "Mafia", emoji: "🕵️", category: .social,
                         minPlayers: 5, maxPlayers: 15, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .heist:
            return .init(displayName: "Heist", emoji: "🏦", category: .social,
                         minPlayers: 3, maxPlayers: 6, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .stockPanic:
            return .init(displayName: "Stock Panic", emoji: "📈", category: .strategy,
                         minPlayers: 2, maxPlayers: 6, hasPrivateInfo: true,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .mindMeld:
            return .init(displayName: "Mind Meld", emoji: "🔮", category: .knowledge,
                         minPlayers: 3, maxPlayers: 8, hasPrivateInfo: false,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .hotGrid:
            return .init(displayName: "Hot Grid", emoji: "💣", category: .strategy,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: false,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .speedSculptor:
            return .init(displayName: "Speed Sculptor", emoji: "🎨", category: .creative,
                         minPlayers: 3, maxPlayers: 8, hasPrivateInfo: true,
                         phoneInputStyle: .draw, supportsRemote: false, soloPlayable: false)
        case .pong:
            return .init(displayName: "Pong", emoji: "🏓", category: .action,
                         minPlayers: 2, maxPlayers: 2, hasPrivateInfo: false,
                         phoneInputStyle: .tilt, supportsRemote: false, soloPlayable: false)
        case .connectFour:
            return .init(displayName: "Connect 4", emoji: "🟡", category: .strategy,
                         minPlayers: 2, maxPlayers: 2, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .chess:
            return .init(displayName: "Chess", emoji: "♟️", category: .strategy,
                         minPlayers: 2, maxPlayers: 2, hasPrivateInfo: false,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .snakeLadder:
            return .init(displayName: "Snake & Ladder", emoji: "🪜", category: .strategy,
                         minPlayers: 2, maxPlayers: 6, hasPrivateInfo: false,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .roulette:
            return .init(displayName: "Roulette", emoji: "🎡", category: .casino,
                         minPlayers: 1, maxPlayers: 8, hasPrivateInfo: false,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .rajaMantri:
            return .init(displayName: "Raja Mantri", emoji: "👑", category: .social,
                         minPlayers: 4, maxPlayers: 4, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .memory:
            return .init(displayName: "Memory", emoji: "🧩", category: .strategy,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .digitGuess:
            return .init(displayName: "Digit Guess", emoji: "🔢", category: .knowledge,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)

        // ---- Party -----------------------------------------------------
        case .bluffIt:
            return .init(displayName: "Bluff It", emoji: "🎭", category: .party,
                         minPlayers: 3, maxPlayers: 16, hasPrivateInfo: true,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .lastTap:
            return .init(displayName: "Last Tap Standing", emoji: "⚡", category: .party,
                         minPlayers: 2, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .herd:
            return .init(displayName: "Herd", emoji: "🐑", category: .party,
                         minPlayers: 3, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .emojiMovie:
            return .init(displayName: "Emoji Movie", emoji: "🎬", category: .party,
                         minPlayers: 3, maxPlayers: 16, hasPrivateInfo: true,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .npat:
            return .init(displayName: "Name Place Animal Thing", emoji: "🅰️", category: .party,
                         minPlayers: 2, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .antakshari:
            return .init(displayName: "Antakshari", emoji: "🎵", category: .party,
                         minPlayers: 2, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .neverHaveIEver:
            // Answers are private until the reveal -- the whole game is
            // finding out who has, so the phone shows what only you chose.
            return .init(displayName: "Never Have I Ever", emoji: "🙋", category: .party,
                         minPlayers: 2, maxPlayers: 20, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)

        // ---- Mid group -------------------------------------------------
        case .cipherGrid:
            return .init(displayName: "Cipher Grid", emoji: "🔠", category: .social,
                         minPlayers: 4, maxPlayers: 12, hasPrivateInfo: true,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .oddOneOut:
            return .init(displayName: "Odd One Out", emoji: "🕶️", category: .social,
                         minPlayers: 4, maxPlayers: 10, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .sealedAuction:
            return .init(displayName: "Sealed Auction", emoji: "💰", category: .strategy,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: true,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .wavelength:
            return .init(displayName: "Wavelength", emoji: "📡", category: .party,
                         minPlayers: 3, maxPlayers: 10, hasPrivateInfo: true,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .kbc:
            return .init(displayName: "KBC Hot Seat", emoji: "💺", category: .knowledge,
                         minPlayers: 1, maxPlayers: 20, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .bollywoodCharades:
            return .init(displayName: "Bollywood Charades", emoji: "💃", category: .party,
                         minPlayers: 3, maxPlayers: 16, hasPrivateInfo: true,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)

        // ---- Duel and co-op --------------------------------------------
        case .defuse:
            return .init(displayName: "Defuse", emoji: "🧨", category: .coop,
                         minPlayers: 2, maxPlayers: 6, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .battleship:
            return .init(displayName: "Battleship", emoji: "🚢", category: .strategy,
                         minPlayers: 2, maxPlayers: 2, hasPrivateInfo: true,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .airHockey:
            return .init(displayName: "Air Hockey", emoji: "🏒", category: .action,
                         minPlayers: 2, maxPlayers: 2, hasPrivateInfo: false,
                         phoneInputStyle: .tilt, supportsRemote: false, soloPlayable: false)
        case .heistEscape:
            return .init(displayName: "Heist Escape", emoji: "🗝️", category: .coop,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .ludo:
            return .init(displayName: "Ludo", emoji: "🎲", category: .strategy,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .carrom:
            return .init(displayName: "Carrom", emoji: "⚫", category: .strategy,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .teenPatti:
            return .init(displayName: "Teen Patti", emoji: "🎴", category: .casino,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)

        // ---- Solo / Siri Remote ----------------------------------------
        case .neonSnake:
            return .init(displayName: "Neon Snake", emoji: "🐍", category: .solo,
                         minPlayers: 1, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .dpad, supportsRemote: true, soloPlayable: true)
        case .twenty48:
            return .init(displayName: "2048", emoji: "2️⃣", category: .solo,
                         minPlayers: 1, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .swipe, supportsRemote: true, soloPlayable: true)
        case .brickBreaker:
            return .init(displayName: "Brick Breaker", emoji: "🧱", category: .solo,
                         minPlayers: 1, maxPlayers: 2, hasPrivateInfo: false,
                         phoneInputStyle: .tilt, supportsRemote: true, soloPlayable: true)
        case .simonSays:
            return .init(displayName: "Simon Says", emoji: "🟩", category: .solo,
                         minPlayers: 1, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .dpad, supportsRemote: true, soloPlayable: true)
        case .atlas:
            // Unlike every other game in this section, Atlas has no remote
            // fallback at all -- its only input is typed text, and there is
            // no on-screen keyboard anywhere in this app. Marking it
            // soloPlayable/supportsRemote used to offer "Play Solo Now" (and
            // a green remote badge on its card) exactly like Neon Snake or
            // Simon Says, which genuinely can be played with nothing but the
            // remote. Reported directly, still broken after the deferred-
            // placeholder fix (see room_manager.Room.pending_host_id): a
            // player who takes "Play Solo Now" at its word never brings out
            // a phone at all, and the round simply times out unanswered.
            // false here routes Atlas through the plain join flow instead,
            // same as Trivia or Poker -- a phone is required from the very
            // first player, which is the only way this game ever works.
            return .init(displayName: "Atlas", emoji: "🌍", category: .solo,
                         minPlayers: 1, maxPlayers: 8, hasPrivateInfo: false,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)

        // ---- Co-op arcade ------------------------------------------------
        case .blastRunners:
            // min_players is 1 server-side (solo play works fine -- the
            // shared life pool just applies to one player), but this game's
            // whole identity is co-op, and offering a "Play Solo Now"
            // shortcut for it would repeat the exact mistake already fixed
            // on Atlas earlier: a player who takes it at its word never
            // brings out a phone, and the game needs one for D-pad + blast
            // input a Siri Remote can't cleanly provide alongside steering.
            // Routing through the normal "Invite Friends" join flow (like
            // Trivia/Poker) is the only configuration that actually works.
            return .init(displayName: "Blast Runners", emoji: "⛏️", category: .coop,
                         minPlayers: 1, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .dpadPlusAction, supportsRemote: false, soloPlayable: false)

        // ---- Game Night ------------------------------------------------
        case .gameNight:
            // Not a game on the grid: the TV offers it as its own button
            // (see TVGameSelectionView.nightBanner). It starts with a single
            // phone -- the iPad that hosts -- and guests keep joining all
            // evening, so min is 1 and the lobby is skipped.
            return .init(displayName: "Game Night", emoji: "🎉", category: .party,
                         minPlayers: 1, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        }
    }

    // Convenience accessors so existing call sites keep working unchanged.
    var displayName: String          { meta.displayName }
    var emoji: String                { meta.emoji }
    var category: GameCategory       { meta.category }
    var minPlayers: Int              { meta.minPlayers }
    var maxPlayers: Int              { meta.maxPlayers }
    var hasPrivateInfo: Bool         { meta.hasPrivateInfo }
    var phoneInputStyle: PhoneInputStyle { meta.phoneInputStyle }
    var supportsRemote: Bool         { meta.supportsRemote }
    var soloPlayable: Bool           { meta.soloPlayable }

    /// Games playable alone on the TV with nothing but the remote.
    static var soloGames: [GameID] { allCases.filter(\.soloPlayable) }
}

enum GameCategory: String, CaseIterable {
    case party     = "Party"
    case knowledge = "Knowledge"
    case social    = "Social"
    case strategy  = "Strategy"
    case casino    = "Casino"
    case coop      = "Co-op"
    case creative  = "Creative"
    case action    = "Action"
    case solo      = "Solo"
}

enum PhoneInputStyle {
    case tap        // single tap on options
    case tapGrid    // tap cells in a grid
    case swipe      // swipe gestures / sliders
    case draw       // drawing canvas
    case tilt       // gyroscope / accelerometer
    case text       // typed answers
    case dpad       // directional pad
    case dpadPlusAction // directional pad plus one large action button
}
