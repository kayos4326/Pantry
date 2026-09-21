import Foundation
import SwiftData
import Testing
@testable import Pantry

@Suite("SwiftData persistence")
struct PersistenceTests {
    private func makeContext() throws -> ModelContext {
        let schema = PantryModelContainer.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func recipe(_ id: String, name: String = "Recipe", instructions: String = "Cook for 10 minutes.") -> SavedRecipe {
        SavedRecipe(
            meal: Fixtures.meal(
                id: id,
                name: name,
                instructions: instructions,
                ingredients: [Ingredient(id: 1, name: "Salt", measure: "1 tsp"), Ingredient(id: 4, name: "Egg", measure: "2")]
            )
        )
    }

    @Test("A store-opening failure is returned without deleting the existing path")
    func failedStoreOpenPreservesData() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A regular file makes this an invalid database directory.
        let marker = root.appending(path: "keep-me")
        let original = Data("existing user data".utf8)
        try original.write(to: marker)
        let unavailableURL = marker.appending(path: "Pantry.store")
        let configuration = ModelConfiguration(
            "FailurePath",
            schema: PantryModelContainer.schema,
            url: unavailableURL
        )

        let result = PantryModelContainer.make(configuration: configuration)

        if case .success = result {
            Issue.record("An unavailable store path unexpectedly opened")
        }
        #expect(try Data(contentsOf: marker) == original)
    }

