import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if !model.isShowingLibrary, let session = model.activeSession {
                ReviewView(sessionID: session.id)
            } else {
                SessionLibraryView()
            }
        }
        .background(ReviewerPalette.canvas)
        .disabled(model.showExport)
        .overlay {
            exportOverlay
        }
        .sheet(isPresented: $model.showNewSession) {
            CardImportView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showAddCards) {
            if let session = model.activeSession {
                CardImportView(sessionID: session.id)
                    .environmentObject(model)
            }
        }
        .alert("Could not restore backup", isPresented: $model.isShowingRestoreError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.restoreError ?? "The backup could not be read.")
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(ReviewerPalette.raised, in: Capsule())
                    .foregroundStyle(ReviewerPalette.ink)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
    }

    @ViewBuilder
    private var exportOverlay: some View {
        if model.showExport, let session = model.activeSession {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { model.showExport = false }
                        .accessibilityHidden(true)

                    ExportView(session: session) {
                        model.showExport = false
                    }
                    .environmentObject(model)
                    .frame(
                        width: min(max(geometry.size.width - 48, 920), 1480),
                        height: min(max(geometry.size.height - 48, 640), 1100)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
            .zIndex(10)
        }
    }
}

private struct SessionLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showRestorePicker = false
    @State private var selectedForDeletion: FlashcardSession?
    @State private var renamingSessionID: UUID?
    @State private var titleDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            libraryHeader
            Divider().overlay(ReviewerPalette.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .bottom) {
                        PageHeading(
                            title: "Your sessions",
                            subtitle: "Review generated cards, make corrections, and keep approved cards ready for Anki."
                        )
                        Spacer(minLength: 16)
                        Button {
                            model.showNewSession = true
                        } label: {
                            Label("New session", systemImage: "plus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(ReviewerPrimaryButtonStyle())
                        .keyboardShortcut("n", modifiers: [.command])
                    }

                    if let recoveryMessage = model.recoveryMessage {
                        recoveryBanner(recoveryMessage)
                    }
                    if case .failed(let message) = model.saveState,
                       model.recoveryMessage == nil,
                       let session = model.activeSession {
                        writeFailureBanner(message, session: session)
                    }

                    if model.sessions.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: sessionColumns, alignment: .center, spacing: 16) {
                            ForEach(model.sessions) { session in
                                sessionRow(session)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Restore from backup…") { showRestorePicker = true }
                            .buttonStyle(.link)
                            .tint(ReviewerPalette.link)
                        Text("Backups restore as separate sessions.")
                            .font(.system(size: 12))
                            .foregroundStyle(ReviewerPalette.muted)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 26)
                .frame(maxWidth: 1420, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            do {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                model.restoreBackup(data: try Data(contentsOf: url))
            } catch {
                model.restoreError = error.localizedDescription
                model.isShowingRestoreError = true
            }
        }
        .alert("Delete session?", isPresented: Binding(
            get: { selectedForDeletion != nil },
            set: { if !$0 { selectedForDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { selectedForDeletion = nil }
            Button("Download backup first") {
                if let selectedForDeletion { model.downloadBackup(for: selectedForDeletion) }
                selectedForDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if let selectedForDeletion { model.deleteSession(selectedForDeletion.id) }
                selectedForDeletion = nil
            }
        } message: {
            if let selectedForDeletion {
                Text("Delete \"\(selectedForDeletion.title)\" and its \(selectedForDeletion.cards.count) cards? Download a backup first if you want to keep them.")
            }
        }
    }

    private var libraryHeader: some View {
        HStack {
            HStack(spacing: 10) {
                AppLogo(size: 24)
                Text("Flashcard Reviewer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ReviewerPalette.ink)
            }
            Spacer()
            AppearanceToggle()
            saveStatus
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 12)
        .frame(maxWidth: 1420)
        .frame(maxWidth: .infinity)
        .background(ReviewerPalette.sidebar)
    }

    private var sessionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 450), spacing: 16, alignment: .top)]
    }

    private var saveStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(saveStatusColor)
                .frame(width: 7, height: 7)
            Text(saveStatusTitle)
                .font(.system(size: 12))
                .foregroundStyle(ReviewerPalette.muted)
        }
    }

    private var saveStatusColor: Color {
        switch model.saveState {
        case .saved: model.recoveryMessage == nil ? ReviewerPalette.green : ReviewerPalette.red
        case .saving: ReviewerPalette.amber
        case .failed: ReviewerPalette.red
        }
    }

    private var saveStatusTitle: String {
        switch model.saveState {
        case .saved: model.recoveryMessage == nil ? "Saved on this Mac" : "Needs recovery"
        case .saving: "Saving…"
        case .failed: "Not saved"
        }
    }

    private var emptyState: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(ReviewerPalette.green)
                Text("Start with a fresh deck")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(ReviewerPalette.ink)
                Text("Paste your cards or import a UTF-8 text file. Every import becomes its own session, so an AI revision can never overwrite this deck.")
                    .font(.system(size: 14))
                    .foregroundStyle(ReviewerPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Create your first session") { model.showNewSession = true }
                    .buttonStyle(ReviewerPrimaryButtonStyle())
                    .padding(.top, 4)
            }
            .frame(maxWidth: 460, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }
    }

    private func recoveryBanner(_ message: String) -> some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ReviewerPalette.red)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Saved data needs attention")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ReviewerPalette.ink)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(ReviewerPalette.muted)
                }
                Spacer()
                if let session = backupSession {
                    Button("Download backup") { model.downloadBackup(for: session) }
                }
                Button("Restore backup…") { showRestorePicker = true }
            }
        }
    }

    private func writeFailureBanner(_ message: String, session: FlashcardSession) -> some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ReviewerPalette.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Changes aren't saved on this Mac.")
                        .font(.system(size: 13, weight: .semibold))
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
                    .buttonStyle(.bordered)
                    .tint(ReviewerPalette.red)
            }
        }
    }

    private var backupSession: FlashcardSession? {
        model.activeSession ?? model.sessions.first
    }

    private func sessionRow(_ session: FlashcardSession) -> some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 10) {
                    if renamingSessionID == session.id {
                        TextField("Session name", text: $titleDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 15, weight: .semibold))
                            .background(ReviewerPalette.input, in: RoundedRectangle(cornerRadius: 6))
                            .onSubmit { saveRename(session.id) }
                    } else {
                        Text(session.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ReviewerPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("\(session.cards.count) cards")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ReviewerPalette.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ReviewerPalette.raised, in: Capsule())
                }

                Text("\(session.cards.filter { $0.verdict != .unreviewed }.count) reviewed · Last used \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(ReviewerPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressStrip(
                    good: session.cards.filter { $0.verdict == .good }.count,
                    adjustment: session.cards.filter { $0.verdict == .needsAdjustment }.count,
                    bad: session.cards.filter { $0.verdict == .bad }.count,
                    unreviewed: session.cards.filter { $0.verdict == .unreviewed }.count
                )

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if renamingSessionID == session.id {
                        Button("Save") { saveRename(session.id) }
                            .buttonStyle(ReviewerPrimaryButtonStyle())
                            .controlSize(.small)
                        Button("Cancel") { renamingSessionID = nil }
                            .buttonStyle(.plain)
                            .foregroundStyle(ReviewerPalette.muted)
                    } else {
                        Button("Rename") {
                            titleDraft = session.title
                            renamingSessionID = session.id
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ReviewerPalette.muted)
                    }
                    Button(role: .destructive) { selectedForDeletion = session } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Delete session")
                    Button("Resume") { model.openSession(session.id) }
                        .buttonStyle(ReviewerPrimaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func saveRename(_ sessionID: UUID) {
        model.renameSession(sessionID, to: titleDraft)
        renamingSessionID = nil
    }
}

