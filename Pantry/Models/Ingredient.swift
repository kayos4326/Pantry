import Foundation

/// One ingredient and its measurement from a recipe.
struct Ingredient: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let measure: String
}
