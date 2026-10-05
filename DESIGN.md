# Flashcard reviewer — first-version design

## Purpose and decisions

Review a batch of 30–50 generated cards quickly, fix small mistakes directly, send larger fixes to an external AI, and take only approved cards into Anki.

Confirmed with the user: short text with occasional LaTeX math; Anki is the primary destination; Good and Bad advance immediately; Needs adjustment commits immediately and focuses notes; Escape leaves editing and arrows move on. Keep separate saved sessions for different subjects. The incoming math format is unknown, so importing must not require the user to choose one.

The original brief is in [REQUIREMENTS.md](REQUIREMENTS.md). This document defines the proposed implementation, including defaults selected to complete the design. The app target is native macOS using SwiftUI.

### Proposed defaults

- Desktop keyboard use first, with complete mouse and touch support.
- Separate named local sessions, with one open at a time.
- English interface; card text can use any language.
- Basic Front/Back cards. Images, cloze templates, AI integration, account management, and cloud sync are outside the first version.
- Automatic local saving. Explicit verdicts are always required for approval.
- Session creation accepts pasted text or a `.txt` file. Add cards in the review header uses the same import form to append additional Unreviewed cards in source order, preserving existing reviews. It opens All on the first addition. There is no automatic matching or merge flow.
- AI revision prompts include only Needs adjustment cards with review context and ask the AI to output only those revised cards. Returned text is reviewed as a new session.
- The existing images `1.png`–`5.png` provide the visual baseline, subject to the behavior corrections below.

## Screens and main journey

The app has a session library, a New Session sheet, Review, and Export. First use opens the empty session library; returning users resume the last open session, card, and filter. The Sessions control in the review header returns to the library.

### Sessions

Show saved sessions with title, total cards, reviewed count, last-used time, and a Resume action. Include New session and Restore backup. Allow inline renaming; do not build folders, tags, or a deck-management dashboard.

New session creates a separate record and never replaces another session. Any AI revision is imported as a new session containing only the revised cards. Counts, exports, notes, selection, and filters are scoped to that session. The title does not preset an Anki deck.

Switching saves the open session and restores the destination's selection/filter. If saving fails, retain the unsaved session in memory and keep its warning visible in the session picker. Deleting a session requires an explicit confirmation with its title/card count and an option to download its backup first. Restore defaults to creating a separate session.

1. Create a named session by pasting or uploading cards, inspect any issues, and begin reviewing.
2. Read both sides. Press `1` for Good, `2` for Bad, or `3` to write adjustment notes.
3. Click either side or press `E` for the front or `R` for the back to make a direct correction. Leave editing with Escape, then explicitly choose a verdict.
4. Download approved cards for Anki. If any cards need adjustment, copy an AI brief that includes and requests only those revised cards; later review the returned cards in a separate new session.

Export is available before review is complete. It always explains how many cards are included and excluded.

## Visual design and layout

Use the warm, restrained appearance of the supplied mockups: off-white workspace, white card surfaces, dark charcoal text, fine neutral borders, and minimal shadows. Use green for Good, amber for Needs adjustment, red for Bad, and neutral gray for Unreviewed. Always accompany color with a label or icon.

Use a readable sans-serif for controls and card editors. A restrained serif can distinguish page headings. Card text should be comfortably readable at about 20–24 px on desktop, with generous line spacing. Long answers expand naturally rather than disappearing into a tiny text box.

### Review layout

```text
Sessions  Session title      18 / 40 reviewed      Saved on this Mac     Export
---------------------------------------------------------------------------------
Filters + counts       Card 19 · Session name · Unreviewed
                       Editing front? Esc to use review shortcuts
Card list              +---------------------------------------------------+
  17  Front snippet ✓  | FRONT                                             |
  18  Front snippet ×  | Directly editable question                         |
> 19  Front snippet ○  |---------------------------------------------------|
  20  Front snippet ○  | BACK                                              |
                       | Directly editable answer                           |
                       +---------------------------------------------------+
                       Original / changes · Notes · Math preview if needed
---------------------------------------------------------------------------------
                       Previous   Good [1]   Bad [2]   Needs adjustment [3]
                       Next without verdict                         Undo [U]
```

