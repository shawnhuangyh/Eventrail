import Foundation
import Testing
@testable import Eventrail

struct LibraryBackupTests {
    /// A file of its own for each test, so tests running side by side never
    /// read each other's.
    func scratchFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "EventrailTests-\(UUID().uuidString).eventrail")
        try data.write(to: url)
        return url
    }

    func sampleArchive() -> LibraryArchive {
        var archive = LibraryArchive()
        let event = Fixtures.event(id: "300001", title: "水瀬いのり LIVE", isDetailed: true)
        archive.events[event.id] = event
        archive.membership[event.id] = Stamped(true, at: Date(timeIntervalSince1970: 1_800_000_000))
        archive.tracking[event.id] = Stamped(Tracking(ticket: .purchased, seat: "A5ブロック 12番",
                                                      cost: 9900, note: "最高"),
                                             at: Date(timeIntervalSince1970: 1_800_000_000))
        return archive
    }

    @Test func writesAndReadsBackTheSameArchive() throws {
        // A creation day of its own, so its file name is unlike any other test's.
        let created = Date(timeIntervalSince1970: 946_684_800)
        let url = try LibraryBackup(archive: sampleArchive(), created: created).write()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.pathExtension == "eventrail")
        let data = try Data(contentsOf: url)
        #expect(data.prefix(8) == Data("EVNTRAIL".utf8))
        #expect(data[data.startIndex + 8] == LibraryBackup.currentFormat)

        let read = try LibraryBackup.read(at: url)
        #expect(read.created == created)
        #expect(read.archive.isInLibrary("300001"))
        #expect(read.archive.events["300001"] == sampleArchive().events["300001"])
        #expect(read.archive.tracking["300001"] == sampleArchive().tracking["300001"])
    }

    @Test func filenameCarriesTheDay() {
        let backup = LibraryBackup(archive: LibraryArchive(), created: Fixtures.date(2027, 5, 9, 12))
        #expect(backup.filename.hasPrefix("Eventrail Backup 2027-05-"))
        #expect(backup.filename.hasSuffix(".eventrail"))
    }

    @Test func refusesAFileFromANewerVersion() throws {
        var data = Data("EVNTRAIL".utf8)
        data.append(LibraryBackup.currentFormat + 1)
        data.append(contentsOf: [0, 1, 2, 3])
        let url = try scratchFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let error = #expect(throws: LibraryBackup.Failure.self) { try LibraryBackup.read(at: url) }
        guard case .tooNew = error else {
            Issue.record("Expected .tooNew, got \(String(describing: error))")
            return
        }
    }

    @Test func refusesADamagedFileCarryingTheSignature() throws {
        var data = Data("EVNTRAIL".utf8)
        data.append(LibraryBackup.currentFormat)
        data.append(Data("not zlib at all".utf8))
        let url = try scratchFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let error = #expect(throws: LibraryBackup.Failure.self) { try LibraryBackup.read(at: url) }
        guard case .damaged = error else {
            Issue.record("Expected .damaged, got \(String(describing: error))")
            return
        }
    }

    @Test func refusesAFileThatIsNotABackup() throws {
        let url = try scratchFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let error = #expect(throws: LibraryBackup.Failure.self) { try LibraryBackup.read(at: url) }
        guard case .unreadable = error else {
            Issue.record("Expected .unreadable, got \(String(describing: error))")
            return
        }
    }

    @Test func readsTheAppsOwnLibraryFile() throws {
        let url = try scratchFile(JSONEncoder().encode(sampleArchive()))
        defer { try? FileManager.default.removeItem(at: url) }

        let read = try LibraryBackup.read(at: url)
        #expect(read.archive.isInLibrary("300001"))
    }
}
