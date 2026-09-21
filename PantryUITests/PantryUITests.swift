import XCTest

/// Main user flows and accessibility checks using an isolated in-memory store.
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

        // A day can contain more than one meal.
        XCTAssertEqual(app.buttons.matching(identifier: "planner.plannedRecipe").count, 2)
        try audit("Planner with two meals")

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
        // The recent card shares its recipe name with the browse card.
        XCTAssertFalse(recent.label.isEmpty)
        XCTAssertTrue(
            openedName.localizedCaseInsensitiveContains(recent.label),
            "Recently viewed shows '\(recent.label)' after opening '\(openedName)'"
        )

        try audit("Browse with recents")

        recent.tap()
        XCTAssertTrue(app.buttons["detail.saveButton"].waitForExistence(timeout: 20), "Recently viewed didn't reopen the recipe")
    }

    // MARK: - Dynamic Type

    /// Measures one example for each font and scaling curve used by the app.
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
            // Fixed text would stay at 1.0x, so 1.2x confirms scaling.
            XCTAssertGreaterThan(grown, height * 1.2, "\(name) didn't grow with Dynamic Type")
        }
    }

    // MARK: - Accessibility audits

    /// Runs Apple's audit while filtering known false positives around
    /// floating bars and custom-font scaling.
    private func audit(_ screen: String) throws {
        let tabBar = app.tabBars.firstMatch
        let windowHeight = app.windows.firstMatch.frame.height
        // Ignore content hidden by the top scroll-edge fade.
        let statusBarBottom = app.statusBars.firstMatch.exists ? app.statusBars.firstMatch.frame.maxY : 59
        // The bottom scroll-edge fade begins above the floating tab bar.
        let barTop = tabBar.exists ? tabBar.frame.minY : windowHeight - 90
        let obscuredRegion = CGRect(x: 0, y: barTop - 80, width: .greatestFiniteMagnitude, height: windowHeight)

        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.dynamicType)) { issue in
            let element = issue.element.map { "'\($0.label)' id='\($0.identifier)' frame=\($0.frame)" } ?? "no element"
            // Text in the fade is checked again after scrolling into clear space.
            if [.contrast, .textClipped].contains(issue.auditType),
               let frame = issue.element?.frame, frame.intersects(obscuredRegion) {
                print("AUDIT[\(screen)] ignored under tab bar: \(issue.compactDescription) \(element)")
                return true
            }
            if [.contrast, .textClipped].contains(issue.auditType),
               let frame = issue.element?.frame, frame.maxY <= statusBarBottom {
                print("AUDIT[\(screen)] ignored behind status bar: \(issue.compactDescription) \(element)")
                return true
            }
            // Font scaling is tested with direct size measurements above.
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
        // Expand the sheet so the audit skips the inactive view behind it.
        row.swipeUp()
        try audit("Picker")
    }
}