private struct CardImportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var sessionID: UUID? = nil
    @State private var title = "Study session"
    @State private var rawText = ""
    @State private var report = DeckImportReport(cards: [], blankLineCount: 0, warnings: [])
    @State private var showFilePicker = false
    @State private var inputError: String?
    @State private var showInputError = false

    private var rawTextBinding: Binding<String> {
        Binding(
            get: { rawText },
            set: { newValue in
                rawText = newValue
                report = FlashcardParser.parse(newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                PageHeading(
                    title: sessionID == nil ? "New session" : "Add flashcards",
                    subtitle: sessionID == nil
                        ? "Paste a deck or import a text file. This starts a separate session."
                        : "Paste cards or choose a text file. Cards are added at the end of this session as Unreviewed."
                )
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(ReviewerPalette.muted)
            }

            if sessionID == nil {
                TextField("Session name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
            }

            HStack {
                Text("CARDS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(ReviewerPalette.muted)
                Text("One card per line: front == back")
                    .font(.system(size: 12))
                    .foregroundStyle(ReviewerPalette.muted)
                Spacer()
                Button { showFilePicker = true } label: {
                    Label("Choose .txt file", systemImage: "square.and.arrow.up")
                }
            }

            TextEditor(text: rawTextBinding)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(ReviewerPalette.input, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReviewerPalette.line, lineWidth: 1))
                .frame(minHeight: 200, maxHeight: .infinity)
                .accessibilityLabel("Paste flashcards")

            HStack(spacing: 8) {
                summaryPill("\(report.cards.count) entries", color: ReviewerPalette.ink)
                summaryPill("\(report.validEntryCount) ready", color: ReviewerPalette.green)
                if report.needsFixingCount > 0 { summaryPill("\(report.needsFixingCount) need fixing", color: ReviewerPalette.amber) }
                if !report.warnings.isEmpty { summaryPill("\(report.warnings.count) duplicate warnings", color: ReviewerPalette.muted) }
                if report.blankLineCount > 0 { summaryPill("\(report.blankLineCount) blank lines ignored", color: ReviewerPalette.muted) }
                Spacer()
            }
            if report.needsFixingCount > 0 || !report.warnings.isEmpty {
                ScrollView {
                    ImportDiagnosticsView(rawText: rawTextBinding, report: report)
                }
                .frame(maxHeight: 150)
            }
            if report.needsFixingCount > 0 {
                Text("Nothing is discarded. Entries with import issues stay in the session and must be fixed before they can be marked Good.")
                    .font(.system(size: 12))
                    .foregroundStyle(ReviewerPalette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Plain backslashes are preserved. Use JSON-quoted fields for newlines or a literal == inside a side.")
                    .font(.system(size: 11))
                    .foregroundStyle(ReviewerPalette.muted)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(sessionID == nil ? "Create and review \(report.cards.count) cards" : "Add \(report.cards.count) cards") {
                    let importReport = report
                    if let sessionID {
                        model.appendCards(importReport.cards, to: sessionID, warnings: importReport.warnings)
                        dismiss()
                        return
                    }
                    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanTitle.isEmpty else {
                        inputError = "Choose a name for the session."
                        showInputError = true
                        return
                    }
                    guard !importReport.cards.isEmpty else {
                        inputError = "Paste at least one card before creating a session."
                        showInputError = true
                        return
                    }
                    model.createSession(
                        title: cleanTitle,
                        cards: importReport.cards,
                        warnings: importReport.warnings
                    )
                    dismiss()
                }
                .buttonStyle(ReviewerPrimaryButtonStyle())
                .disabled(report.cards.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(minWidth: 720, idealWidth: 920, maxWidth: 1180, minHeight: 620, idealHeight: 760, maxHeight: 940)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ReviewerPalette.canvas)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            do {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let imported = try FlashcardParser.parse(data: data)
                rawText = String(decoding: data, as: UTF8.self)
                report = imported
                if title == "Study session" {
                    title = url.deletingPathExtension().lastPathComponent
                }
                if imported.cards.isEmpty { inputError = "This file has no nonblank card entries."; showInputError = true }
            } catch {
                inputError = "Could not read this UTF-8 text file: \(error.localizedDescription)"
                showInputError = true
            }
        }
        .alert("Import problem", isPresented: $showInputError) {
            Button("OK", role: .cancel) { }
        } message: { Text(inputError ?? "Please check the session details.") }
    }

    private func summaryPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
    }
}
