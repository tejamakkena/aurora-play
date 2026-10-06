import Foundation

// MARK: - Would You Rather dilemmas
//
// 150 bundled, family-friendly dilemmas. Each side is the part after
// "Would you rather", so the card can split them into two halves.

struct WouldRatherDilemma: Identifiable, Equatable {
    let a: String
    let b: String

    var id: String { PhonePlayDealer.key(a + " | " + b) }

    /// Splits an AI line such as "Would you rather fly or be invisible?"
    /// into its two sides. When the line has several " or "s, the split
    /// nearest the middle wins. Nil when it cannot be split cleanly.
    static func parse(_ line: String) -> WouldRatherDilemma? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = "would you rather"
        if text.lowercased().hasPrefix(lead) {
            text = String(text.dropFirst(lead.count))
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;-"))
        while text.hasSuffix("?") || text.hasSuffix(".") || text.hasSuffix("!") {
            text = String(text.dropLast())
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lower = text.lowercased()
        var best: Range<String.Index>? = nil
        var bestDistance = Int.max
        let middle = lower.count / 2
        var searchStart = lower.startIndex
        while let found = lower.range(of: " or ", range: searchStart..<lower.endIndex) {
            let offset = lower.distance(from: lower.startIndex, to: found.lowerBound)
            let distance = abs(offset - middle)
            if distance < bestDistance {
                bestDistance = distance
                best = found
            }
            searchStart = found.upperBound
        }
        guard let split = best else { return nil }
        // `lower` and `text` have the same characters for plain text, but
        // lowercasing can change lengths for a few scripts: map by offset.
        let startOffset = lower.distance(from: lower.startIndex, to: split.lowerBound)
        let endOffset = lower.distance(from: lower.startIndex, to: split.upperBound)
        guard endOffset <= text.count else { return nil }
        let first = String(text.prefix(startOffset))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        let second = String(text.dropFirst(endOffset))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        guard first.count >= 2, second.count >= 2 else { return nil }
        return WouldRatherDilemma(a: first, b: second)
    }
}

enum WouldRatherDeck {

    static let all: [WouldRatherDilemma] = pairs.map { WouldRatherDilemma(a: $0.0, b: $0.1) }

