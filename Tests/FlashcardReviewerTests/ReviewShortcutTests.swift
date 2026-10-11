import AppKit
import XCTest
@testable import FlashcardReviewer

final class ReviewShortcutTests: XCTestCase {
    func testArrowKeysNavigateInBothDirections() {
        XCTAssertEqual(ReviewShortcutMatcher.navigationDelta(keyCode: 123), -1)
        XCTAssertEqual(ReviewShortcutMatcher.navigationDelta(keyCode: 126), -1)
        XCTAssertEqual(ReviewShortcutMatcher.navigationDelta(keyCode: 124), 1)
        XCTAssertEqual(ReviewShortcutMatcher.navigationDelta(keyCode: 125), 1)
        XCTAssertNil(ReviewShortcutMatcher.navigationDelta(keyCode: 20))
    }

    func testHeldArrowKeysContinueNavigationWithoutRepeatingOtherShortcuts() {
        for keyCode: UInt16 in [123, 124, 125, 126] {
            XCTAssertTrue(ReviewShortcutMatcher.handlesNavigationRepeat(keyCode: keyCode))
        }
        XCTAssertFalse(ReviewShortcutMatcher.handlesNavigationRepeat(keyCode: 19))
    }

    func testTabMovesBetweenFrontAndBackEditorsInRequestedDirections() {
        XCTAssertTrue(ReviewShortcutMatcher.isForwardEditorTab(keyCode: 48, modifiers: []))
        XCTAssertTrue(ReviewShortcutMatcher.isForwardEditorTab(keyCode: 48, modifiers: [.capsLock]))
        XCTAssertFalse(ReviewShortcutMatcher.isForwardEditorTab(keyCode: 48, modifiers: [.shift]))
        XCTAssertFalse(ReviewShortcutMatcher.isForwardEditorTab(keyCode: 48, modifiers: [.command]))

        XCTAssertTrue(ReviewShortcutMatcher.isBackwardEditorTab(keyCode: 48, modifiers: [.shift]))
        XCTAssertTrue(ReviewShortcutMatcher.isBackwardEditorTab(keyCode: 48, modifiers: [.shift, .capsLock]))
        XCTAssertFalse(ReviewShortcutMatcher.isBackwardEditorTab(keyCode: 48, modifiers: []))
        XCTAssertFalse(ReviewShortcutMatcher.isBackwardEditorTab(keyCode: 48, modifiers: [.shift, .command]))
        XCTAssertFalse(ReviewShortcutMatcher.isBackwardEditorTab(keyCode: 123, modifiers: [.shift]))
    }

    @MainActor
    func testAdjustmentIsSavedImmediatelyAndNotesSurviveNavigationAndRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cards = [Flashcard(front: "Q1", back: "A1"), Flashcard(front: "Q2", back: "A2")]
        let model = AppModel(storageDirectory: directory)
        model.createSession(title: "Adjustment", cards: cards)

        model.markNeedsAdjustment()

        XCTAssertEqual(model.activeCard?.id, cards[0].id)
        XCTAssertEqual(model.activeCard?.verdict, .needsAdjustment)
        XCTAssertEqual(model.saveState, .saved)
        let immediatelyReopened = AppModel(storageDirectory: directory)
        XCTAssertEqual(immediatelyReopened.activeCard?.verdict, .needsAdjustment)
        model.updateNotes(cards[0].id, text: "Explain the example")
        model.moveSelection(by: 1)
        XCTAssertEqual(model.activeCard?.id, cards[1].id)
        model.moveSelection(by: -1)
        XCTAssertEqual(model.activeCard?.notes, "Explain the example")
        model.flushPendingWrites()

