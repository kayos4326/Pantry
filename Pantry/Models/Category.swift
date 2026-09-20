import Foundation

struct Category: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let thumbnailURL: URL?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case id = "idCategory"
        case name = "strCategory"
        case thumbnailURL = "strCategoryThumb"
        case description = "strCategoryDescription"
    }
}

struct CategoryResponse: Codable {
    let categories: [Category]
}
