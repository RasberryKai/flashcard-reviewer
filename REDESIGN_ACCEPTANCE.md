# Review redesign acceptance

The 2026-10-05 user references supersede the original visual layout in DESIGN.md.

| Outcome | Implementation owner | Verification |
| --- | --- | --- |
| Warm light/dark colors follow macOS appearance; legible native controls and math | theme_library | Build and runtime appearance/screenshots |
| Sessions header, serif heading, compact session cards, progress and actions match reference | theme_library | Wide/narrow library runtime screenshots |
| Minimal review header, sidebar and card surfaces; no character counts or redundant helper text | review_ui | Runtime review screenshot |
| Filter disclosure is togglable and initially collapsed; All is the initial filter | review_ui | Runtime expand/collapse and filtering |
| Feedback hidden by default; Needs adjustment commits and reveals/focuses notes | review_ui | Runtime button/3, typing, Escape and navigation |
| Stable minimal bottom bar in Good, Bad, Needs adjustment order | review_ui | Runtime screenshot before/after feedback |
| Cmd+1 selects Review; Cmd+2 selects Flashcard; editor typing and existing shortcuts remain safe | review_ui | Shortcut tests and runtime interactions |
| Persisted cards, edits, verdicts and selected card survive redesign | both | Existing persistence suite and isolated runtime archive |
| Existing import, Add cards, export, undo and recovery remain reachable | both | Independent source review and targeted runtime |

Keep explicit rejection-feedback access even though ordinary feedback is conditional. Preserve existing uncommitted work. Runtime QA uses a separate storage directory so it does not change the user's sessions.

## Verification on 2026-10-05

- All 28 SwiftPM tests passed after the math-source interpolation correction. Final mode-tab contrast adjustment changed styling only; its release package built successfully.
- Independent source review found no actionable redesign defects. Parent inspected the final dark Review window against the supplied reference.
- Isolated runtime QA verified collapsed/expandable filters, All default, Needs adjustment filtering, immediate notes focus, saved feedback, Escape and navigation hiding notes on other cards.
- Runtime QA verified Cmd+1/Cmd+2 while editing, ordinary numeric typing and arrows in editors, Space answer reveal, and Good grading/advance.
- Library runtime QA verified two columns wide and one column at half width. Dark appearance and button contrast were inspected; Light appearance was not exercised.
- New session creation was exercised. Add cards, full export/restore/recovery, secondary action execution, and assistive-technology behavior were not exhaustively re-tested in this redesign; existing unit coverage and source review remain the evidence for those paths.
- Known renderer limitation: fixing the malformed encoded-source interpolation restored preview content, but MathJax formulas still display raw TeX in the packaged QA app. Typesetting remains unresolved.
- QA used `/tmp/flashcard-reviewer-redesign-qa`. The normal session archive is visible in the final app window and was only observed during QA completion.
