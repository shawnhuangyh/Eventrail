import Foundation
import Testing
@testable import Eventrail

struct LibraryFileTests {
    /// A library file in a folder of its own, so a set-aside copy lands
    /// somewhere this test alone can see.
    private func file() throws -> (LibraryFile, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LibraryFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var file = LibraryFile()
        file.url = directory.appending(path: "library.json")
        return (file, directory)
    }

    private func archive(holding id: Event.ID) -> LibraryArchive {
        var archive = LibraryArchive()
        archive.events[id] = Fixtures.event(id: id)
        archive.membership[id] = Stamped(true)
        return archive
    }

    private func contents(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }

    @Test func readsWhatItSaved() throws {
        let (file, directory) = try file()
        defer { try? FileManager.default.removeItem(at: directory) }

        file.save(archive(holding: "1"))
        let loaded = file.load()
        #expect(loaded.archive.isInLibrary("1"))
        #expect(loaded.unreadable == 0)
        #expect(!loaded.recovered)
    }

    @Test func noFileIsAnEmptyLibraryAndNothingToReport() throws {
        let (file, directory) = try file()
        defer { try? FileManager.default.removeItem(at: directory) }

        let loaded = file.load()
        #expect(loaded.archive.holdsNothing)
        #expect(loaded.unreadable == 0)
        #expect(!loaded.isBlocked)
    }

    @Test func anUnreadableFileIsSetAsideRatherThanSavedOver() throws {
        let (file, directory) = try file()
        defer { try? FileManager.default.removeItem(at: directory) }
        let garbage = Data("{ not a library".utf8)
        try garbage.write(to: file.url)

        let loaded = file.load()
        #expect(loaded.archive.holdsNothing)
        #expect(loaded.unreadable == 1)

        // The launch goes on to save; the unreadable copy must survive it.
        file.save(archive(holding: "2"))
        let names = try contents(of: directory)
        #expect(names.count == 2)
        let aside = try #require(names.first { $0 != "library.json" })
        #expect(try Data(contentsOf: directory.appending(path: aside)) == garbage)

        // Still unreadable on the next launch, and still reported.
        #expect(file.load().unreadable == 1)
    }

    @Test func aSetAsideFileThatReadsNowIsFoldedBackIn() throws {
        let (file, directory) = try file()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Stands in for a file an earlier build could not read and a later one can.
        try JSONEncoder().encode(archive(holding: "old"))
            .write(to: directory.appending(path: "library.unreadable-20260926T120000-abcd1234.json"))
        file.save(archive(holding: "new"))

        let loaded = file.load()
        #expect(loaded.archive.isInLibrary("old"))
        #expect(loaded.archive.isInLibrary("new"))
        #expect(loaded.recovered)
        #expect(loaded.unreadable == 0)
        // Still there until the merged library has been saved.
        #expect(try contents(of: directory).count == 2)

        #expect(file.save(loaded.archive))
        file.discard(loaded.recoveredCopies)
        #expect(try contents(of: directory) == ["library.json"])
    }

    @Test func aFileThatWillNotOpenIsBlockedRatherThanReadAsEmpty() throws {
        let (file, directory) = try file()
        defer { try? FileManager.default.removeItem(at: directory) }
        file.save(archive(holding: "1"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.url.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.url.path(percentEncoded: false)) }

        let loaded = file.load()
        #expect(loaded.isBlocked)
        #expect(loaded.archive.holdsNothing)
        #expect(try contents(of: directory) == ["library.json"])
    }

    @Test func anUnreadableFileThatCannotBeMovedAsideIsBlocked() throws {
        let (file, directory) = try file()
        defer { try? FileManager.default.removeItem(at: directory) }
        let garbage = Data("{ not a library".utf8)
        try garbage.write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path(percentEncoded: false)) }

        let loaded = file.load()
        #expect(loaded.isBlocked)
        #expect(!file.save(archive(holding: "2")))
        #expect(try Data(contentsOf: file.url) == garbage)
    }
}
