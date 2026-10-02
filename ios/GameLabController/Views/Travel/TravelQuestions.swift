import Foundation

// MARK: - Travel trivia question fetch
//
// Topic-based generation for Travel Mode trivia. The backend worker owns
// the endpoint; this client coordinates by convention:
//
//   GET {serverURL}/api/travel/questions?topic=<url-encoded>&count=10
//
// Expected response (tolerant parse — see parseTravelQuestions):
//   { "questions": [ { "question": "...",
//                      "options": ["a","b","c","d"],
//                      "correct_answer": 2,
//                      "explanation": "..." } ],
//     "fallback": false }                 // true = server used its offline pack
//
// The parse also accepts the legacy shape (`{"success": true, "questions":
// [...]}` from POST /trivia/generate) and a bare JSON array, so either
// backend iteration works without a client change.
//
// Fallback chain — trivia never dead-ends:
//   1. travel endpoint (live generation)
//   2. legacy POST /trivia/generate (the Gemini route that exists today)
//   3. bundled offline deck (TravelOfflineQuestions.deck)
// Whenever the questions did not come from live generation, `usedOffline`
// is true and the UI shows a small "Using offline questions" note —
// informational, never a blocking error.

enum TravelQuestionSource {
    case live
    case offline
}

struct TravelQuestionFetch {
    let questions: [TravelQuestion]
    let source: TravelQuestionSource
}

func fetchTravelQuestions(topic: String, count: Int = 10) async -> TravelQuestionFetch {
    let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
    let effectiveTopic = cleanTopic.isEmpty ? "General Knowledge" : cleanTopic
    let base = AppConstants.serverURL

    // 1. The travel endpoint (backend worker's build).
    if let result = await fetchFromTravelEndpoint(base: base, topic: effectiveTopic, count: count) {
        return result
    }
    // 2. Legacy Gemini route as a second chance.
    if let result = await fetchFromLegacyTrivia(base: base, topic: effectiveTopic, count: count) {
        return result
    }
    // 3. Bundled deck — always works, even with no signal at all.
    let deck = Array(TravelOfflineQuestions.deck.shuffled().prefix(count))
    return TravelQuestionFetch(questions: deck, source: .offline)
}

// MARK: - Endpoint 1: GET /api/travel/questions

private func fetchFromTravelEndpoint(base: URL, topic: String, count: Int) async -> TravelQuestionFetch? {
    var components = URLComponents(url: base.appendingPathComponent("api/travel/questions"),
                                   resolvingAgainstBaseURL: false)
    components?.queryItems = [
        URLQueryItem(name: "topic", value: topic),
        URLQueryItem(name: "count", value: String(count)),
    ]
    guard let url = components?.url else { return nil }
    guard let (data, response) = await get(url: url) else { return nil }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let questions = parseTravelQuestions(json["questions"] ?? json)
    guard !questions.isEmpty else { return nil }
    // The server says it served its offline pack: still playable, but the
    // UI notes it so the passenger knows a retry later may get fresh ones.
    let fallback = (json["fallback"] as? Bool) ?? false
    return TravelQuestionFetch(questions: Array(questions.prefix(count)),
                               source: fallback ? .offline : .live)
}

// MARK: - Endpoint 2: POST /trivia/generate (legacy Gemini route)

private func fetchFromLegacyTrivia(base: URL, topic: String, count: Int) async -> TravelQuestionFetch? {
    let url = base.appendingPathComponent("trivia/generate")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
        "topic": topic, "difficulty": "medium", "count": count,
    ])
    guard let (data, response) = await send(request: request) else { return nil }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (json["success"] as? Bool) == true else { return nil }
    let questions = parseTravelQuestions(json["questions"] ?? [])
    guard !questions.isEmpty else { return nil }
    // Legacy route has no fallback flag; treat any success here as live.
    return TravelQuestionFetch(questions: Array(questions.prefix(count)), source: .live)
}

// MARK: - Parsing

/// Accepts a bare array or any dict holding the array; each item goes
/// through TravelQuestion's own tolerant init.
private func parseTravelQuestions(_ raw: Any) -> [TravelQuestion] {
    let list: [Any]
    if let arr = raw as? [Any] { list = arr }
    else if let dict = raw as? [String: Any], let arr = dict["questions"] as? [Any] { list = arr }
    else { return [] }
    return list.compactMap { ($0 as? [String: Any]).flatMap(TravelQuestion.init(dict:)) }
}

// MARK: - Transport

/// Generous timeouts: the hosted server sleeps when idle (30-60s cold
/// start) and question generation itself takes seconds.
private func travelSession() -> URLSession {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 90
    return URLSession(configuration: config)
}

private func get(url: URL) async -> (Data, URLResponse)? {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    return await send(request: request)
}

private func send(request: URLRequest) async -> (Data, URLResponse)? {
    do {
        return try await travelSession().data(for: request)
    } catch {
        return nil
    }
}
