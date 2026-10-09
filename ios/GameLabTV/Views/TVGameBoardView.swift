import SwiftUI

/// Routes to the correct game board based on the room's gameID.
struct TVGameBoardView: View {
    let room: Room

    var body: some View {
        switch room.gameID {
        // Invented games
        case .heist:         TVHeistBoardView(room: room)
        case .mindMeld:      TVMindMeldBoardView(room: room)
        case .speedSculptor: TVSpeedSculptorBoardView(room: room)

        // Knowledge
        case .trivia:        TVTriviaBoardView(room: room)

        // Casino
        case .poker:         TVPokerBoardView(room: room)
        case .tambola:       TVTambolaBoardView(room: room)
        case .roulette:      TVRouletteBoardView(room: room)

        // Social
        case .mafia:         TVMafiaBoardView(room: room)
        case .rajaMantri:    TVRajaMantriBoard(room: room)

        // Strategy / Board
        case .connectFour:   TVConnect4BoardView(room: room)
        case .snakeLadder:   TVSnakeLadderBoardView(room: room)

        // Party
        case .bluffIt:       TVBluffItBoardView(room: room)
        case .lastTap:       TVLastTapBoardView(room: room)
        case .herd:          TVHerdBoardView(room: room)
        case .emojiMovie:    TVEmojiMovieBoardView(room: room)
        case .npat:          TVNPATBoardView(room: room)
        case .antakshari:    TVAntakshariBoardView(room: room)
        case .atlas:         TVAtlasBoardView(room: room)
        case .mostLikelyTo:  TVMostLikelyToBoardView(room: room)
        case .brainBattle:   TVBrainBattleBoardView(room: room)
        case .truthOrDare:   TVTruthDareBoardView(room: room)

        // Mid group
        case .cipherGrid:    TVCipherGridBoardView(room: room)
        case .oddOneOut:     TVOddOneOutBoardView(room: room)
        case .sealedAuction: TVSealedAuctionBoardView(room: room)
        case .wavelength:    TVWavelengthBoardView(room: room)
        case .bollywoodCharades: TVBollywoodCharadesBoardView(room: room)

        // Duel and co-op
        case .defuse:        TVDefuseBoardView(room: room)
        case .battleship:    TVBattleshipBoardView(room: room)
        case .heistEscape:   TVHeistEscapeBoardView(room: room)
        case .ludo:          TVLudoBoardView(room: room)
        case .teenPatti:     TVTeenPattiBoardView(room: room)

        // Talk games — argue and ask out loud.
        case .hotTakes:       TVHotTakesBoardView(room: room)
        case .twentyQuestions: TVTwentyQuestionsBoardView(room: room)

        // Retired games stay decodable (a room made by an older build can
        // still carry one) but have no board: say so and send people back
        // to the game list.
        case .chess, .pong, .airHockey, .carrom, .blastRunners,
             .neonSnake, .twenty48, .brickBreaker, .simonSays,
             .memory, .digitGuess, .hotGrid, .stockPanic,
             .kbc, .storyChain:
            PlaceholderBoardView(game: room.gameID)
        }
    }
}
