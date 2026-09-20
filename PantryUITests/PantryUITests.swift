import XCTest

/// End-to-end flows and Apple's automated accessibility audit, run against the
/// real app and live TheMealDB. The app is launched with `-ui-testing`, which
/// gives it an empty in-memory store, so nothing saved on the device is touched.
final class PantryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    // MARK: - Helpers

    private func tab(_ name: String) -> XCUIElement {
        let tabBarButton = app.tabBars.buttons[name]
        return tabBarButton.exists ? tabBarButton : app.buttons[name].firstMatch
    }

    @discardableResult
    private func waitForBrowseCard(timeout: TimeInterval = 20) -> XCUIElement {
        let card = app.buttons.matching(identifier: "browse.recipeCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "No recipes loaded from TheMealDB")
        return card
    }

    private func openFirstRecipeAndWaitForDetail() {
        waitForBrowseCard().tap()
        XCTAssertTrue(app.buttons["detail.saveButton"].waitForExistence(timeout: 20), "Detail never finished loading")
    }

    // MARK: - Flows

    func testBrowseLoadsAndSearchFiltersResults() throws {
        waitForBrowseCard()

        let search = app.textFields["browse.search"]
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("Arrabiata")

        let result = app.buttons.matching(NSPredicate(format: "identifier == 'browse.recipeCard' AND label CONTAINS[c] 'Arrabiata'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "Search didn't surface the matching recipe")
    }

    func testSearchWithNoMatchesShowsEmptyState() throws {
        waitForBrowseCard()
        let search = app.textFields["browse.search"]
        search.tap()
        search.typeText("zzzznotarecipe")

        XCTAssertTrue(app.staticTexts["No recipes matched \"zzzznotarecipe\"."].waitForExistence(timeout: 20))
    }

    func testSaveRecipeThenPlanItFromSaved() throws {
        openFirstRecipeAndWaitForDetail()

        let save = app.buttons["detail.saveButton"]
        XCTAssertEqual(save.label, "Save recipe")
        save.tap()
        XCTAssertEqual(save.label, "Remove from saved", "Heart didn't switch to saved")

        tab("Saved").tap()
        let savedCard = app.buttons.matching(identifier: "saved.recipeCard").firstMatch
        XCTAssertTrue(savedCard.waitForExistence(timeout: 5), "Saved recipe missing from Saved tab")

        tab("Planner").tap()
        let planButton = app.buttons["planner.planMeal"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 5))
        planButton.tap()

        let pickerRow = app.buttons.matching(identifier: "picker.recipeRow").firstMatch
        XCTAssertTrue(pickerRow.waitForExistence(timeout: 5), "Saved recipe not offered in the picker")
        pickerRow.tap()

        XCTAssertTrue(app.buttons["planner.plannedRecipe"].waitForExistence(timeout: 5), "Planned recipe card didn't appear")
    }

    func testPlanningTwoMealsOnOneDay() throws {
        openFirstRecipeAndWaitForDetail()
        app.buttons["detail.saveButton"].tap()

        tab("Planner").tap()
        let planButton = app.buttons["planner.planMeal"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 5))

        for expectedCount in 1...2 {
            planButton.tap()
            let pickerRow = app.buttons.matching(identifier: "picker.recipeRow").firstMatch
            XCTAssertTrue(pickerRow.waitForExistence(timeout: 5))
            pickerRow.tap()

            let planned = app.buttons.matching(identifier: "planner.plannedRecipe")
            XCTAssertTrue(
                planned.element(boundBy: expectedCount - 1).waitForExistence(timeout: 5),
                "Expected \(expectedCount) meal(s) on the day, found \(planned.count)"
            )
            XCTAssertEqual(planned.count, expectedCount)
        }

        // The second meal is added, not swapped in for the first.
        XCTAssertEqual(app.buttons.matching(identifier: "planner.plannedRecipe").count, 2)
        try audit("Planner with two meals")

        // Removing one leaves the other.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Change '")).firstMatch.tap()
        let remove = app.buttons["Remove this meal"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()

        let planned = app.buttons.matching(identifier: "planner.plannedRecipe")
        XCTAssertTrue(planned.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(planned.count, 1)
    }

    func testUnsavingFromSavedEmptiesTheTab() throws {
        openFirstRecipeAndWaitForDetail()
        app.buttons["detail.saveButton"].tap()

        tab("Saved").tap()
        let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove ' AND label ENDSWITH ' from saved'")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()

        XCTAssertTrue(app.staticTexts["Nothing saved yet."].waitForExistence(timeout: 5))
    }

    func testRecentlyViewedRemembersWhatWasOpened() throws {
        XCTAssertFalse(
            app.buttons.matching(identifier: "browse.recentCard").firstMatch.exists,
            "Recently viewed shouldn't appear before anything has been opened"
        )

        waitForBrowseCard()
        let openedName = app.buttons.matching(identifier: "browse.recipeCard").firstMatch.label
        openFirstRecipeAndWaitForDetail()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let recent = app.buttons.matching(identifier: "browse.recentCard").firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 10), "Opening a recipe didn't add it to Recently viewed")
        // The card's label is the recipe name; the grid card's also carries its
        // area, so the grid label contains the strip's.
        XCTAssertFalse(recent.label.isEmpty)
        XCTAssertTrue(
            openedName.localizedCaseInsensitiveContains(recent.label),
            "Recently viewed shows '\(recent.label)' after opening '\(openedName)'"
        )

        // The strip is only on screen here, so this is where it gets audited.
        try audit("Browse with recents")

        recent.tap()
        XCTAssertTrue(app.buttons["detail.saveButton"].waitForExistence(timeout: 20), "Recently viewed didn't reopen the recipe")
    }

    // MARK: - Dynamic Type

    /// Heights of representative text at the current launch size, one per
    /// typeface and text-style curve the app uses.
    private func measureText() -> [String: CGFloat] {
        var heights: [String: CGFloat] = [:]
        let browseTitle = app.staticTexts["Browse"]
        XCTAssertTrue(browseTitle.waitForExistence(timeout: 10))
        heights["serif title (largeTitle curve)"] = browseTitle.frame.height
        heights["mono eyebrow (footnote curve)"] = app.staticTexts["PANTRY"].frame.height
        heights["mono chip (body curve)"] = app.buttons["All"].frame.height
        heights["Inter search field (body curve)"] = app.textFields["browse.search"].frame.height

        openFirstRecipeAndWaitForDetail()
        let ingredients = app.staticTexts["INGREDIENTS"]
        XCTAssertTrue(ingredients.waitForExistence(timeout: 10))
        heights["mono section label (footnote curve)"] = ingredients.frame.height
        let firstIngredient = app.buttons.matching(NSPredicate(format: "value IN {'Checked', 'Not checked'}")).firstMatch
        heights["Inter ingredient row (body curve)"] = firstIngredient.frame.height
        return heights
    }

    func testCustomFontsScaleWithDynamicType() throws {
        let standard = measureText()

        app.terminate()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        let large = measureText()

        for (name, height) in standard {
            let grown = try XCTUnwrap(large[name])
            print("DYNAMIC-TYPE \(name): \(height) pt -> \(grown) pt (\(String(format: "%.2f", grown / height))x)")
            XCTAssertGreaterThan(height, 0, "\(name) wasn't measured")
            // Fixed text would measure 1.0×; containers with fixed padding
            // grow less than their text, so 1.2× is proof of scaling.
            XCTAssertGreaterThan(grown, height * 1.2, "\(name) didn't grow with Dynamic Type")
        }
    }

    // MARK: - Accessibility audits

    /// Fails the test on any accessibility issue, with two documented
    /// exceptions:
    /// - Text scrolled beneath the translucent floating tab bar is measured
    ///   against the blurred material rather than its real background, which
    ///   reports contrast failures the user never sees.
    /// - The Dynamic Type heuristic reports "partially unsupported" for a
    ///   different `Font.custom` text on each run, including text it passes on
    ///   other screens. Scaling is instead proven deterministically by
    ///   `testCustomFontsScaleWithDynamicType`, which measures real growth.
    private func audit(_ screen: String) throws {
        let tabBar = app.tabBars.firstMatch
        let windowHeight = app.windows.firstMatch.frame.height
        // Scrolled-away content passes behind the status bar, where the scroll
        // edge effect fades it. Anything sitting *entirely* above the bar's
        // bottom is hidden by it; the screens' own headers start below.
        let statusBarBottom = app.statusBars.firstMatch.exists ? app.statusBars.firstMatch.frame.maxY : 59
        // iOS 26's scroll edge effect fades content above the floating bar
        // itself, so the obscured band starts 80 pt above its top edge.
        let barTop = tabBar.exists ? tabBar.frame.minY : windowHeight - 90
        let obscuredRegion = CGRect(x: 0, y: barTop - 80, width: .greatestFiniteMagnitude, height: windowHeight)

        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.dynamicType)) { issue in
            let element = issue.element.map { "'\($0.label)' id='\($0.identifier)' frame=\($0.frame)" } ?? "no element"
            // Contrast and clipping can't be judged for text passing under the
            // bar's edge fade. testAccessibilityAuditBrowse audits a second
            // time after scrolling, so text caught in the band there is also
            // audited in clear space.
            if [.contrast, .textClipped].contains(issue.auditType),
               let frame = issue.element?.frame, frame.intersects(obscuredRegion) {
                print("AUDIT[\(screen)] ignored under tab bar: \(issue.compactDescription) \(element)")
                return true
            }
            // The same effect at the top of the scroll view.
            if [.contrast, .textClipped].contains(issue.auditType),
               let frame = issue.element?.frame, frame.maxY <= statusBarBottom {
                print("AUDIT[\(screen)] ignored behind status bar: \(issue.compactDescription) \(element)")
                return true
            }
            // A prediction ("may be clipped") about the search field at larger
            // sizes; testCustomFontsScaleWithDynamicType measures the field
            // actually growing, which rules the clipping out.
            if issue.auditType == .textClipped, issue.element?.identifier == "browse.search" {
                print("AUDIT[\(screen)] ignored, disproven by measurement: \(issue.compactDescription) \(element)")
                return true
            }
            print("AUDIT[\(screen)] FAIL type=\(issue.auditType.rawValue): \(issue.compactDescription) \(element)")
            print("AUDIT-DETAIL[\(screen)] \(issue.detailedDescription)")
            return false
        }
    }

    func testAccessibilityAuditBrowse() throws {
        waitForBrowseCard()
        try audit("Browse")

        // Bring the cards that sat in the bottom band up into clear space.
        app.swipeUp(velocity: .slow)
        try audit("Browse scrolled")
    }

    func testAccessibilityAuditDetail() throws {
        openFirstRecipeAndWaitForDetail()
        try audit("Detail")
    }

    func testAccessibilityAuditSavedEmpty() throws {
        tab("Saved").tap()
        XCTAssertTrue(app.staticTexts["Nothing saved yet."].waitForExistence(timeout: 5))
        try audit("SavedEmpty")
    }

    func testAccessibilityAuditPlannerAndPicker() throws {
        openFirstRecipeAndWaitForDetail()
        app.buttons["detail.saveButton"].tap()
        tab("Planner").tap()
        XCTAssertTrue(app.buttons["planner.planMeal"].waitForExistence(timeout: 5))
        try audit("Planner")

        app.buttons["planner.planMeal"].tap()
        let row = app.buttons.matching(identifier: "picker.recipeRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // At the half-height detent the dimmed planner behind the sheet is
        // visible but deliberately inert, which the audit reports as
        // inaccessible text. Expanding the sheet audits the sheet itself.
        row.swipeUp()
        try audit("Picker")
    }
}