        let reopened = AppModel(storageDirectory: directory)
        XCTAssertEqual(reopened.activeCard?.id, cards[0].id)
        XCTAssertEqual(reopened.activeCard?.verdict, .needsAdjustment)
        XCTAssertEqual(reopened.activeCard?.notes, "Explain the example")
    }

    @MainActor
    func testAdjustmentKeepsCardAvailableWhenFilterWouldHideItAndUndoRestoresFilter() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let card = Flashcard(front: "Question", back: "Answer")
        let model = AppModel(storageDirectory: directory)
        model.createSession(title: "Filtered adjustment", cards: [card])
        model.selectFilter(.unreviewed)

        model.markNeedsAdjustment()

        XCTAssertEqual(model.filter, .all)
        XCTAssertEqual(model.activeCard?.id, card.id)
        XCTAssertEqual(model.activeCard?.verdict, .needsAdjustment)
        model.updateNotes(card.id, text: "More detail")
        XCTAssertEqual(model.activeCard?.notes, "More detail")
        model.undo()
        XCTAssertEqual(model.filter, .unreviewed)
        XCTAssertEqual(model.activeCard, card)
    }

    func testCopyRequiresCommandCWithoutOtherModifiers() {
        XCTAssertTrue(ReviewShortcutMatcher.copiesCards(characters: "c", modifiers: [.command]))
        XCTAssertTrue(ReviewShortcutMatcher.copiesCards(characters: "c", modifiers: [.command, .capsLock]))
        XCTAssertFalse(ReviewShortcutMatcher.copiesCards(characters: "c", modifiers: []))
        XCTAssertFalse(ReviewShortcutMatcher.copiesCards(characters: "c", modifiers: [.command, .shift]))
        XCTAssertFalse(ReviewShortcutMatcher.copiesCards(characters: "c", modifiers: [.command, .option]))
        XCTAssertFalse(ReviewShortcutMatcher.copiesCards(characters: "c", modifiers: [.command, .control]))
        XCTAssertFalse(ReviewShortcutMatcher.copiesCards(characters: "v", modifiers: [.command]))
    }

    func testSpaceShortcutKeysUsePhysicalKeyAndShiftForCopySelection() {
        XCTAssertTrue(ReviewShortcutMatcher.isUnmodifiedSpace(keyCode: 49, modifiers: []))
        XCTAssertFalse(ReviewShortcutMatcher.isUnmodifiedSpace(keyCode: 49, modifiers: [.shift]))
        XCTAssertFalse(ReviewShortcutMatcher.isUnmodifiedSpace(keyCode: 36, modifiers: []))

        XCTAssertTrue(ReviewShortcutMatcher.selectsCopySelection(keyCode: 49, modifiers: [.shift]))
        XCTAssertTrue(ReviewShortcutMatcher.selectsCopySelection(keyCode: 49, modifiers: [.shift, .capsLock]))
        XCTAssertFalse(ReviewShortcutMatcher.selectsCopySelection(keyCode: 49, modifiers: []))
        XCTAssertFalse(ReviewShortcutMatcher.selectsCopySelection(keyCode: 49, modifiers: [.shift, .command]))
        XCTAssertFalse(ReviewShortcutMatcher.selectsCopySelection(keyCode: 36, modifiers: [.shift]))
    }

    func testCommandNumberShortcutsSwitchReviewModesWithoutExtraModifiers() {
        XCTAssertTrue(ReviewShortcutMatcher.switchesToReviewMode(keyCode: 18, modifiers: [.command]))
        XCTAssertTrue(ReviewShortcutMatcher.switchesToReviewMode(keyCode: 18, modifiers: [.command, .capsLock]))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToReviewMode(keyCode: 19, modifiers: [.command]))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToReviewMode(keyCode: 18, modifiers: []))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToReviewMode(keyCode: 18, modifiers: [.command, .shift]))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToReviewMode(keyCode: 18, modifiers: [.command, .option]))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToReviewMode(keyCode: 18, modifiers: [.command, .control]))

        XCTAssertTrue(ReviewShortcutMatcher.switchesToFlashcardMode(keyCode: 19, modifiers: [.command]))
        XCTAssertTrue(ReviewShortcutMatcher.switchesToFlashcardMode(keyCode: 19, modifiers: [.command, .capsLock]))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToFlashcardMode(keyCode: 18, modifiers: [.command]))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToFlashcardMode(keyCode: 19, modifiers: []))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToFlashcardMode(keyCode: 19, modifiers: [.command, .shift]))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToFlashcardMode(keyCode: 19, modifiers: [.command, .option]))
        XCTAssertFalse(ReviewShortcutMatcher.switchesToFlashcardMode(keyCode: 19, modifiers: [.command, .control]))
    }

    @MainActor
    func testCopySelectionSurvivesNavigationAndUsesDeckOrderAndCurrentText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cards = [
            Flashcard(front: "First", back: "Answer 1", verdict: .good),
            Flashcard(front: "Second", back: "Answer 2"),
            Flashcard(front: "第三", back: "\\(x^2\\)\nSecond line")
        ]
        let model = AppModel(storageDirectory: directory)
        model.createSession(title: "Copy test", cards: cards)

        XCTAssertEqual(model.reviewCopyText, "First == Answer 1")
        model.selectCard(cards[2].id)
        model.toggleCopySelection()
        model.selectCard(cards[0].id)
        model.toggleCopySelection()
        model.moveSelection(by: 1)
        model.updateBack(cards[0].id, text: "Edited answer")

        XCTAssertEqual(model.selectedCardID, cards[1].id)
        XCTAssertEqual(model.cardsToCopy.map(\.id), [cards[0].id, cards[2].id])
        XCTAssertEqual(model.reviewCopyText, "First == Edited answer\n第三 == \\(x^2\\)\nSecond line")
        model.selectFilter(.unreviewed)
        XCTAssertEqual(model.cardsToCopy.map(\.id), [cards[0].id, cards[2].id])

        model.selectCard(cards[2].id)
        model.toggleCopySelection()
        XCTAssertEqual(model.cardsToCopy.map(\.id), [cards[0].id])
        model.clearCopySelection()
        XCTAssertEqual(model.cardsToCopy.map(\.id), [cards[2].id])
        model.selectFilter(.bad)
        model.toggleCopySelection()
        XCTAssertTrue(model.cardsToCopy.isEmpty)
        XCTAssertEqual(model.reviewCopyText, "")
        model.flushPendingWrites()
    }

    @MainActor
    func testCopySelectionClearsWhenLeavingOrChangingSessions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashcardReviewerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageDirectory: directory)
        model.createSession(title: "First", cards: [Flashcard(front: "Q1", back: "A1")])
        let firstSessionID = try XCTUnwrap(model.activeSessionID)
        model.toggleCopySelection()
        model.returnToLibrary()
        XCTAssertTrue(model.selectedCopyCardIDs.isEmpty)

        model.openSession(firstSessionID)
        model.toggleCopySelection()
        model.createSession(title: "Second", cards: [Flashcard(front: "Q2", back: "A2")])
        XCTAssertTrue(model.selectedCopyCardIDs.isEmpty)
        XCTAssertEqual(model.reviewCopyText, "Q2 == A2")
        model.toggleCopySelection()
        model.openSession(firstSessionID)
        XCTAssertTrue(model.selectedCopyCardIDs.isEmpty)
        XCTAssertEqual(model.reviewCopyText, "Q1 == A1")
        model.toggleCopySelection()
        model.deleteSession(firstSessionID)
        XCTAssertTrue(model.selectedCopyCardIDs.isEmpty)
        XCTAssertTrue(model.cardsToCopy.isEmpty)
    }

    func testShiftTwoUsesPhysicalKeyEvenWhenShiftChangesTheTypedSymbol() {
        XCTAssertTrue(
            ReviewShortcutMatcher.startsReplacementFlow(keyCode: 19, modifiers: [.shift])
        )
        XCTAssertFalse(
            ReviewShortcutMatcher.startsReplacementFlow(keyCode: 19, modifiers: [])
        )
        XCTAssertFalse(
            ReviewShortcutMatcher.startsReplacementFlow(keyCode: 20, modifiers: [.shift])
        )
        XCTAssertFalse(
            ReviewShortcutMatcher.startsReplacementFlow(keyCode: 19, modifiers: [.shift, .command])
        )
    }
}
