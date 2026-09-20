import Foundation

/// A wait long enough that the cook has to start on an earlier day —
/// marinating, brining, overnight chilling.
struct MakeAheadRequirement: Hashable {
    let hours: Double
    /// The sentence it was found in, so the UI can show its evidence rather
    /// than asking the user to trust a number.
    let phrase: String
    /// "These may now be frozen…" offers a head start; "marinate overnight"
    /// demands one. The UI words these differently.
    let isOptional: Bool

    /// Whole days ahead of serving that prep must begin.
    var leadDays: Int {
        max(1, Int((hours / 24).rounded(.up)))
    }
}

/// TheMealDB has no cook-time, prep-time or serving field — the only timing
/// information is prose inside strInstructions. Everything here is derived
/// from that text, never invented.
struct RecipeTiming: Hashable {
    /// Sum of durations mentioned in ordinary cooking steps.
    let activeMinutes: Int?
    /// A wait that pushes prep to an earlier day.
    let makeAhead: MakeAheadRequirement?
    /// Marinating, chilling or resting short enough to still happen on the day.
    let sameDayWaitMinutes: Int?

    static let none = RecipeTiming(activeMinutes: nil, makeAhead: nil, sameDayWaitMinutes: nil)
}

enum RecipeTimingParser {
    /// Waits below this stay same-day; at or above it, prep moves to an
    /// earlier date. Six hours keeps "chill for 2 hrs" on the day while
    /// catching anything overnight.
    private static let makeAheadThresholdHours: Double = 6

    /// Ordinary steps longer than this are almost always a parsing artefact.
    private static let maxActiveStepMinutes: Double = 8 * 60

    /// Word-bounded so "chilli", "improve", "waterproof" and "the rest of the
    /// oil" don't read as waiting. "marinated" is left out on purpose: "add the
    /// marinated chicken" describes an ingredient, not a wait.
    /// "rise", "set" and "sit" only count in their imperative forms, so "bake
    /// until risen" stays cooking time.
    private static let waitTrigger = try! NSRegularExpression(
        pattern: #"\b(?:marinat(?:e|es|ing)|marinade|refrigerat\w*|fridge|chill(?:s|ed|ing)?|soak(?:s|ed|ing)?|brin(?:e|es|ed|ing)|freez(?:e|es|ing)|frozen|overnight|prov(?:e|es|ed|ing)|proof(?:s|ed|ing)?|cure|curing|(?:rest|stand|cool|rise|set|sit)\s+for|(?:to|let\s+\w+(?:\s+\w+)?)\s+(?:rest|stand|cool|rise|set|sit)|keep\s+for|ahead|in\s+advance|the\s+(?:night|day)\s+before)\b"#,
        options: [.caseInsensitive]
    )

    /// "keep for at least 2 days before cutting" is maturing a cake, which
    /// looks like storage advice but is actually a requirement.
    private static let maturingPhrasing = try! NSRegularExpression(
        pattern: #"\b(?:at\s+least|minimum\s+of|before\s+(?:cutting|eating|slicing))\b"#,
        options: [.caseInsensitive]
    )

    /// "at least 12 hrs, or ideally 24" — the minimum is a hard requirement
    /// even though the sentence also offers an optional extension.
    private static let statedMinimum = try! NSRegularExpression(
        pattern: #"\b(?:at\s+least|a\s+least|minimum\s+of)\b"#, options: [.caseInsensitive]
    )

    /// Storage advice ("keeps in the fridge for up to 3 days", "to defrost,
    /// thaw overnight") is about leftovers, not about when to start cooking.
    private static let storagePhrasing = try! NSRegularExpression(
        pattern: #"\b(?:stor(?:e|ed|ing|age)|kept|keeps?\s+(?:in|for|well)|will\s+keep|will\s+last|lasts?\s+(?:for|up)|leftovers?|airtight|stash|within|to\s+(?:defrost|thaw))\b"#,
        options: [.caseInsensitive]
    )

    /// "can be prepared up to a day ahead and kept in the fridge" mentions
    /// keeping, but it's make-ahead advice rather than storage.
    private static let advancePhrasing = try! NSRegularExpression(
        pattern: #"\b(?:ahead|in\s+advance|the\s+day\s+before)\b"#, options: [.caseInsensitive]
    )

    /// Serving notes ("Serve… save some for overnight") never schedule prep.
    private static let servingSentence = try! NSRegularExpression(
        pattern: #"^\W*serv(?:e|ing)\b"#, options: [.caseInsensitive]
    )

