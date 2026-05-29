import Foundation

/// Builds absolute URLs for ByteFM archive audio files (`https://archiv.bytefm.com/…`).
enum ArchivAudioURL {
    static let base = "https://archiv.bytefm.com/"

    private static let pathAllowedCharacters: CharacterSet = {
        var c = CharacterSet.urlPathAllowed
        c.remove(charactersIn: "/")
        return c
    }()

    /// Accepts a relative archive path or an absolute `http(s)` URL string.
    static func make(from pathOrURL: String) -> URL? {
        var path = pathOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        while path.hasPrefix("/") { path.removeFirst() }
        let segments = path.split(separator: "/").map { substr -> String in
            String(substr).addingPercentEncoding(withAllowedCharacters: pathAllowedCharacters) ?? String(substr)
        }
        guard !segments.isEmpty else { return nil }
        return URL(string: base + segments.joined(separator: "/"))
    }
}
