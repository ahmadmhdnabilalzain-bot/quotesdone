# Drawings (ledger 31, 580) and the model-on seat exam (ledger 1084): measured 27 Oct 2026

Seats: sales_engineer (drawings), it_engineer (exam and the `dwg` gate step). Every subject is ZZ DEMO with
`@example.invalid` addresses and planted counts, contacts and project names. No real customer file was used and
nothing went to a real supplier. OpenRouter stayed on (ruling 1260). The runs went against production
`htdblwldjkcgjvmqkbeh` inside capped rehearsal windows.

## The `dwg` gate step: why it failed, and the fix

- **Measured on origin/main 679bf9ef from a Claude cloud session:** 2 of 23 tests passed and 21 failed. Every DWG
  read answered "The DWG reader could not run (fetch failed)".
- **Cause:** the session's egress proxy refuses `cdn.jsdelivr.net` (CONNECT 403; `unpkg.com` too). `dwg.ts` loaded
  the LibreDWG wasm only from that host. The two tests that passed are the binary-DXF ones, which never load the wasm.
  The code was not at fault: the network was, and since ledger 1279 the gate runs in exactly these sessions.
- **Fix (branch `it_engineer/dwg-wasm-from-npm-registry`):** jsDelivr is still tried first. When it fails, the same
  file is taken from the package's npm-registry tarball, which `registry.npmjs.org` can reach. Either source is
  accepted only on the unchanged pinned SHA-256, and the tarball's wasm matches it byte for byte (measured).
- **Result:** `dwg_samples.check.ts` now passes 24 tests with 0 failures. dwg.test.ts passes 7 of 7.
- **Prevented by:** a new test that fetches the npm source on its own.

## Ledger 31: element understanding per format

### Offline: production code, no model

`drawing_bench.test.ts` was run in full with OCR available:

| format | read | elements counted exactly | leaks to a supplier |
|---|---|---|---|
| DXF ascii (dynamic doors, MINSERT, nested) | yes | 4/4 | 0 |
| DXF binary | yes | 4/4 | 0 |
| PDF vector | yes | 4/4 | 0 |
| BOQ xlsx / BOQ pdf | yes | 4/4 each | 0 |
| image PNG (sample fire-alarm sheet) | yes | 4/7 | 0 |
| photo JPG (rotated, blurred, q60) | yes | **0/7** (53 call points read against 10, 74 smoke detectors against 11) | 0 |
| PDF scanned (routed to OCR) | yes (OCR) | 3/7 | 0 |
| BOQ image (OCR) | yes | 3/4 | 0 |
| **total** | 9/9 | **30/45** | **0** |

DWG: `dwg_samples.check.ts` read 9 LibreDWG drawings, releases R14 to 2018. In every one, each take-off quantity
equals the AutoCAD-written DXF of the same drawing. The one exception is the pinned LibreDWG defect in R14 and 2000:
one layer comes out 0.95 sqm and 0.43 m short.

### Live: production customer_api, models on (run f7557263)

| format (the door it was sent through) | elements exact | note |
|---|---|---|
| DXF ascii (analyze_document) | **2/2** (SD 7, SKT 5) | |
| DXF binary (analyze_document) | **2/2** | |
| DWG AutoCAD 2018 (analyze_drawing) | **5/5 quantities** (8, 2, 129.36 sqm, 80.56 m, 12.64 m) | The supplier's copy renames the blocks and layers to "block unnamed" and "layer 3" (identity scrub), so the two block lines can no longer be told apart. |
| PDF vector (analyze_document) | **0/3** | The document door returns only "stroked line length". The drawing-set reader does not run on this path. The portal sends PDFs through analyze_drawing, which is covered under 580 below. |
| PDF scanned, no browser OCR (analyze_document) | **0/3** | The model reading returned one line, "Smoke detector", with no quantity. |
| image JPG / PNG (analyze_document) | read (HTTP 200), **not scored** | The run asserted a refusal under ruling 1000, which was wrong: images are not refused by name. The script now scores them, but that version has not run yet. |

**Finding:** `drawing_boq` mode `vision_count` (the model counting legend symbols on a redacted photo or scan) has
**no caller** anywhere in customer_api, src or scripts. Photos and scans are therefore counted only by template
matching, which scored 0/7 on the photo above.