- Header: Sessions navigation, session title, and reviewed count on the left; a segmented progress bar centered across the window; save status, Add cards, Export, and shortcuts on the right. No logo in the review header.
- Sidebar: All, Unreviewed, Good, Needs adjustment, and Bad filters with live counts; scrollable card list with number, front snippet, verdict, and issue/edited badges. Highlight and reveal the selected row.
- Center: front above back, both visible and directly editable through native multiline inputs. Keep originals collapsed by default. Show a before/after comparison on demand.
- Bottom: a stable verdict/navigation bar. Never move these buttons when notes open.
- Notes appear beneath the card in the same view. No modal or separate adjustment page.
- The native window keeps both sides stacked, the card list visible, and the verdict bar fixed while the center review area scrolls.

Progress means cards with a committed verdict, including Bad and Needs adjustment. It does not mean all cards are ready for Anki.

## Import and adding cards

Use a large paste area with Upload `.txt`, a session name, and a live summary. Session creation always creates a separate named session and leaves previous sessions intact.

### Parsing and text preservation

- Read UTF-8 files and accept LF or CRLF record endings. Preserve Unicode and source text; ignore a leading UTF-8 BOM for parsing.
- One nonblank source line represents one entry. Blank lines are counted and reported as ignored spacing.
- A normal entry is `front == back`. Trim separator padding only; preserve the raw source line for reference.
- Plain entries preserve every backslash literally. Do **not** interpret plain `\n` as a newline: this conflicts with LaTeX commands such as `\neq` and `\nu`.
- For multiline sides or literal `==` inside a side, support explicitly JSON-quoted fields: `"front" == "back"`. Decode escapes only inside these quoted fields. Both fields must be quoted in this mode.
- A quoted example is `"Name the two parts" == "First part\nSecond part"`. Literal backslashes inside JSON strings require JSON escaping; ordinary unquoted math does not.
- Parse the delimiter outside quoted strings. Multiple unquoted delimiters are ambiguous and require a selected split; do not guess.

### Issues and duplicates

Show each malformed entry with its line number, exact source, issue, and Edit line action. Missing separator, empty side, ambiguous split, and invalid quoted syntax are distinct issues.

The user can fix issues before import or add entries with unresolved issues. Such entries remain Unreviewed with an Import issue badge; retain their entire source and require the front/back split to be resolved before Good is possible. Bad remains available. Never silently remove entries or invent a missing side.

Show exact duplicate and same-front warnings within the batch and against current cards. Keep them unless the user explicitly removes a source line. A warning alone never changes a verdict.

The summary must be numerically consistent: for example, “9 entries: 6 valid, 3 need fixing; 1 duplicate warning; 1 blank line ignored.” Duplicate warnings can overlap with validity counts.

Create a new named session with cards in source order. Every card is Unreviewed. Existing sessions and entries remain unchanged. Select the first imported entry.

## Review behavior and state rules

The stored verdict is one of Unreviewed, Good, Bad, or Needs adjustment. Edited, Import issue, Duplicate warning, and Replacement requested are metadata, not extra verdicts.

| Action | Result |
| --- | --- |
| Good / `1` | Commit Good and advance; disallowed for unresolved import issues or empty sides. |
| Bad / `2` | Commit Bad and advance; no compulsory note. |
| Needs adjustment / `3` | Immediately commit Needs adjustment without advancing and focus notes. Switch to All if the current filter would hide the card. |
| Edit either side | Autosave current text; never approve through editing. |
| Change a Good card's text | Return it to Unreviewed immediately and show “Changed after approval — review again.” |
| Previous / Next / click list | Navigate without changing the verdict. |
| Mark Unreviewed | Clear the verdict while retaining text and feedback. |
| Restore original text | Restore both original sides as an undoable action; a changed Good card becomes Unreviewed. |

