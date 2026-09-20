import Foundation
@testable import Pantry

enum Fixtures {
    /// A full meal as search.php / lookup.php return it, including blank and
    /// whitespace-only ingredient slots and a lowercase ingredient name.
    static func fullMealJSON(
        id: String = "52795",
        name: String = "Chicken Handi",
        instructions: String = "Heat oil.\\r\\nAdd onions and fry for 5 minutes.\\r\\nMarinate overnight.",
        thumb: String = "https://www.themealdb.com/images/media/meals/wyxwsp1486979827.jpg"
    ) -> String {
        var fields: [String] = [
            #""idMeal": "\#(id)""#,
            #""strMeal": "\#(name)""#,
            #""strCategory": "Chicken""#,
            #""strArea": "Indian""#,
            #""strInstructions": "\#(instructions)""#,
            #""strMealThumb": "\#(thumb)""#,
            #""strTags": "Spicy,Curry""#,
            #""strYoutube": null"#
        ]
        let ingredients: [(String?, String?)] = [
            ("Chicken", "1.2 kg"), ("  onion ", " 5 sliced "), ("", ""), ("   ", "2 tbsp"), (nil, nil),
            ("Garlic", nil)
        ]
        for index in 1...20 {
            let pair = index <= ingredients.count ? ingredients[index - 1] : ("", "")
            fields.append(#""strIngredient\#(index)": \#(pair.0.map { "\"\($0)\"" } ?? "null")"#)
            fields.append(#""strMeasure\#(index)": \#(pair.1.map { "\"\($0)\"" } ?? "null")"#)
        }
        return "{\(fields.joined(separator: ","))}"
    }

    static func mealsResponse(_ meals: [String]) -> String {
        #"{"meals":[\#(meals.joined(separator: ","))]}"#
    }

    static let emptyMeals = #"{"meals":null}"#

    static func filterMealJSON(id: String, name: String) -> String {
        #"{"strMeal":"\#(name)","strMealThumb":"https://example.com/\#(id).jpg","idMeal":"\#(id)","strArea":"British"}"#
    }

    static let categories = #"""
    {"categories":[
      {"idCategory":"1","strCategory":"Beef","strCategoryThumb":"https://example.com/beef.png","strCategoryDescription":"Beef."},
      {"idCategory":"2","strCategory":"Chicken","strCategoryThumb":"https://example.com/chicken.png","strCategoryDescription":"Chicken."}
    ]}
    """#

    static func meal(
        id: String = "1",
        name: String = "Test Meal",
        instructions: String? = "Cook for 10 minutes.",
        ingredients: [Ingredient] = [Ingredient(id: 1, name: "Salt", measure: "1 tsp")]
    ) -> Meal {
        Meal(
            id: id,
            name: name,
            thumbnailURL: URL(string: "https://example.com/\(id).jpg"),
            category: "Chicken",
            area: "Indian",
            instructions: instructions,
            ingredients: ingredients
        )
    }
}
