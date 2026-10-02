import Foundation

/// Which commit this build came from, e.g. "Build ced5a5d · Oct 2, 2026".
///
/// `ios/build-stamp.sh` (wired as an XcodeGen pre-build script phase in
/// `ios/project.yml`) writes `BuildStamp.json` into this bundle before
/// every build, so the installed app is always traceable to a commit --
/// this is what answers "is my Apple TV running the new code?".
///
/// Reading is fully optional: a bundle without the file (an older build,
/// or a stamp step that never ran) simply reports "dev build" instead of
/// crashing or showing a placeholder.
enum BuildStamp {
    private struct Payload: Decodable {
        var commit: String = "dev"
        var date: String = "unknown"
    }

    private static let payload: Payload? = {
        guard let url = Bundle.main.url(forResource: "BuildStamp", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        return decoded
    }()

    /// "Build ced5a5d · Oct 2, 2026", or "dev build" when no stamp exists.
    static var displayString: String {
        guard let payload else { return "dev build" }
        let datePart = formattedDate(payload.date).map { " · \($0)" } ?? ""
        return "Build \(payload.commit)\(datePart)"
    }

    private static func formattedDate(_ iso: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
