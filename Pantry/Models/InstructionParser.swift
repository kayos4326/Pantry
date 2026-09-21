import Foundation

enum InstructionLine: Hashable {
    case header(String)
    case step(String)
}

/// Cleans TheMealDB instructions into headings and numbered steps.
enum InstructionParser {
    /// Split long single-paragraph instructions into separate steps.
    private static let paragraphSplitThreshold = 250

    private static let markerOnly = try! NSRegularExpression(
        pattern: #"^(?:step\s*)?\d+\s*[.):\-–]?$"#, options: [.caseInsensitive]
    )
    private static let leadingMarker = try! NSRegularExpression(
        pattern: #"^(?:step\s*\d+\s*[.):\-–]?\s*|\d+\s*[.)]\s+|[-•*]\s+)"#, options: [.caseInsensitive]
    )
    private static let sentenceBoundary = try! NSRegularExpression(
        pattern: #"(?<=[.!?])\s+(?=[A-Z0-9"“(])"#
    )

    private static let redundantHeadings: Set<String> = [
        "instructions", "method", "directions", "steps", "preparation instructions"
    ]
    private static let knownHeadings: Set<String> = [
        "cooking", "serving", "baking", "assembly", "equipment", "notes", "note",
        "tips", "tip", "pro tips", "preparation", "prep", "to serve", "garnish"
    ]

    private final class Box { let value: [InstructionLine]; init(_ value: [InstructionLine]) { self.value = value } }
    private static let cache = NSCache<NSString, Box>()

    static func lines(from instructions: String?) -> [InstructionLine] {
        guard let instructions else { return [] }

        if let cached = cache.object(forKey: instructions as NSString) {
            return cached.value
        }
        let lines = parse(instructions)
        cache.setObject(Box(lines), forKey: instructions as NSString)
        return lines
    }

    private static func parse(_ instructions: String) -> [InstructionLine] {
        var result: [InstructionLine] = []
        for rawLine in instructions.components(separatedBy: .newlines) {
            var line = rawLine
                .replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Preserve headings supplied in Markdown-style instructions.
            let isMarkdownHeading = line.hasPrefix("#")
            while line.hasPrefix("#") { line.removeFirst() }
            line = line.trimmingCharacters(in: .whitespaces)

            // Ignore lines that contain only decoration.
            guard line.rangeOfCharacter(from: .alphanumerics) != nil else { continue }
            guard !matches(markerOnly, line) else { continue }

            line = strip(leadingMarker, from: line)
            guard line.rangeOfCharacter(from: .alphanumerics) != nil else { continue }

            let title: String? = isMarkdownHeading ? headingText(line) : heading(from: line)
            if let title {
                if !redundantHeadings.contains(title.lowercased()) {
                    result.append(.header(title))
                }
            } else {
                result.append(.step(line))
            }
        }

        return splitRunOnParagraph(result)
    }

    // MARK: - Helpers

    private static func heading(from line: String) -> String? {
        let trimmed = headingText(line)
        let wordCount = trimmed.split(separator: " ").count
        let lower = trimmed.lowercased()

        if line.hasSuffix(":") && wordCount <= 5 { return trimmed }
        if knownHeadings.contains(lower) || redundantHeadings.contains(lower) { return trimmed }
        return nil
    }

    private static func headingText(_ line: String) -> String {
        let withoutColon = line.hasSuffix(":") ? String(line.dropLast()) : line
        return withoutColon.trimmingCharacters(in: .whitespaces)
    }

    private static func splitRunOnParagraph(_ lines: [InstructionLine]) -> [InstructionLine] {
        let steps = lines.compactMap { line -> String? in
            if case .step(let text) = line { return text }
            return nil
        }
        guard steps.count == 1, let only = steps.first, only.count > paragraphSplitThreshold else {
            return lines
        }

        let sentences = split(only, on: sentenceBoundary)
        guard sentences.count > 1 else { return lines }

        return lines.flatMap { line -> [InstructionLine] in
            if case .step = line { return sentences.map { .step($0) } }
            return [line]
        }
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func strip(_ regex: NSRegularExpression, from text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func split(_ text: String, on regex: NSRegularExpression) -> [String] {
        var parts: [String] = []
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            parts.append(String(text[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        parts.append(String(text[cursor...]))
        return parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
