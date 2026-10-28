import SwiftUI

// MARK: - Game Night as a party, on the phone
//
// Server: games/night_party.py. The host dresses the night as an occasion (a
// birthday, an anniversary...), names the guest of honour and picks a host style.
// The TV then holds a welcome screen ("Welcome to Venkat's Birthday Party") until
// the host taps Begin, and a voice welcomes everyone and announces the games.

/// One choice in the party form. `id` is the value the server stores.
struct NightPartyChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
}

/// What the host picks. Sent with start_night (`NightPartyPayload`). The ids are
/// the server's (night_party.py, _humor.py, _nhie_packs.py); it validates them.
struct NightPartySettings: Equatable {
    var occasion = "gathering"
    var honoree = ""
    var style = "party_host"
    var humor = "mix"
    var nhiePack = "mix"
    var nhieRounds = 10

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
    static let humors: [NightPartyChoice] = [
        NightPartyChoice(id: "mix", title: "Surprise Mix", symbol: "shuffle"),
        NightPartyChoice(id: "desi", title: "Desi Masala", symbol: "flame.fill"),
        NightPartyChoice(id: "dad", title: "Dad Jokes", symbol: "face.smiling"),
        NightPartyChoice(id: "savage", title: "Savage Roast", symbol: "bolt.fill"),
    ]
    static let nhiePacks: [NightPartyChoice] = [
        NightPartyChoice(id: "mix", title: "Surprise Mix", symbol: "shuffle"),
        NightPartyChoice(id: "classic", title: "Classic", symbol: "face.smiling"),
        NightPartyChoice(id: "funny", title: "Funny and Awkward", symbol: "theatermasks.fill"),
        NightPartyChoice(id: "desi", title: "Desi Edition", symbol: "sparkles"),
        NightPartyChoice(id: "work", title: "Work and School", symbol: "briefcase.fill"),
        NightPartyChoice(id: "foodtravel", title: "Food and Travel", symbol: "airplane"),
        NightPartyChoice(id: "party", title: "Party Night 18+", symbol: "wineglass.fill"),
        NightPartyChoice(id: "afterdark", title: "After Dark 18+", symbol: "moon.stars.fill"),
    ]
    static let roundChoices = [5, 10, 15, 20]

    /// What the name field asks for, or nil when the occasion has no guest of honour.
    var nameLabel: String? {
        switch occasion {
        case "birthday": return "Birthday person"
        case "anniversary": return "Celebrating"
        case "housewarming": return "Home of"
        case "festival": return "Festival (Diwali, Holi, Eid...)"
        case "gathering": return "Hosted by (optional)"
        default: return nil
        }
    }

    var payload: NightPartyPayload {
        NightPartyPayload(occasion: occasion,
                          honoree: honoree.trimmingCharacters(in: .whitespacesAndNewlines),
                          style: style, humor: humor, nhiePack: nhiePack, nhieRounds: nhieRounds)
    }
}

/// The optional "Make it a party" section of the Game Night planner.
struct NightPartyForm: View {
    @Binding var settings: NightPartySettings
    /// Which of tonight's games have options worth showing.
    let hasNeverHaveIEver: Bool
    let hasGuessTheSong: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("OCCASION") {
                chips(NightPartySettings.occasions, selected: settings.occasion) { settings.occasion = $0 }
            }
            if let label = settings.nameLabel {
                TextField(label, text: $settings.honoree)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                        .fill(Color.white.opacity(0.08)))
            }
            section("HOST STYLE") {
                chips(NightPartySettings.styles, selected: settings.style) { settings.style = $0 }
            }
            if hasGuessTheSong {
                section("HUMOR") {
                    chips(NightPartySettings.humors, selected: settings.humor) { settings.humor = $0 }
                }
            }
            if hasNeverHaveIEver {
                section("NEVER HAVE I EVER PACK") {
                    chips(NightPartySettings.nhiePacks, selected: settings.nhiePack) { settings.nhiePack = $0 }
                    HStack(spacing: 8) {
                        Text("Rounds")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                        ForEach(NightPartySettings.roundChoices, id: \.self) { rounds in
                            OneStopChip(title: "\(rounds)", selected: settings.nhieRounds == rounds,
                                        tint: PhonePlayDesign.orange) {
                                settings.nhieRounds = rounds
                            }
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))
            content()
        }
    }

    private func chips(_ options: [NightPartyChoice], selected: String,
                       pick: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(options) { option in
                OneStopChip(title: option.title, selected: selected == option.id,
                            tint: PhonePlayDesign.pink) {
                    PhonePlayHaptics.tap()
                    pick(option.id)
                }
            }
        }
    }
}

/// Shown in the running-night card until the host begins the party.
struct NightBeginPartyRow: View {
    let room: Room
    let party: NightParty
    let isHost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(party.title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            if isHost {
                Text("The TV is showing the welcome screen. Begin when the guests are in.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                OneStopPrimaryButton(title: "Begin the party", systemImage: "party.popper.fill",
                                     colors: OneStopTheme.nightGradient, enabled: true) {
                    OneStopEvents.beginParty(roomCode: room.code)
                }
            } else {
                Text("Waiting for the host to begin the party")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}