## Ledger 580: count, contacts, BOQ PDF, inquiry (run 6dd2316c)

The input was an 8-sheet ZZ DEMO mechanical set, rasterised the way the portal does it. Planted on it: a consultant,
a (555) phone, a web host, a street address, a project name, an e-mail `ZZ.MEP@EXAMPLE.INVALID` and a mobile
`+971 50 000 0091`.

- **OCR control:** on the ORIGINAL sheet, tesseract read all 8 planted strings, so a clean redacted page is a real
  result and not an OCR blind spot.
- **Contact details left, measured:**
  - BOQ lines: **0**
  - 8 of 8 redacted pages, read by OCR: **0**
  - The redaction verified 8 pages in and 8 out, with 0 lost.
- **Count, live: 2/7 exact.**
  - Correct: RTU-1 1, IRH-1 1.
  - Wrong: EF-1 read 2 (truth 1) and EF-2 read 2 (truth 1).
  - Missing: WC/L-1, the 2,400 type-A air devices and the 16,432.8 m of 26x18 duct.
  - Offline, `boqFromDrawingSet` on the same bytes reads **7/7**: 2,400 air devices and duct 16,433.2 m (0.002% off).
- **Cause of the miss:** in `drawing_boq`, the code reader ran only when there was no AI key or the model refused.
  Since ruling 1260 the key is always present, so the vision model drafted the take-off. Two drawing_boq calls took
  39.6 s and 38.1 s.
- **Fix (branch `sales_engineer/drawings-measured-end-to-end`):** when a PDF's text layer gives a drawing set, code
  counts it before the model is asked.
  - Prevented by: `drawing_boq/set_before_model.test.ts`.
  - It deploys at merge. The live 7/7 still has to be re-measured after that.
- **BOQ PDF and inquiry: NOT produced.** The intake stayed `held` for 10 turns with **0 questions asked**. The agent
  runs show readiness 55 to 70, `status_computed=held`, `questions=0`. create_inquiry answered 428 intake_required.
  So there is no inquiry id and no BOQ PDF path.
  - This is a real dead end in the product: a held intake that asks nothing.
  - The redacted pages were stored, but nothing reached a supplier.
- drawing_redact answered 546 twice during the run, on retries, out of 18 calls.

## Ledger 1084: the model-on exam

- **Not live before today:** 0 rows in `seat_exam_asked` and `seat_exam_fix`. The workflow is
  workflow_dispatch-only, GitHub Actions is off, and `CLAUDE_CODE_OAUTH_TOKEN` is unset. The coordinator has moved
  the daily run to a scheduled Claude session.
- **Run 2f71d5c5:** 18 items over 6 seats, each in a fresh wording that hints at no answer, put to think() end to end.
  - Graded by code: 8/18.
  - After Claude's judgement of the code misses: **17/18**.
  - Recorded on production: 18 asks, 1 open fix.
- **The miss:** accountant-exam-03. The answer said no surcharge, but left out Stripe's 2.9% plus AED 1.
  - Fix: that figure is now in the sentence of `accountant:company-pricing-and-fee-arithmetic` that answers the question.
- **A contradiction found:** ceo-exam-01's key says "one network per trade and area". That contradicts the
  founder's fact that every supplier covers the whole UAE, and the seat followed the founder.
  - `ceo:network-effects-and-defensibility` is corrected (EN and AR).
  - The exam key was not edited. It should be reviewed by its owner.

## Spend and cleanup

- AI spend, from ai_cost_log by run tag: exam USD 0.80, run 580 USD 0.36, run 31 USD 0.01. **Total USD 1.17.**
- Cleanup:
  - Both drawing runs were killed by a 30-minute `timeout` inside their own teardown, because the management API
    was throttled by about 10 sessions at once.
  - They were torn down afterwards by their exact tags with the harness's own teardown.
  - **Proved 0 left for 6dd2316c and for f7557263**, on every leftovers line: auth users, customers, leads,
    inquiries, intakes, email verifications, storage objects.
  - 0 drawing redaction runs and 0 drawing-files objects for the two customers.
  - 0 cad_read_jobs, and every rehearsal window closed, the exam's (2f71d5c5) included.
  - The exam's 18 `seat_exam_asked` rows and its 1 open `seat_exam_fix` are the exam's record and are kept on purpose.
