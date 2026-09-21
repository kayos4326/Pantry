import Foundation
@testable import Pantry

/// Intercepts requests so network tests run offline with fixed responses.
final class StubURLProtocol: URLProtocol {
    enum Reply {
        case json(String, status: Int = 200, delay: Duration = .zero)
        case data(Data, status: Int = 200)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (URLRequest) -> Reply = { _ in .failure(.unknown) }
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static func install(_ handler: @escaping (URLRequest) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        recorded = []
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    /// Creates a manager with an isolated response cache.
    static func makeNetworkManager(
        cache: ResponseCache? = nil,
        _ handler: @escaping (URLRequest) -> Reply
    ) -> NetworkManager {
        install(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return NetworkManager(session: URLSession(configuration: configuration), cache: cache ?? makeCache())
    }

    static func makeCache(limit: Int = 40) -> ResponseCache {
        ResponseCache(
            directory: URL.temporaryDirectory.appending(
                path: "PantryTestCaches/\(UUID().uuidString)",
                directoryHint: .isDirectory
            ),
            limit: limit
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let reply = Self.handler(request)
        Self.lock.unlock()

        switch reply {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .data(let data, let status):
            respond(status: status, body: data)
        case .json(let body, let status, let delay):
            if delay == .zero {
                respond(status: status, body: Data(body.utf8))
            } else {
                let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in
                    self?.respond(status: status, body: Data(body.utf8))
                }
            }
        }
    }

    override func stopLoading() {}

    private func respond(status: Int, body: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

extension URLRequest {
    func queryValue(_ name: String) -> String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first { $0.name == name }?.value
    }
}
