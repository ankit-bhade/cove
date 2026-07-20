import XCTest
@testable import Cove

final class NoteWriterTests: XCTestCase {
    func testOlderWriteCannotFinishAfterNewerRevision() async throws {
        let probe = RevisionProbe()
        let writer = NoteWriter { revision in
            try await probe.persist(revision)
        }
        let firstRevision = revision(1, "one", expected: "original")
        let secondRevision = revision(2, "two", expected: "original")

        let first = Task { try await writer.submit(firstRevision) }
        await probe.waitUntilStarted(1)
        let second = Task { try await writer.submit(secondRevision) }
        await waitForPending(2, in: writer)
        await probe.release(1)
        await probe.waitUntilStarted(2)
        await probe.release(2)

        let firstResult = try await first.value
        let secondResult = try await second.value
        let persistedNumbers = await probe.persistedNumbers()
        let flushed = try await writer.flush()
        XCTAssertEqual(firstResult.number, 2)
        XCTAssertEqual(secondResult.number, 2)
        XCTAssertEqual(persistedNumbers, [1, 2])
        XCTAssertEqual(flushed?.text, "two")
    }

    func testRapidPendingEditsCoalesceToNewestPhysicalWrite() async throws {
        let probe = RevisionProbe()
        let writer = NoteWriter { revision in
            try await probe.persist(revision)
        }

        let firstRevision = revision(1, "one")
        let secondRevision = revision(2, "two")
        let thirdRevision = revision(3, "three")
        let first = Task { try await writer.submit(firstRevision) }
        await probe.waitUntilStarted(1)
        let second = Task { try await writer.submit(secondRevision) }
        await waitForPending(2, in: writer)
        let third = Task { try await writer.submit(thirdRevision) }
        await waitForPending(3, in: writer)
        await probe.release(1)
        await probe.waitUntilStarted(3)
        await probe.release(3)

        _ = try await (first.value, second.value, third.value)
        let persistedNumbers = await probe.persistedNumbers()
        let flushed = try await writer.flush()
        XCTAssertEqual(persistedNumbers, [1, 3])
        XCTAssertEqual(flushed?.text, "three")
    }

    func testFailedRevisionRemainsPendingForFlushRetry() async throws {
        let probe = RevisionProbe(failOnce: [1], suspends: false)
        let writer = NoteWriter { revision in
            try await probe.persist(revision)
        }

        do {
            _ = try await writer.submit(revision(1, "retry"))
            XCTFail("Expected the injected first attempt to fail")
        } catch is RevisionProbe.ProbeError {
            // Expected.
        }

        let persisted = try await writer.flush()
        XCTAssertEqual(persisted?.number, 1)
        XCTAssertEqual(persisted?.text, "retry")
        let persistedNumbers = await probe.persistedNumbers()
        XCTAssertEqual(persistedNumbers, [1])
    }

    func testExternalDiskVersionIsPreservedBeforeLocalSave() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cove-writer-conflict-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let note = root.appendingPathComponent("Note.md")
        try "external".write(to: note, atomically: true, encoding: .utf8)
        let writer = NoteWriter(fileURL: note,
                                sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)

        let result = try await writer.submit(
            revision(1, "local", expected: "original"))

        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "local")
        let conflictURL = try XCTUnwrap(result.conflictCopyURL)
        XCTAssertEqual(try String(contentsOf: conflictURL, encoding: .utf8), "external")
    }

    private func revision(_ number: UInt64,
                          _ text: String,
                          expected: String = "original") -> NoteWriter.Revision {
        NoteWriter.Revision(number: number, text: text, expectedDiskText: expected)
    }

    private func waitForPending(_ number: UInt64, in writer: NoteWriter) async {
        while await writer.pendingRevisionNumber != number { await Task.yield() }
    }
}

private actor RevisionProbe {
    enum ProbeError: Error { case injected }

    private var failOnce: Set<UInt64>
    private let suspends: Bool
    private var started: Set<UInt64> = []
    private var gates: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private var persisted: [UInt64] = []

    init(failOnce: Set<UInt64> = [], suspends: Bool = true) {
        self.failOnce = failOnce
        self.suspends = suspends
    }

    func persist(_ revision: NoteWriter.Revision) async throws -> NoteWriter.PersistedRevision {
        started.insert(revision.number)
        if suspends {
            await withCheckedContinuation { continuation in
                gates[revision.number] = continuation
            }
        }
        if failOnce.remove(revision.number) != nil {
            throw ProbeError.injected
        }
        persisted.append(revision.number)
        return NoteWriter.PersistedRevision(number: revision.number,
                                            text: revision.text,
                                            conflictCopyURL: nil)
    }

    func waitUntilStarted(_ number: UInt64) async {
        while !started.contains(number) { await Task.yield() }
    }

    func release(_ number: UInt64) {
        gates.removeValue(forKey: number)?.resume()
    }

    func persistedNumbers() -> [UInt64] { persisted }
}
