import Foundation
import Testing
@testable import Pantry

@Suite("Recipe timing")
struct RecipeTimingTests {
    private func timing(_ text: String) -> RecipeTiming {
        RecipeTimingParser.analyse(text)
    }

    // MARK: Required head starts

    @Test(
        "Genuine plan-ahead waits are required",
        arguments: [
            ("Pour everything over the chicken and marinate overnight to two days.", 1),
            ("Soak the beans overnight in plenty of water.", 1),
            ("Marinate the beef in the fridge for 24 hours.", 1),
            ("Brine the turkey for two days before roasting.", 2),
            ("Freeze for 8 hours until set.", 1),
            ("Place in the refrigerator and cure for 4 days, flipping brisket twice a day.", 4),
            ("Leave to rise in a warm place for at least 12 hrs, or ideally 24 hrs.", 1),
            ("Wrap in foil and keep for at least 2 days before cutting.", 2),
            ("Prepare the almonds the day before.", 1),
            ("Refrigerate for 2 to 3 days before eating.", 2)
        ]
    )
    func requiredMakeAhead(sentence: String, days: Int) throws {
        let ahead = try #require(timing(sentence).makeAhead, "expected a make-ahead for: \(sentence)")
        #expect(ahead.leadDays == days)
        #expect(!ahead.isOptional)
        #expect(ahead.phrase == sentence)
    }

    // MARK: Optional head starts

    @Test(
        "Offered head starts are optional",
        arguments: [
            "These may now be frozen for up to 1 month or chilled up to a day ahead.",
            "You can make and chill this a day ahead or freeze it for 1 month.",
            "Can be made up to 1 day ahead.",
            "If you have the time, marinate for up to 24 hrs, but this is not essential.",
            "Let them cool completely (preferably overnight), then peel and mash.",
            "Tip: if making the day before, wrap in cling wrap."
        ]
    )
    func optionalMakeAhead(sentence: String) throws {
        let ahead = try #require(timing(sentence).makeAhead, "expected a make-ahead for: \(sentence)")
        #expect(ahead.isOptional)
    }

    // MARK: Things that must NOT be a head start

    @Test(
        "Same-day waits, storage and wording traps are not make-ahead",
        arguments: [
            "Add the rest of the oil, then the peppers and cook for another 5 minutes.",
            "Let the meat rest for about 10 minutes before slicing.",
            "Marinate beef for at least 30 minutes.",
            "Cover and chill for at least 2 hrs, or up to 12 hrs.",
            "Leave to marinate in the fridge for a couple of hours or overnight.",
            "Let the dough rise for 1½ hours at room temperature, or for 24 hours in the refrigerator.",
            "Add the chillies and simmer for 8 hours on low.",
            "Stir to improve the texture and cook for 10 hours.",
            "Simmer the stock for 2 hours until reduced.",
            "Keep in the fridge for up to 3 days.",
            "The onions are best kept in the fridge and used within 4 weeks.",
            "Cover and put in the fridge until required (it will last for 3 days in the fridge).",
            "To defrost, thaw in the fridge overnight.",
            "Once iced, enjoy within 3 days – just keep in the fridge, but remove before serving.",
            "Serve immediately with steamed rice and save some for overnight.",
            "DO NOT marinate overnight, but only for a few hours."
        ]
    )
    func notMakeAhead(sentence: String) {
        #expect(timing(sentence).makeAhead == nil, "unexpected make-ahead for: \(sentence)")
    }

    // MARK: Durations

    @Test("Ranges use the lower bound for the requirement")
    func rangeLowerBound() {
        let result = timing("Marinate for 4-8 hours in the fridge.")
        #expect(result.makeAhead == nil)
        #expect(result.sameDayWaitMinutes == 240)
    }

    @Test("\"1 hour 30 minutes\" is one duration of 90 minutes")
    func compoundDuration() {
        #expect(timing("Marinate for 1 hour 30 minutes.").sameDayWaitMinutes == 90)
        #expect(timing("Bake for 1 hr and 15 mins.").activeMinutes == 75)
    }

    @Test("Word durations are understood", arguments: [
        ("Chill for half an hour.", 30),
        ("Chill for an hour and a half.", 90),
        ("Chill for a couple of hours.", 120),
        ("Chill for a few minutes.", 3),
        ("Chill for ½ hour.", 30)
    ])
    func wordDurations(sentence: String, minutes: Int) {
        #expect(timing(sentence).sameDayWaitMinutes == minutes)
    }

    @Test("Decimals survive sentence splitting")
    func decimals() {
        #expect(timing("Marinate for 1.5 hours. Then grill.").sameDayWaitMinutes == 90)
    }

    // MARK: Active time

    @Test("Cooking steps are summed across sentences")
    func activeSum() {
        let result = timing("Fry the onions for 8 mins.\nCover and cook for 2 hrs.\nBake for 20-25 minutes.")
        #expect(result.activeMinutes == 8 + 120 + 25)
    }

    @Test("Alternative methods aren't added to the main method's time")
    func alternativesExcluded() {
        let text = """
        Cover and cook for 2 hrs, or until tender.
        You can also use a slow cooker on the short method (4 hr).
        Another method is to cook it in the oven for 3-4 hrs.
        """
        #expect(timing(text).activeMinutes == 120)
    }

    @Test("Frequencies are not durations")
    func frequencies() {
        #expect(timing("Stir every 10 minutes and cook for 1 hour.").activeMinutes == 60)
    }

    @Test("Waiting doesn't count as cooking time")
    func waitsNotActive() {
        let result = timing("Leave to cool for 20 minutes. Bake for 30 minutes.")
        #expect(result.activeMinutes == 30)
        #expect(result.sameDayWaitMinutes == 20)
    }

    @Test("A required head start outranks an optional one in the same recipe")
    func requiredBeatsOptional() {
        let text = "You can make the sauce 2 days in advance.\nMarinate the chicken overnight."
        let ahead = timing(text).makeAhead
        #expect(ahead?.isOptional == false)
        #expect(ahead?.leadDays == 1)
    }

    @Test("No instructions means no timing")
    func noInstructions() {
        #expect(RecipeTimingParser.analyse(nil) == .none)
        #expect(RecipeTimingParser.analyse("") == .none)
        #expect(timing("Mix and serve.") == .none)
    }

    @Test("Results are stable across repeated calls (memoised)")
    func memoised() {
        let text = "Marinate overnight. Grill for 12 minutes."
        #expect(timing(text) == timing(text))
    }

    @Test("Lead days round up partial days")
    func leadDaysRounding() {
        #expect(MakeAheadRequirement(hours: 6, phrase: "", isOptional: false).leadDays == 1)
        #expect(MakeAheadRequirement(hours: 24, phrase: "", isOptional: false).leadDays == 1)
        #expect(MakeAheadRequirement(hours: 25, phrase: "", isOptional: false).leadDays == 2)
        #expect(MakeAheadRequirement(hours: 96, phrase: "", isOptional: false).leadDays == 4)
    }
}
