import Foundation
import Testing
@testable import Pantry

@Suite("Instruction parsing")
struct InstructionParserTests {
    private func steps(_ text: String) -> [String] {
        InstructionParser.lines(from: text).compactMap {
            if case .step(let s) = $0 { return s }
            return nil
        }
    }

    private func headers(_ text: String) -> [String] {
        InstructionParser.lines(from: text).compactMap {
            if case .header(let h) = $0 { return h }
            return nil
        }
    }

    @Test("Splits on CRLF, LF and CR")
    func lineEndings() {
        #expect(steps("Heat oil.\r\nAdd onion.\nFry.\rServe.") == ["Heat oil.", "Add onion.", "Fry.", "Serve."])
    }

    @Test("Bare STEP markers used by a third of the catalogue are dropped")
    func stepMarkers() {
        let text = "step 1\r\nMake the filling.\r\nSTEP 2\r\nFry the fritters.\r\n3.\r\nServe.\r\n4\r\nEat."
        #expect(steps(text) == ["Make the filling.", "Fry the fritters.", "Serve.", "Eat."])
    }

    @Test("Own numbering is stripped so steps aren't double-numbered")
    func numberingPrefix() {
        let text = "1. In a bowl, combine.\n2) Heat the pan.\nStep 3: Pour in.\nSTEP 4 - Simmer."
        #expect(steps(text) == ["In a bowl, combine.", "Heat the pan.", "Pour in.", "Simmer."])
    }

    @Test("Quantities at the start of a step are not mistaken for numbering")
    func quantitiesKept() {
        #expect(steps("1.5 kg lamb goes in the pot.\n2 eggs, beaten, go next.") ==
                ["1.5 kg lamb goes in the pot.", "2 eggs, beaten, go next."])
    }

    @Test("Decorative glyph lines are dropped")
    func glyphLines() {
        #expect(steps("Whisk.\r\n▢\r\nFold.\r\n—\r\n•") == ["Whisk.", "Fold."])
    }

    @Test("Bullets and bold markers are removed; markdown headings become headers")
    func bulletsAndMarkdown() {
        let text = "- Chop the **onions**\n• Fry them\n## Cook the rice\nBoil for 10 minutes."
        #expect(steps(text) == ["Chop the onions", "Fry them", "Boil for 10 minutes."])
        #expect(headers(text) == ["Cook the rice"])
    }

    @Test("Sub-headings become headers, not numbered steps")
    func subHeadings() {
        let text = "For the sauce:\nWhisk soy and honey.\nPro Tips:\nUse day-old rice.\nServing\nPlate up."
        #expect(headers(text) == ["For the sauce", "Pro Tips", "Serving"])
        #expect(steps(text) == ["Whisk soy and honey.", "Use day-old rice.", "Plate up."])
    }

    @Test("Headings that just repeat 'Steps' are dropped entirely")
    func redundantHeadings() {
        let lines = InstructionParser.lines(from: "Instructions:\nBoil water.\nMethod\nAdd pasta.")
        #expect(lines == [.step("Boil water."), .step("Add pasta.")])
    }

    @Test("A long sentence ending in a colon stays a step")
    func longColonLineIsStep() {
        let text = "Once the sauce has thickened and turned glossy, add the following:\nPeas."
        #expect(steps(text).count == 2)
    }

    @Test("A single run-on paragraph is split into sentence steps")
    func runOnParagraph() {
        let paragraph = String(repeating: "Stir the pot gently and keep the heat low for a while. ", count: 5)
            + "Serve with rice."
        let result = steps(paragraph)
        #expect(result.count == 6)
        #expect(result.last == "Serve with rice.")
    }

    @Test("Short single-step recipes aren't split")
    func shortSingleStep() {
        #expect(steps("Mix everything. Serve cold.") == ["Mix everything. Serve cold."])
    }

    @Test("Nil and empty instructions give no lines")
    func empty() {
        #expect(InstructionParser.lines(from: nil).isEmpty)
        #expect(InstructionParser.lines(from: "").isEmpty)
        #expect(InstructionParser.lines(from: "\r\n\r\n").isEmpty)
    }

    @Test("Meal.instructionSteps exposes only the steps")
    func mealSteps() {
        let meal = Fixtures.meal(instructions: "STEP 1\nChop.\nTo serve:\nPlate.")
        #expect(meal.instructionSteps == ["Chop.", "Plate."])
        #expect(meal.instructionLines.count == 3)
    }
}
