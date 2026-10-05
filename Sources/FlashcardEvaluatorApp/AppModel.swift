import AppKit
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

enum ReviewFilter: String, CaseIterable, Identifiable {
    case all
    case unreviewed
    case good
    case needsAdjustment
    case bad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .unreviewed: "Unreviewed"
        case .good: "Good"
        case .needsAdjustment: "Needs adjustment"
        case .bad: "Bad"
        }
    }

    func includes(_ card: Flashcard) -> Bool {
        switch self {
        case .all: true
        case .unreviewed: card.verdict == .unreviewed
        case .good: card.verdict == .good
        case .needsAdjustment: card.verdict == .needsAdjustment
        case .bad: card.verdict == .bad
        }
    }
}

enum SaveState: Equatable {
    case saved
    case saving
    case failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [FlashcardSession] = []
    @Published var activeSessionID: UUID?
    @Published var isShowingLibrary = true
    @Published var selectedCardID: UUID?
    @Published private(set) var selectedCopyCardIDs: Set<UUID> = []
    @Published var filter: ReviewFilter = .all
    @Published var saveState: SaveState = .saved
    @Published var notice: String? {
        didSet { restartNoticeDismissal() }
    }
    @Published var recoveryMessage: String?
    @Published var showNewSession = false
    @Published var showAddCards = false
    @Published var showExport = false
    @Published var showShortcuts = false
    @Published var restoreError: String?
    @Published var isShowingRestoreError = false

    private struct Archive: Codable {
        var schemaVersion: Int = 1
        var sessions: [FlashcardSession]
        var activeSessionID: UUID?
        var deletedSessionIDs: [UUID: Date] = [:]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, sessions, activeSessionID, deletedSessionIDs
        }