    @Test("A saved recipe round-trips every field, including ingredients, for offline use")
    func roundTrip() throws {
        let context = try makeContext()
        context.insert(recipe("52795", name: "Chicken Handi"))
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<SavedRecipe>()).first)
        #expect(fetched.name == "Chicken Handi")
        #expect(fetched.ingredients.map(\.name) == ["Salt", "Egg"])
        #expect(fetched.ingredients.map(\.id) == [1, 4])

        let meal = fetched.asMeal
        #expect(meal.id == "52795")
        #expect(meal.isFullyLoaded)
        #expect(meal.thumbnailURL?.absoluteString == "https://example.com/52795.jpg")
    }

    @Test("Saving the same meal twice doesn't create a duplicate")
    func uniqueMealID() throws {
        let context = try makeContext()
        context.insert(recipe("1"))
        try context.save()
        context.insert(recipe("1"))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<SavedRecipe>()) == 1)
    }

    @Test("Planned dates are normalised to midnight")
    func dateNormalised() throws {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: .now)!
        let plan = PlannedMeal(date: noon, recipe: nil)
        #expect(plan.date == Calendar.current.startOfDay(for: noon))
    }

    @Test("Unsaving a planned recipe removes its plans and leaves other days alone")
    func cascadeDelete() throws {
        let context = try makeContext()
        let handi = recipe("1", name: "Handi")
        let stew = recipe("2", name: "Stew")
        context.insert(handi)
        context.insert(stew)
        let calendar = Calendar.current
        context.insert(PlannedMeal(date: .now, recipe: handi))
        context.insert(PlannedMeal(date: calendar.date(byAdding: .day, value: 3, to: .now)!, recipe: handi))
        context.insert(PlannedMeal(date: calendar.date(byAdding: .day, value: 1, to: .now)!, recipe: stew))
        try context.save()
        #expect(handi.plannedMeals.count == 2)

        context.delete(handi)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<PlannedMeal>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.recipe?.name == "Stew")
        #expect(remaining.allSatisfy { $0.recipe != nil })
    }

    @Test("Unsaving clears every meal it was planned for, including two on one day")
    func cascadeDeleteWithinADay() throws {
        let context = try makeContext()
        let handi = recipe("1", name: "Handi")
        let stew = recipe("2", name: "Stew")
        context.insert(handi)
        context.insert(stew)
        context.insert(PlannedMeal(date: .now, recipe: handi))
        context.insert(PlannedMeal(date: .now, recipe: handi))
        context.insert(PlannedMeal(date: .now, recipe: stew))
        try context.save()

        context.delete(handi)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<PlannedMeal>())
        #expect(remaining.map { $0.recipe?.name } == ["Stew"])
    }

    @Test("A day holds several meals, in the order they were added")
    func severalMealsPerDay() throws {
        let context = try makeContext()
        let a = recipe("1", name: "A")
        let b = recipe("2", name: "B")
        context.insert(a)
        context.insert(b)
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        context.insert(PlannedMeal(date: noon, recipe: a, plannedAt: .now))
        context.insert(PlannedMeal(date: noon, recipe: b, plannedAt: .now.addingTimeInterval(5)))
        try context.save()

        let plans = try context.fetch(
            FetchDescriptor<PlannedMeal>(sortBy: [SortDescriptor(\.plannedAt)])
        )
        #expect(plans.count == 2)
        #expect(plans.map { $0.recipe?.name } == ["A", "B"])
        #expect(plans[0].date == plans[1].date)
    }

    @Test("The same recipe can be planned twice on one day, and counts as one day")
    func sameRecipeTwiceInADay() throws {
        let context = try makeContext()
        let a = recipe("1", name: "A")
        context.insert(a)
        let today = Date.now
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        context.insert(PlannedMeal(date: today, recipe: a))
        context.insert(PlannedMeal(date: today, recipe: a))
        context.insert(PlannedMeal(date: tomorrow, recipe: a))
        try context.save()

        #expect(a.plannedMeals.count == 3)
        #expect(a.plannedDayCount == 2)
    }

    @Test("Only a required head start schedules prep")
    func requiredLeadDays() throws {
        let context = try makeContext()
        let marinated = recipe("1", instructions: "Marinate the lamb overnight.")
        let optional = recipe("2", instructions: "You can make this a day ahead.")
        let plain = recipe("3", instructions: "Fry for 5 minutes.")
        [marinated, optional, plain].forEach(context.insert)

        let meal = Calendar.current.date(byAdding: .day, value: 5, to: .now)!
        let marinatedPlan = PlannedMeal(date: meal, recipe: marinated)
        let optionalPlan = PlannedMeal(date: meal, recipe: optional)
        let plainPlan = PlannedMeal(date: meal, recipe: plain)

        #expect(marinatedPlan.requiredLeadDays == 1)
        #expect(marinatedPlan.prepStartDate == Calendar.current.date(byAdding: .day, value: -1, to: marinatedPlan.date))
        #expect(optionalPlan.requiredLeadDays == nil)
        #expect(optionalPlan.prepStartDate == optionalPlan.date)
        #expect(plainPlan.requiredLeadDays == nil)
    }

    @Test("A missing image is stored as nil until downloaded")
    func imageDefaultsToNil() throws {
        let context = try makeContext()
        let saved = recipe("1")
        context.insert(saved)
        try context.save()
        #expect(saved.imageData == nil)
        #expect(saved.gridThumbnailURL?.absoluteString == "https://example.com/1.jpg/preview")
    }
}

