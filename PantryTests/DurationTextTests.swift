import Testing
@testable import Pantry

@Suite("Duration formatting")
struct DurationTextTests {
    @Test("Estimates under an hour stay in minutes", arguments: [(5, "~5 min"), (43, "~43 min"), (59, "~59 min")])
    func underAnHour(minutes: Int, expected: String) {
        #expect(DurationText.approximate(minutes: minutes) == expected)
    }

    @Test("Estimates over an hour round to five minutes", arguments: [
        (60, "~1 h"), (65, "~1 h 5 min"), (67, "~1 h 5 min"), (68, "~1 h 10 min"), (118, "~2 h"), (544, "~9 h 5 min")
    ])
    func overAnHour(minutes: Int, expected: String) {
        #expect(DurationText.approximate(minutes: minutes) == expected)
    }

    @Test("Exact durations aren't rounded", arguments: [(30, "30 min"), (60, "1 h"), (90, "1 h 30 min"), (67, "1 h 7 min")])
    func exact(minutes: Int, expected: String) {
        #expect(DurationText.exact(minutes: minutes) == expected)
    }
}
