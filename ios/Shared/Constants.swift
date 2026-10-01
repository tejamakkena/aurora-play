import Foundation
import SwiftUI

enum AppConstants {
    // Stable, permanent deployment -- no more rebuilding every time a LAN
    // IP changes. Render's free tier sleeps after ~15 min idle and takes
    // 30-60s to wake on the first request after that; that's expected, not
    // a bug.
    static let defaultServerURL = URL(string: "https://gamelab2.onrender.com")!

    /// UserDefaults key for a host-chosen server, e.g. a laptop on the party
    /// Wi-Fi ("http://192.168.1.20:5000") when the internet is unreliable.
    static let serverOverrideKey = "aurora_server_url"

    /// The game server: a saved override (set from the phone's join screen),
    /// else an `AuroraServerURL` Info.plist value baked in at build time,
    /// else the hosted default.
    static var serverURL: URL {
        if let saved = UserDefaults.standard.string(forKey: serverOverrideKey),
           let url = validServerURL(saved) {
            return url
        }
        if let baked = Bundle.main.object(forInfoDictionaryKey: "AuroraServerURL") as? String,
           let url = validServerURL(baked) {
            return url
        }
        return defaultServerURL
    }

    /// Accepts "192.168.1.20:5000" or a full http(s) URL; nil if unusable.
    static func validServerURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The native apps talk to their own Socket.IO namespace, kept separate
    /// from the browser games so the two cannot collide.
    static let socketNamespace = "/native"

    // Stable per-device identifier (persisted in UserDefaults)
    static var deviceID: String {
        let key = "gamelab_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}

// MARK: - Color(hex:) convenience

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double((int >>  0) & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
