# Real supplier profiles: the truth the reader is scored against

Seats: sales_engineer (the reading); it_engineer (the harness). Kept under version control so every change to the
truth can be diffed (review of #1412, 13 Oct 2026).

- `truth.json` is the hand-written truth for 29 real UAE company profiles and catalogues. It holds the file list,
  plus each file's core `trades`, its `trades_also`, company, emirate, products and certifications.
  `corrections_log` lists every correction the author made after seeing model answers, each with the independent
  reviewer's verdict. Only entries marked "kept" or "allowed" are in the truth.
- `SOURCES.md` lists where each file was published, and when.
- The files themselves are real companies' publications. They are never committed. They sit in the founder's
  Desktop folder `QuotesDone Sandbox Test 2026-10\real_profiles\`.
- This is the IN-SAMPLE set: the trade-choice prompt was tuned on it. The honest score is the held-out set's
  (`../real_profiles_heldout/`), whose truth was written blind, before any run.

Rerun: `node scripts/e2e/document_intake_accuracy.mjs --corpus "<folder holding the files and this truth.json>" --model gateway --cap-usd 1 --label <name>`