        init(
            schemaVersion: Int = 1,
            sessions: [FlashcardSession],
            activeSessionID: UUID?,
            deletedSessionIDs: [UUID: Date] = [:]
        ) {
            self.schemaVersion = schemaVersion
            self.sessions = sessions
            self.activeSessionID = activeSessionID
            self.deletedSessionIDs = deletedSessionIDs
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            sessions = try values.decode([FlashcardSession].self, forKey: .sessions)
            activeSessionID = try values.decodeIfPresent(UUID.self, forKey: .activeSessionID)
            deletedSessionIDs = try values.decodeIfPresent([UUID: Date].self, forKey: .deletedSessionIDs) ?? [:]
        }
    }

    private struct UndoEntry {
        var sessionID: UUID
        var card: Flashcard
        var selectedCardID: UUID?
        var filter: ReviewFilter
    }

    private var undoStack: [UndoEntry] = []
    private var editGroupStart: [UUID: Flashcard] = [:]
    private var saveTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private let noticeDuration: Duration
    private var loadedCorruptArchive = false
    private var usingRecoveryArchive = false
    private var recoveryWriteURL: URL?
    private var persistedArchiveData: Data?
    private var persistedArchivePath: String?
    private let storageDirectoryOverride: URL?
    private var deletedSessionIDs: [UUID: Date] = [:]
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var libraryURL: URL {
        let directory = storageDirectoryOverride ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FlashcardReviewer", isDirectory: true)
        return directory.appendingPathComponent("sessions.json")
    }

    private var recoveryArchiveURL: URL {
        libraryURL.deletingLastPathComponent().appendingPathComponent("recovered-sessions.json")
    }

    private var archiveLockURL: URL {
        libraryURL.deletingLastPathComponent().appendingPathComponent("sessions.lock")
    }

    init(storageDirectory: URL? = nil, noticeDuration: Duration = .seconds(2.2)) {
        storageDirectoryOverride = storageDirectory
        self.noticeDuration = noticeDuration
        loadFromDisk()
        isShowingLibrary = activeSession == nil
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.flushPendingWrites() }
        }
    }

    var activeSession: FlashcardSession? {
        guard let activeSessionID else { return nil }
        return sessions.first { $0.id == activeSessionID }
    }

    var activeCard: Flashcard? {
        guard let session = activeSession else { return nil }
        guard let selectedCardID,
              let selected = session.cards.first(where: { $0.id == selectedCardID }),
              filter.includes(selected) else { return nil }
        return selected
    }

    var visibleCards: [Flashcard] {
        guard let session = activeSession else { return [] }
        return session.cards.filter(filter.includes)
    }

    var cardsToCopy: [Flashcard] {
        guard let session = activeSession else { return [] }
        if !selectedCopyCardIDs.isEmpty {
            return session.cards.filter { selectedCopyCardIDs.contains($0.id) }
        }
        return activeCard.map { [$0] } ?? []
    }

    var reviewCopyText: String {
        cardsToCopy.map { "\($0.front) == \($0.back)" }.joined(separator: "\n")
    }

    func toggleCopySelection() {
        guard let card = activeCard else { return }
        if !selectedCopyCardIDs.insert(card.id).inserted {
            selectedCopyCardIDs.remove(card.id)
        }
    }

    func clearCopySelection() {
        selectedCopyCardIDs.removeAll()
    }

    func copyReviewCards() {
        let count = cardsToCopy.count
        guard count > 0 else { return }
        copy(reviewCopyText, successMessage: "Copied \(count) \(count == 1 ? "card" : "cards")")
    }

    var reviewedCount: Int {
        activeSession?.cards.filter { $0.verdict != .unreviewed }.count ?? 0
    }

    var unreviewedCount: Int {
        activeSession?.cards.filter { $0.verdict == .unreviewed }.count ?? 0
    }

    var isSessionComplete: Bool {
        guard let session = activeSession, !session.cards.isEmpty else { return false }
        return session.cards.allSatisfy { $0.verdict != .unreviewed }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    private func restartNoticeDismissal() {
        noticeTask?.cancel()
        noticeTask = nil
        guard notice != nil else { return }
        let duration = noticeDuration
        noticeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func count(for verdict: CardVerdict) -> Int {
        activeSession?.cards.filter { $0.verdict == verdict }.count ?? 0
    }

    func createSession(
        title: String,
        cards: [Flashcard],
        warnings: [FlashcardImportWarning] = []
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        var session = FlashcardSession(
            title: cleanTitle,
            cards: cards,
            importWarnings: warnings
        )
        session.selectedCardID = session.cards.first?.id
        session.reviewFilter = ReviewFilter.all.rawValue
        sessions.insert(session, at: 0)
        deletedSessionIDs.removeValue(forKey: session.id)
        activeSessionID = session.id
        clearCopySelection()
        isShowingLibrary = false
        selectedCardID = session.selectedCardID
        filter = .all
        undoStack.removeAll()
        persistNow()
    }

    func openSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        clearCopySelection()
        activeSessionID = id
        isShowingLibrary = false
        filter = ReviewFilter(rawValue: sessions[index].reviewFilter) ?? .all
        selectedCardID = sessions[index].selectedCardID
        if selectedCardID == nil || !sessions[index].cards.contains(where: { $0.id == selectedCardID && filter.includes($0) }) {
            selectedCardID = sessions[index].cards.first(where: filter.includes)?.id
        }
        sessions[index].updatedAt = Date()
        undoStack.removeAll()
        persistNow()
    }

    func appendCards(_ cards: [Flashcard], to sessionID: UUID, warnings: [FlashcardImportWarning] = []) {
        guard !cards.isEmpty, activeSessionID == sessionID, !isShowingLibrary,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        finishAnyEditGroups()
        sessions[index].cards.append(contentsOf: cards)
        sessions[index].importWarnings.append(contentsOf: warnings)
        sessions[index].updatedAt = Date()
        filter = .all
        selectedCardID = cards.first?.id
        sessions[index].reviewFilter = filter.rawValue
        sessions[index].selectedCardID = selectedCardID
        clearCopySelection()
        persistNow()
        notice = "Added \(cards.count) \(cards.count == 1 ? "card" : "cards")"
    }

    func returnToLibrary() {
        finishAnyEditGroups()
        clearCopySelection()
        isShowingLibrary = true
        undoStack.removeAll()
        persistNow()
    }

    func renameSession(_ id: UUID, to title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        sessions[index].title = clean
        sessions[index].updatedAt = Date()
        persistSoon()
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        deletedSessionIDs[id] = Date()
        if activeSessionID == id {
            clearCopySelection()
            activeSessionID = nil
            selectedCardID = nil
            isShowingLibrary = true
        }
        persistNow()
    }

    func selectFilter(_ newFilter: ReviewFilter) {
        finishAnyEditGroups()
        filter = newFilter
        if let index = activeSessionIndex {
            sessions[index].reviewFilter = newFilter.rawValue
            selectedCardID = sessions[index].cards.first(where: newFilter.includes)?.id
            sessions[index].selectedCardID = selectedCardID
        }
        persistSoon()
    }

    func selectCard(_ id: UUID) {
        guard let session = activeSession, session.cards.contains(where: { $0.id == id && filter.includes($0) }) else { return }
        finishAnyEditGroups()
        selectedCardID = id
        if let index = activeSessionIndex {
            sessions[index].selectedCardID = id
        }
        persistSoon()
    }

    func moveSelection(by delta: Int) {
        let ids = visibleCards.map(\.id)
        guard !ids.isEmpty else { return }
        guard let currentIndex = selectedCardID.flatMap({ ids.firstIndex(of: $0) }) else {
            guard delta < 0 else {
                notice = "End of this list"
                return
            }
            selectCard(ids[ids.count - 1])
            return
        }
        let destination = currentIndex + delta
        guard ids.indices.contains(destination) else {
            notice = "End of this list"
            return
        }
        selectCard(ids[destination])
    }

    func beginEditGroup(for id: UUID) {
        guard editGroupStart[id] == nil, let card = card(id: id) else { return }
        editGroupStart[id] = card
    }

    func endEditGroup(for id: UUID) {
        guard let before = editGroupStart.removeValue(forKey: id), let after = card(id: id), before != after else { return }
        pushUndo(card: before)
        persistNow()
    }

    func finishAnyEditGroups() {
        for id in Array(editGroupStart.keys) { endEditGroup(for: id) }
    }

    func updateFront(_ id: UUID, text: String) {
        updateCard(id) { $0.front = text }
    }

    func updateBack(_ id: UUID, text: String) {
        updateCard(id) { $0.back = text }
    }

    func updateNotes(_ id: UUID, text: String) {
        updateCard(id) { $0.notes = text }
    }

    func toggleReplacementRequest(_ id: UUID, enabled: Bool) {
        updateCard(id) { $0.replacementRequested = enabled }
    }

    func markGood() {
        guard let card = activeCard else { return }
        guard card.canBeApproved else {
            notice = card.issue == nil ? "Both sides need text before approval." : "Resolve the import issue before approval."
            return
        }
        commitVerdict(.good)
    }

    func markBad() {
        commitVerdict(.bad)
    }

    func markNeedsAdjustment() {
        commitVerdict(.needsAdjustment, advances: false)
    }

    func commitBadWithFeedback(note: String, replacementRequested: Bool) {
        commitFeedbackVerdict(.bad, note: note, replacementRequested: replacementRequested)
    }

    func setMathInterpretation(_ id: UUID, span: String, interpretation: MathInterpretation) {
        updateCard(id) { $0.mathInterpretations[span] = interpretation }
    }

    func clearVerdict() {
        commitVerdict(.unreviewed, advances: false)
    }

    func restoreOriginalText() {
        guard let card = activeCard else { return }
        pushUndo(card: card)
        updateCard(card.id) {
            $0.front = $0.originalFront
            $0.back = $0.originalBack
            $0.issue = nil
        }
        notice = "Original text restored"
        persistNow()
    }

    func undo() {
        finishAnyEditGroups()
        guard let entry = undoStack.popLast(), let sessionIndex = sessions.firstIndex(where: { $0.id == entry.sessionID }),
              let cardIndex = sessions[sessionIndex].cards.firstIndex(where: { $0.id == entry.card.id }) else { return }
        sessions[sessionIndex].cards[cardIndex] = entry.card
        sessions[sessionIndex].selectedCardID = entry.selectedCardID
        sessions[sessionIndex].reviewFilter = entry.filter.rawValue
        sessions[sessionIndex].updatedAt = Date()
        if activeSessionID == entry.sessionID {
            selectedCardID = entry.selectedCardID
            filter = entry.filter
        }
        notice = "Last card change undone"
        persistNow()
    }

    func restoreBackup(data: Data) {
        do {
            var session = try SessionBackup.decode(data)
            try session.validate()
            if sessions.contains(where: { $0.id == session.id }) {
                session.id = UUID()
                session.title += " (Restored copy)"
            }
            session.selectedCardID = session.cards.first?.id
            session.reviewFilter = ReviewFilter.all.rawValue
            sessions.insert(session, at: 0)
            openSession(session.id)
            if loadedCorruptArchive {
                usingRecoveryArchive = true
                recoveryWriteURL = uniqueRecoveryArchiveURL()
                loadedCorruptArchive = false
                recoveryMessage = "The unreadable session files were kept untouched. Restored sessions are saved in a new recovery file."
            }
            persistNow()
            if saveState == .saved {
                notice = "Backup restored as a new session"
            } else {
                notice = "Restored in memory. Download a backup before closing."
            }
        } catch {
            restoreError = "This backup could not be restored: \(error.localizedDescription)"
            isShowingRestoreError = true
        }
    }

    func copy(_ text: String, successMessage: String = "Copied to clipboard") {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) {
            notice = successMessage
        } else {
            notice = "Copy failed. Select the preview and copy it manually."
        }
    }

    func saveText(_ text: String, suggestedName: String, fileExtension: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = fileExtension == "json" ? [.json] : [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            notice = "Saved \(url.lastPathComponent)"
        } catch {
            notice = "Could not save the export: \(error.localizedDescription)"
        }
    }

    func backupJSON(for session: FlashcardSession) throws -> String {
        let data = try SessionBackup.encode(session)
        return String(decoding: data, as: UTF8.self)
    }

    func downloadBackup(for session: FlashcardSession) {
        do {
            saveText(try backupJSON(for: session), suggestedName: "\(session.title)-backup.json", fileExtension: "json")
        } catch {
            notice = "Could not prepare backup: \(error.localizedDescription)"
        }
    }

    func retrySave() {
        guard !loadedCorruptArchive else { return }
        persistNow()
    }

    func flushPendingWrites() {
        finishAnyEditGroups()
        persistNow()
    }

    func restartCurrentList() {
        selectedCardID = visibleCards.first?.id
        if let index = activeSessionIndex { sessions[index].selectedCardID = selectedCardID }
        persistSoon()
    }

    func resolveImportSplit(cardID: UUID, atUTF16Offset offset: Int) {
        guard let sessionIndex = activeSessionIndex,
              let cardIndex = sessions[sessionIndex].cards.firstIndex(where: { $0.id == cardID }) else { return }
        var card = sessions[sessionIndex].cards[cardIndex]
        let source = card.rawImportLine
        let units = source.utf16
        guard offset >= 0, offset + 2 <= units.count else { return }
        let start16 = units.index(units.startIndex, offsetBy: offset)
        let end16 = units.index(start16, offsetBy: 2)
        guard let start = String.Index(start16, within: source), let end = String.Index(end16, within: source) else { return }
        var front = String(source[..<start])
        var back = String(source[end...])
        if card.sourceLineNumber == 1, front.hasPrefix("\u{FEFF}") { front.removeFirst() }
        while front.last == " " || front.last == "\t" { front.removeLast() }
        while back.first == " " || back.first == "\t" { back.removeFirst() }
        guard card.issue?.kind == .ambiguousSplit else { return }
        pushUndo(card: card)
        card.front = front
        card.back = back
        card.originalFront = front
        card.originalBack = back
        card.issue = nil
        sessions[sessionIndex].cards[cardIndex] = card
        sessions[sessionIndex].updatedAt = Date()
        selectedCardID = card.id
        sessions[sessionIndex].selectedCardID = card.id
        notice = "Import split resolved"
        persistNow()
    }

    func changeSessionTitle(_ title: String) {
        guard let activeSessionID else { return }
        renameSession(activeSessionID, to: title)
    }

    private var activeSessionIndex: Int? {
        guard let activeSessionID else { return nil }
        return sessions.firstIndex { $0.id == activeSessionID }
    }

    private func card(id: UUID) -> Flashcard? {
        activeSession?.cards.first { $0.id == id }
    }

    private func updateCard(
        _ id: UUID,
        transform: (inout Flashcard) -> Void
    ) {
        guard let sessionIndex = activeSessionIndex,
              let cardIndex = sessions[sessionIndex].cards.firstIndex(where: { $0.id == id }) else { return }
        let old = sessions[sessionIndex].cards[cardIndex]
        let previousVisibleIDs = visibleCards.map(\.id)
        var updated = old
        transform(&updated)
        let textChanged = updated.front != old.front || updated.back != old.back
        if textChanged, old.verdict == .good {
            updated.verdict = .unreviewed
            notice = "Changed after approval — review again."
        }
        if updated.issue != nil,
           !updated.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !updated.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.issue = nil
        }
        sessions[sessionIndex].cards[cardIndex] = updated
        sessions[sessionIndex].updatedAt = Date()
        if selectedCardID == id && !filter.includes(updated) {
            let oldPosition = previousVisibleIDs.firstIndex(of: id) ?? previousVisibleIDs.count
            let candidates = Array(previousVisibleIDs.dropFirst(min(oldPosition + 1, previousVisibleIDs.count)).reversed())
                + Array(previousVisibleIDs.prefix(oldPosition).reversed())
            let nextID = candidates.first { candidate in
                sessions[sessionIndex].cards.first(where: { $0.id == candidate }).map(filter.includes) == true
            }
            selectedCardID = nextID
            sessions[sessionIndex].selectedCardID = nextID
        }
        persistSoon()
    }

    private func commitFeedbackVerdict(
        _ verdict: CardVerdict,
        note: String,
        replacementRequested: Bool?
    ) {
        finishAnyEditGroups()
        guard let sessionIndex = activeSessionIndex,
              let target = activeCard,
              let cardIndex = sessions[sessionIndex].cards.firstIndex(where: { $0.id == target.id }) else { return }
        let beforeIDs = visibleCards.map(\.id)
        pushUndo(card: target)
        sessions[sessionIndex].cards[cardIndex].notes = note
        if let replacementRequested {
            sessions[sessionIndex].cards[cardIndex].replacementRequested = replacementRequested
        }
        sessions[sessionIndex].cards[cardIndex].verdict = verdict
        sessions[sessionIndex].updatedAt = Date()
        if let currentIndex = beforeIDs.firstIndex(of: target.id), beforeIDs.indices.contains(currentIndex + 1) {
            selectedCardID = beforeIDs[currentIndex + 1]
        } else {
            selectedCardID = nil
        }
        sessions[sessionIndex].selectedCardID = selectedCardID
        notice = "Card marked \(verdict.label)"
        persistNow()
    }

    private func commitVerdict(_ verdict: CardVerdict, advances: Bool = true) {
        finishAnyEditGroups()
        guard let sessionIndex = activeSessionIndex, let card = activeCard,
              let cardIndex = sessions[sessionIndex].cards.firstIndex(where: { $0.id == card.id }) else { return }
        let beforeIDs = visibleCards.map(\.id)
        pushUndo(card: card)
        sessions[sessionIndex].cards[cardIndex].verdict = verdict
        sessions[sessionIndex].updatedAt = Date()
        if advances, let currentIndex = beforeIDs.firstIndex(of: card.id), beforeIDs.indices.contains(currentIndex + 1) {
            selectedCardID = beforeIDs[currentIndex + 1]
        } else if advances {
            selectedCardID = nil
        } else if !filter.includes(sessions[sessionIndex].cards[cardIndex]) {
            // Keep the rated card available for feedback when its old filter no longer includes it.
            filter = .all
            sessions[sessionIndex].reviewFilter = filter.rawValue
        }
        sessions[sessionIndex].selectedCardID = selectedCardID
        notice = "Card marked \(verdict.label)"
        persistNow()
    }

    private func pushUndo(card: Flashcard) {
        guard let session = activeSession else { return }
        undoStack.append(UndoEntry(sessionID: session.id, card: card, selectedCardID: selectedCardID, filter: filter))
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
    }

    private func loadFromDisk() {
        let primaryExists = fileManager.fileExists(atPath: libraryURL.path)
        let recoveryCandidates = recoveryArchiveCandidates()
        guard primaryExists || !recoveryCandidates.isEmpty else { return }

        if primaryExists {
            do {
                try loadArchive(at: libraryURL)
                return
            } catch {
                for candidate in recoveryCandidates {
                    do {
                        try loadArchive(at: candidate)
                        usingRecoveryArchive = true
                        recoveryWriteURL = candidate
                        recoveryMessage = "The original sessions file could not be read and was left untouched. Recovered sessions were loaded from a separate recovery file."
                        return
                    } catch {
                        continue
                    }
                }
                let suffix = recoveryCandidates.isEmpty ? "" : " Neither the original nor the recovery files could be read."
                recoveryMessage = "Saved session data could not be read. The original files were left untouched; restore a backup before creating new sessions.\(suffix) (\(error.localizedDescription))"
                loadedCorruptArchive = true
                saveState = .failed("Local session data needs recovery")
                return
            }
        }

        for candidate in recoveryCandidates {
            do {
                try loadArchive(at: candidate)
                usingRecoveryArchive = true
                recoveryWriteURL = candidate
                recoveryMessage = "Recovered sessions are being saved separately from the primary sessions file."
                return
            } catch {
                continue
            }
        }
        loadedCorruptArchive = true
        recoveryMessage = "The recovery file could not be read. Its contents were left untouched; restore a backup to continue."
        saveState = .failed("Local session data needs recovery")
    }

    private func recoveryArchiveCandidates() -> [URL] {
        let directory = libraryURL.deletingLastPathComponent()
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { url in
            let name = url.lastPathComponent
            return name == "recovered-sessions.json"
                || (name.hasPrefix("recovered-sessions-") && url.pathExtension == "json")
        }.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }
    }

    private func loadArchive(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let archive = try decoder.decode(Archive.self, from: data)
        guard archive.schemaVersion == 1 else {
            throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "Unsupported local session version."])
        }
        for session in archive.sessions { try session.validate() }
        sessions = archive.sessions
        activeSessionID = archive.activeSessionID
        deletedSessionIDs = archive.deletedSessionIDs
        persistedArchiveData = data
        persistedArchivePath = url.standardizedFileURL.path
        if url.standardizedFileURL.path == recoveryArchiveURL.standardizedFileURL.path {
            recoveryWriteURL = url
        }
        if let activeSessionID, let current = sessions.first(where: { $0.id == activeSessionID }) {
            selectedCardID = current.selectedCardID
            filter = ReviewFilter(rawValue: current.reviewFilter) ?? .all
        }
    }

    private func persistSoon() {
        guard !loadedCorruptArchive else { return }
        saveState = .saving
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func persistNow() {
        guard !loadedCorruptArchive else { return }
        saveTask?.cancel()
        saveTask = nil
        if let index = activeSessionIndex {
            sessions[index].selectedCardID = selectedCardID
            sessions[index].reviewFilter = filter.rawValue
        }
        let archive = Archive(sessions: sessions, activeSessionID: activeSessionID, deletedSessionIDs: deletedSessionIDs)
        do {
            let data = try encoder.encode(archive)
            let targetURL = usingRecoveryArchive ? (recoveryWriteURL ?? recoveryArchiveURL) : libraryURL
            let directory = targetURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let lockDescriptor = Darwin.open(archiveLockURL.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
            guard lockDescriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES) }
            defer { _ = Darwin.close(lockDescriptor) }
            guard flock(lockDescriptor, LOCK_EX) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
            }
            defer { _ = flock(lockDescriptor, LOCK_UN) }

            let standardizedPath = targetURL.standardizedFileURL.path
            let targetExists = fileManager.fileExists(atPath: standardizedPath)
            if persistedArchivePath == standardizedPath {
                guard targetExists,
                      let expected = persistedArchiveData,
                      try Data(contentsOf: targetURL) == expected else {
                    throw ArchiveConflictError.changedOnDisk
                }
            } else if targetExists {
                // Another app process created this archive after this process opened.
                // Refuse to replace it with a stale in-memory snapshot.
                throw ArchiveConflictError.changedOnDisk
            }
            try data.write(to: targetURL, options: .atomic)
            persistedArchiveData = data
            persistedArchivePath = standardizedPath
            saveState = .saved
        } catch {
            saveState = .failed("Could not save sessions: \(error.localizedDescription)")
        }
    }

    private func uniqueRecoveryArchiveURL() -> URL {
        libraryURL.deletingLastPathComponent()
            .appendingPathComponent("recovered-sessions-\(UUID().uuidString).json")
    }
}

private enum ArchiveConflictError: LocalizedError {
    case changedOnDisk

    var errorDescription: String? {
        "The saved sessions changed in another app process. Your in-memory changes are safe here, but this stale copy was not allowed to overwrite them. Download a backup or close and reopen the newer saved sessions."
    }
}
