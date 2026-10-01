import SwiftUI

/// Routes the phone to the correct controller UI based on the game.
struct ControllerGameView: View {
    let room: Room
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    var body: some View {
        switch room.gameID {
        // Invented games
        case .heist:         HeistControllerView(privateData: privateData, onAction: onAction)
        case .stockPanic:    StockPanicControllerView(privateData: privateData, onAction: onAction)
        case .mindMeld:      MindMeldControllerView(privateData: privateData, onAction: onAction)
        case .hotGrid:       HotGridControllerView(privateData: privateData, onAction: onAction)
        case .speedSculptor: SpeedSculptorControllerView(privateData: privateData, onAction: onAction)

        // Knowledge
        case .trivia:        TriviaControllerView(privateData: privateData, onAction: onAction)
        case .digitGuess:    DigitGuessControllerView(privateData: privateData, onAction: onAction)

        // Casino
        case .poker:         PokerControllerView(privateData: privateData, onAction: onAction)
        case .tambola:       TambolaControllerView(privateData: privateData, onAction: onAction)
        case .roulette:      RouletteControllerView(privateData: privateData, onAction: onAction)

        // Social
        case .mafia:         MafiaControllerView(privateData: privateData, onAction: onAction)
        case .rajaMantri:    RajaMantriControllerView(privateData: privateData, onAction: onAction)

        // Strategy / Board
        case .chess:         ChessControllerView(privateData: privateData, onAction: onAction)
        case .connectFour:   Connect4ControllerView(privateData: privateData, onAction: onAction)
        case .memory:        MemoryControllerView(privateData: privateData, onAction: onAction)
        case .snakeLadder:   ShakeToRollControllerView(privateData: privateData, onAction: onAction)

        // Action
        case .pong:          PongControllerView(privateData: privateData, onAction: onAction)

        // Party
        case .bluffIt:       BluffItControllerView(privateData: privateData, onAction: onAction)
        case .lastTap:       LastTapControllerView(privateData: privateData, onAction: onAction)
        case .herd:          HerdControllerView(privateData: privateData, onAction: onAction)
        case .emojiMovie:    EmojiMovieControllerView(privateData: privateData, onAction: onAction)
        case .npat:          NPATControllerView(privateData: privateData, onAction: onAction)
        case .antakshari:    AntakshariControllerView(privateData: privateData, onAction: onAction)
        case .mostLikelyTo:  MostLikelyToControllerView(privateData: privateData, onAction: onAction)

        // Mid group
        case .cipherGrid:    CipherGridControllerView(privateData: privateData, onAction: onAction)
        case .oddOneOut:     OddOneOutControllerView(privateData: privateData, onAction: onAction)
        case .sealedAuction: SealedAuctionControllerView(privateData: privateData, onAction: onAction)
        case .wavelength:    WavelengthControllerView(privateData: privateData, onAction: onAction)
        case .kbc:           KBCControllerView(privateData: privateData, onAction: onAction)
        case .bollywoodCharades:
            BollywoodCharadesControllerView(privateData: privateData, onAction: onAction)

        // Duel and co-op
        case .defuse:        DefuseControllerView(privateData: privateData, onAction: onAction)
        case .battleship:    BattleshipControllerView(privateData: privateData, onAction: onAction)
        case .airHockey:     AirHockeyControllerView(privateData: privateData, onAction: onAction)
        case .heistEscape:   HeistEscapeControllerView(privateData: privateData, onAction: onAction)
        case .ludo:          LudoControllerView(privateData: privateData, onAction: onAction)
        case .carrom:        CarromControllerView(privateData: privateData, onAction: onAction)
        case .teenPatti:     TeenPattiControllerView(privateData: privateData, onAction: onAction)

        // Solo — the phone is optional here; the Siri Remote sends the same actions.
        case .neonSnake:
            DPadControllerView(title: "Neon Snake", actionName: "turn",
                               payloadKey: "direction",
                               privateData: privateData, onAction: onAction)
        case .simonSays:
            SimonSaysControllerView(privateData: privateData, onAction: onAction)
        case .twenty48:      SwipeControllerView(privateData: privateData, onAction: onAction)
        case .brickBreaker:  PaddleControllerView(privateData: privateData, onAction: onAction)
        case .atlas:         AtlasControllerView(privateData: privateData, onAction: onAction)

        // Co-op arcade
        case .blastRunners:
            BlastRunnersControllerView(privateData: privateData, onAction: onAction)
        }
    }
}
