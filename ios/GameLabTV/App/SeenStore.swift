import Foundation

/// The questions, prompts and puzzles this family's TV has already shown.
///
/// The server used to remember this itself, but a free host wipes its disk
/// whenever it sleeps or is redeployed, so the same questions kept coming back.
/// Now the TV keeps the list (as short hashes, never the text), gives it to the
/// server when a room opens, and takes the new ones back when a game ends.
/// Server side: games/content_service.py (restore_seen, snapshot_for_tv).
enum SeenStore {
    private static let defaultsKey = "aurora_tv_seen_v1"
    /// Hashes kept per kind, the most recent last.
    static let cap = 600

    static func load() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return saved
    }

    /// Adds `incoming` (most recent last) to what is stored. A hash seen again
    /// moves to the back, and each kind keeps only its latest `cap`.
    static func merge(_ incoming: [String: [String]]) {
        guard !incoming.isEmpty else { return }
        var all = load()
        for (kind, hashes) in incoming {
            var list = all[kind] ?? []
            for hash in hashes {
                list.removeAll { $0 == hash }
                list.append(hash)
            }
            if list.count > cap { list.removeFirst(list.count - cap) }
            all[kind] = list
        }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
