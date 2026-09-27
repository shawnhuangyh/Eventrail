import Foundation
import Testing
@testable import Eventrail

struct KeptFileTests {
    /// A file in a folder of its own, and defaults of its own to have been
    /// kept in before.
    private func file() throws -> (KeptFile<String, Int>, URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KeptFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "KeptFileTests-\(UUID().uuidString)"))
        let url = directory.appending(path: "kept.json")
        return (KeptFile(url: url, formerKey: "former", defaults: defaults), url, defaults)
    }

    private func stored(at url: URL) throws -> [String: Int] {
        try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))
    }

    @Test func readsWhatItWrote() async throws {
        let (file, url, _) = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var contents = ["a": 1]
        file.write(&contents)
        await file.settled()
        #expect(file.read() == ["a": 1])
    }

    @Test func noFileIsNothingKept() throws {
        let (file, url, _) = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(file.read().isEmpty)
    }

    @Test func whatUserDefaultsHeldIsMovedAcrossAndTheKeyDropped() throws {
        let (file, url, defaults) = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        defaults.set(try JSONEncoder().encode(["a": 1, "b": 2]), forKey: "former")

        #expect(file.read() == ["a": 1, "b": 2])
        #expect(try stored(at: url) == ["a": 1, "b": 2])
        #expect(defaults.data(forKey: "former") == nil)
    }

    @Test func aFileWrittenBesideTheOldKeyWinsOverIt() throws {
        let (file, url, defaults) = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try JSONEncoder().encode(["a": 10]).write(to: url)
        defaults.set(try JSONEncoder().encode(["a": 1, "b": 2]), forKey: "former")

        #expect(file.read() == ["a": 10, "b": 2])
    }

    @Test func aFileThatWillNotOpenIsNotWrittenOverAndIsFoldedInOnceItDoes() async throws {
        let (file, url, _) = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try JSONEncoder().encode(["a": 1, "b": 2]).write(to: url)
        let path = url.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        var contents = file.read()
        #expect(contents.isEmpty)

        // What a launch that could not read the file finds is not written
        // over what the file holds.
        contents["b"] = 20
        file.write(&contents)
        await file.settled()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        #expect(try stored(at: url) == ["a": 1, "b": 2])

        // The next write finds it open, and keeps the newer answer.
        contents["c"] = 3
        file.write(&contents)
        #expect(contents == ["a": 1, "b": 20, "c": 3])
        await file.settled()
        #expect(try stored(at: url) == ["a": 1, "b": 20, "c": 3])
    }

    @Test func aRemovalDropsAWriteStillWaiting() async throws {
        let (file, url, _) = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var contents = ["a": 1]
        file.write(&contents)
        file.remove()
        await file.settled()
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
