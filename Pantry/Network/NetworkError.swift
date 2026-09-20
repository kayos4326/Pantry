import Foundation

enum NetworkError: LocalizedError, Equatable {
    case noConnection
    case badResponse(statusCode: Int)
    case emptyResults
    case decodingFailed
    case invalidURL
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection. Check your network and try again."
        case .badResponse(let statusCode):
            return "The server returned an unexpected response (code \(statusCode))."
        case .emptyResults:
            return "No results found."
        case .decodingFailed:
            return "Couldn't read the data from the server."
        case .invalidURL:
            return "That request couldn't be built."
        case .unknown(let message):
            return message
        }
    }
}
