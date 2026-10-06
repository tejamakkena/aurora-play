import Foundation

// MARK: - Travel Mode models
//
// Travel Mode is one phone in the car running a talking quizmaster:
// riddles and fun quiz questions, read aloud, answered out loud. There is
// no roster, no seats, no room and no setup beyond picking Riddles, Quiz
// or Mix -- everyone in the car just shouts. The quizmaster listens,
// reacts, gives a hint, reveals the answer and moves on by itself.
//
// Content is bundled (TravelDeck.swift) so it works with no signal; Quiz
// also tops itself up with fresh questions from the server when online
// (TravelQuestions.swift).

enum TravelCopy {
    static let safetyLine = "Driver: eyes on the road. Just talk -- no tapping needed."
    static let entrySubtitle = "Riddles and quiz questions, read aloud"
}

// MARK: - Play style

/// The only choice Travel Mode asks for.
enum TravelPlayStyle: String, CaseIterable, Identifiable {
    case riddles
    case quiz
    case brain
    case mix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .riddles: return "Riddles"
        case .quiz:    return "Quiz"
        case .brain:   return "Brain Teasers"
        case .mix:     return "Mix it up"
        }
    }

    var blurb: String {
        switch self {
        case .riddles: return "Brain teasers and silly puzzlers"
        case .quiz:    return "Fun facts about animals, space and the world"
        case .brain:   return "Patterns, quick maths, memory and logic. Gets harder as you go"
        case .mix:     return "A riddle, then a quiz question, and so on"
        }
    }

    var sfSymbol: String {
        switch self {
        case .riddles: return "puzzlepiece.fill"
        case .quiz:    return "lightbulb.fill"
        case .brain:   return "brain.head.profile"
        case .mix:     return "shuffle"
        }
    }
}

// MARK: - TravelItem

/// One riddle or quiz question. Every item is open-answer: the car says
/// the answer out loud and `accepts` lists the phrasings that count.
struct TravelItem: Identifiable, Equatable {
    enum Kind { case riddle, quiz, brain }

    let kind: Kind
    let prompt: String
    /// Shown and spoken on the reveal ("a piano").
    let answer: String
    /// Extra spoken forms that count as correct. `answer` always counts.
    let accepts: [String]
    let hint: String
    /// Fun fact or punchline spoken after the answer.
    let fact: String?
    /// Server quiz questions arrive multiple-choice; the choices are read
    /// out with the question so it stays answerable.
    let options: [String]?
    /// What the quizmaster SAYS when it differs from what's shown: a
    /// memory test speaks the digits but must not print them.
    let spoken: String?

    var id: String { prompt + (spoken ?? "") }

    init(kind: Kind, prompt: String, answer: String, accepts: [String] = [],
         hint: String, fact: String? = nil, options: [String]? = nil,
         spoken: String? = nil) {
        self.spoken = spoken
        self.kind = kind
        self.prompt = prompt
        self.answer = answer
        self.accepts = accepts
        self.hint = hint
        self.fact = fact
        self.options = options
    }

    /// Everything that counts as the right answer.
    var acceptedAnswers: [String] { [answer] + accepts }
}

// MARK: - Server quiz questions

/// One multiple-choice question from GET /api/travel/questions.
struct TravelQuestion {
    let question: String
    let options: [String]   // exactly 4
    let correctIndex: Int   // 0...3
    let explanation: String?

    /// Defensive parse: accepts the endpoint's keys (`question`, `options`,
    /// `correct_answer`) as well as near-miss variants.
    init?(dict: [String: Any]) {
        let q = (dict["question"] as? String) ?? (dict["text"] as? String) ?? ""
        let opts = (dict["options"] as? [String]) ?? (dict["choices"] as? [String]) ?? []
        guard !q.isEmpty, opts.count == 4 else { return nil }
        let ci: Int?
        if let v = dict["correct_answer"] as? Int { ci = v }
        else if let v = dict["correctIndex"] as? Int { ci = v }
        else if let v = dict["answer"] as? Int { ci = v }
        else { ci = nil }
        guard let correct = ci, (0...3).contains(correct) else { return nil }
        self.question = q
        self.options = opts
        self.correctIndex = correct
        self.explanation = dict["explanation"] as? String
    }

    /// The open-answer form the quizmaster plays.
    var asItem: TravelItem {
        let right = options[correctIndex]
        let wrong = options.enumerated()
            .filter { $0.offset != correctIndex }
            .map(\.element)
            .randomElement() ?? right
        let pair = Bool.random() ? [right, wrong] : [wrong, right]
        return TravelItem(
            kind: .quiz,
            prompt: question,
            answer: right,
            hint: "It's either \(pair[0]) or \(pair[1]).",
            fact: explanation,
            options: options
        )
    }
}

// MARK: - Answer matching

/// Forgiving spoken-answer matcher: "it's a piano!", "PIANO" and "pianos"
/// all count for "a piano". Pure and local, so grading is instant.
enum TravelAnswerMatcher {
    private static let fillers: Set<String> = [
        "a", "an", "the", "it", "its", "is", "s", "i", "think", "um", "uh",
        "maybe", "my", "your", "answer", "guess", "oh", "ok", "okay", "be",
    ]

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// The word itself plus its singular guesses ("echoes" -> "echo").
    private static func forms(_ word: String) -> Set<String> {
        var out: Set<String> = [word]
        if word.count > 3, word.hasSuffix("s") { out.insert(String(word.dropLast())) }
        if word.count > 4, word.hasSuffix("es") { out.insert(String(word.dropLast(2))) }
        return out
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        !forms(a).isDisjoint(with: forms(b))
    }

    static func matches(_ transcript: String, accepted: [String]) -> Bool {
        let heard = words(transcript)
        guard !heard.isEmpty else { return false }
        let heardJoined = heard.joined()
        for answer in accepted {
            var target = words(answer)
            // "a piano" -> "piano"; keep the word if it's the whole answer.
            let trimmed = target.filter { !fillers.contains($0) }
            if !trimmed.isEmpty { target = trimmed }
            guard !target.isEmpty else { continue }
            // Contiguous run: "a big piano" still contains "piano".
            if heard.count >= target.count {
                for start in 0...(heard.count - target.count) {
                    let window = heard[start..<(start + target.count)]
                    if zip(window, target).allSatisfy({ same($0, $1) }) { return true }
                }
            }
            // Spacing differences: "sun flower" vs "sunflower".
            let joined = target.joined()
            if joined.count >= 4, heardJoined.contains(joined) { return true }
        }
        return false
    }
}

// MARK: - Spoken commands

/// What the car can say instead of an answer.
enum TravelCommand {
    case hint, giveUp, repeatQuestion, skip

    static func parse(_ transcript: String) -> TravelCommand? {
        let t = " " + TravelAnswerMatcher.words(transcript).joined(separator: " ") + " "
        if t.contains(" hint ") || t.contains(" clue ") { return .hint }
        if t.contains(" give up ") || t.contains(" dont know ") || t.contains(" do not know ")
            || t.contains(" no idea ") || t.contains(" tell us ") || t.contains(" tell me ") {
            return .giveUp
        }
        if t.contains(" repeat ") || t.contains(" say it again ") || t.contains(" one more time ")
            || t.contains(" what was the question ") {
            return .repeatQuestion
        }
        if t.contains(" skip ") || t.contains(" next question ") { return .skip }
        return nil
    }
}