An adjustment note is recommended, but optional: manual changes may already explain the correction. Notes autosave. Escape leaves the textbox without changing the committed verdict; navigate separately with the arrow keys.

Add a secondary “Reject with feedback” action, also available through `Shift+2`. It opens notes, then Save rejection commits Bad and advances. There is no replacement-request checkbox. Preserve replacement flags from older backups without inferring new replacement intent from free text. Previously rejected cards can also receive feedback by opening their notes.

Text edits on Bad or Needs adjustment cards retain their verdict until the user chooses another one. Changing only notes does not revoke Good.

### Navigation and filtering

Default to All in source order. After a verdict, select the next entry in the current filter's pre-action order. For filters where the current card disappears, use that snapshot so the next card is never skipped. Do not automatically wrap to the first card.

If the filter has no next entry, show “End of this list” with Resume unreviewed, Review from start, and Export. Show Review complete when every card has a verdict. If unresolved cards remain elsewhere, never imply the whole session is finished.

### Undo

Every verdict produces a short notification such as “Card 19 marked Good” with Undo. A persistent Undo button remains available after the notification disappears.

Keep at least 50 undoable card actions during the open session. Undo restores the previous verdict, text, notes, replacement flag, and selection affected by that action. Restore the previous filter when needed to reveal the card. Group continuous typing into meaningful edit operations. Navigation is not an undo action. Undo history need not survive reload, but saved card state must.

## Keyboard and focus

| Key | Review behavior |
| --- | --- |
| `1` | Good, then next. |
| `2` | Bad, then next. |
| `3` | Immediately mark Needs adjustment and focus notes. |
| `Shift+2` | Reject with feedback. |
| Left / Up, Right / Down | Previous / next without changing the verdict. |
| `E` | Focus front editor. |
| `R` | Focus back editor. |
| `O` | Toggle original/changes. |
| `U` | Undo the latest card action. |
| `?` | Show shortcut help. |
| Escape | Leave an editor or close a panel; preserve saved drafts. |
| Cmd/Ctrl+Enter | Commit rejection feedback and advance if open; otherwise leave editing. |

Number, arrow, and letter shortcuts operate only when no input, textarea, editable element, or modal has focus. Ignore held-key repeat and IME composition. Use the actual shifted key mapping for `Shift+2`, accounting for keyboard layout.

Within text fields, typing, arrow keys, Enter, and native Cmd/Ctrl+Z behave normally. Tab follows the visible focus order. Verdict buttons remain clickable while editing, committing the latest text before applying the verdict. After a verdict, focus the card container so keyboard review can continue.

Use visible focus rings, labeled native controls, and polite announcements for verdicts/progress. Dialogs return focus to their trigger. Do not rely on hover-only controls.

## Math

Support TeX math through a locally bundled MathJax preview. Accept common AI wrappers: `$...$`, `$$...$$`, `\(...\)`, and `\[...\]`. Use Anki's documented `\(...\)` inline and `\[...\]` display delimiters in the Anki export. [Anki math reference](https://docs.ankiweb.net/math.html)

Keep source directly editable and unchanged by detection. Show a compact rendered preview only when math is present; preview errors are visible and never erase the source. Export recognized dollar-wrapped formulas in Anki delimiters and show a “Math formatting adapted for Anki” notice with source/output previews. This conversion affects the Anki file only; approved text, AI originals/current text, and backups retain the entered source.

Do not interpret a lone dollar sign or ordinary currency as math. Require balanced wrappers; flag uncertain dollar-pair spans, unmatched delimiters, and unsupported syntax. Offer a local “Treat as math / Keep as text” choice for ambiguous spans, stored with the card. Never make the user choose one math format for the whole batch. List unresolved warnings before export; require resolving ambiguity before downloading the Anki file rather than guessing. Full LaTeX documents, local TeX compilation, and custom package setup are outside scope.

