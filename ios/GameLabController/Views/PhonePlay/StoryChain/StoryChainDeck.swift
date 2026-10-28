import Foundation

// MARK: - Secret Story templates
//
// Bundled and offline. Each story has blanks; each player fills one in on the
// phone without seeing anyone else's, then the phone puts them together and
// reads the result aloud. `story` refers to blanks by number: {0}, {1}...
// Prompts say what kind of answer fits, and each has an example (shown
// greyed out in the box, and used if a player taps "Surprise me").
// Everything here is family friendly and gender-neutral.

struct SecretStoryBlank: Equatable {
    let prompt: String
    let example: String
}

struct SecretStoryTemplate: Equatable, Identifiable {
    let id: String
    let title: String
    let symbol: String
    let blanks: [SecretStoryBlank]
    let story: String
}

enum StoryChainDeck {

    static let templates: [SecretStoryTemplate] = [
        SecretStoryTemplate(
            id: "classic", title: "The Classic", symbol: "person.2.fill",
            blanks: [
                .init(prompt: "Name a person. Anyone: someone here, a film star, your aunt.", example: "Shah Rukh Khan"),
                .init(prompt: "Name another person.", example: "the milkman"),
                .init(prompt: "Where did they meet?", example: "on the roof of a moving bus"),
                .init(prompt: "What did the first one say?", example: "Is this seat taken?"),
                .init(prompt: "What did the other one say back?", example: "Only on Tuesdays"),
                .init(prompt: "What happened next?", example: "they opened a samosa shop"),
                .init(prompt: "What did the neighbours say about it?", example: "We always knew"),
            ],
            story: "{0} met {1} {2}. {0} said: \"{3}.\" {1} replied: \"{4}.\" And then {5}. The neighbours said: \"{6}.\""),
        SecretStoryTemplate(
            id: "bollywood", title: "Bollywood Blockbuster", symbol: "film.fill",
            blanks: [
                .init(prompt: "Our hero's name", example: "Raju"),
                .init(prompt: "The other lead's name", example: "Simran"),
                .init(prompt: "Where do they first meet?", example: "at a mango festival in Switzerland"),
                .init(prompt: "What is the villain's evil plan?", example: "to cancel every wedding in India"),
                .init(prompt: "Where do they suddenly break into a song?", example: "on a hilltop, in the rain"),
                .init(prompt: "The shocking twist", example: "the villain is the hero's long-lost twin"),
                .init(prompt: "How does the film end?", example: "everyone dances at a wedding"),
            ],
            story: "In this summer's biggest blockbuster, {0} meets {1} {2}. But the villain has a plan: {3}. Suddenly, they break into a song {4}. Then the twist: {5}! And in the end, {6}. Five stars."),
        SecretStoryTemplate(
            id: "news", title: "Breaking News", symbol: "newspaper.fill",
            blanks: [
                .init(prompt: "Somebody: a person or an animal", example: "a very confident goat"),
                .init(prompt: "What did they do?", example: "stole the mayor's bicycle"),
                .init(prompt: "Where?", example: "in the middle of a cricket match"),
                .init(prompt: "Why? Their excuse", example: "I was late for yoga"),
                .init(prompt: "What did an eyewitness say?", example: "I have seen things today"),
                .init(prompt: "What do the police tell everyone to do?", example: "lock up their bicycles"),
            ],
            story: "Breaking news! Earlier today, {0} {1} {2}. When asked why, they said: \"{3}.\" One eyewitness told us: \"{4}.\" Police are asking everyone to {5}. Back to you in the studio."),
        SecretStoryTemplate(
            id: "wedding", title: "The Wedding Speech", symbol: "heart.fill",
            blanks: [
                .init(prompt: "One half of the happy couple", example: "Rohit"),
                .init(prompt: "The other half", example: "Pooja"),
                .init(prompt: "How did they meet?", example: "fighting over the last samosa"),
                .init(prompt: "A secret talent", example: "crying at cooking shows"),
                .init(prompt: "A terrible habit", example: "replying 'k' to every message"),
                .init(prompt: "Advice for married life", example: "never share the remote"),
                .init(prompt: "Raise your glasses to...", example: "free food"),
            ],
            story: "Friends and family, thank you for coming. {0} and {1} met {2}, and it was love at first sight. Not many people know that {0} has a secret talent: {3}. And {1}'s terrible habit? {4}. My advice for married life: {5}. So please, raise your glasses to {6}!"),
        SecretStoryTemplate(
            id: "interview", title: "The Job Interview", symbol: "briefcase.fill",
            blanks: [
                .init(prompt: "The candidate", example: "Uncle Mehta"),
                .init(prompt: "The job they want", example: "astronaut"),
                .init(prompt: "Their greatest strength", example: "eating very fast"),
                .init(prompt: "Their greatest weakness", example: "scared of pigeons"),
                .init(prompt: "Why did they leave their last job?", example: "the boss saw their dance videos"),
                .init(prompt: "The boss's final decision", example: "hired, but only on weekends"),
            ],
            story: "Today, {0} came in for an interview for the job of {1}. Greatest strength? {2}. Greatest weakness? {3}. Why did they leave their last job? {4}. The final decision: {5}."),
        SecretStoryTemplate(
            id: "fairy", title: "A Fairy Tale", symbol: "sparkles",
            blanks: [
                .init(prompt: "Once upon a time there lived a...", example: "grumpy princess"),
                .init(prompt: "Where did they live?", example: "a castle made of cheese"),
                .init(prompt: "One day, the hero found...", example: "a talking spoon"),
                .init(prompt: "It said...", example: "Do not open the fridge"),
                .init(prompt: "So what did the hero do?", example: "opened the fridge"),
                .init(prompt: "What was inside?", example: "a dragon eating ice cream"),
                .init(prompt: "The moral of the story", example: "always read the label"),
            ],
            story: "Once upon a time, there lived a {0} in {1}. One day, they found {2}, and it said: \"{3}.\" So, naturally, they {4}. Inside was {5}! And the moral of the story: {6}."),
        SecretStoryTemplate(
            id: "postcard", title: "Holiday Postcard", symbol: "airplane",
            blanks: [
                .init(prompt: "Where did you go on holiday?", example: "Goa"),
                .init(prompt: "Who did you go with?", example: "my dentist"),
                .init(prompt: "What did you eat every single day?", example: "cold noodles"),
                .init(prompt: "The worst thing that happened", example: "a monkey stole my passport"),
                .init(prompt: "The best thing that happened", example: "I won a dance contest"),
                .init(prompt: "Something you are bringing home", example: "a coconut named Steve"),
            ],
            story: "Greetings from {0}! I came here with {1}. Every day we ate {2}. The worst moment: {3}. The best moment: {4}. I am bringing home {5}. Wish you were here!"),
        SecretStoryTemplate(
            id: "superhero", title: "Superhero Origin", symbol: "bolt.fill",
            blanks: [
                .init(prompt: "A superhero name", example: "Captain Chutney"),
                .init(prompt: "Their boring day job", example: "a sleepy bank clerk"),
                .init(prompt: "How did they get their powers?", example: "bitten by a radioactive mosquito"),
                .init(prompt: "Their superpower", example: "turning anything into pakoras"),
                .init(prompt: "Their one weakness", example: "loud aunties"),
                .init(prompt: "Their catchphrase", example: "Not today, traffic"),
            ],
            story: "By day, {1}. By night, {0}! It all began when they were {2}. Now they have the power of {3}. Their only weakness: {4}. And when danger strikes, they shout: \"{5}!\""),
    ]

    /// The story with every blank filled. Trailing full stops, exclamation
    /// and question marks are dropped from answers, since the story
    /// supplies its own punctuation.
    static func fill(_ template: SecretStoryTemplate, answers: [String]) -> String {
        var text = template.story
        for index in template.blanks.indices {
            let raw = answers.indices.contains(index) ? answers[index] : ""
            var answer = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = answer.last, ".!?".contains(last) { answer.removeLast() }
            if answer.isEmpty { answer = template.blanks[index].example }
            text = text.replacingOccurrences(of: "{\(index)}", with: answer)
        }
        return text
    }
}
