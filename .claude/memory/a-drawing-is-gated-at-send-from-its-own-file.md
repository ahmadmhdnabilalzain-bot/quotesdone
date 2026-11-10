---
name: a-drawing-is-gated-at-send-from-its-own-file
description: "10 Nov 2026 (evidence run ea40c830): a portal timeout sent a drawing to browser OCR and a misread client name into a BOQ line; the BOQ is now gated at Send from the stored file's title block. Also: one definition of held; a harness never holds a page request across slow writes."
metadata:
  type: lesson
  modified: 2026-11-10
---

**What happened.** The customer portal's `call()` aborts at 30 s; analyze_drawing ran 39.7 s with the model on (drawing_boq
35 s). The composer then OCR'd the sheet in the browser (it did that for ANY PDF that came back without lines) and the
take-off carried the title block's client as "Mir. 22 Demo Owner". create_inquiry stores the BOQ the browser sends, and
redactBoq knows only the account's own identity, so nothing on the server could have caught it.

**How to apply.**
- Anything supplier-facing read from a drawing passes `customer_api/drawing_send_gate.ts` at Send, with the title strip's
  terms re-read from the STORED file (`lib/drawings.storedDrawingTerms`). Never trust lines from the request body.
- An OCR misread is matched folded (`drawing_identity_gate.ocrMisreads`): present folded, absent as written = drop. A term
  written out stays redaction's to paint (dropping it lost the DXF FCU line's quantity).
- A long server read gets its own client timeout (`DRAWING_READ_TIMEOUT_MS`), and every wrapper of `call` must forward the
  4th argument (Dashboard's did not). A timeout is a hold, said to the customer, never a reason to take another read path.
- "Held" in a comparison is `reveal_guard.heldQuoteIds` (assessQuote, what the hold desk releases on), never
  `quotes.quality.pass` - that is scored on the quote as first submitted.
- A harness must not hold a page request while it does slow work: the form's own abort (20 s supplier portal) decides
  first. Write, confirm on the server, then reload (`scripts/e2e/fixture_mobile.mjs`).

Related: [[identity-shapes-live-in-one-list]], [[a-journey-step-is-proved-by-its-outcome]].