The AI brief requests Anki-compatible delimiters. Match the local WKWebView preview's supported math features to Anki as closely as practical; Anki's built-in renderer can differ by client and version.

## Export

Use the layout in `3.png`, with **Anki import selected by default**. Each export shows its included count, a preview, and Copy and/or Download as appropriate. Include all matching cards in the session, regardless of the current review filter.

| Export | Included entries | Output |
| --- | --- | --- |
| Anki import | Good only, current text | UTF-8 `.txt`, two tab-separated fields. |
| Approved cards | Good only, current text | Copy or `.txt` in the app's `front == back` interchange format. |
| AI revision brief | Needs adjustment only | Copy or Markdown `.md`. |
| Session backup | Every entry and all session data | Versioned `.json`. |

Disable empty card/brief exports with an explanation. Keep backup available whenever a session exists. Report excluded unreviewed cards prominently. Successful copying shows feedback; clipboard failure offers the selectable preview and download. A download never marks cards as exported or reviewed.

### Anki file contract

Write headers `#separator:Tab`, `#html:true`, and `#columns:Front<TAB>Back`; `<TAB>` means an actual tab. Do not preset a deck or note type. Escape literal HTML characters, represent line breaks as `<br>`, and quote fields containing tabs or quotes, doubling internal quotes. Preserve Unicode and TeX backslashes. These choices use Anki's documented text-import features. [Anki text-import reference](https://docs.ankiweb.net/importing/text-files.html)

After download, display: “In Anki, choose File → Import, select this file, map Front/Back, and choose your deck.” Provide a small preview of both fields. The imported line count is not a promise that Anki will create that many new notes; its duplicate settings can affect the result.

### Approved text format

Use ordinary `front == back` where unambiguous. If either side contains a newline, literal delimiter, or would be mistaken for quoted input, JSON-quote both sides. This makes the app's exported text re-importable without damaging math or multiline content.

### AI brief contract

Start with concise revision instructions and the session name, then list each Needs adjustment card with stable ID, verdict, original front/back, current front/back, explicit before/after manual changes, and adjustment notes. Exclude Good, Unreviewed, and Bad cards from the prompt data and counts. Do not include session-wide import warnings for excluded cards.

Instructions:

1. Revise Needs adjustment cards according to feedback. Current text contains manual fixes; preserve them unless feedback says otherwise.
2. Return only the revised cards in the provided order. Bad cards are excluded even when Replacement requested is true; mark a card Needs adjustment to request revision.
3. Use one clear recall target per card and concise answers. Split a card only when feedback requires it.
4. Use Anki-compatible math delimiters.
5. Return only card lines in the supported interchange format. Explain quoted-field escaping and include a short example. No headings, numbering, commentary, or code fences.

The prompt asks for only the revised cards. Importing that output creates a separate new session; no automatic matching, replacement, or approval occurs. The original session remains available. Earlier Needs adjustment cards remain in future briefs until their verdict is explicitly changed.

### Backup and restore

Back up the open session: schema version, session title/ID, ordering, raw imported lines, original and current sides, import issues, verdicts, notes, replacement flags, math interpretation choices, timestamps, selected card, and filter. Derived counts are recalculated. Exports never include other saved sessions implicitly. Older backups with batch labels remain readable; obsolete labels are ignored.

Validate the whole file before modifying storage. Invalid or unsupported backups leave existing data intact. Restore always creates a separate session; if its ID already exists, assign a new ID and label it as a restored copy. Write restored data successfully before showing success; if writing fails, retain existing persistent sessions and make the restored in-memory copy downloadable.

## Persistence and privacy

Store sessions in a versioned JSON archive under `~/Library/Application Support/FlashcardReviewer/`; remember the last-open session, selected card, and filter. Keep edits in memory immediately; debounce text persistence briefly and save verdicts/imports promptly. Only display “Saved on this Mac” after the corresponding write succeeds. Show Saving while pending.

