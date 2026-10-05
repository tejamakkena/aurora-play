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
