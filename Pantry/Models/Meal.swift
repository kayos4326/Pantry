import Foundation

/// A recipe returned by TheMealDB. Different endpoints return different
/// subsets of these fields (e.g. filter.php only gives id/name/thumbnail),
/// so every field besides `id` and `name` is optional.
struct Meal: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let thumbnailURL: URL?
    let category: String?
    let area: String?
    let instructions: String?
    let tags: String?
    let youtubeURL: String?
    let ingredients: [Ingredient]

    private enum CodingKeys: String, CodingKey {
        case id = "idMeal"
        case name = "strMeal"
        case thumbnailURL = "strMealThumb"
        case category = "strCategory"
        case area = "strArea"
        case instructions = "strInstructions"
        case tags = "strTags"
        case youtubeURL = "strYoutube"
    }

    /// Keys for the 20 numbered ingredient/measure pairs, e.g. "strIngredient1", "strMeasure1".
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Decoded leniently: TheMealDB is crowd-sourced, and one malformed
        // image URL would otherwise fail decoding for an entire result list.
        let thumbnailString = try? container.decodeIfPresent(String.self, forKey: .thumbnailURL)
        thumbnailURL = thumbnailString.flatMap { URL(string: $0) }
        category = try container.decodeIfPresent(String.self, forKey: .category)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        youtubeURL = try container.decodeIfPresent(String.self, forKey: .youtubeURL)

        let dynamicContainer = try decoder.container(keyedBy: DynamicKey.self)
        ingredients = Meal.parseIngredients(from: dynamicContainer)
    }

    init(
        id: String,
        name: String,
        thumbnailURL: URL?,
        category: String?,
        area: String?,
        instructions: String?,
        tags: String? = nil,
        youtubeURL: String? = nil,
        ingredients: [Ingredient]
    ) {
        self.id = id
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.category = category
        self.area = area
        self.instructions = instructions
        self.tags = tags
        self.youtubeURL = youtubeURL
        self.ingredients = ingredients
    }

    /// Walks strIngredient1...20 / strMeasure1...20, skipping any pair where
    /// the ingredient name is missing, empty, or whitespace-only.
    private static func parseIngredients(from container: KeyedDecodingContainer<DynamicKey>) -> [Ingredient] {
        var result: [Ingredient] = []
        for index in 1...20 {
            guard
                let nameKey = DynamicKey(stringValue: "strIngredient\(index)"),
                let measureKey = DynamicKey(stringValue: "strMeasure\(index)")
            else { continue }

            let rawName = (try? container.decodeIfPresent(String.self, forKey: nameKey)) ?? nil
            let rawMeasure = (try? container.decodeIfPresent(String.self, forKey: measureKey)) ?? nil

            guard let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                continue
            }
            let measure = rawMeasure?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // ~300 ingredient names in the catalogue start lowercase ("garlic"),
            // which looks inconsistent next to "Garlic" in the same list.
            let displayName = name.prefix(1).uppercased() + name.dropFirst()
            result.append(Ingredient(id: index, name: displayName, measure: measure))
        }
        return result
    }

    /// TheMealDB serves a ~9KB thumbnail alongside the ~112KB full image.
    /// Used in grids so scrolling doesn't pull down full-size photos.
    var gridThumbnailURL: URL? {
        thumbnailURL?.appendingPathComponent("preview")
    }

    /// filter.php returns meals without instructions or ingredients, so the
    /// detail screen uses this to decide whether it needs to re-fetch by id.
    var isFullyLoaded: Bool {
        !(instructions ?? "").isEmpty && !ingredients.isEmpty
    }

    /// strTags is a comma-separated string when present, e.g. "Spicy,Curry".
    var tagList: [String] {
        (tags ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Steps interleaved with any sub-headings, ready for display.
    var instructionLines: [InstructionLine] {
        InstructionParser.lines(from: instructions)
    }

    var instructionSteps: [String] {
        instructionLines.compactMap { line in
            if case .step(let text) = line { return text }
            return nil
        }
    }
}

/// search.php, filter.php, and lookup.php all wrap results in a top-level
/// "meals" key, which is `null` (not an empty array) when there are no matches.
struct MealResponse: Decodable {
    let meals: [Meal]?
}