@Suite("Recently viewed")
@MainActor
struct RecentRecipeTests {
    private func makeContext() throws -> ModelContext {
        let schema = PantryModelContainer.schema
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func recents(_ context: ModelContext) throws -> [RecentRecipe] {
        try context.fetch(FetchDescriptor<RecentRecipe>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)]))
    }

    @Test("Opening a recipe records the whole recipe, so it reopens offline")
    func recordsAVisit() throws {
        let context = try makeContext()

        RecentRecipe.record(Fixtures.meal(id: "52795", name: "Chicken Handi"), in: context)
        try context.save()

        let recent = try #require(try recents(context).first)
        #expect(recent.mealID == "52795")
        #expect(recent.name == "Chicken Handi")
        #expect(recent.category == "Chicken")
        #expect(recent.gridThumbnailURL?.absoluteString == "https://example.com/52795.jpg/preview")

        let meal = recent.asMeal
        #expect(meal.id == "52795")
        #expect(meal.isFullyLoaded, "a recorded visit has to be openable with no connection")
        #expect(meal.ingredients.map(\.name) == ["Salt"])
        #expect(meal.instructions == "Cook for 10 minutes.")
    }

    @Test("A visit recorded before the recipe loaded is completed by the next one")
    func partialVisitCompletedLater() throws {
        let context = try makeContext()
        let partial = Meal(
            id: "9", name: "Beef Pie", thumbnailURL: URL(string: "https://example.com/9.jpg"),
            category: nil, area: nil, instructions: nil, ingredients: []
        )
        RecentRecipe.record(partial, in: context)
        try context.save()
        #expect(try recents(context).first?.asMeal.isFullyLoaded == false)

        RecentRecipe.record(Fixtures.meal(id: "9", name: "Beef Pie"), in: context)
        try context.save()

        #expect(try recents(context).first?.asMeal.isFullyLoaded == true)
    }

    @Test("A later partial visit never wipes the full recipe already recorded")
    func partialVisitKeepsFullRecipe() throws {
        let context = try makeContext()
        RecentRecipe.record(Fixtures.meal(id: "9", name: "Beef Pie"), in: context)
        try context.save()

        let partial = Meal(
            id: "9", name: "Beef Pie", thumbnailURL: nil,
            category: nil, area: nil, instructions: nil, ingredients: []
        )
        RecentRecipe.record(partial, in: context)
        try context.save()

        let recent = try #require(try recents(context).first)
        #expect(recent.asMeal.isFullyLoaded)
        #expect(recent.category == "Chicken")
        #expect(recent.thumbnailURLString == "https://example.com/9.jpg")
    }

    @Test("Opening the same recipe again moves it to the front instead of duplicating it")
    func repeatVisitMovesToFront() throws {
        let context = try makeContext()
        RecentRecipe.record(Fixtures.meal(id: "1", name: "First"), in: context)
        RecentRecipe.record(Fixtures.meal(id: "2", name: "Second"), in: context)
        try context.save()
        #expect(try recents(context).map(\.name) == ["Second", "First"])

        RecentRecipe.record(Fixtures.meal(id: "1", name: "First"), in: context)
        try context.save()

        #expect(try recents(context).map(\.name) == ["First", "Second"])
        #expect(try context.fetchCount(FetchDescriptor<RecentRecipe>()) == 2)
    }

    @Test("A later visit fills in details the first card didn't carry")
    func backfillsMissingDetails() throws {
        let context = try makeContext()
        let fromCategoryBrowsing = Meal(
            id: "9", name: "Beef Pie", thumbnailURL: URL(string: "https://example.com/9.jpg"),
            category: nil, area: nil, instructions: nil, ingredients: []
        )
        RecentRecipe.record(fromCategoryBrowsing, in: context)
        try context.save()
        #expect(try recents(context).first?.category == nil)

        RecentRecipe.record(Fixtures.meal(id: "9", name: "Beef Pie"), in: context)
        try context.save()

        #expect(try recents(context).first?.category == "Chicken")
    }

    @Test("The list is trimmed to the most recent few")
    func trimsToLimit() throws {
        let context = try makeContext()
        for index in 1...8 {
            RecentRecipe.record(Fixtures.meal(id: "\(index)", name: "Meal \(index)"), in: context)
        }
        try context.save()

        RecentRecipe.record(Fixtures.meal(id: "9", name: "Meal 9"), in: context, limit: 3)
        try context.save()

        let kept = try recents(context)
        #expect(kept.count == 3)
        #expect(kept.map(\.name) == ["Meal 9", "Meal 8", "Meal 7"])
    }

    @Test("Clearing empties the strip")
    func clearing() throws {
        let context = try makeContext()
        RecentRecipe.record(Fixtures.meal(id: "1"), in: context)
        RecentRecipe.record(Fixtures.meal(id: "2"), in: context)
        try context.save()

        RecentRecipe.clear(in: context)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<RecentRecipe>()) == 0)
    }

    @Test("Recents are separate from saved recipes: clearing one leaves the other")
    func independentOfSaved() throws {
        let context = try makeContext()
        let saved = SavedRecipe(meal: Fixtures.meal(id: "1"))
        context.insert(saved)
        RecentRecipe.record(Fixtures.meal(id: "1"), in: context)
        try context.save()

        RecentRecipe.clear(in: context)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<SavedRecipe>()) == 1)
    }
}
