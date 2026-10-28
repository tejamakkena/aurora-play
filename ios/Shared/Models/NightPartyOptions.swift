import Foundation

/// One choice for a Game Night party: an occasion or a host style. `id` is the
/// value the server stores (games/night_party.py); `symbol` is an SF Symbol.
struct NightPartyChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
}

/// The occasions and host styles the host can pick, on the phone planner and
/// on the TV's own Game Night panel. The server validates the ids.
enum NightPartyOptions {
    static let occasions: [NightPartyChoice] = [
        NightPartyChoice(id: "birthday", title: "Birthday", symbol: "gift.fill"),
        NightPartyChoice(id: "anniversary", title: "Anniversary", symbol: "heart.fill"),
        NightPartyChoice(id: "housewarming", title: "Housewarming", symbol: "house.fill"),
        NightPartyChoice(id: "festival", title: "Festival", symbol: "sparkles"),
        NightPartyChoice(id: "newyear", title: "New Year's Eve", symbol: "moon.stars.fill"),
        NightPartyChoice(id: "gathering", title: "Get-together", symbol: "person.3.fill"),
    ]
    static let styles: [NightPartyChoice] = [
        NightPartyChoice(id: "party_host", title: "Party Host", symbol: "party.popper.fill"),
        NightPartyChoice(id: "game_show", title: "Game Show", symbol: "mic.fill"),
        NightPartyChoice(id: "desi_dost", title: "Desi Dost", symbol: "hands.sparkles.fill"),
        NightPartyChoice(id: "chill", title: "Chill", symbol: "cup.and.saucer.fill"),
    ]
}
