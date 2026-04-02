import Foundation

extension String {
    /// Strips common HTML line breaks / tags from API titles for list and header text.
    public var bitefm_sanitizedDisplayLine: String {
        var s = self
        let breaks = ["<br>", "<br/>", "<br />", "<BR>", "<BR/>", "<BR />"]
        for b in breaks {
            s = s.replacingOccurrences(of: b, with: " ", options: .caseInsensitive)
        }
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        }
        s = s.replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "  ", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
