import Foundation
import XCTest
@testable import FlashcardReviewer

final class AppModelPersistenceTests: XCTestCase {
    @MainActor
    func testReopeningSessionRestoresSelectionAndFilter() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cards = (1...40).map { Flashcard(front: "Question \($0)", back: "Answer", verdict: .good) }
        let model = AppModel(storageDirectory: directory)
        model.createSession(title: "Selection", cards: cards)
        let sessionID = try XCTUnwrap(model.activeSessionID)
        model.selectFilter(.good)
        model.selectCard(cards[30].id)
        model.returnToLibrary()
        model.openSession(sessionID)
        XCTAssertEqual(model.selectedCardID, cards[30].id)
        XCTAssertEqual(model.filter, .good)
        model.flushPendingWrites()

        let reopened = AppModel(storageDirectory: directory)
        XCTAssertEqual(reopened.selectedCardID, cards[30].id)
        XCTAssertEqual(reopened.filter, .good)
    }

    @MainActor
    func testAppendingCardsPreservesReviewedCardsAndSurvivesRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Flashcard(front: "Original", back: "Edited answer", verdict: .good, notes: "Keep this note")
        let model = AppModel(storageDirectory: directory)
        model.createSession(title: "Existing", cards: [original])
        let sessionID = try XCTUnwrap(model.activeSessionID)
        model.selectFilter(.good)
        model.toggleCopySelection()
        let report = FlashcardParser.parse("New == \\(x^2\\)\nNew == \\(x^2\\)\nMissing delimiter")
        model.appendCards(report.cards, to: sessionID, warnings: report.warnings)

        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.activeSession?.id, sessionID)
        XCTAssertEqual(model.activeSession?.cards, [original] + report.cards)
        XCTAssertEqual(model.activeSession?.importWarnings, report.warnings)
        XCTAssertEqual(model.selectedCardID, report.cards.first?.id)
        XCTAssertEqual(model.filter, .all)
        XCTAssertTrue(model.selectedCopyCardIDs.isEmpty)
        XCTAssertTrue(report.cards.allSatisfy { $0.verdict == .unreviewed })
        XCTAssertNotNil(model.activeSession?.cards.last?.issue)

        let reopened = AppModel(storageDirectory: directory)
        XCTAssertEqual(reopened.activeSession?.cards, [original] + report.cards)
        XCTAssertEqual(reopened.activeSession?.importWarnings, report.warnings)
        XCTAssertEqual(reopened.selectedCardID, report.cards.first?.id)
        XCTAssertEqual(reopened.filter, .all)
        let backup = try SessionBackup.decode(SessionBackup.encode(try XCTUnwrap(reopened.activeSession)))
        XCTAssertEqual(backup.cards, [original] + report.cards)
    }

    @MainActor
    func testAppendingEmptyInputOrToAnotherSessionDoesNothing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageDirectory: directory)
        model.createSession(title: "First", cards: [Flashcard(front: "Q1", back: "A1")])
        let firstID = try XCTUnwrap(model.activeSessionID)
        model.createSession(title: "Second", cards: [Flashcard(front: "Q2", back: "A2")])
        let before = model.sessions
        model.appendCards([Flashcard(front: "Wrong session", back: "A")], to: firstID)
        model.appendCards([], to: try XCTUnwrap(model.activeSessionID))
        XCTAssertEqual(model.sessions, before)
    }

    @MainActor
    func testNoticesDismissWithoutAViewAndRepeatedMessagesRestartTimer() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageDirectory: directory, noticeDuration: .milliseconds(300))
        model.notice = "Copied 1 card"
        try await Task.sleep(for: .milliseconds(200))
        model.notice = "Copied 1 card"
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.notice, "Copied 1 card")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.notice)
    }

    @MainActor
    func testNewNoticeGetsItsOwnTimerAcrossNavigation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageDirectory: directory, noticeDuration: .milliseconds(300))
        model.createSession(title: "Navigation", cards: [Flashcard(front: "Q", back: "A")])
        let sessionID = try XCTUnwrap(model.activeSessionID)
        model.notice = "First notice"
        try await Task.sleep(for: .milliseconds(200))
        model.returnToLibrary()
        model.openSession(sessionID)
        model.notice = "Second notice"
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.notice, "Second notice")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.notice)
    }

    @MainActor
    func testStaleProcessCannotOverwriteNewerArchive() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = AppModel(storageDirectory: directory)
        first.createSession(title: "Original", cards: [Flashcard(front: "Q", back: "A")])
        let stale = AppModel(storageDirectory: directory)

        first.renameSession(first.sessions[0].id, to: "Saved by first process")
        first.flushPendingWrites()
        stale.renameSession(stale.sessions[0].id, to: "Stale process overwrite")
        stale.flushPendingWrites()

        guard case .failed(let message) = stale.saveState else {
            return XCTFail("A stale process should report a save conflict instead of overwriting the newer archive.")
        }
        XCTAssertTrue(message.contains("another app process"))

        let reopened = AppModel(storageDirectory: directory)
        XCTAssertEqual(reopened.sessions.first?.title, "Saved by first process")
    }

    @MainActor
    func testCorruptArchiveIsPreservedAndRestoredBackupSurvivesRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptFile = directory.appendingPathComponent("sessions.json")
        let corruptBytes = Data("{ invalid".utf8)
        try corruptBytes.write(to: corruptFile)

        let sourceSession = FlashcardSession(title: "Restored session", cards: [
            Flashcard(front: "Question", back: "Answer", verdict: .needsAdjustment, notes: "Keep this note")
        ])
        let model = AppModel(storageDirectory: directory)
        model.restoreBackup(data: try SessionBackup.encode(sourceSession))

        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(try Data(contentsOf: corruptFile), corruptBytes)
        XCTAssertEqual(model.activeSession?.title, "Restored session")

        let reopened = AppModel(storageDirectory: directory)
        XCTAssertEqual(reopened.activeSession?.title, "Restored session")
        XCTAssertEqual(reopened.activeSession?.cards.first?.notes, "Keep this note")
    }
}
