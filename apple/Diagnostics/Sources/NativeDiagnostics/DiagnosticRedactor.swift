import Foundation

/// Removes credentials from diagnostic text while keeping the server, path and error codes that make recovery possible.
public enum DiagnosticRedactor {
    public static let removed = "[redacted]"

    public static func redact(_ text: String, maskingAddresses: Bool = false) -> String {
        var result = replace(#"[A-Za-z][A-Za-z0-9+.\-]*://[^\s"'<>]+"#, in: text) { address($0, masking: maskingAddresses) }
        result = replace(#"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+(\.[A-Za-z0-9_\-]*)?"#, in: result) { _ in removed }
        result = replace(#"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=\-]+"#, in: result) { match in
            String(match.prefix { !$0.isWhitespace }) + " " + removed
        }
        // A cookie header can carry several credentials under any names, so its whole value goes.
        result = replace(#"(?im)^([ \t]*(?:set-)?cookie[ \t]*:)[^\n]*"#, in: result) { match in
            String(match[...match.firstIndex(of: ":")!]) + " " + removed
        }
        // Key names may carry a prefix (absRefreshToken, x-refresh-token); values may be quoted or printed as Optional("…").
        let keys = #"access[_\-]?token|refresh[_\-]?token|id[_\-]?token|token|password|passwd|client[_\-]?secret|secret|api[_\-]?key|authorization|code[_\-]?verifier|cookie"#
        // Quoted values run to the real closing quote: a backslash escapes the next character, including a quote.
        // Without a closing quote or Optional parenthesis, as in a truncated line, the value runs to the end of the line.
        let doubleQuoted = #""(?:[^"\\\n]|\\.)*"?"#, singleQuoted = #"'(?:[^'\\\n]|\\.)*'?"#
        let value = #"Optional\((?:"# + doubleQuoted + "|" + singleQuoted + #"|[^)\s]*)\)?|"# + doubleQuoted + "|" + singleQuoted + #"|[^\s&,;"'}]+"#
        result = replace(#"(?i)("?)\b[A-Za-z0-9_\-]*?("# + keys + #")\b("?\s*[:=]\s*)("# + value + #")"#, in: result) { match in
            guard let separator = match.firstIndex(where: { $0 == ":" || $0 == "=" }) else { return match }
            let tail = match[match.index(after: separator)...]
            let spacing = tail.prefix { $0 == " " }
            let quoted = tail.dropFirst(spacing.count).first == "\""
            return match[...separator] + spacing + (quoted ? "\"" + removed + "\"" : removed)
        }
        return result
    }

    /// Domain and code identify the failure without its localized wording; Swift errors add their case.
    public static func describe(_ error: Error) -> String {
        let failure = error as NSError
        var parts = ["\(failure.domain) \(failure.code)"]
        // Only the case name: associated values are arbitrary text that may hold credentials.
        if !failure.domain.hasPrefix("NS"), !failure.domain.hasPrefix("kCF") {
            parts.append("(" + String(String(describing: error).prefix { $0 != "(" }) + ")")
        }
        if let url = failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL { parts.append(url.absoluteString) }
        else if let url = failure.userInfo[NSURLErrorFailingURLStringErrorKey] as? String { parts.append(url) }
        if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError { parts.append("underlying \(underlying.domain) \(underlying.code)") }
        return redact(parts.joined(separator: " "))
    }

    private static func address(_ match: String, masking: Bool) -> String {
        var raw = Substring(match)
        var trailing = ""
        while let last = raw.last, ".,;:)]".contains(last) { trailing = String(last) + trailing; raw = raw.dropLast() }
        guard let parts = URLComponents(string: String(raw)), let scheme = parts.scheme, let host = parts.host else {
            let withoutUser = replace(#"://[^/@\s]*@"#, in: String(raw)) { _ in "://" }
            return replace(#"[?#].*$"#, in: withoutUser) { _ in "?" + removed } + trailing
        }
        var result = scheme + "://" + (masking ? "[server]" : host + (parts.port.map { ":\($0)" } ?? ""))
        result += parts.percentEncodedPath
        if let query = parts.queryItems, !query.isEmpty {
            result += "?" + query.map { $0.name + ($0.value == nil ? "" : "=" + removed) }.joined(separator: "&")
        }
        return result + trailing
    }

    private static func replace(_ pattern: String, in text: String, with transform: (String) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }
}