On failure, show a persistent banner: “Changes aren't saved on this Mac. Download a backup to keep them.” Include Retry and Download backup using the latest in-memory state. Continue allowing review, but never falsely report saving success. Flush pending changes when the app terminates.

Restore the last-open session when the app reopens. App windows share one in-memory model. Separate app processes serialize archive writes through a lock and compare the loaded file snapshot before saving; a stale process reports the conflict and keeps its unsaved work available for backup rather than overwriting newer data.

Bundle fonts, math assets, and all libraries locally. No analytics, AI requests, remote rendering, external images, or uploads of card content. Treat imported text as text rather than executable HTML. User-initiated copy/download is the only way content leaves the app.

Creating or switching sessions never deletes another session. Only explicit deletion or confirmed replacement can remove stored work.

## Completion view

Use `4.png` as the baseline. Show verdict counts and distinguish remaining AI work from approved cards. Export opens on the Anki tab; the AI brief remains available for Needs adjustment cards only. Include Return to review and Download backup. Revisions always start as a new session.

“All cards reviewed” is accurate even when some need adjustment; do not label the session “ready” or “all approved.” Creating a session from a returned deck starts a separate review with all cards Unreviewed.

## Corrections to the supplied mockups

- `1.png`: replace unconditional `\n` decoding with explicit quoted fields; preserve ambiguous lines without a guessed split. Correct overlapping summary categories. New session creates a separate saved session rather than replacing the current one.
- `2.png`: keep its stable layout, but ensure both sides are genuine direct-edit controls and provide math previews when relevant.
- `3.png`: default to Anki; give every AI card section proper line breaks and show complete changes. Previews must match downloaded content.
- `4.png`: move Anki export ahead of the AI handoff to match the user's primary destination.
- `5.png`: use only four verdict states; replacement is a flag. Use the Anki serialization contract above. Clarify that editor shortcuts never hijack native text entry.

## Implementation acceptance criteria

1. Importing 40 ordinary entries creates 40 Unreviewed cards in source order; blanks, duplicates, and malformed entries are explicitly accounted for.
2. Plain `\neq`, `\nu`, Unicode, and literal backslashes survive import, editing, backup, and export. Quoted multiline fields round-trip exactly.
3. `1` and `2` commit once and advance. Holding a key cannot approve or reject a run of cards. Typing digits or using IME in editors never triggers verdicts.
4. `3` immediately commits Needs adjustment and focuses notes. Notes autosave; Escape leaves editing and arrows navigate.
5. Editing a Good card removes it from approved exports until reapproved. Navigating or typing alone never approves.
6. Undo reverses a verdict and returns to the affected card, including when a filter removed it from view.
7. Empty/unresolved cards cannot be approved. Rejected cards can be recorded without inventing missing content.
8. Anki export includes only Good cards and passes an actual Anki import check with multiline text, tabs, quotes, `<`, `&`, Unicode, and inline/display math. Verify both field contents and rendered cards; do not rely only on file inspection.
9. AI brief contains only Needs adjustment entries with originals, current text, changes, and notes. Good, Unreviewed, and Bad entries are excluded, including requested replacements. Reimported AI output never overwrites or approves an original.
10. Backup restore reproduces all session data; corrupt/unsupported files and storage failures cannot destroy the previous session.
11. Reload resumes successfully saved progress. Simulated saving failure produces a persistent warning and a backup of current in-memory work.
12. Keyboard-only and narrow-screen users can import, edit, classify, navigate, undo, and export. Card review generates no network requests carrying content.
13. Separate sessions keep independent cards, progress, and selection; creating, switching, or restoring a copy cannot overwrite another session. Concurrent app processes cannot silently overwrite a newer sessions archive.
14. All four supported math wrappers preview correctly for supported formulas. Anki export adapts dollar wrappers while source/backup remain unchanged; currency stays text, and unresolved ambiguity is surfaced before download.