    /// Alternative methods ("You can also use a slow cooker (4 hr)") describe
    /// a different route, so their times mustn't be added to the main one.
    private static let alternativeMethod = try! NSRegularExpression(
        pattern: #"\b(?:alternatively|another\s+(?:method|option|way)|you\s+can\s+also|or\s+you\s+can|instead|if\s+using)\b"#,
        options: [.caseInsensitive]
    )

    private static let upToPrefix = try! NSRegularExpression(
        pattern: #"\bup\s+to\s*$"#, options: [.caseInsensitive]
    )

    /// "twice a day", "every 2 hours" are frequencies, not durations.
    private static let frequencyPrefix = try! NSRegularExpression(
        pattern: #"\b(?:once|twice|thrice|times|every|per|each)\s*$"#, options: [.caseInsensitive]
    )

    private static let optionalPhrasing = try! NSRegularExpression(
        pattern: #"\b(?:may|can\s+be|could\s+be|you\s+can|if\s+you|if\s+making|optional(?:ly)?|if\s+preferred|preferabl[ey]|ideally|if\s+possible|for\s+best\s+results?|alternatively|or\s+(?:freeze|frozen)|up\s+to\s+a\s+day\s+ahead)\b"#,
        options: [.caseInsensitive]
    )

    private static let unicodeFractions: [(String, String)] = [
        ("½", ".5"), ("¼", ".25"), ("¾", ".75"), ("⅓", ".33"), ("⅔", ".67")
    ]

    /// Optional leading range ("4-8", "4 to 8"), then a number or number-word,
    /// then a unit.
    private static let durationPattern = try! NSRegularExpression(
        pattern: #"(?:(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*)?(?:(\d+(?:\.\d+)?)|\b(a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|couple|few)\b)\s*(?:of\s+)?(minute|min|hour|hr|day|week)s?\b"#,
        options: [.caseInsensitive]
    )

    private static let sentenceBoundary = try! NSRegularExpression(
        pattern: #"(?<=[.!?])\s+"#
    )

