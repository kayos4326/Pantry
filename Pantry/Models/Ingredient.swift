import Foundation

/// A single ingredient/measure pair, flattened out of a Meal's
/// strIngredient1...20 / strMeasure1...20 fields.
struct Ingredient: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let measure: String
}
