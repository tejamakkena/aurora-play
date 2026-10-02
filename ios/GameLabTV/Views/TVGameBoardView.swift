import SwiftUI

/// Routes to the correct game board based on the room's gameID.
struct TVGameBoardView: View {
    let room: Room

    var body: some View {
        switch room.gameID {
        // Invented games — full implementations
        case .heist:         TVHeistBoardView(room: room)
        case .stockPanic:    TVStockPanicBoardView(room: room)
        case .mindMeld:      TVMindMeldBoardView(room: room)
        case .hotGrid:       TVHotGridBoardView(room: room)
        case .speedSculptor: TVSpeedSculptorBoardView(room: room)

        // Knowledge
        case .trivia:        TVTriviaBoardView(room: room)
        case .digitGuess:    TVDigitGuessBoardView(room: room)

        // Casino
        case .poker:         TVPokerBoardView(room: room)
        case .tambola:       TVTambolaBoardView(room: room)
        case .roulette:      TVRouletteBoardView(room: room)

        // Social
        case .mafia:         TVMafiaBoardView(room: room)
        case .rajaMantri:    TVRajaMantriBoard(room: room)

        // Strategy / Board
        case .chess:         TVChessBoardView(room: room)
        case .connectFour:   TVConnect4BoardView(room: room)
        case .memory:        TVMemoryBoardView(room: room)
        case .snakeLadder:   TVSnakeLadderBoardView(room: room)

        // Action
        case .pong:          TVPongBoardView(room: room)

        // Party
        case .bluffIt:       TVBluffItBoardView(room: room)
        case .lastTap:       TVLastTapBoardView(room: room)
        case .herd:          TVHerdBoardView(room: room)
        case .emojiMovie:    TVEmojiMovieBoardView(room: room)
        case .npat:          TVNPATBoardView(room: room)
        case .antakshari:    TVAntakshariBoardView(room: room)
        case .mostLikelyTo:  TVMostLikelyToBoardView(room: room)

        // Mid group
        case .cipherGrid:    TVCipherGridBoardView(room: room)
        case .oddOneOut:     TVOddOneOutBoardView(room: room)
        case .sealedAuction: TVSealedAuctionBoardView(room: room)
        case .wavelength:    TVWavelengthBoardView(room: room)
        case .kbc:           TVKBCBoardView(room: room)
        case .bollywoodCharades: TVBollywoodCharadesBoardView(room: room)

        // Duel and co-op
        case .defuse:        TVDefuseBoardView(room: room)
        case .battleship:    TVBattleshipBoardView(room: room)
        case .airHockey:     TVAirHockeyBoardView(room: room)
        case .heistEscape:   TVHeistEscapeBoardView(room: room)
        case .ludo:          TVLudoBoardView(room: room)
        case .carrom:        TVCarromBoardView(room: room)
        case .teenPatti:     TVTeenPattiBoardView(room: room)

        // Solo — these also read the Siri Remote directly.
        case .neonSnake:     TVNeonSnakeBoardView(room: room)
        case .twenty48:      TVTwenty48BoardView(room: room)
        case .brickBreaker:  TVBrickBreakerBoardView(room: room)
        case .simonSays:     TVSimonSaysBoardView(room: room)
        case .atlas:         TVAtlasBoardView(room: room)

        // Co-op arcade
        case .blastRunners:  TVBlastRunnersBoardView(room: room)

        // Travel Mode — phone-hosted games; the TV has no board for them.
        case .storyChain:     PlaceholderBoardView(game: .storyChain)
        case .twentyQuestions: PlaceholderBoardView(game: .twentyQuestions)
        case .hotTakes:       PlaceholderBoardView(game: .hotTakes)
        }
    }
}
