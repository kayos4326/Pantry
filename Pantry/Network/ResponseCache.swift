import Foundation

/// Stores recent API responses in the system cache directory for offline use.
actor ResponseCache {
    struct Entry: Equatable {
        let data: Data
        let storedAt: Date
    }

    static let shared: ResponseCache = {
        // Keep UI test data separate from the normal app cache.
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        return ResponseCache(
            directory: URL.cachesDirectory.appending(
                path: isUITesting ? "ResponseCache-uitests" : "ResponseCache",
                directoryHint: .isDirectory
            )
        )
    }()

    private let directory: URL
    private let limit: Int
    private let fileManager = FileManager.default

    init(directory: URL? = nil, limit: Int = 40) {
        self.directory = directory ?? URL.cachesDirectory.appending(path: "ResponseCache", directoryHint: .isDirectory)
        self.limit = limit
    }

    func store(_ data: Data, for key: String) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: key), options: .atomic)
            prune()
        } catch {
            // A cache failure should not turn a successful request into an error.
        }
    }

    func entry(for key: String) -> Entry? {
        let file = url(for: key)
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        let storedAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return Entry(data: data, storedAt: storedAt ?? .now)
    }

    func removeAll() {
        try? fileManager.removeItem(at: directory)
    }

    /// Base64 gives each cache key a safe, unique filename.
    private func url(for key: String) -> URL {
        let name = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appending(path: "\(name).json")
    }

    private func prune() {
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ),
            files.count > limit
        else { return }

        let oldestFirst = files.sorted { modified($0) < modified($1) }
        for file in oldestFirst.prefix(files.count - limit) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func modified(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}
