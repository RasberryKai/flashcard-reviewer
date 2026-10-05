# Flashcard reviewer — requirements brief

## Design process

Ask questions about this project, then design the whole app with the best usability in mind.

## Goal

Quickly review generated flashcards, correct them manually, or collect feedback for an AI to revise them.

## Form

A native macOS app with keyboard-first controls. No account or backend required. Sessions and card content stay on the Mac unless the user explicitly copies or exports them.

## Import

- Paste text or upload a `.txt` file containing one `front == back` card per line.
- Identify malformed lines; never silently discard cards.
- Creating a session accepts pasted text or a `.txt` file.
- New session imports create a separate session. Within a session, Add cards appends pasted or imported flashcards as Unreviewed while preserving existing cards and reviews. AI-revised output contains only revised cards and is reviewed in a new session; do not automatically match, replace, or merge it with existing cards.

## Review

- Show one card at a time, with both sides visible and directly editable.
- Three verdicts: Good, Bad, Needs adjustment.
- Allow adjustment notes alongside manual edits. No replacement-request checkbox.
- Left/Up navigates backward; Right/Down navigates forward outside text editors.
- Shortcuts: `1` good, `2` bad, `3` immediately marks Needs adjustment and focuses notes; Escape leaves editing, and arrows navigate.
- Include previous/next navigation, undo, progress, and filters by verdict.
- Keep original text for reference. Editing alone never approves a card.

## Copy and export

- **Approved cards:** Copy/download the latest versions as `front == back`.
- **AI brief:** Copy/download only Needs adjustment cards with verdicts, current text, manual changes, and adjustment notes. Exclude Good, Unreviewed, and Bad cards, even when a replacement was requested. Ask for only the revised cards in their original order.
- **Anki import:** Download approved cards as a UTF-8, tab-separated `.txt` file with Front/Back fields and no preset deck. Preserve multiline text and special characters.
- **Session backup:** Download/restore all cards, edits, verdicts, and notes.

## Persistence

- Automatically save progress locally; make saving failures visible.
- Card content leaves the Mac only through user-initiated copy/export.

## First-version scope

Manual review and external AI handoff. AI revision prompts request only the revised Needs adjustment cards. Returned revisions start as a new session with all cards Unreviewed.

## Confirmed design decisions

- Typical batch size: 30–50 cards.
- Primary destination for approved cards: Anki.
- Content: mostly short text, occasionally LaTeX math.
- Good and Bad immediately advance to the next card.
- Needs adjustment immediately saves the verdict and focuses notes. Notes autosave; Escape leaves editing.
- Keep separate named sessions for different subjects, saved locally on the Mac.
- The user does not know the incoming math delimiter format. Support common formats and show any ambiguity; do not require a format choice before import.
