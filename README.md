# Flashcard Reviewer for Mac

A local SwiftUI app for reviewing, correcting, and exporting generated flashcards. Card text stays on this Mac; the app makes no network requests.

## Open and run in Xcode

Requirements: macOS 14 or later and Xcode.

```sh
open FlashcardReviewer.xcodeproj
```

In Xcode, select the **FlashcardReviewer** scheme and **My Mac**, then press **Run**. This is the native macOS app target with its own bundle identifier and MathJax resources; opening `Package.swift` runs a Swift Package executable and is not the app workflow.

The Xcode project is generated from `project.yml`. After changing project targets or resource membership, regenerate it with `xcodegen generate`.

## Build and launch a standalone app

The local packaging script remains available when you want a standalone bundle outside Xcode:

```sh
./scripts/package-app.sh
open .build/FlashcardReviewer.app
```

To build from the command line using the Xcode app target:

```sh
xcodebuild -project FlashcardReviewer.xcodeproj -scheme FlashcardReviewer -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/XcodeDerivedData build
```

Unit tests are also available from the Xcode scheme's **Test** action or with `swift test`.

The app stores sessions in `~/Library/Application Support/FlashcardReviewer/`. Use **Download backup** before moving or removing local session data.

## Create a session

Choose **New session**, give it a name, and paste cards or select a UTF-8 `.txt` file. Use one `front == back` card per line. Malformed lines stay in the session with an issue badge so they can be corrected; plain backslashes and Unicode are preserved. The AI revision brief includes only **Needs adjustment** cards with their edits and feedback, and asks for only those revised cards. Good, Unreviewed, and Bad cards are excluded, even when a Bad card has a replacement request. Returned revisions can be reviewed as another new session.

To extend an existing session, choose **Add cards** in its header. Paste additional cards or choose a UTF-8 `.txt` file; the cards are appended in source order as Unreviewed, preserving existing cards, edits, and ratings. The All filter opens on the first addition. AI revisions should still be reviewed in a new session.

## Keyboard shortcuts

During review, use `1` for Good, `2` for Bad, `3` to immediately mark Needs adjustment and focus the notes textbox, left/up and right/down arrows to navigate, `E` to edit the front, `R` to edit the back, `O` to show originals, and `U` to undo. Press `Space` to select or deselect the focused card; selected cards show a checkmark. `⌘C` copies the front and back of all selected cards in deck order as `front == back`, or the focused card if nothing is selected. Selection survives navigation and filter changes; use **Clear** in the sidebar to reset it. Leaving or opening a session clears selection. Notes save automatically. Press Escape to leave the textbox, then right/down to move on; there is no Save and next step. If marking Needs adjustment would hide the current card under its filter, the app switches to All so the card stays available for feedback. Shortcuts are disabled while an editor has focus, where typing and native text copying keep working.

## Scope

The app provides session creation, appending additional cards, local persistence, review, feedback, approved-card export, Anki text export, an AI revision prompt, and JSON backup/restore. Appending adds new entries; it does not match, replace, or merge them with prior cards.
