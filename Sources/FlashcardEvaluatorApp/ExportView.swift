import SwiftUI

private enum ExportKind: String, CaseIterable, Identifiable {
    case anki
    case approved
    case aiBrief
    case backup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anki: "Anki import"
        case .approved: "Approved cards"
        case .aiBrief: "AI revision brief"
        case .backup: "Session backup"
        }
    }

    var subtitle: String {
        switch self {
        case .anki: "Good cards as a tab-separated text file."
        case .approved: "Good cards in the re-importable front == back format."
        case .aiBrief: "Only Needs adjustment cards and their feedback."
        case .backup: "Every card, edit, verdict, note, and math choice."
        }
    }

    var symbol: String {
        switch self {
        case .anki: "tablecells"
        case .approved: "checkmark"
        case .aiBrief: "pencil.and.outline"
        case .backup: "shippingbox"
        }
    }
}

private struct MathChoiceItem: Identifiable {
    var cardID: UUID
    var cardNumber: Int
    var side: FlashcardSide
    var span: String

    var id: String { "\(cardID.uuidString)-\(side.rawValue)-\(span)" }
}

private struct MathAdaptation: Identifiable {
    var cardID: UUID
    var cardNumber: Int
    var side: FlashcardSide
    var source: String
    var output: String

    var id: String { "\(cardID.uuidString)-\(side.rawValue)-\(source)" }
}

