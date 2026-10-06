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
    let sfSymbol: String
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
    case mostLikelyTo  = "most_likely_to"
    case brainBattle   = "brain_battle"

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

    // MARK: Travel Mode — voice-first car games, one phone hosts
    case storyChain     = "story_chain"
    case twentyQuestions = "twenty_questions"
    case hotTakes       = "hot_takes"

    var meta: GameMeta {
        switch self {

        // ---- Originals -------------------------------------------------
        case .trivia:
            return .init(displayName: "Trivia", sfSymbol: "brain.head.profile", category: .knowledge,
                         minPlayers: 2, maxPlayers: 10, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .poker:
            return .init(displayName: "Poker", sfSymbol: "suit.spade.fill", category: .casino,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: true,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .tambola:
            return .init(displayName: "Tambola", sfSymbol: "circle.grid.3x3.fill", category: .casino,
                         minPlayers: 2, maxPlayers: 20, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .mafia:
            return .init(displayName: "Mafia", sfSymbol: "eye.fill", category: .social,
                         minPlayers: 5, maxPlayers: 15, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .heist:
            return .init(displayName: "Heist", sfSymbol: "banknote.fill", category: .social,
                         minPlayers: 3, maxPlayers: 6, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .stockPanic:
            return .init(displayName: "Stock Panic", sfSymbol: "chart.line.uptrend.xyaxis", category: .strategy,
                         minPlayers: 2, maxPlayers: 6, hasPrivateInfo: true,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .mindMeld:
            return .init(displayName: "Mind Meld", sfSymbol: "sparkles", category: .knowledge,
                         minPlayers: 3, maxPlayers: 8, hasPrivateInfo: false,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .hotGrid:
            return .init(displayName: "Hot Grid", sfSymbol: "burst.fill", category: .strategy,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: false,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .speedSculptor:
            return .init(displayName: "Speed Sculptor", sfSymbol: "paintpalette.fill", category: .creative,
                         minPlayers: 3, maxPlayers: 8, hasPrivateInfo: true,
                         phoneInputStyle: .draw, supportsRemote: false, soloPlayable: false)
        case .pong:
            return .init(displayName: "Pong", sfSymbol: "circle.fill", category: .action,
                         minPlayers: 2, maxPlayers: 2, hasPrivateInfo: false,
                         phoneInputStyle: .tilt, supportsRemote: false, soloPlayable: false)
        case .connectFour:
            return .init(displayName: "Connect 4", sfSymbol: "square.grid.3x3.fill", category: .strategy,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .chess:
            return .init(displayName: "Chess", sfSymbol: "checkerboard.rectangle", category: .strategy,
                         minPlayers: 2, maxPlayers: 2, hasPrivateInfo: false,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .snakeLadder:
            return .init(displayName: "Snake & Ladder", sfSymbol: "arrow.up.right", category: .strategy,
                         minPlayers: 2, maxPlayers: 6, hasPrivateInfo: false,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .roulette:
            return .init(displayName: "Roulette", sfSymbol: "record.circle.fill", category: .casino,
                         minPlayers: 1, maxPlayers: 8, hasPrivateInfo: false,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .rajaMantri:
            return .init(displayName: "Raja Mantri", sfSymbol: "crown.fill", category: .social,
                         minPlayers: 4, maxPlayers: 4, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .memory:
            return .init(displayName: "Memory", sfSymbol: "puzzlepiece.fill", category: .strategy,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .digitGuess:
            return .init(displayName: "Digit Guess", sfSymbol: "textformat.123", category: .knowledge,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)

        // ---- Party -----------------------------------------------------
        case .bluffIt:
            return .init(displayName: "Bluff It", sfSymbol: "eye.slash.fill", category: .party,
                         minPlayers: 3, maxPlayers: 16, hasPrivateInfo: true,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .lastTap:
            return .init(displayName: "Last Tap Standing", sfSymbol: "bolt.fill", category: .party,
                         minPlayers: 2, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .herd:
            return .init(displayName: "Herd", sfSymbol: "person.3.fill", category: .party,
                         minPlayers: 3, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .emojiMovie:
            return .init(displayName: "Emoji Movie", sfSymbol: "clapperboard.fill", category: .party,
                         minPlayers: 3, maxPlayers: 16, hasPrivateInfo: true,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .npat:
            return .init(displayName: "Name Place Animal Thing", sfSymbol: "a.circle.fill", category: .party,
                         minPlayers: 2, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .antakshari:
            return .init(displayName: "Antakshari", sfSymbol: "music.note", category: .party,
                         minPlayers: 2, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)
        case .mostLikelyTo:
            return .init(displayName: "Most Likely To", sfSymbol: "hand.thumbsup.fill", category: .party,
                         minPlayers: 3, maxPlayers: 20, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .brainBattle:
            return .init(displayName: "Brain Battle", sfSymbol: "brain", category: .knowledge,
                         minPlayers: 2, maxPlayers: 12, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)

        // ---- Mid group -------------------------------------------------

        case .cipherGrid:
            return .init(displayName: "Cipher Grid", sfSymbol: "key.fill", category: .social,
                         minPlayers: 4, maxPlayers: 12, hasPrivateInfo: true,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .oddOneOut:
            return .init(displayName: "Odd One Out", sfSymbol: "eyeglasses", category: .social,
                         minPlayers: 4, maxPlayers: 10, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .sealedAuction:
            return .init(displayName: "Sealed Auction", sfSymbol: "hammer.fill", category: .strategy,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: true,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .wavelength:
            return .init(displayName: "Wavelength", sfSymbol: "antenna.radiowaves.left.and.right", category: .party,
                         minPlayers: 3, maxPlayers: 10, hasPrivateInfo: true,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .kbc:
            return .init(displayName: "KBC Hot Seat", sfSymbol: "trophy.fill", category: .knowledge,
                         minPlayers: 1, maxPlayers: 20, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .bollywoodCharades:
            // Positioned as Dumb Charades; the content pack is Bollywood
            // movies. Engine id stays "bollywood_charades" (wire protocol).
            return .init(displayName: "Dumb Charades", sfSymbol: "figure.dance", category: .party,
                         minPlayers: 3, maxPlayers: 16, hasPrivateInfo: true,
                         phoneInputStyle: .text, supportsRemote: false, soloPlayable: false)

        // ---- Duel and co-op --------------------------------------------
        case .defuse:
            return .init(displayName: "Defuse", sfSymbol: "timer.fill", category: .coop,
                         minPlayers: 2, maxPlayers: 6, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .battleship:
            return .init(displayName: "Battleship", sfSymbol: "sailboat.fill", category: .strategy,
                         minPlayers: 2, maxPlayers: 2, hasPrivateInfo: true,
                         phoneInputStyle: .tapGrid, supportsRemote: false, soloPlayable: false)
        case .airHockey:
            return .init(displayName: "Air Hockey", sfSymbol: "hockey.puck.fill", category: .action,
                         minPlayers: 2, maxPlayers: 2, hasPrivateInfo: false,
                         phoneInputStyle: .tilt, supportsRemote: false, soloPlayable: false)
        case .heistEscape:
            return .init(displayName: "Heist Escape", sfSymbol: "door.left.hand.open", category: .coop,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .ludo:
            return .init(displayName: "Ludo", sfSymbol: "dice.fill", category: .strategy,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .carrom:
            return .init(displayName: "Carrom", sfSymbol: "circle.dashed", category: .strategy,
                         minPlayers: 2, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .swipe, supportsRemote: false, soloPlayable: false)
        case .teenPatti:
            return .init(displayName: "Teen Patti", sfSymbol: "rectangle.stack.fill", category: .casino,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)

        // ---- Solo / Siri Remote ----------------------------------------
        case .neonSnake:
            return .init(displayName: "Neon Snake", sfSymbol: "waveform.path", category: .solo,
                         minPlayers: 1, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .dpad, supportsRemote: true, soloPlayable: true)
        case .twenty48:
            return .init(displayName: "2048", sfSymbol: "square.grid.2x2.fill", category: .solo,
                         minPlayers: 1, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .swipe, supportsRemote: true, soloPlayable: true)
        case .brickBreaker:
            return .init(displayName: "Brick Breaker", sfSymbol: "rectangle.grid.2x2.fill", category: .solo,
                         minPlayers: 1, maxPlayers: 2, hasPrivateInfo: false,
                         phoneInputStyle: .tilt, supportsRemote: true, soloPlayable: true)
        case .simonSays:
            return .init(displayName: "Simon Says", sfSymbol: "circle.grid.2x2.fill", category: .solo,
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
            return .init(displayName: "Atlas", sfSymbol: "globe", category: .solo,
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
            return .init(displayName: "Blast Runners", sfSymbol: "figure.run", category: .coop,
                         minPlayers: 1, maxPlayers: 4, hasPrivateInfo: false,
                         phoneInputStyle: .dpadPlusAction, supportsRemote: false, soloPlayable: false)

        // ---- Travel Mode ------------------------------------------------
        // Voice-first car games: one phone hosts (passenger operates),
        // driver plays by voice only. Engine ids must stay in sync with
        // utils/validators.py GAME_IDS.
        case .storyChain:
            return .init(displayName: "Story Chain", sfSymbol: "text.book.closed.fill", category: .creative,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .twentyQuestions:
            return .init(displayName: "Twenty Questions", sfSymbol: "questionmark.circle.fill", category: .knowledge,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: true,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        case .hotTakes:
            return .init(displayName: "Hot Takes", sfSymbol: "flame.fill", category: .social,
                         minPlayers: 2, maxPlayers: 8, hasPrivateInfo: false,
                         phoneInputStyle: .tap, supportsRemote: false, soloPlayable: false)
        }
    }

    // Convenience accessors so existing call sites keep working unchanged.
    var displayName: String          { meta.displayName }
    var sfSymbol: String             { meta.sfSymbol }
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
