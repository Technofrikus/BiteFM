import Foundation

extension String {
    /// Shared, compiled-once regex that strips HTML tags. Compiling `NSRegularExpression`
    /// on every call was wasteful because this property is evaluated per row, per render
    /// (e.g. during list scrolling and the 1 Hz playback time tick).
    private static let bitefmTagStrippingRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "<[^>]+>", options: [])
    }()

    /// Strips common HTML line breaks / tags from API titles for list and header text.
    public var bitefm_sanitizedDisplayLine: String {
        var s = self
        let breaks = ["<br>", "<br/>", "<br />", "<BR>", "<BR/>", "<BR />"]
        for b in breaks {
            s = s.replacingOccurrences(of: b, with: " ", options: .caseInsensitive)
        }
        if let regex = Self.bitefmTagStrippingRegex {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        }
        s = s.replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "  ", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