struct ExportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: FlashcardSession

    @State private var selectedKind: ExportKind = .anki

    private var goodCards: [Flashcard] {
        session.cards.filter { $0.verdict == .good && $0.canBeApproved }
    }

    private var adjustmentCount: Int {
        session.cards.filter { $0.verdict == .needsAdjustment }.count
    }

    private var unreviewedCount: Int {
        session.cards.filter { $0.verdict == .unreviewed }.count
    }

    private var unresolvedMathChoices: [MathChoiceItem] {
        session.cards.enumerated().flatMap { index, card in
            guard card.verdict == .good && card.canBeApproved else { return [] as [MathChoiceItem] }
            return unresolvedChoices(in: card, cardNumber: index + 1)
        }
    }

    private var mathAdaptations: [MathAdaptation] {
        session.cards.enumerated().flatMap { index, card in
            guard card.verdict == .good && card.canBeApproved else { return [] as [MathAdaptation] }
            return adaptations(in: card, cardNumber: index + 1)
        }
    }

    private var includedCount: Int {
        switch selectedKind {
        case .anki, .approved: goodCards.count
        case .aiBrief: adjustmentCount
        case .backup: session.cards.count
        }
    }

    private var excludedCount: Int { max(session.cards.count - includedCount, 0) }

    private var hasNoExportableContent: Bool {
        switch selectedKind {
        case .anki, .approved: goodCards.isEmpty
        case .aiBrief: adjustmentCount == 0
        case .backup: false
        }
    }

    private var isBlockedByMath: Bool {
        selectedKind == .anki && !unresolvedMathChoices.isEmpty
    }

    private var previewText: String? {
        guard !hasNoExportableContent, !isBlockedByMath else { return nil }
        do {
            switch selectedKind {
            case .anki:
                return try CardExport.ankiText(session: session)
            case .approved:
                return try CardExport.approvedText(session: session)
            case .aiBrief:
                return try CardExport.aiRevisionBrief(session: session)
            case .backup:
                return try model.backupJSON(for: session)
            }
        } catch {
            return nil
        }
    }

    private var previewError: String? {
        guard !hasNoExportableContent, !isBlockedByMath else { return nil }
        do {
            switch selectedKind {
            case .anki: _ = try CardExport.ankiText(session: session)
            case .approved: _ = try CardExport.approvedText(session: session)
            case .aiBrief: _ = try CardExport.aiRevisionBrief(session: session)
            case .backup: _ = try model.backupJSON(for: session)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if unreviewedCount > 0 {
                unreviewedBanner
            }

            HStack(alignment: .top, spacing: 20) {
                exportPicker
                    .frame(width: 245)

                exportDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(26)
        .frame(minWidth: 920, idealWidth: 1200, maxWidth: 1480, minHeight: 640, idealHeight: 820, maxHeight: 1100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ReviewerPalette.canvas)
    }

    private var header: some View {
        HStack(alignment: .top) {
            PageHeading(title: "Export", subtitle: "Nothing leaves this Mac unless you copy or save it.")
            Spacer()
            Button {
                dismiss()
            } label: {
                Label("Back to review", systemImage: "arrow.uturn.backward")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Back to review")
        }
    }

    private var unreviewedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(ReviewerPalette.amber)
            Text("\(unreviewedCount) \(pluralized(unreviewedCount, singular: "card")) \(unreviewedCount == 1 ? "is" : "are") unreviewed.")
                .fontWeight(.semibold)
            Text("Only the session backup includes them.")
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(ReviewerPalette.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ReviewerPalette.amberWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var exportPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ExportKind.allCases) { kind in
                exportOption(kind)
            }

            Spacer(minLength: 12)

            Text("Have a backup?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ReviewerPalette.muted)
            Text("Restore it from the sessions screen. Restored backups create a separate session.")
                .font(.system(size: 12))
                .foregroundStyle(ReviewerPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func exportOption(_ kind: ExportKind) -> some View {
        let isSelected = selectedKind == kind
        return Button {
            selectedKind = kind
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(isSelected ? ReviewerPalette.ink : ReviewerPalette.grayWash, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(isSelected ? ReviewerPalette.surface : ReviewerPalette.muted)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(kind.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ReviewerPalette.ink)
                        Spacer(minLength: 6)
                        Text("\(tabCount(for: kind))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(ReviewerPalette.muted)
                    }
                    Text(kind.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(ReviewerPalette.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ReviewerPalette.surface : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? ReviewerPalette.line : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var exportDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            Divider().overlay(ReviewerPalette.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    countSummary

                    if selectedKind == .anki {
                        ankiGuidance
                        if !unresolvedMathChoices.isEmpty { unresolvedMathPanel }
                        if unresolvedMathChoices.isEmpty && !mathAdaptations.isEmpty { mathAdaptationPanel }
                        if unresolvedMathChoices.isEmpty, let fields = firstAnkiFields {
                            ankiFieldPreview(fields)
                        }
                    } else if selectedKind == .aiBrief {
                        aiBriefGuidance
                    }

                    if hasNoExportableContent {
                        emptyExportState
                    } else if isBlockedByMath {
                        mathBlockedState
                    } else if let previewText {
                        exactPreview(previewText)
                    } else if let previewError {
                        exportErrorState(previewError)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id("\(session.id.uuidString)-\(selectedKind.rawValue)")
            .frame(maxHeight: .infinity)

            Divider().overlay(ReviewerPalette.line)
            actionBar
        }
        .background(ReviewerPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReviewerPalette.line.opacity(0.8), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedKind.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ReviewerPalette.ink)
                Text(detailDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(ReviewerPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(downloadButtonTitle) { downloadSelectedExport() }
                .buttonStyle(.bordered)
                .disabled(!canExport)
            Button(copyButtonTitle) { copySelectedExport() }
                .buttonStyle(.borderedProminent)
                .tint(ReviewerPalette.ink)
                .disabled(!canExport)
                .keyboardShortcut("c", modifiers: [.command])
                .accessibilityLabel(copyButtonTitle)
        }
        .padding(18)
    }

    private var detailDescription: String {
        switch selectedKind {
        case .anki:
            "UTF-8 text with Front and Back fields. Choose the destination deck in Anki."
        case .approved:
            "The latest text of every Good card, in the front == back interchange format."
        case .aiBrief:
            "A revision prompt with current text and feedback for Needs adjustment cards only."
        case .backup:
            "A versioned JSON copy of this session, including cards that are not reviewed."
        }
    }

    private var countSummary: some View {
        HStack(spacing: 10) {
            countPill(title: selectedKind == .aiBrief ? "To revise" : "Included", value: includedCount, color: ReviewerPalette.green)
            countPill(title: "Excluded", value: excludedCount, color: ReviewerPalette.muted)
            Spacer(minLength: 0)
        }
    }

    private func countPill(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ReviewerPalette.muted)
        }
        .frame(minWidth: 104, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(ReviewerPalette.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var ankiGuidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("In Anki, choose File → Import, select this file, map Front/Back, and choose your deck.", systemImage: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ReviewerPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("No deck is preset. Anki’s duplicate settings affect whether these rows create new notes.")
                .font(.system(size: 11))
                .foregroundStyle(ReviewerPalette.muted)
                .padding(.leading, 21)
        }
        .padding(12)
        .background(ReviewerPalette.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var unresolvedMathPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Resolve math warnings before exporting", systemImage: "function")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ReviewerPalette.amber)
            Text("These spans appear in Good cards. Choose how the Anki file should treat each one. The card text stays unchanged.")
                .font(.system(size: 12))
                .foregroundStyle(ReviewerPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(unresolvedMathChoices) { item in
                mathChoiceRow(item)
            }
        }
        .padding(14)
        .background(ReviewerPalette.amberWash.opacity(0.65), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(ReviewerPalette.amber.opacity(0.25), lineWidth: 1)
        }
    }

    private func mathChoiceRow(_ item: MathChoiceItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Card \(item.cardNumber) · \(item.side.rawValue.capitalized)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ReviewerPalette.muted)
                Text(item.span)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ReviewerPalette.ink)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button("Treat as math") {
                    model.setMathInterpretation(item.cardID, span: item.span, interpretation: .treatAsMath)
                }
                .buttonStyle(.bordered)
                Button("Keep as text") {
                    model.setMathInterpretation(item.cardID, span: item.span, interpretation: .keepAsText)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var mathAdaptationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Math formatting adapted for Anki", systemImage: "function")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ReviewerPalette.green)
            Text("Dollar-wrapped formulas are converted in this Anki file only. The session text and backup keep the original source.")
                .font(.system(size: 12))
                .foregroundStyle(ReviewerPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(mathAdaptations.prefix(3)) { example in
                VStack(alignment: .leading, spacing: 5) {
                    Text("Card \(example.cardNumber) · \(example.side.rawValue.capitalized)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ReviewerPalette.muted)
                    HStack(alignment: .top, spacing: 7) {
                        Text(example.source)
                            .foregroundStyle(ReviewerPalette.ink)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(ReviewerPalette.green)
                        Text(example.output)
                            .foregroundStyle(ReviewerPalette.green)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ReviewerPalette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if mathAdaptations.count > 3 {
                Text("And \(mathAdaptations.count - 3) more converted formulas.")
                    .font(.system(size: 11))
                    .foregroundStyle(ReviewerPalette.muted)
            }
        }
        .padding(14)
        .background(ReviewerPalette.greenWash.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func ankiFieldPreview(_ fields: (front: String, back: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("First approved card · Anki fields")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ReviewerPalette.ink)
            HStack(alignment: .top, spacing: 10) {
                previewField(title: "FRONT", text: fields.front)
                previewField(title: "BACK", text: fields.back)
            }
        }
    }

    private func previewField(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ReviewerPalette.muted)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ReviewerPalette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReviewerPalette.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var aiBriefGuidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Only Needs adjustment cards are included", systemImage: "pencil.and.outline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ReviewerPalette.ink)
            Text("The AI receives their original text, current edits, and notes, and returns only revised cards. Good, Unreviewed, and Bad cards are excluded, including Bad cards with a replacement request.")
                .font(.system(size: 11))
                .foregroundStyle(ReviewerPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(ReviewerPalette.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var emptyExportState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(emptyTitle, systemImage: "tray")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ReviewerPalette.ink)
            Text(emptyExplanation)
                .font(.system(size: 12))
                .foregroundStyle(ReviewerPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReviewerPalette.grayWash.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var mathBlockedState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Anki export is paused", systemImage: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ReviewerPalette.amber)
            Text("Resolve all \(unresolvedMathChoices.count) listed \(pluralized(unresolvedMathChoices.count, singular: "choice")) to preview, copy, or save the Anki file.")
                .font(.system(size: 12))
                .foregroundStyle(ReviewerPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReviewerPalette.amberWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func exportErrorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Could not prepare this export", systemImage: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ReviewerPalette.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(ReviewerPalette.muted)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReviewerPalette.redWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func exactPreview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Exact file preview")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ReviewerPalette.ink)
                Spacer()
                Text(fileTypeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ReviewerPalette.muted)
            }
            ScrollView(.vertical) {
                Text(verbatim: text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ReviewerPalette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 175, maxHeight: 390)
            .background(ReviewerPalette.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ReviewerPalette.line.opacity(0.65), lineWidth: 1)
            }
            if let previewError {
                Text(previewError)
                    .font(.system(size: 11))
                    .foregroundStyle(ReviewerPalette.red)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            if selectedKind == .anki {
                Text("\(goodCards.count) \(pluralized(goodCards.count, singular: "row")) in this file")
                    .font(.system(size: 11))
                    .foregroundStyle(ReviewerPalette.muted)
            } else if selectedKind == .aiBrief {
                Text("\(adjustmentCount) to revise · \(excludedCount) excluded")
                    .font(.system(size: 11))
                    .foregroundStyle(ReviewerPalette.muted)
            } else {
                Text("\(includedCount) \(pluralized(includedCount, singular: "card")) included")
                    .font(.system(size: 11))
                    .foregroundStyle(ReviewerPalette.muted)
            }
            Spacer()
        }
        .padding(14)
    }

    private var canExport: Bool {
        !hasNoExportableContent && !isBlockedByMath && previewText != nil
    }

    private var emptyTitle: String {
        switch selectedKind {
        case .anki: "No approved cards to import"
        case .approved: "No approved cards to copy"
        case .aiBrief: "No cards need AI work"
        case .backup: "This session has no cards"
        }
    }

    private var emptyExplanation: String {
        switch selectedKind {
        case .anki: "Mark at least one valid card Good. Only Good cards appear in the Anki file."
        case .approved: "Mark at least one valid card Good to create an approved-card text file."
        case .aiBrief: "Mark a card Needs adjustment to include it in the AI brief. Good, Unreviewed, and Bad cards are excluded."
        case .backup: "The backup includes this session and its current review state."
        }
    }

    private var downloadButtonTitle: String {
        switch selectedKind {
        case .anki: "Download .txt"
        case .approved: "Download .txt"
        case .aiBrief: "Download .md"
        case .backup: "Download backup"
        }
    }

    private var copyButtonTitle: String {
        switch selectedKind {
        case .anki: "Copy"
        case .approved: "Copy cards"
        case .aiBrief: "Copy brief"
        case .backup: "Copy JSON"
        }
    }

    private var fileTypeLabel: String {
        switch selectedKind {
        case .anki: "UTF-8 · TAB SEPARATED · .TXT"
        case .approved: "FRONT == BACK · .TXT"
        case .aiBrief: "MARKDOWN · .MD"
        case .backup: "VERSIONED JSON · .JSON"
        }
    }

    private func tabCount(for kind: ExportKind) -> Int {
        switch kind {
        case .anki, .approved: goodCards.count
        case .aiBrief: adjustmentCount
        case .backup: session.cards.count
        }
    }

    private func downloadSelectedExport() {
        guard let previewText else { return }
        switch selectedKind {
        case .anki:
            model.saveText(previewText, suggestedName: "\(session.title)-anki.txt", fileExtension: "txt")
        case .approved:
            model.saveText(previewText, suggestedName: "\(session.title)-approved.txt", fileExtension: "txt")
        case .aiBrief:
            model.saveText(previewText, suggestedName: "\(session.title)-ai-revision-brief.md", fileExtension: "md")
        case .backup:
            model.downloadBackup(for: session)
        }
    }

    private func copySelectedExport() {
        guard let previewText else { return }
        let message: String
        switch selectedKind {
        case .anki: message = "Anki import copied to clipboard"
        case .approved: message = "Approved cards copied to clipboard"
        case .aiBrief: message = "AI revision brief copied to clipboard"
        case .backup: message = "Session backup JSON copied to clipboard"
        }
        model.copy(previewText, successMessage: message)
    }

    private func unresolvedChoices(in card: Flashcard, cardNumber: Int) -> [MathChoiceItem] {
        var seen = Set<String>()
        var result: [MathChoiceItem] = []
        for (side, text) in [(FlashcardSide.front, card.front), (.back, card.back)] {
            for span in FlashcardMathAnalyzer.analyze(text) where span.requiresChoice {
                guard card.mathInterpretations[span.source] == nil,
                      seen.insert("\(side.rawValue):\(span.source)").inserted else { continue }
                result.append(MathChoiceItem(cardID: card.id, cardNumber: cardNumber, side: side, span: span.source))
            }
        }
        return result
    }

    private func adaptations(in card: Flashcard, cardNumber: Int) -> [MathAdaptation] {
        var result: [MathAdaptation] = []
        for (side, text) in [(FlashcardSide.front, card.front), (.back, card.back)] {
            let spans = FlashcardMathAnalyzer.analyze(text)
            guard spans.contains(where: { $0.kind == .inlineDollar || $0.kind == .displayDollar }),
                  let output = try? FlashcardMathFormatter.formatForAnki(text, interpretations: card.mathInterpretations),
                  output != text else { continue }
            result.append(MathAdaptation(cardID: card.id, cardNumber: cardNumber, side: side, source: text, output: output))
        }
        return result
    }

    private var firstAnkiFields: (front: String, back: String)? {
        guard !goodCards.isEmpty, let text = previewText else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 3 else { return nil }
        return parseAnkiRow(lines[3])
    }

    private func parseAnkiRow(_ row: String) -> (front: String, back: String)? {
        let characters = Array(row)
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                inQuotes.toggle()
            } else if character == "\t", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        fields.append(current)
        guard fields.count == 2 else { return nil }
        return (fields[0], fields[1])
    }

    private func pluralized(_ count: Int, singular: String) -> String {
        count == 1 ? singular : "\(singular)s"
    }
}