    private static let pairs: [(String, String)] = [
        ("be able to fly", "be able to turn invisible"),
        ("never have to sleep", "never have to eat"),
        ("live by the beach", "live in the mountains"),
        ("eat only biryani forever", "never eat biryani again"),
        ("talk to animals", "speak every human language"),
        ("be a famous singer", "be a famous cricketer"),
        ("have a pet dragon", "have a pet unicorn"),
        ("always be ten minutes late", "always be twenty minutes early"),
        ("have no phone for a month", "have no TV for a year"),
        ("be the funniest person in the room", "be the smartest person in the room"),
        ("explore space", "explore the deep ocean"),
        ("have a rewind button for your life", "have a pause button for your life"),
        ("live without music", "live without films"),
        ("only whisper", "only shout"),
        ("be a superhero", "be a wizard"),
        ("have hiccups forever", "always feel like you need to sneeze"),
        ("eat ice cream every day", "eat pizza every day"),
        ("be able to read minds", "be able to see the future"),
        ("live in a treehouse", "live in a houseboat"),
        ("have super speed", "have super strength"),
        ("travel to the past", "travel to the future"),
        ("never get stuck in traffic again", "never get a cold again"),
        ("be a giant", "be the size of an ant"),
        ("have a personal chef", "have a personal driver"),
        ("win the lottery", "live twice as long"),
        ("lose your sense of taste", "lose your sense of smell"),
        ("be stuck on an island alone", "be stuck on an island with someone annoying"),
        ("have a photographic memory", "be able to learn any skill in a day"),
        ("go to a concert", "go to a cricket final"),
        ("always have to sing instead of speak", "always have to dance when you walk"),
        ("live in a world without colour", "live in a world without sound"),
        ("only eat sweet food", "only eat spicy food"),
        ("be famous on the internet", "be rich but unknown"),
        ("have a robot that does homework", "have a robot that does chores"),
        ("be able to breathe underwater", "be able to walk on walls"),
        ("have a pet tiger", "have a pet elephant"),
        ("be the best at every board game", "be the best at every video game"),
        ("never have to brush your teeth", "never have to take a bath"),
        ("live in a castle", "live in a spaceship"),
        ("be a chef", "be a pilot"),
        ("have a nose that glows", "have hair that changes colour with your mood"),
        ("eat a whole lemon", "eat a whole raw onion"),
        ("go one week without your phone", "go one week without sweets"),
        ("be able to teleport", "be able to stop time"),
        ("always know when someone is lying", "always get away with lying"),
        ("live in the city", "live in a village"),
        ("have a holiday every month", "have a three-month holiday once a year"),
        ("be a famous actor", "be a famous scientist"),
        ("never have homework", "never have exams"),
        ("ride a horse to work", "ride a camel to work"),
        ("have a ghost as a friend", "have an alien as a friend"),
        ("be an amazing dancer", "be an amazing singer"),
        ("live where it is always summer", "live where it is always winter"),
        ("have legs as long as a giraffe's", "have a neck as long as a giraffe's"),
        ("be able to fix anything", "be able to cook anything"),
        ("have ten brothers and sisters", "be an only child"),
        ("eat with chopsticks forever", "eat with your hands forever"),
        ("watch only cartoons", "watch only documentaries"),
        ("have a magic carpet", "have a car that can drive underwater"),
        ("be in a film", "write a best-selling book"),
        ("lose all your photos", "lose all your messages"),
        ("live on the moon", "live at the bottom of the sea"),
        ("be twice as tall", "be twice as fast"),
        ("have free food for life", "have free travel for life"),
        ("have a talking parrot", "have a dog that can do maths"),
        ("be able to control the weather", "be able to talk to plants"),
        ("never feel cold", "never feel tired"),
        ("visit every country", "visit every planet"),
        ("know what your pet is thinking", "know what your friends really think of you"),
        ("drink only water forever", "never drink water again but drink anything else"),
        ("have a pool in your room", "have a slide from your room to the kitchen"),
        ("be a famous YouTuber", "be a famous painter"),
        ("lose your eyebrows", "lose your eyelashes"),
        ("have a third eye", "have a third arm"),
        ("be stuck in a lift for a day", "be stuck at an airport for a week"),
        ("only wear pyjamas", "only wear formal clothes"),
        ("be the oldest in your family", "be the youngest in your family"),
        ("have a free shopping spree", "have a free trip abroad"),
        ("be a cat", "be a dog"),
        ("never use social media again", "never watch a film again"),
        ("always win at cards", "always win at races"),
        ("be able to jump as high as a house", "be able to run as fast as a car"),
        ("get a new phone every year", "get a new bicycle every month"),
        ("have a pet penguin", "have a pet monkey"),
        ("eat dessert first", "eat dessert last"),
        ("be a detective", "be a spy"),
        ("know every song's lyrics", "know every film's story"),
        ("sneeze glitter", "cry chocolate milk"),
        ("live in a house made of chocolate", "live in a house made of cheese"),
        ("have your own island", "have your own aeroplane"),
        ("give up mangoes", "give up chocolate"),
        ("be invisible to cameras", "be able to see through walls"),
        ("have a theme park in your garden", "have a cinema in your bedroom"),
        ("always have to tell the truth", "always have to keep a secret"),
        ("go on a safari", "go on a cruise"),
        ("never play a game again", "never read a book again"),
        ("be a mermaid", "be a centaur"),
        ("be able to shrink anything", "be able to make anything bigger"),
        ("have a voice like a chipmunk", "have a voice like a giant"),
        ("be an astronaut", "be a deep-sea diver"),
        ("always be too hot", "always be too cold"),
        ("have a dinosaur as a pet", "have a dinosaur as a teacher"),
        ("live without the internet", "live without air conditioning"),
        ("eat only breakfast foods", "eat only dinner foods"),
        ("never get lost", "never lose anything"),
        ("be a king or queen for a day", "be a superhero for an hour"),
        ("speak only in rhymes", "speak only in questions"),
        ("have a jetpack", "have a hoverboard"),
        ("learn to play every instrument", "learn to speak every language"),
        ("live in a world with no rules", "live in a world with too many rules"),
        ("have your thoughts shown on a screen", "have every conversation recorded"),
        ("be the first person on Mars", "be the first person to meet aliens"),
        ("meet your favourite celebrity", "meet your great-great-grandparents"),
        ("go back to the age of five", "skip ahead to the age of fifty"),
        ("have a bottomless bag of chips", "have a never-ending glass of juice"),
        ("be famous for something silly", "be unknown for something great"),
        ("wake up at 5 in the morning every day", "go to bed at 8 at night every day"),
        ("be a famous chef", "be a famous footballer"),
        ("have only one shoe", "have only one sock"),
        ("live next to a zoo", "live next to an amusement park"),
        ("be able to fly but only a metre off the ground", "be invisible but only when no one is looking"),
        ("lick a slug", "eat a spoonful of hot chilli"),
        ("win an Olympic gold medal", "win an Oscar"),
        ("find a treasure map", "find a magic lamp"),
        ("go camping in a jungle", "go camping in a desert"),
        ("never eat street food again", "never eat at a restaurant again"),
        ("have a twin", "have a clone"),
        ("be stuck in a funny film", "be stuck in an adventure film"),
        ("have a phone that never dies", "have a car that never needs fuel"),
        ("be great at maths", "be great at art"),
        ("ride a roller coaster", "ride a hot air balloon"),
        ("have your own robot", "have your own dragon"),
        ("never have to wait in a queue", "never have to do the dishes"),
        ("live in the year 1900", "live in the year 2200"),
        ("always smell like onions", "always smell like fish"),
        ("eat a bug for money", "sing in public for free"),
        ("be best friends with a superhero", "be best friends with a famous wizard"),
        ("have a new hobby every week", "be the best in the world at one hobby"),
        ("be able to remember every dream", "never have a bad dream"),
        ("swim with dolphins", "fly with eagles"),
        ("live in a huge house far away", "live in a tiny flat close to friends"),
        ("give a speech to a thousand people", "sing a song to ten friends"),
        ("travel by train across the country", "travel by plane around the world"),
        ("have every day be your birthday", "have every day be a holiday"),
        ("be a famous inventor", "be a famous explorer"),
        ("only use a pencil", "only use a pen"),
        ("have a secret door in your house", "have a secret tunnel to school"),
        ("eat pani puri every day", "eat dosa every day"),
        ("be able to talk to your future self", "be able to talk to your past self"),
        ("get a surprise gift every week", "get one huge gift every year"),
    ]
}
