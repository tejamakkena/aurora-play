import Foundation

/// Instant feedback for a tap.
///
/// Every vote or answer travels phone -> server -> phone before the
/// controller used to react, so on a slow connection the button just sat
/// there. For the actions below the phone already knows what the server will
/// say back (each patch is exactly the private-state change the engine makes,
/// pinned by tests/test_optimistic_echo.py), so it shows that at once. The
/// server's own reply still wins: a tap it rejects is corrected by the next
/// private_state, at most `holdSeconds` later.
///
/// Keep in step with static/play/js/optimistic.js (the browser controller).
enum OptimisticEcho {

    /// How long a predicted change is laid over incoming private states
    /// (same round and phase only). Covers a pump update that was already on
    /// its way when the tap went out, which would otherwise flick it back.
    static let holdSeconds: TimeInterval = 1.5

    static func patch(game: GameID, action: String, data: [String: Any]) -> [String: Any]? {
        switch (game, action) {
        case (.wouldRather, "vote"), (.hostLies, "vote"), (.hotTakes, "vote"):
            guard let side = data["side"] as? String else { return nil }
            return ["myVote": side, "hasVoted": true, "hasSubmitted": true]
        case (.mostLikelyTo, "vote"):
            guard let target = data["targetID"] as? String else { return nil }
            return ["myVoteTargetID": target, "hasVoted": true, "hasSubmitted": true]
        case (.oddOneOut, "vote"):
            guard let target = data["targetID"] as? String else { return nil }
            return ["myVote": target, "canVote": false]
        case (.bluffIt, "submit_lie"):
            guard let text = data["text"] as? String, !text.isEmpty else { return nil }
            return ["myLie": text, "hasSubmitted": true]
        case (.bluffIt, "pick"):
            guard let index = data["index"] as? Int else { return nil }
            return ["myPick": index, "hasSubmitted": true]
        case (.herd, "answer"):
            guard let text = data["text"] as? String, !text.isEmpty else { return nil }
            return ["myAnswer": text, "hasSubmitted": true]
        case (.emojiMovie, "submit_emoji"):
            guard let emoji = data["emoji"] as? String, !emoji.isEmpty else { return nil }
            return ["myEmoji": emoji, "hasSubmitted": true]
        case (.npat, "submit"):
            return ["myEntry": data, "hasSubmitted": true]
        case (.atlas, "judge"):
            guard let verdict = data["verdict"] as? String else { return nil }
            return ["myVote": verdict]
        default:
            return nil
        }
    }
}
