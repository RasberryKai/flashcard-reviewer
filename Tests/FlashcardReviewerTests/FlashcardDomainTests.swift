import Foundation
import XCTest
@testable import FlashcardReviewer

final class FlashcardDomainTests: XCTestCase {
    func testDollarMathWrappersConvertOnlyInAnkiExportAndPreserveSource() throws {
        let source = #"inline $x + 1$; display $$y^2$$; \(z\); \[w\]; \neq"#
        let card = Flashcard(front: source, back: "Answer", verdict: .good)
        let session = FlashcardSession(title: "Math", cards: [card])

        let formatted = try FlashcardMathFormatter.formatForAnki(source)
        XCTAssertEqual(formatted, #"inline \(x + 1\); display \[y^2\]; \(z\); \[w\]; \neq"#)

        let anki = try CardExport.ankiText(session: session)
        XCTAssertTrue(anki.contains(#"inline \(x + 1\); display \[y^2\]"#))
        XCTAssertEqual(session.cards[0].front, source)
    }

    func testCurrencyAndLoneDollarSignsRemainLiteralText() throws {
        let source = #"Price $5; range $5 and $10; a lone $ sign."#
        let spans = FlashcardMathAnalyzer.analyze(source)

        XCTAssertTrue(spans.contains { $0.kind == .currencyOrProse })
        XCTAssertFalse(spans.contains(where: \.requiresChoice))
        XCTAssertEqual(try FlashcardMathFormatter.formatForAnki(source), source)

        let card = Flashcard(front: source, back: "Cost", verdict: .good)
        let anki = try CardExport.ankiText(session: FlashcardSession(title: "Prices", cards: [card]))
        XCTAssertTrue(anki.contains(source))
    }

    func testAmbiguousAndUnmatchedDollarMathRequireAndUseExplicitChoices() throws {
        let ambiguous = #"$hello world$"#
        let card = Flashcard(front: "Define \(ambiguous)", back: "Meaning", verdict: .good)
        let session = FlashcardSession(title: "Ambiguous", cards: [card])
        let analyzed = FlashcardMathAnalyzer.analyze(card.front)
        XCTAssertTrue(analyzed.contains { $0.source == ambiguous && $0.requiresChoice })

        XCTAssertThrowsError(try CardExport.ankiText(session: session)) { error in
            guard case CardExportError.unresolvedMathChoice(let cardID, let side, let span) = error else {
                return XCTFail("Expected an actionable unresolved math choice error.")
            }
            XCTAssertEqual(cardID, card.id)
            XCTAssertEqual(side, .front)
            XCTAssertEqual(span, ambiguous)
            XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("Keep as text") == true)
        }

        var keepAsText = session
        keepAsText.cards[0].mathInterpretations[ambiguous] = .keepAsText
        XCTAssertTrue(try CardExport.ankiText(session: keepAsText).contains(ambiguous))

        var treatAsMath = session
        treatAsMath.cards[0].mathInterpretations[ambiguous] = .treatAsMath
        XCTAssertTrue(try CardExport.ankiText(session: treatAsMath).contains(#"\(hello world\)"#))

        let unmatched = #"$x + 1"#
        XCTAssertTrue(FlashcardMathAnalyzer.analyze(unmatched).contains {
            $0.kind == .unmatchedDollar && $0.requiresChoice
        })
        XCTAssertThrowsError(try FlashcardMathFormatter.formatForAnki(unmatched))
        XCTAssertEqual(
            try FlashcardMathFormatter.formatForAnki(unmatched, interpretations: [unmatched: .treatAsMath]),
            #"\(x + 1\)"#
        )

        let unmatchedCard = Flashcard(front: unmatched, back: "Answer", verdict: .good)
        XCTAssertThrowsError(try CardExport.ankiText(session: FlashcardSession(title: "Unmatched", cards: [unmatchedCard])))
        var resolvedUnmatched = FlashcardSession(title: "Unmatched", cards: [unmatchedCard])
        resolvedUnmatched.cards[0].mathInterpretations[unmatched] = .treatAsMath
        XCTAssertTrue(try CardExport.ankiText(session: resolvedUnmatched).contains(#"\(x + 1\)"#))
    }

    func testAnkiFieldsEscapeTabsNewlinesQuotesHTMLAndUnicode() throws {
        let front = "Q\t\"é\" <tag> &"
        let back = "line 1\nline \"2\" <β> &"
        let card = Flashcard(front: front, back: back, verdict: .good)
        let anki = try CardExport.ankiText(session: FlashcardSession(title: "Fields", cards: [card]))

        XCTAssertTrue(anki.contains("#columns:Front\tBack"))
        XCTAssertTrue(anki.contains("\"Q\t\"\"é\"\" &lt;tag&gt; &amp;\""))
        XCTAssertTrue(anki.contains("\"line 1<br>line \"\"2\"\" &lt;β&gt; &amp;\""))
    }

    func testApprovedInterchangePreservesSeparatorBoundaryWhitespace() throws {
        let card = Flashcard(front: " front ", back: "\tanswer\t", verdict: .good)
        let session = FlashcardSession(title: "Padding", cards: [card])

        let interchange = try CardExport.approvedText(session: session)
        let report = DeckParser.parse(interchange)
        XCTAssertEqual(report.cards.count, 1)
        XCTAssertEqual(report.cards[0].front, card.front)
        XCTAssertEqual(report.cards[0].back, card.back)
    }

    func testParserBackupRoundTripPersistsChoicesWarningsAndSelection() throws {
        let report = DeckParser.parse("Q == A\nQ == A\nOther == B")
        XCTAssertEqual(report.cards.count, 3)
        XCTAssertTrue(report.warnings.contains { $0.kind == .exactDuplicate })
        let parsedCardIDs = Set(report.cards.map(\.id))
        XCTAssertTrue(report.warnings.allSatisfy { Set($0.cardIDs).isSubset(of: parsedCardIDs) })
        let selectedID = report.cards[0].id
        var selectedCard = report.cards[0]
        selectedCard.mathInterpretations = [
            #"$hello world$"#: .keepAsText,
            #"$x + 1$"#: .treatAsMath
        ]
        var cards = report.cards
        cards[0] = selectedCard
        let session = FlashcardSession(
            title: "Backed up",
            cards: cards,
            importWarnings: report.warnings,
            selectedCardID: selectedID,
            reviewFilter: "needsAdjustment"
        )

        let restored = try SessionBackup.decode(SessionBackup.encode(session))
        XCTAssertEqual(restored.cards[0].mathInterpretations, selectedCard.mathInterpretations)
        XCTAssertEqual(restored.title, session.title)
        XCTAssertEqual(restored.importWarnings, report.warnings)
        XCTAssertEqual(restored.selectedCardID, selectedID)
        XCTAssertEqual(restored.reviewFilter, "needsAdjustment")
    }

    func testOlderBackupsDefaultNewMathAndImportMetadataFields() throws {
        let card = Flashcard(front: "Q", back: "A")
        let session = FlashcardSession(title: "Older", cards: [card])
        let data = try SessionBackup.encode(session)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var sessionObject = try XCTUnwrap(root["session"] as? [String: Any])
        sessionObject.removeValue(forKey: "importWarnings")
        var cards = try XCTUnwrap(sessionObject["cards"] as? [[String: Any]])
        cards[0].removeValue(forKey: "mathInterpretations")
        sessionObject["cards"] = cards
        root["session"] = sessionObject

        let legacyData = try JSONSerialization.data(withJSONObject: root)
        let restored = try SessionBackup.decode(legacyData)
        XCTAssertEqual(restored.cards[0].mathInterpretations, [:])
        XCTAssertEqual(restored.importWarnings, [])
    }

    func testBackupsIgnoreRemovedBatchLabelAndOmitItOnExport() throws {
        let session = FlashcardSession(
            title: "Existing session",
            cards: [Flashcard(front: "Q", back: "A")],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: SessionBackup.encode(session)) as? [String: Any])
        var sessionObject = try XCTUnwrap(root["session"] as? [String: Any])
        sessionObject["batchLabel"] = "Legacy source"
        root["session"] = sessionObject

        let restored = try SessionBackup.decode(JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(restored, session)
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: SessionBackup.encode(restored)) as? [String: Any])
        let exportedSession = try XCTUnwrap(exported["session"] as? [String: Any])
        XCTAssertNil(exportedSession["batchLabel"])
    }

    func testDedicatedAnkiFixtureCoversEscapingAndMathExport() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AnkiImportFixture.txt")
        let source = try String(contentsOf: fixtureURL, encoding: .utf8)
        var report = DeckParser.parse(source)
        XCTAssertEqual(report.cards.count, 8)
        XCTAssertEqual(report.needsFixingCount, 0)
        XCTAssertTrue(report.warnings.isEmpty)

        for index in report.cards.indices { report.cards[index].verdict = .good }
        let session = FlashcardSession(title: "Anki fixture", cards: report.cards)
        let anki = try CardExport.ankiText(session: session)
        XCTAssertTrue(anki.contains("Café 漢字"))
        XCTAssertTrue(anki.contains("&lt;tag&gt; &amp; attr"))
        XCTAssertTrue(anki.contains(#"\(x^2 + y^2\)"#))
        XCTAssertTrue(anki.contains(#"\[\frac{a}{b}\]"#))
        XCTAssertTrue(anki.contains("<br>"))
        XCTAssertTrue(anki.contains("$5 and $10"))
    }

    func testFortyEntriesRetainOrderAndAccountForBlanksDuplicatesAndIssues() throws {
        let ordinary = (1...40).map { "Question \($0) == Answer \($0)" }.joined(separator: "\n")
        let source = ordinary + "\n\nQuestion 1 == Answer 1\nmalformed entry\nEmpty front == \n"
        let report = DeckParser.parse(source)

        XCTAssertEqual(report.cards.count, 43)
        XCTAssertEqual(report.cards.prefix(40).map(\.front), (1...40).map { "Question \($0)" })
        XCTAssertTrue(report.cards.allSatisfy { $0.verdict == .unreviewed })
        XCTAssertEqual(report.validEntryCount, 41)
        XCTAssertEqual(report.needsFixingCount, 2)
        XCTAssertEqual(report.blankLineCount, 1)
        XCTAssertTrue(report.warnings.contains { $0.kind == .exactDuplicate })
        XCTAssertEqual(report.cards[41].issue?.kind, .missingSeparator)
        XCTAssertEqual(report.cards[42].issue?.kind, .emptySide)
    }

    func testAIRevisionBriefIncludesOnlyAdjustmentCardsWithFeedbackInOrder() throws {
        let good = Flashcard(front: "Good front", back: "Good back", verdict: .good)
        let unreviewed = Flashcard(front: "Unreviewed front", back: "Unreviewed back")
        let adjustment = Flashcard(front: "Revised front", back: "Revised back", originalFront: "Old front", verdict: .needsAdjustment, notes: "Keep the definition concise")
        let rejected = Flashcard(front: "Reject without replacement", back: "Rejected answer", verdict: .bad)
        let replacement = Flashcard(front: "Replacement topic", back: "Old answer", verdict: .bad, notes: "Use a better example", replacementRequested: true)
        let secondAdjustment = Flashcard(front: "Second adjustment", back: "Second answer", verdict: .needsAdjustment)
        let session = FlashcardSession(
            title: "Complete deck",
            cards: [good, unreviewed, adjustment, rejected, replacement, secondAdjustment]
        )

        let brief = try CardExport.aiRevisionBrief(session: session)
        for required in [
            "Old front", "Revised front", "Keep the definition concise",
            "Second adjustment", "Second answer",
            "Complete deck", "Return only the revised cards", "separate session"
        ] {
            XCTAssertTrue(brief.localizedCaseInsensitiveContains(required), "Missing AI context: \(required)")
        }
        for excluded in [
            "Good front", "Good back", "Unreviewed front", "Unreviewed back",
            "Reject without replacement", "Rejected answer", "Replacement topic", "Old answer",
            "Use a better example", "replacementRequested"
        ] {
            XCTAssertFalse(brief.contains(excluded), "Unexpected AI context: \(excluded)")
        }
        let json = try XCTUnwrap(brief.components(separatedBy: "Card data:\n").last)
        let context = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(context["sessionTitle"] as? String, session.title)
        XCTAssertNil(context["batchLabel"])
        let cards = try XCTUnwrap(context["cards"] as? [[String: Any]])
        XCTAssertEqual(cards.compactMap { $0["id"] as? String }, [adjustment.id.uuidString, secondAdjustment.id.uuidString])
        let manualChange = try XCTUnwrap(cards.first?["manualFrontChange"] as? [String: String])
        XCTAssertEqual(manualChange, ["before": "Old front", "after": "Revised front"])
    }

    func testAIRevisionBriefHasNoCardsWhenNoneNeedAdjustment() throws {
        let session = FlashcardSession(title: "No revision needed", cards: [
            Flashcard(front: "Good", back: "Answer", verdict: .good),
            Flashcard(front: "Unreviewed", back: "Answer"),
            Flashcard(front: "Rejected", back: "Answer", verdict: .bad),
            Flashcard(front: "Replacement", back: "Answer", verdict: .bad, replacementRequested: true)
        ])
        let brief = try CardExport.aiRevisionBrief(session: session)
        let json = try XCTUnwrap(brief.components(separatedBy: "Card data:\n").last)
        let context = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let cards = try XCTUnwrap(context["cards"] as? [[String: Any]])
        XCTAssertTrue(cards.isEmpty)
    }
}
