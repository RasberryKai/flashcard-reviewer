import SwiftUI

struct ImportDiagnosticsView: View {
    @Binding var rawText: String
    let report: DeckImportReport
    @State private var editingLineNumber: Int?
    @State private var lineDraft = ""
    @State private var editError: String?

    private var cardsWithIssues: [Flashcard] { report.cards.filter { $0.issue != nil } }

    var body: some View {
        if !cardsWithIssues.isEmpty || !report.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("IMPORT CHECK")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(ReviewerPalette.muted)

                ForEach(cardsWithIssues) { card in
                    issueCard(card)
                }

                ForEach(Array(report.warnings.enumerated()), id: \.offset) { entry in
                    let warning = entry.element
                    SurfaceCard {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(ReviewerPalette.muted)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(warning.kind == .exactDuplicate ? "Duplicate cards" : "Same front, different backs")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ReviewerPalette.ink)
                                Text("\(warning.message) Lines \(warning.sourceLineNumbers.map(String.init).joined(separator: ", ")).")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ReviewerPalette.muted)
                            }
                            Spacer()
                        }
                    }
                }

                if let editError {
                    Text(editError)
                        .font(.system(size: 11))
                        .foregroundStyle(ReviewerPalette.red)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Import issues and duplicate warnings")
        }
    }

    private func issueCard(_ card: Flashcard) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("LINE \(card.sourceLineNumber ?? 0)")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(ReviewerPalette.muted)
                    Text(card.issue?.kind.title ?? "Import issue")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ReviewerPalette.amber)
                    Spacer(minLength: 6)
                    Button(editingLineNumber == card.sourceLineNumber ? "Cancel edit" : "Edit line") {
                        if editingLineNumber == card.sourceLineNumber {
                            editingLineNumber = nil
                            lineDraft = ""
                        } else {
                            editingLineNumber = card.sourceLineNumber
                            lineDraft = card.rawImportLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                }

                Text(card.issue?.message ?? "This entry needs a front/back split.")
                    .font(.system(size: 12))
                    .foregroundStyle(ReviewerPalette.muted)

                Text(card.rawImportLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ReviewerPalette.ink)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(ReviewerPalette.canvas, in: RoundedRectangle(cornerRadius: 6))

                if editingLineNumber == card.sourceLineNumber, let lineNumber = card.sourceLineNumber {
                    TextField("Edit this source line", text: $lineDraft)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveEditedLine(lineNumber) }
                    HStack {
                        Text("The preview updates immediately after saving.")
                            .font(.system(size: 10))
                            .foregroundStyle(ReviewerPalette.muted)
                        Spacer()
                        Button("Save line") { saveEditedLine(lineNumber) }
                            .buttonStyle(.bordered)
                    }
                }

                if card.issue?.kind == .ambiguousSplit, let issue = card.issue, !issue.delimiterUTF16Offsets.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Choose the separator that divides front from back:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ReviewerPalette.ink)
                        ForEach(Array(issue.delimiterUTF16Offsets.enumerated()), id: \.offset) { index, offset in
                            Button {
                                resolveSplit(card, at: offset)
                            } label: {
                                Label("Split at separator \(index + 1)", systemImage: "arrow.left.and.right")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func saveEditedLine(_ lineNumber: Int) {
        replaceLine(lineNumber, with: lineDraft)
        editingLineNumber = nil
        lineDraft = ""
        editError = nil
    }

    private func resolveSplit(_ card: Flashcard, at utf16Offset: Int) {
        let source = card.rawImportLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        let utf16 = source.utf16
        guard utf16Offset >= 0, utf16Offset + 2 <= utf16.count else {
            editError = "Could not apply that separator. Edit the source line instead."
            return
        }
        let start16 = utf16.index(utf16.startIndex, offsetBy: utf16Offset)
        let end16 = utf16.index(start16, offsetBy: 2)
        guard let start = String.Index(start16, within: source), let end = String.Index(end16, within: source) else {
            editError = "Could not apply that separator. Edit the source line instead."
            return
        }
        var front = trimPadding(String(source[..<start]))
        let back = trimPadding(String(source[end...]))
        if card.sourceLineNumber == 1, front.hasPrefix("\u{FEFF}") { front.removeFirst() }
        do {
            let encoder = JSONEncoder()
            guard let frontJSON = String(data: try encoder.encode(front), encoding: .utf8),
                  let backJSON = String(data: try encoder.encode(back), encoding: .utf8),
                  let lineNumber = card.sourceLineNumber else { return }
            replaceLine(lineNumber, with: "\(frontJSON) == \(backJSON)")
            editError = nil
        } catch {
            editError = "Could not encode that split: \(error.localizedDescription)"
        }
    }

    private func replaceLine(_ lineNumber: Int, with replacement: String) {
        var lines = rawText.components(separatedBy: "\n")
        let index = lineNumber - 1
        guard lines.indices.contains(index) else {
            editError = "The source line moved. Reopen the session draft and try again."
            return
        }
        let hadCarriageReturn = lines[index].hasSuffix("\r")
        lines[index] = replacement + (hadCarriageReturn ? "\r" : "")
        rawText = lines.joined(separator: "\n")
    }

    private func trimPadding(_ value: String) -> String {
        var output = value
        while output.first == " " || output.first == "\t" { output.removeFirst() }
        while output.last == " " || output.last == "\t" { output.removeLast() }
        return output
    }
}

private extension FlashcardImportIssue.Kind {
    var title: String {
        switch self {
        case .missingSeparator: "No == separator"
        case .emptySide: "An empty side"
        case .ambiguousSplit: "Multiple == separators"
        case .invalidQuotedSyntax: "Invalid quoted fields"
        }
    }
}
