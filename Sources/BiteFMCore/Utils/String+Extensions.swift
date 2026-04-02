import Foundation

extension String {
    /// Lightweight entity decoding for short API labels in hot UI paths.
    /// Avoids NSAttributedString HTML parsing during SwiftUI body evaluation.
    var decodedBasicHTMLEntities: String {
        Self.decodeCommonHTMLEntities(self)
    }

    var unescapedHTML: String {
        guard let data = self.data(using: .utf8) else { return self }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributedString.string
        }
        
        // Simple manual replacement for &ndash; if it fails
        return self.replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
    
    /// Plain text for API/HTML fragments (e.g. show descriptions): decodes entities like `&nbsp;`, turns `<br>` into newlines.
    var htmlFragmentPlainText: String {
        var fragment = self
        fragment = fragment.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        fragment = fragment.replacingOccurrences(of: "(?i)</p>", with: "\n\n", options: .regularExpression)
        fragment = fragment.replacingOccurrences(of: "(?i)<p[^>]*>", with: "", options: .regularExpression)
        
        let wrapped = """
        <!DOCTYPE html><html><head><meta charset="utf-8"></head><body>\(fragment)</body></html>
        """
        guard let data = wrapped.data(using: .utf8) else { return Self.decodeCommonHTMLEntities(fragment.strippedHTMLTags) }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{2028}", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\u{00A0}")))
        }
        
        return Self.decodeCommonHTMLEntities(fragment.strippedHTMLTags)
    }
    
    private var strippedHTMLTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
    
    private static func decodeCommonHTMLEntities(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "&nbsp;", with: " ")
        t = t.replacingOccurrences(of: "&#160;", with: " ")
        t = t.replacingOccurrences(of: "&#xA0;", with: " ", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "&ndash;", with: "–")
        t = t.replacingOccurrences(of: "&mdash;", with: "—")
        t = t.replacingOccurrences(of: "&amp;", with: "&")
        t = t.replacingOccurrences(of: "&lt;", with: "<")
        t = t.replacingOccurrences(of: "&gt;", with: ">")
        t = t.replacingOccurrences(of: "&quot;", with: "\"")
        t = t.replacingOccurrences(of: "&apos;", with: "'")
        t = t.replacingOccurrences(of: "\u{00A0}", with: " ")
        return t
    }
}
