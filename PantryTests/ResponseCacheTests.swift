import Foundation
import Testing
@testable import Pantry

@Suite("ResponseCache")
struct ResponseCacheTests {
    private func makeCache(limit: Int = 40) -> ResponseCache {
        StubURLProtocol.makeCache(limit: limit)
    }

    @Test("A stored response reads back with the time it was written")
    func roundTrip() async throws {
        let cache = makeCache()
        let body = Data(#"{"meals":[]}"#.utf8)

        await cache.store(body, for: "search:chicken")

        let entry = try #require(await cache.entry(for: "search:chicken"))
        #expect(entry.data == body)
        #expect(abs(entry.storedAt.timeIntervalSinceNow) < 5)
    }

    @Test("Nothing stored means nothing to show")
    func missingKey() async {
        let cache = makeCache()
        #expect(await cache.entry(for: "search:nothing") == nil)
    }

    @Test("Keys don't collide, including ones differing only in punctuation")
    func separateKeys() async throws {
        let cache = makeCache()
        await cache.store(Data("beef".utf8), for: "filter:beef")
        await cache.store(Data("chicken".utf8), for: "filter:chicken")
        // "/" and "+" appear in raw base64 and must not escape into a path.
        await cache.store(Data("odd".utf8), for: "search:a/b+c d")

        #expect(await cache.entry(for: "filter:beef")?.data == Data("beef".utf8))
        #expect(await cache.entry(for: "filter:chicken")?.data == Data("chicken".utf8))
        #expect(await cache.entry(for: "search:a/b+c d")?.data == Data("odd".utf8))
    }

    @Test("Re-storing a key replaces it rather than growing the cache")
    func overwrite() async throws {
        let cache = makeCache()
        await cache.store(Data("old".utf8), for: "categories")
        await cache.store(Data("new".utf8), for: "categories")

        #expect(await cache.entry(for: "categories")?.data == Data("new".utf8))
    }

    @Test("Past the limit the least recently written entries are dropped")
    func eviction() async throws {
        let cache = makeCache(limit: 3)
        for index in 1...3 {
            await cache.store(Data("meal\(index)".utf8), for: "lookup:\(index)")
            // Modification dates have coarse resolution on some filesystems,
            // so space the writes enough for the order to be unambiguous.
            try await Task.sleep(for: .milliseconds(20))
        }

        await cache.store(Data("meal4".utf8), for: "lookup:4")

        #expect(await cache.entry(for: "lookup:1") == nil, "the oldest entry should have gone")
        #expect(await cache.entry(for: "lookup:3")?.data == Data("meal3".utf8))
        #expect(await cache.entry(for: "lookup:4")?.data == Data("meal4".utf8))
    }

    @Test("Clearing removes everything")
    func removeAll() async {
        let cache = makeCache()
        await cache.store(Data("x".utf8), for: "categories")

        await cache.removeAll()

        #expect(await cache.entry(for: "categories") == nil)
    }

    @Test("An unwritable directory fails silently instead of throwing")
    func unwritableDirectory() async {
        // /dev/null can't hold a directory, so every write fails.
        let cache = ResponseCache(directory: URL(fileURLWithPath: "/dev/null/nope"))

        await cache.store(Data("x".utf8), for: "categories")

        #expect(await cache.entry(for: "categories") == nil)
    }
}
