import SwiftUI

/// Routes the phone to the correct controller UI based on the game.
///
/// Every controller sits on the Phone Play backdrop, so a screen that does
/// not paint its own background (or is still appearing during a
/// transition) never flashes a different shade.
struct ControllerGameView: View {
    let room: Room
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            controller
        }
    }

    @ViewBuilder
    private var controller: some View {
        switch room.gameID {
        // Invented games
        case .heist:         HeistControllerView(privateData: privateData, onAction: onAction)
        case .mindMeld:      MindMeldControllerView(privateData: privateData, onAction: onAction)
        case .speedSculptor: SpeedSculptorControllerView(privateData: privateData, onAction: onAction)

        // Knowledge
        case .trivia:        TriviaControllerView(privateData: privateData, onAction: onAction)

        // Casino
        case .poker:         PokerControllerView(privateData: privateData, onAction: onAction)
        case .tambola:       TambolaControllerView(privateData: privateData, onAction: onAction)
        case .roulette:      RouletteControllerView(privateData: privateData, onAction: onAction)

        // Social
        case .mafia:         MafiaControllerView(privateData: privateData, onAction: onAction)
        case .rajaMantri:    RajaMantriControllerView(privateData: privateData, onAction: onAction)

        // Strategy / Board
        case .connectFour:   Connect4ControllerView(privateData: privateData, onAction: onAction)
        case .snakeLadder:   ShakeToRollControllerView(privateData: privateData, onAction: onAction)

        // Party
        case .bluffIt:       BluffItControllerView(privateData: privateData, onAction: onAction)
        case .lastTap:       LastTapControllerView(privateData: privateData, onAction: onAction)
        case .herd:          HerdControllerView(privateData: privateData, onAction: onAction)
        case .emojiMovie:    EmojiMovieControllerView(privateData: privateData, onAction: onAction)
        case .npat:          NPATControllerView(privateData: privateData, onAction: onAction)
        case .antakshari:    AntakshariControllerView(privateData: privateData, onAction: onAction)
        case .atlas:         AtlasControllerView(privateData: privateData, onAction: onAction)
        case .mostLikelyTo:  MostLikelyToControllerView(privateData: privateData, onAction: onAction)
        case .brainBattle:   BrainBattleControllerView(privateData: privateData, onAction: onAction)
        case .truthOrDare:   TruthDareControllerView(privateData: privateData, onAction: onAction)

        // Mid group
        case .cipherGrid:    CipherGridControllerView(privateData: privateData, onAction: onAction)
        case .oddOneOut:     OddOneOutControllerView(privateData: privateData, onAction: onAction)
        case .sealedAuction: SealedAuctionControllerView(privateData: privateData, onAction: onAction)
        case .wavelength:    WavelengthControllerView(privateData: privateData, onAction: onAction)
        case .bollywoodCharades:
            BollywoodCharadesControllerView(privateData: privateData, onAction: onAction)

        // Duel and co-op
        case .defuse:        DefuseControllerView(privateData: privateData, onAction: onAction)
        case .battleship:    BattleshipControllerView(privateData: privateData, onAction: onAction)
        case .heistEscape:   HeistEscapeControllerView(privateData: privateData, onAction: onAction)
        case .ludo:          LudoControllerView(privateData: privateData, onAction: onAction)
        case .teenPatti:     TeenPattiControllerView(privateData: privateData, onAction: onAction)

        // Talk games — argue and ask out loud.
        case .hotTakes:
            HotTakesControllerView(privateData: privateData, onAction: onAction)
        case .twentyQuestions:
            TwentyQuestionsControllerView(privateData: privateData, onAction: onAction)

        // Retired games stay decodable (a room made by an older build can
        // still carry one) but have no controller: say so.
        case .chess, .pong, .airHockey, .carrom, .blastRunners,
             .neonSnake, .twenty48, .brickBreaker, .simonSays,
             .memory, .digitGuess, .hotGrid, .stockPanic,
             .kbc, .storyChain:
            RetiredGameControllerView(gameID: room.gameID)
        }
    }
}

/// A retired game has no TV board or phone controller; if a room made by an
/// older build still carries one, say so instead of showing a blank screen.
private struct RetiredGameControllerView: View {
    let gameID: GameID

    var body: some View {
        WaitingState(systemIcon: gameID.sfSymbol,
                     text: gameID.displayName,
                     detail: "This game has been retired. Pick another game on the TV.")
    }
}
