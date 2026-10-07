import Foundation

// MARK: - NeuroPulse endpoints
//
//   GET  api/neuro/daily?device=&date=&name=
//   POST api/neuro/result
//   GET  api/neuro/profile/<device>
//   GET  api/neuro/leaderboard?date=&device=
//
// Built in the style of ios/Shared/Models/OneStop.swift: every call is
// optional, every failure is silent and returns nil, and nothing here
// touches the main actor, so a call can be made from anywhere. The server
// is games/neuropulse.py; an older server that does not know these paths
// simply 404s and the Mind Gym runs from its cache.

enum NeuroAPI {
    /// A fetch must not hold the workout up: the UI shows the cached or
    /// locally built session straight away and reconciles when this lands.
    private static let timeout: TimeInterval = 15

    private static func url(_ path: String, _ query: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(url: AppConstants.serverURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        return components?.url
    }

    /// The decoded body of a 200 with `success: true`, else nil.
    private static func send(_ request: URLRequest) async -> [String: Any]? {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any],
              NeuroJSON.bool(dict["success"], true) else { return nil }
        return dict
    }

    // MARK: Today's ten steps

    static func daily(device: String = AppConstants.deviceID, date: String,
                      name: String) async -> NeuroSession? {
        var query = [URLQueryItem(name: "device", value: device),
                     URLQueryItem(name: "date", value: date)]
        if !name.isEmpty { query.append(URLQueryItem(name: "name", value: name)) }
        guard let target = url("api/neuro/daily", query) else { return nil }
        var request = URLRequest(url: target)
        request.timeoutInterval = timeout
        guard let body = await send(request) else { return nil }
        return NeuroSession(json: body)
    }

    // MARK: Rate a finished session

    /// `body` is the full POST payload, so a queued session can be replayed
    /// later exactly as it was built.
    static func post(result body: [String: Any]) async -> NeuroSummary? {
        guard let payload = NeuroJSON.data(body) else { return nil }
        return await post(resultData: payload)
    }

    /// The payload already serialised, which is what the view model sends:
    /// `Data` crosses between the main actor and this call cleanly.
    static func post(resultData payload: Data) async -> NeuroSummary? {
        guard let target = url("api/neuro/result") else { return nil }
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        guard let reply = await send(request) else { return nil }
        return NeuroSummary(json: reply)
    }

    /// Posts everything that was queued while offline and returns what is
    /// still waiting (so a second failure keeps its place in the queue).
    static func flush(_ queued: [[String: Any]]) async -> [[String: Any]] {
        var left: [[String: Any]] = []
        for body in queued {
            if await post(result: body) == nil { left.append(body) }
        }
        return left
    }

    // MARK: The long-term picture

    static func profile(device: String = AppConstants.deviceID) async -> NeuroProfile? {
        guard let target = url("api/neuro/profile/\(device)") else { return nil }
        var request = URLRequest(url: target)
        request.timeoutInterval = timeout
        guard let body = await send(request) else { return nil }
        return NeuroProfile(json: body)
    }

    // MARK: Today's pulse scores

    static func leaderboard(date: String,
                            device: String = AppConstants.deviceID) async
        -> (everyone: [NeuroLeaderRow], friends: [NeuroLeaderRow])? {
        let query = [URLQueryItem(name: "date", value: date),
                     URLQueryItem(name: "device", value: device)]
        guard let target = url("api/neuro/leaderboard", query) else { return nil }
        var request = URLRequest(url: target)
        request.timeoutInterval = timeout
        guard let body = await send(request) else { return nil }
        return (everyone: NeuroJSON.dicts(body["everyone"]).map { NeuroLeaderRow(json: $0) },
                friends: NeuroJSON.dicts(body["friends"]).map { NeuroLeaderRow(json: $0) })
    }
}
