import AppKit
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    let sessionID: UUID

    @State private var showOriginal = false
    @State private var replacementFlow = false
    @FocusState private var focusedEditor: EditorField?

    private enum EditorField: Hashable {
        case front
        case back
        case notes
    }

    private var session: FlashcardSession? {
        guard model.activeSession?.id == sessionID else { return nil }
        return model.activeSession
    }

    private var cardNumber: Int? {
        guard let card = model.activeCard, let session else { return nil }
        return session.cards.firstIndex(where: { $0.id == card.id }).map { $0 + 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if case .failed(let message) = model.saveState, let session {
                saveFailureBanner(message, session: session)
            }
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 258)
                Rectangle()
                    .fill(ReviewerPalette.line)
                    .frame(width: 1)
                detailPane
            }
            actionBar
        }
        .background(ReviewerPalette.canvas)
        .background {
            ReviewShortcutMonitor { event in handleShortcut(event) }
                .frame(width: 0, height: 0)
        }
        .onChange(of: focusedEditor) { oldValue, newValue in
            guard let card = model.activeCard else { return }
            if oldValue == .front || oldValue == .back { model.endEditGroup(for: card.id) }
            if newValue == .front || newValue == .back { model.beginEditGroup(for: card.id) }
        }
        .onChange(of: model.selectedCardID) { _, _ in
            replacementFlow = false
            showOriginal = false
            focusedEditor = nil
        }
        .sheet(isPresented: $model.showShortcuts) {
            shortcutsSheet
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            headerNavigation
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if let session {
                ProgressStrip(
                    good: session.cards.filter { $0.verdict == .good }.count,
                    adjustment: session.cards.filter { $0.verdict == .needsAdjustment }.count,
                    bad: session.cards.filter { $0.verdict == .bad }.count,
                    unreviewed: session.cards.filter { $0.verdict == .unreviewed }.count
                )
                .frame(width: 190)
            }

            headerActions
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(ReviewerPalette.surface)
        .overlay(alignment: .bottom) { ReviewerPalette.line.frame(height: 1) }
    }

    private var headerNavigation: some View {
        HStack(spacing: 18) {
            Button { model.returnToLibrary() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Sessions")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ReviewerPalette.muted)

            VStack(alignment: .leading, spacing: 2) {
                Text(session?.title ?? "Review")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ReviewerPalette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let session {
                    Text("\(session.cards.count) cards · \(model.reviewedCount) reviewed")
                        .font(.system(size: 11))
                        .foregroundStyle(ReviewerPalette.muted)
                }
            }
            .frame(maxWidth: 250, alignment: .leading)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 12) {
            saveStatus
            Button {
                focusedEditor = nil
                model.finishAnyEditGroups()
                model.showAddCards = true
            } label: {
                Label("Add cards", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            Button("Export") { model.showExport = true }
                .buttonStyle(.borderedProminent)
                .tint(ReviewerPalette.ink)
            Button { model.showShortcuts = true } label: {
                Image(systemName: "keyboard")
            }
            .buttonStyle(.plain)
            .foregroundStyle(ReviewerPalette.muted)
            .help("Keyboard shortcuts")
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch model.saveState {
        case .saved:
            Label("Saved on this Mac", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ReviewerPalette.green)
        case .saving:
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ReviewerPalette.muted)
        case .failed:
            Label("Not saved", systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ReviewerPalette.red)
        }
    }

    private func saveFailureBanner(_ message: String, session: FlashcardSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ReviewerPalette.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Changes aren't saved on this Mac.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ReviewerPalette.ink)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(ReviewerPalette.muted)
                    .lineLimit(2)
            }
            Spacer()
            Button("Retry") { model.retrySave() }
                .buttonStyle(.bordered)
            Button("Download backup") { model.downloadBackup(for: session) }
                .buttonStyle(.borderedProminent)
                .tint(ReviewerPalette.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(ReviewerPalette.redWash)
        .overlay(alignment: .bottom) { ReviewerPalette.line.frame(height: 1) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("FILTERS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(ReviewerPalette.muted)
                ForEach(ReviewFilter.allCases) { filter in
                    filterRow(filter)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 17)
            .padding(.bottom, 14)

            Rectangle().fill(ReviewerPalette.line).frame(height: 1)

            HStack {
                Text("CARDS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(ReviewerPalette.muted)
                Spacer()
                Text("\(model.visibleCards.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ReviewerPalette.muted)
            }
            .padding(.horizontal, 15)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if !model.selectedCopyCardIDs.isEmpty {
                HStack {
                    Text("\(model.selectedCopyCardIDs.count) selected · ⌘C to copy")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ReviewerPalette.ink)
                    Spacer()
                    Button("Clear") { model.clearCopySelection() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .help("Clear card selection")
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(model.visibleCards.enumerated()), id: \.element.id) { index, card in
                            cardRow(card, number: index + 1)
                                .id(card.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .task(id: sessionID) {
                    // The lazy list's scroll view is not ready in the first appearance pass.
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        return
                    }
                    if let id = model.selectedCardID { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: model.selectedCardID) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .background(ReviewerPalette.canvas)
    }

    private func filterRow(_ filter: ReviewFilter) -> some View {
        let selected = model.filter == filter
        return Button { model.selectFilter(filter) } label: {
            HStack(spacing: 9) {
                Image(systemName: filterSymbol(filter))
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                    .foregroundStyle(selected ? ReviewerPalette.ink : ReviewerPalette.muted)
                Text(filter.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(ReviewerPalette.ink)
                Spacer()
                Text("\(count(for: filter))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ReviewerPalette.muted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(selected ? ReviewerPalette.grayWash : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func cardRow(_ card: Flashcard, number: Int) -> some View {
        let selected = model.selectedCardID == card.id
        let selectedForCopy = model.selectedCopyCardIDs.contains(card.id)
        let warning = session?.importWarnings.contains(where: { $0.cardIDs.contains(card.id) }) == true
        return Button { model.selectCard(card.id) } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ReviewerPalette.muted)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.front.isEmpty ? "Untitled card" : card.front.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(ReviewerPalette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Image(systemName: card.verdict.symbol)
                            .foregroundStyle(card.verdict.color)
                        if card.issue != nil {
                            Text("Import issue").foregroundStyle(ReviewerPalette.amber)
                        } else if warning {
                            Text("Duplicate warning").foregroundStyle(ReviewerPalette.muted)
                        } else if card.front != card.originalFront || card.back != card.originalBack {
                            Text("Edited").foregroundStyle(ReviewerPalette.muted)
                        } else {
                            Text(card.verdict.label).foregroundStyle(card.verdict.color)
                        }
                    }
                    .font(.system(size: 9, weight: .medium))
                }
                Spacer(minLength: 0)
                if selectedForCopy {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ReviewerPalette.green)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? ReviewerPalette.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                if selected { RoundedRectangle(cornerRadius: 1).fill(ReviewerPalette.ink).frame(width: 2).padding(.vertical, 5) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Card \(number), \(card.verdict.label)\(card.issue == nil ? "" : ", import issue")")
        .accessibilityValue(selectedForCopy ? "Selected for copying" : "Not selected for copying")
        .accessibilityAddTraits(selectedForCopy ? .isSelected : [])
        .help("Click to focus, then press Space to select or deselect for copying")
    }

    private var detailPane: some View {
        Group {
            if let card = model.activeCard {
                cardDetail(card)
            } else {
                endOfList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ReviewerPalette.canvas)
    }

    private func cardDetail(_ card: Flashcard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CARD \(cardNumber.map { String(format: "%02d", $0) } ?? "—") · \(session?.title ?? "Study session")")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(ReviewerPalette.muted)
                        Text(card.issue == nil ? "Read both sides, then choose a verdict." : "Resolve the import split or keep this card flagged.")
                            .font(.system(size: 13))
                            .foregroundStyle(ReviewerPalette.muted)
                    }
                    Spacer()
                    VerdictBadge(verdict: card.verdict)
                }

                if let issue = card.issue {
                    issueBanner(card, issue: issue)
                }

                sideEditor(
                    title: "FRONT",
                    text: card.front,
                    field: .front,
                    card: card,
                    binding: Binding(
                        get: { model.activeCard?.front ?? card.front },
                        set: { model.updateFront(card.id, text: $0) }
                    )
                )

                sideEditor(
                    title: "BACK",
                    text: card.back,
                    field: .back,
                    card: card,
                    binding: Binding(
                        get: { model.activeCard?.back ?? card.back },
                        set: { model.updateBack(card.id, text: $0) }
                    )
                )

                if showOriginal {
                    originalsCard(card)
                }

                feedbackCard(card)

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { showOriginal.toggle() }
                    } label: {
                        Label(showOriginal ? "Hide original" : "Show original / changes", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ReviewerPalette.muted)
                    .font(.system(size: 11, weight: .medium))

                    if card.front != card.originalFront || card.back != card.originalBack {
                        Button("Restore original") { model.restoreOriginalText() }
                            .buttonStyle(.plain)
                            .foregroundStyle(ReviewerPalette.amber)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Spacer()
                    Button("Mark unreviewed") { model.clearVerdict() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(ReviewerPalette.muted)
                        .disabled(card.verdict == .unreviewed)
                }
            }
            .padding(22)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func sideEditor(
        title: String,
        text: String,
        field: EditorField,
        card: Flashcard,
        binding: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(ReviewerPalette.muted)
                Spacer()
                Text(field == .front ? "E edits front" : "R edits back")
                    .font(.system(size: 10))
                    .foregroundStyle(ReviewerPalette.muted)
            }
            TextEditor(text: binding)
                .font(.system(size: 18, weight: .regular))
                .lineSpacing(5)
                .foregroundStyle(ReviewerPalette.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: field == .front ? 78 : 100)
                .background(ReviewerPalette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReviewerPalette.line, lineWidth: 1))
                .focused($focusedEditor, equals: field)
                .accessibilityLabel(field == .front ? "Card front" : "Card back")
                .overlay(alignment: .bottomTrailing) {
                    Text("\(text.count) chars")
                        .font(.system(size: 9))
                        .foregroundStyle(ReviewerPalette.muted.opacity(0.75))
                        .padding(8)
                        .allowsHitTesting(false)
                }

            MathPreviewView(text: text)
            ambiguousMathChoices(text: text, card: card, side: field == .front ? .front : .back)
        }
    }

    @ViewBuilder
    private func ambiguousMathChoices(text: String, card: Flashcard, side: FlashcardSide) -> some View {
        let choices = FlashcardMathAnalyzer.analyze(text).filter(\.requiresChoice)
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Label("Choose how ambiguous dollar text should export", systemImage: "function")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ReviewerPalette.amber)
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    HStack(spacing: 8) {
                        Text(choice.source)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        mathChoiceButton("Treat as math", value: .treatAsMath, card: card, span: choice.source)
                        mathChoiceButton("Keep as text", value: .keepAsText, card: card, span: choice.source)
                    }
                }
            }
            .padding(11)
            .background(ReviewerPalette.amberWash.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func mathChoiceButton(_ title: String, value: MathInterpretation, card: Flashcard, span: String) -> some View {
        let selected = card.mathInterpretations[span] == value
        return Button(title) { model.setMathInterpretation(card.id, span: span, interpretation: value) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(selected ? ReviewerPalette.green : ReviewerPalette.muted)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func issueBanner(_ card: Flashcard, issue: FlashcardImportIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ReviewerPalette.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import issue · line \(card.sourceLineNumber ?? 0)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ReviewerPalette.ink)
                    Text(issue.message)
                        .font(.system(size: 11))
                        .foregroundStyle(ReviewerPalette.muted)
                }
                Spacer()
            }
            Text(card.rawImportLine)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ReviewerPalette.surface, in: RoundedRectangle(cornerRadius: 6))
            if issue.kind == .ambiguousSplit {
                Text("Choose the separator that divides front from back:")
                    .font(.system(size: 11, weight: .medium))
                HStack {
                    ForEach(Array(issue.delimiterUTF16Offsets.enumerated()), id: \.offset) { index, offset in
                        Button("Split at separator \(index + 1)") {
                            model.resolveImportSplit(cardID: card.id, atUTF16Offset: offset)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            Text("Good is disabled until this issue is resolved. Bad and Needs adjustment remain available.")
                .font(.system(size: 10))
                .foregroundStyle(ReviewerPalette.muted)
        }
        .padding(13)
        .background(ReviewerPalette.amberWash, in: RoundedRectangle(cornerRadius: 10))
    }

    private func originalsCard(_ card: Flashcard) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 11) {
                Text("ORIGINAL TEXT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(ReviewerPalette.muted)
                originalSide(title: "Front", original: card.originalFront, current: card.front)
                originalSide(title: "Back", original: card.originalBack, current: card.back)
            }
        }
    }

    private func originalSide(title: String, original: String, current: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(ReviewerPalette.muted)
            Text(original.isEmpty ? "(empty)" : original)
                .font(.system(size: 12))
                .foregroundStyle(ReviewerPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if original != current {
                Label("Edited", systemImage: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ReviewerPalette.amber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(ReviewerPalette.canvas, in: RoundedRectangle(cornerRadius: 7))
    }

    private func feedbackCard(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("FEEDBACK FOR AI")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(ReviewerPalette.muted)
            }
            TextEditor(text: Binding(
                get: { model.activeCard?.notes ?? card.notes },
                set: { model.updateNotes(card.id, text: $0) }
            ))
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 62, maxHeight: 94)
            .background(ReviewerPalette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ReviewerPalette.line, lineWidth: 1))
            .focused($focusedEditor, equals: .notes)
            .accessibilityLabel("Adjustment notes and AI feedback")
            Text("Notes save automatically. Press Esc to leave the textbox, then ↓ or → for the next card.")
                .font(.system(size: 10))
                .foregroundStyle(ReviewerPalette.muted)
        }
        .padding(13)
        .background(ReviewerPalette.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReviewerPalette.line, lineWidth: 1))
    }

    private var actionBar: some View {
        HStack(spacing: 9) {
            Button { model.moveSelection(by: -1) } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(model.visibleCards.isEmpty)
            .help("Previous card · ← or ↑")

            Spacer(minLength: 8)

            Button { model.markGood() } label: {
                Label("Good", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(ReviewerPalette.green)
            .disabled(model.activeCard?.canBeApproved != true)
            .help("Mark Good and move to the next card · 1")

            if replacementFlow {
                Button("Save rejection") {
                    model.commitBadWithFeedback(
                        note: model.activeCard?.notes ?? "",
                        replacementRequested: model.activeCard?.replacementRequested ?? false
                    )
                    replacementFlow = false
                }
                .buttonStyle(.borderedProminent)
                .tint(ReviewerPalette.red)
            } else {
                Button { model.markBad() } label: {
                    Label("Bad", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .tint(ReviewerPalette.red)
                .help("Mark Bad and move to the next card · 2")
            }

            Button { markNeedsAdjustment() } label: {
                Label("Needs adjustment", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .tint(ReviewerPalette.amber)
            .disabled(model.activeCard == nil)
            .help("Mark Needs adjustment and focus feedback notes · 3")

            Spacer(minLength: 8)

            Button { model.moveSelection(by: 1) } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .disabled(model.visibleCards.isEmpty)
            .help("Next card · → or ↓")

            Button { model.undo() } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canUndo)
            .help("Undo last card action · U")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(ReviewerPalette.surface)
        .overlay(alignment: .top) { ReviewerPalette.line.frame(height: 1) }
    }

    private var endOfList: some View {
        VStack(spacing: 13) {
            Image(systemName: model.visibleCards.isEmpty ? "line.3.horizontal.decrease.circle" : "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(model.visibleCards.isEmpty ? ReviewerPalette.muted : ReviewerPalette.green)
            Text(endHeading)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(ReviewerPalette.ink)
            Text(endSubheading)
                .font(.system(size: 13))
                .foregroundStyle(ReviewerPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            if model.isSessionComplete {
                HStack(spacing: 12) {
                    countSummary("Good", count: model.count(for: .good), color: ReviewerPalette.green)
                    countSummary("Needs adjustment", count: model.count(for: .needsAdjustment), color: ReviewerPalette.amber)
                    countSummary("Bad", count: model.count(for: .bad), color: ReviewerPalette.red)
                }
                .padding(.vertical, 6)
                Button("Export this session") { model.showExport = true }
                    .buttonStyle(.borderedProminent)
                    .tint(ReviewerPalette.ink)
            }
            if !model.visibleCards.isEmpty {
                Button("Review this list from the beginning") { model.restartCurrentList() }
                    .buttonStyle(.bordered)
            }
            if model.visibleCards.isEmpty {
                Button("Show all cards") { model.selectFilter(.all) }
                    .buttonStyle(.bordered)
            }
            if let session, !model.isSessionComplete, model.visibleCards.isEmpty,
               session.cards.contains(where: { $0.verdict == .unreviewed }) {
                Button("Review unreviewed cards") { model.selectFilter(.unreviewed) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var endHeading: String {
        if model.visibleCards.isEmpty { return "No cards in this filter" }
        return model.isSessionComplete ? "All cards reviewed" : "End of this list"
    }

    private var endSubheading: String {
        if model.visibleCards.isEmpty {
            return "Choose another filter to keep reviewing this session. Your cards and their verdicts are unchanged."
        }
        if model.isSessionComplete {
            return "Every card has a saved verdict. Good, Needs adjustment, and Bad are all represented in this total."
        }
        return "You've reached the end of this filter. Nothing wraps automatically; go back or restart the list when you're ready."
    }

    private func countSummary(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(ReviewerPalette.muted)
        }
        .padding(.horizontal, 10)
    }

    private var shortcutsSheet: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                PageHeading(title: "Keyboard shortcuts")
                Spacer()
                Button { model.showShortcuts = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            shortcutRow("1", "Mark Good and advance")
            shortcutRow("2", "Mark Bad and advance")
            shortcutRow("3", "Mark Needs adjustment and focus notes")
            shortcutRow("⇧2", "Write rejection feedback")
            shortcutRow("← / ↑", "Previous card")
            shortcutRow("→ / ↓", "Next card")
            shortcutRow("Esc", "Leave the editor; keep saved changes")
            shortcutRow("Space", "Select or deselect the focused card")
            shortcutRow("⌘C", "Copy selected cards, or the focused card")
            shortcutRow("E", "Edit the front")
            shortcutRow("R", "Edit the back")
            shortcutRow("O", "Show or hide original text")
            shortcutRow("U", "Undo the latest card change")
            shortcutRow("?", "Show this help")
            Text("Review shortcuts pause while a text editor is focused, so typing and native undo keep working.")
                .font(.system(size: 11))
                .foregroundStyle(ReviewerPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 470, height: 570)
        .background(ReviewerPalette.canvas)
    }

    private func shortcutRow(_ key: String, _ action: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(ReviewerPalette.ink)
                .frame(width: 60, alignment: .trailing)
            Text(action).font(.system(size: 12)).foregroundStyle(ReviewerPalette.muted)
            Spacer()
        }
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard !model.showExport, !model.showNewSession, !model.showAddCards, !model.showShortcuts,
              !model.isShowingRestoreError, !model.isShowingLibrary else { return false }
        if event.isARepeat { return true }
        if ReviewShortcutMatcher.copiesCards(
            characters: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags
        ) {
            guard !model.cardsToCopy.isEmpty else { return false }
            model.copyReviewCards()
            return true
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if event.keyCode == 36, !modifiers.isEmpty {
            if replacementFlow {
                model.commitBadWithFeedback(
                    note: model.activeCard?.notes ?? "",
                    replacementRequested: model.activeCard?.replacementRequested ?? false
                )
                replacementFlow = false
            } else {
                focusedEditor = nil
            }
            return true
        }
        if event.keyCode == 53 {
            focusedEditor = nil
            replacementFlow = false
            return true
        }
        if event.characters == "?" {
            model.showShortcuts = true
            return true
        }
        guard modifiers.isEmpty else { return false }
        let shiftDown = event.modifierFlags.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if ReviewShortcutMatcher.startsReplacementFlow(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            guard model.activeCard != nil else { return true }
            replacementFlow = true
            focusNotes()
            return true
        }
        if shiftDown { return false }
        if let direction = ReviewShortcutMatcher.navigationDelta(keyCode: event.keyCode) {
            model.moveSelection(by: direction)
            return true
        }
        if event.keyCode == 49 { model.toggleCopySelection(); return true }
        switch key {
        case "1": model.markGood(); return true
        case "2": model.markBad(); return true
        case "3": markNeedsAdjustment(); return true
        case "e": focusedEditor = .front; return true
        case "r": focusedEditor = .back; return true
        case "o": showOriginal.toggle(); return true
        case "u": model.undo(); return true
        default: return false
        }
    }

    private func markNeedsAdjustment() {
        guard model.activeCard != nil else { return }
        replacementFlow = false
        model.markNeedsAdjustment()
        focusNotes()
    }

    private func focusNotes() {
        let cardID = model.selectedCardID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard model.selectedCardID == cardID, model.activeCard != nil else { return }
            focusedEditor = .notes
        }
    }

    private func filterSymbol(_ filter: ReviewFilter) -> String {
        switch filter {
        case .all: "square.grid.2x2"
        case .unreviewed: "circle.dashed"
        case .good: "checkmark.circle"
        case .needsAdjustment: "pencil.circle"
        case .bad: "xmark.circle"
        }
    }

    private func count(for filter: ReviewFilter) -> Int {
        guard let session else { return 0 }
        return session.cards.filter(filter.includes).count
    }
}

enum ReviewShortcutMatcher {
    static func navigationDelta(keyCode: UInt16) -> Int? {
        switch keyCode {
        case 123, 126: -1
        case 124, 125: 1
        default: nil
        }
    }

    static func copiesCards(characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        characters?.lowercased() == "c"
            && modifiers.intersection([.command, .control, .option, .shift]) == .command
    }

    static func startsReplacementFlow(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let disallowedModifiers = modifiers.intersection([.command, .control, .option])
        // Match the physical top-row 2 key so the shortcut works when Shift changes its symbol.
        return keyCode == 19 && modifiers.contains(.shift) && disallowedModifiers.isEmpty
    }
}

private struct ReviewShortcutMonitor: NSViewRepresentable {
    var onKey: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKey = onKey
        context.coordinator.view = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var onKey: (NSEvent) -> Bool
        weak var view: NSView?
        private var monitor: Any?

        init(onKey: @escaping (NSEvent) -> Bool) { self.onKey = onKey }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let view = self.view, event.window === view.window else { return event }
                guard NSApp.modalWindow == nil else { return event }
                let commitsFeedback = event.keyCode == 36
                    && !event.modifierFlags.intersection([.command, .control]).isEmpty
                if event.keyCode == 53 || commitsFeedback {
                    return self.onKey(event) ? nil : event
                }
                if let responder = event.window?.firstResponder,
                   responder is NSTextView || responder is NSTextField || responder is NSSearchField {
                    return event
                }
                return self.onKey(event) ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
