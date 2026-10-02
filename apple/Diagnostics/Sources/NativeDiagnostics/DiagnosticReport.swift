import Foundation

/// The exported text stays in English so it can be shared with maintainers whatever the interface language.
public enum DiagnosticReport {
    public struct Line {
        public let label: String
        public let value: String
        public init(_ label: String, _ value: String) { self.label = label; self.value = value }
    }
    public struct Section {
        public let title: String
        public let lines: [Line]
        public init(title: String, lines: [Line]) { self.title = title; self.lines = lines }
    }

    public static func text(sections: [Section], events: [DiagnosticEvent], generated: Date, maskingAddresses: Bool) -> String {
        var output = ["Audiobookshelf native diagnostics", "Generated: \(timestamp(generated))", ""]
        for section in sections {
            output.append(section.title)
            output += section.lines.map { "\($0.label): \($0.value)" }
            output.append("")
        }
        output.append("Recent events (newest first)")
        if events.isEmpty { output.append("None") }
        for event in events.sorted(by: { $0.lastDate > $1.lastDate }) {
            var line = "\(timestamp(event.lastDate)) [\(event.category.rawValue)] \(event.message)"
            if event.count > 1 { line += " (×\(event.count) since \(timestamp(event.firstDate)))" }
            output.append(line)
            if let detail = event.detail { output.append("    " + detail) }
        }
        return DiagnosticRedactor.redact(output.joined(separator: "\n"), maskingAddresses: maskingAddresses)
    }

    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