    private static let wordNumbers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "couple": 2, "few": 3
    ]

    /// Phrasings the unit regex can't express, rewritten into plain minutes first.
    private static let rewrites: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"\b(?:an|one)\s+hour\s+and\s+a\s+half\b"#, options: [.caseInsensitive]), "90 minutes"),
        (try! NSRegularExpression(pattern: #"\bhalf\s+an?\s+hour\b"#, options: [.caseInsensitive]), "30 minutes"),
        (try! NSRegularExpression(pattern: #"\ba\s+half\s+hour\b"#, options: [.caseInsensitive]), "30 minutes"),
        (try! NSRegularExpression(pattern: #"\bthe\s+(?:night|day)\s+before\b"#, options: [.caseInsensitive]), "1 day")
    ]

    private static let compoundHoursMinutes = try! NSRegularExpression(
        pattern: #"\b(\d+)\s*(?:hours?|hrs?)\s*(?:and\s*)?(\d+)\s*(?:minutes?|mins?)\b"#,
        options: [.caseInsensitive]
    )

    private final class Box { let value: RecipeTiming; init(_ value: RecipeTiming) { self.value = value } }

    /// Parsing costs ~1 ms and the planner asks for every planned recipe on
    /// every date redraw, so results are memoised by instruction text.
    private static let cache = NSCache<NSString, Box>()

    static func analyse(_ instructions: String?) -> RecipeTiming {
        guard let instructions, !instructions.isEmpty else { return .none }

        if let cached = cache.object(forKey: instructions as NSString) {
            return cached.value
        }
        let timing = parse(instructions)
        cache.setObject(Box(timing), forKey: instructions as NSString)
        return timing
    }

    private static func parse(_ instructions: String) -> RecipeTiming {
        var makeAhead: MakeAheadRequirement?
        var activeMinutes: Double = 0
        var sameDayWait: Double = 0

        for sentence in sentences(in: instructions) {
            let spans = durations(in: sentence)
            guard !spans.isEmpty else { continue }

            let isServingNote = matches(servingSentence, sentence)

            if matches(waitTrigger, sentence) && !isServingNote {
                let isStorage = matches(storagePhrasing, sentence)
                    && !matches(advancePhrasing, sentence)
                    && !matches(maturingPhrasing, sentence)
                guard !isStorage else { continue }

                // "at least 2 hrs, or up to 12 hrs" and "4-8 hours" both state a
                // minimum, and the minimum is what constrains when you must
                // start. "up to 2 days" on its own is a ceiling, not a demand.
                let required = spans.filter { !$0.isUpperBoundOnly }
                let isOptional = required.isEmpty
                    || (matches(optionalPhrasing, sentence) && !matches(statedMinimum, sentence))
                let requiredMinutes = required.isEmpty
                    ? (spans.map(\.high).max() ?? 0)
                    : (required.map(\.low).min() ?? 0)
                let requiredHours = requiredMinutes / 60

                if requiredHours >= makeAheadThresholdHours {
                    // A demanded head start outranks an offered one; within the
                    // same kind, the longer lead wins.
                    let current = makeAhead
                    let replaces = current == nil
                        || (current!.isOptional && !isOptional)
                        || (current!.isOptional == isOptional && requiredHours > current!.hours)
                    if replaces {
                        makeAhead = MakeAheadRequirement(hours: requiredHours, phrase: sentence, isOptional: isOptional)
                    }
                } else if !required.isEmpty {
                    sameDayWait = max(sameDayWait, requiredMinutes)
                }
            } else if !matches(alternativeMethod, sentence) {
                activeMinutes += spans.map(\.high).filter { $0 <= maxActiveStepMinutes }.reduce(0, +)
            }
        }

        return RecipeTiming(
            activeMinutes: activeMinutes > 0 ? Int(activeMinutes.rounded()) : nil,
            makeAhead: makeAhead,
            sameDayWaitMinutes: sameDayWait > 0 ? Int(sameDayWait.rounded()) : nil
        )
    }

    // MARK: - Helpers

    /// Splits on line breaks and on sentence-ending punctuation followed by
    /// whitespace, so decimals like "1.5 hours" stay intact.
    private static func sentences(in text: String) -> [String] {
        text.components(separatedBy: .newlines).flatMap { line -> [String] in
            var parts: [String] = []
            var cursor = line.startIndex
            for match in sentenceBoundary.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let range = Range(match.range, in: line) else { continue }
                parts.append(String(line[cursor..<range.lowerBound]))
                cursor = range.upperBound
            }
            parts.append(String(line[cursor...]))
            return parts
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func normalised(_ sentence: String) -> String {
        var text = sentence
        for (glyph, decimal) in unicodeFractions {
            // "1½" → "1.5", a bare "½" → "0.5".
            text = text.replacingOccurrences(of: glyph, with: decimal)
            text = text.replacingOccurrences(of: #"(?<!\d)\#(NSRegularExpression.escapedPattern(for: decimal))"#, with: "0\(decimal)", options: .regularExpression)
        }
        for (regex, replacement) in rewrites {
            text = regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement
            )
        }

        // "1 hour 30 minutes" is one duration, not a range of 60 and 30.
        let range = NSRange(text.startIndex..., in: text)
        for match in compoundHoursMinutes.matches(in: text, range: range).reversed() {
            guard
                let whole = Range(match.range, in: text),
                let hours = Range(match.range(at: 1), in: text).flatMap({ Double(text[$0]) }),
                let minutes = Range(match.range(at: 2), in: text).flatMap({ Double(text[$0]) })
            else { continue }
            text.replaceSubrange(whole, with: "\(Int(hours * 60 + minutes)) minutes")
        }
        return text
    }

    private typealias Span = (low: Double, high: Double, isUpperBoundOnly: Bool)

    /// Every duration in a sentence as a span in minutes. A plain "20 minutes"
    /// has low == high; "up to 2 days" is flagged as a ceiling only.
    private static func durations(in sentence: String) -> [Span] {
        let text = normalised(sentence)
        var result: [Span] = []

        if text.range(of: #"\bovernight\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            result.append((12 * 60, 12 * 60, false))
        }

        let range = NSRange(text.startIndex..., in: text)
        for match in durationPattern.matches(in: text, range: range) {
            guard let unitRange = Range(match.range(at: 4), in: text) else { continue }

            var high: Double?
            if let digits = Range(match.range(at: 2), in: text) {
                high = Double(text[digits])
            } else if let word = Range(match.range(at: 3), in: text) {
                high = wordNumbers[text[word].lowercased()]
            }
            guard let upper = high else { continue }
            let lower = Range(match.range(at: 1), in: text).flatMap { Double(text[$0]) } ?? upper

            let multiplier: Double
            switch text[unitRange].lowercased() {
            case "minute", "min": multiplier = 1
            case "hour", "hr": multiplier = 60
            case "day": multiplier = 24 * 60
            case "week": multiplier = 7 * 24 * 60
            default: continue
            }
            let prefix = String(text[text.startIndex..<(Range(match.range, in: text)?.lowerBound ?? text.startIndex)])
            guard !matches(frequencyPrefix, prefix) else { continue }
            let isCeiling = matches(upToPrefix, prefix)
            result.append((min(lower, upper) * multiplier, max(lower, upper) * multiplier, isCeiling))
        }

        return result
    }
}

extension Meal {
    var timing: RecipeTiming {
        RecipeTimingParser.analyse(instructions)
    }
}
