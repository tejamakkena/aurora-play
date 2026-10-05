import Foundation

// MARK: - Fresh quiz questions from the server
//
//   GET {serverURL}/api/travel/questions?topic=<url-encoded>&count=10
//       &device=<id>&exclude=<json array of already-asked question texts>
//
// Response: { "questions": [ { "question", "options": [4],
//             "correct_answer": 0-3, "explanation" } ], "fallback": bool }
//
// Purely a top-up: Travel Mode starts on the bundled deck instantly and
// mixes these in when they arrive. No signal, a sleeping server or a bad
// response all just mean "keep playing the bundled deck" -- never an error.

/// Kid-friendly topics the quiz rotates through.
let travelQuizTopics = [
    "Fun Animal Facts", "Space and Planets", "World Geography",
    "Food Around the World", "Human Body", "Inventions",
]

func fetchLiveQuizQuestions(topic: String, count: Int = 8,
                            exclude: [String] = []) async -> [TravelQuestion] {
    var components = URLComponents(
        url: AppConstants.serverURL.appendingPathComponent("api/travel/questions"),
        resolvingAgainstBaseURL: false)
    var queryItems = [
        URLQueryItem(name: "topic", value: topic),
        URLQueryItem(name: "count", value: String(count)),
        URLQueryItem(name: "device", value: AppConstants.deviceID),
    ]
    // History is oldest-first; the most recent texts matter most.
    let recent = Array(exclude.suffix(150))
    if !recent.isEmpty,
       let json = try? JSONSerialization.data(withJSONObject: recent),
       let text = String(data: json, encoding: .utf8) {
        queryItems.append(URLQueryItem(name: "exclude", value: text))
    }
    components?.queryItems = queryItems
    guard let url = components?.url else { return [] }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    // Generous: the hosted server can take 30-60 s to wake. Nobody waits
    // on this -- the game is already running on the bundled deck.
    request.timeoutInterval = 60
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: data) else { return [] }

    let raw: Any = (json as? [String: Any])?["questions"] ?? json
    let list = raw as? [Any] ?? []
    return list.compactMap { ($0 as? [String: Any]).flatMap(TravelQuestion.init(dict:)) }
}

// MARK: - Fresh riddles / fun-fact questions (games/travel_items.py)
//
//   POST {serverURL}/api/travel/items
//        {"kind": "riddle"|"quiz", "count": 8, "device": <id>,
//         "seen": [answers this phone has already heard]}
//
// The server writes these with its model (OpenAI, then Gemini) and keeps
// a shared pool, deduped by ANSWER per device -- so a riddle can't come
// back reworded. An empty list (no model configured, offline, pool and
// model both dry) just means "keep playing the bundled deck".

func fetchTravelItems(kind: TravelItem.Kind, count: Int = 8,
                      seenAnswers: [String]) async -> [TravelItem] {
    let url = AppConstants.serverURL.appendingPathComponent("api/travel/items")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 60
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
        "kind": kind == .riddle ? "riddle" : "quiz",
        "count": count,
        "device": AppConstants.deviceID,
        "seen": Array(seenAnswers.suffix(300)),
    ] as [String: Any])
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = json["items"] as? [[String: Any]] else { return [] }
    return list.compactMap { raw -> TravelItem? in
        guard let prompt = raw["prompt"] as? String, !prompt.isEmpty,
              let answer = raw["answer"] as? String, !answer.isEmpty,
              let hint = raw["hint"] as? String else { return nil }
        return TravelItem(kind: kind, prompt: prompt, answer: answer,
                          accepts: raw["accepts"] as? [String] ?? [],
                          hint: hint, fact: raw["fact"] as? String)
    }
}
