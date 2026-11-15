---
name: identity-shapes-live-in-one-list
description: "Every scrubber between customer and supplier runs _shared/identity_text.ts; the planted-identity corpus (identity_never_leaks_before_reveal.mjs) is the measurement. Never add a pattern to one scrubber only."
metadata:
  type: lesson
  modified: 2026-11-03
---

3 Nov 2026 (sales_engineer, qualification matrix gap #3): five scrubbers stood between the two sides (supplier_api
identity_scrub, drawing_boq scrubIdentity, quote_documents maskContacts, messages_api stripContact, a drifted copy in
customer_api), each with its own partial list. The planted-identity corpus measured 140 of 160 trials leaking: IBANs,
P.O. Boxes, "(050) 000 0076", Arabic-Indic digits, Arabic firm names, "Prepared by: <name>", and the supplier's own
name whenever it contained "Co…" (companyRe stripped `co` with no word end).

**How to apply:** a new identity shape goes into `supabase/functions/_shared/identity_text.ts` (and its test), never into
one scrubber. A known name is matched by `knownNameRe`. Re-measure with
`node scripts/e2e/identity_never_leaks_before_reveal.mjs --repeats 3` (480 trials, OCR, ~1 h, USD 0) and report the
hold rate beside the leak rate. Supplier-facing documents before the reveal print no contact detail of any shape,
ours included (`options.contact = false`, doc_template.SUPPLIER_ASK).

**Loosening is held to BOTH lists, and the corpus keeps planting what was loosened.** The first review of #1838 fixed
over-redaction and, in the same change, stopped the corpus planting six-digit "CN-" licences, so the run read 0 leaks
over a leak it had reopened; a second review found eight more reopened shapes (sign-offs without a comma, ALL-CAPS and
particle names, "(+971)", Arabic legal forms without شركة). A KEEP row never licenses removing a LEAKED row or a corpus
form: tell the two apart by context (the label before a code, the word after شركة), not by dropping the measurement.

**Places below the emirate (13 Nov 2026, founder ledger 1683).** `_shared/identity_places.ts` reduces every community,
premises number, street, building, landmark, Makani, coordinate and what3words to its EMIRATE ("Villa 15, Al Barsha 2,
Dubai" -> "Dubai"); scrubIdentityText runs it, so every scrubber does. A new community goes into its gazetteer, never into
a scrubber. Known names run BEFORE the shared list now (a project or firm named after its area must be matched whole
before "Barsha" becomes "Dubai"). Four #1838 MUST-KEEP rows became REDUCED rows by that ruling; a KEEP row that is a
place below the emirate is not kept. The model path has its own planted corpus:
`quote_extract/a_careless_model_reading_reaches_no_customer_document.test.ts`.
**Precision first (13 Nov 2026, coordinator after the independent review).** The code layer is the high-precision backstop:
a rule that removes a legitimate technical word ("Manual [removed]", "Dubai blue", "█ Studs") is a defect as serious as a
leak. Every new shape is held to `_shared/identity_keeps_trade_text_corpus.test.ts` (421 trade sentences, 0 changed) and
`identity_scrubbers_finish_on_adversarial_input.test.ts` (a hard time limit per scrubber). Fuzzy shapes (an unlabelled
person, a house brand, initials, an unlisted place) go to the model-based second reader, never to a regex.
