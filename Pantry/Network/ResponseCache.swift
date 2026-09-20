import Foundation

/// The last successful JSON response for each endpoint, written to disk so the
/// app can still show recipes with no connection. TheMealDB sends no cache
/// headers, so `URLCache` never keeps these — they're stored deliberately.
///
/// This lives in Caches/, which the system may purge when storage runs low.
/// That's the right trade for a convenience copy: losing it costs one refresh,
/// while saved recipes and plans live in SwiftData and are never at risk.
actor ResponseCache {
    struct Entry: Equatable {
        let data: Data
        /// When the response was written, so the UI can say how old it is.
        let storedAt: Date
    }

    static let shared: ResponseCache = {
        // UI tests get a directory of their own, so a test run never reads or
        // overwrites the offline copy the app itself is relying on — the same
        // promise `PantryModelContainer` makes about saved recipes.
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        return ResponseCache(
            directory: URL.cachesDirectory.appending(
                path: isUITesting ? "ResponseCache-uitests" : "ResponseCache",
                directoryHint: .isDirectory
            )
        )
    }()

    private let directory: URL
    /// Room for the default feed, every category, and a long run of searches
    /// and recipes. Past this the least recently written file is dropped.
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
            // The request itself already succeeded; failing to keep a copy of
            // it is never a reason to fail the call.
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

    /// One file per endpoint. Base64 keeps every character legal in a filename
    /// and keeps distinct keys distinct; the keys are short, so the names are.
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
