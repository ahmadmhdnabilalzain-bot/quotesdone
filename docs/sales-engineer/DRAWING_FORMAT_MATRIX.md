# Drawing format matrix — what the sales engineer reads, counts, prices and shares

> **Superseded in part, 28 Sep 2026 — founder ruling 1000:** drawings are accepted as **PDF, DWG and DXF
> only**. Revit (.rvt / .rfa), IFC and DGN are never accepted: their readers (`rvt.ts`, `ifc.ts`, `dgn.ts`)
> and tests were removed, `attachment.ts` allows none of their types, and the portals no longer offer them.
> The RVT, DGN and IFC rows below are history, not capability.

Seat: `sales_engineer`. Written 24 Sep 2026 for founder instructions 30, 31, 32, 64, 579, 580, 696, 698,
701 and 703. The capability bar is OpenConstructionERP's README (DWG/DGN/RVT/IFC take-off by
category, type and level; DWG polylines and calibrated PDF measurement; a scoped BOQ with confidence;
magic-byte validation). It is AGPL, so it is a bar only: no code was copied.

**The rule for this page: a cell is SUPPORTED only when a test that was run proves it.** Evidence is
`file:line`. BEFORE is `origin/main` at `252f400`. AFTER is this branch. Where a cell rests on code that
has not yet run on production, because nothing here is deployed, it says so and is not SUPPORTED.

Steps:
- **read**: the production reader opens the bytes, identified by their magic bytes and never by the file name.
- **count**: tagged elements equal the count known by construction.
- **BOQ PDF EN / AR**: the take-off, after create_inquiry's gate and the supplier inbox's gate, renders
  to a real PDF on our template.
- **redact**: no project identity survives in what a supplier receives, and the drawing's content does.
  Identity means title block, building, location, consultant, client, contacts, drawing and job numbers,
  metadata, file name and the CAD original.
- **send**: a supplier receives it through create_inquiry, the matcher and the inbox.

Legend: **S** = SUPPORTED, **P** = PARTIAL, **M** = MISSING, **H** = held on purpose (fail closed, never shared).

## BEFORE (origin/main, 252f400)

| format | read | count | BOQ PDF EN | BOQ PDF AR | redact | send |
|---|---|---|---|---|---|---|
| DWG | S | P | P | P | P | P |
| DXF ascii | S | P | P | P | P | P |
| DXF binary | S | P | P | P | P | P |
| PDF vector | S | S | S | S | P | P |
| PDF scanned | P | P | P | P | M (H) | P |
| PDF multi-sheet | S | P | S | S | P | P |
| RVT | P | M | M | M | H | M |
| DGN | P | M | M | M | H | M |
| IFC | S | S | P | P | P | P |
| image JPG/PNG | P | P | P | P | M (H) | P |

Evidence (BEFORE):
- **DWG read**: `_shared/doc_read/dwg.ts:55` (1.5 MB edge ceiling), `scripts/cad_read_worker.ts:73` (no ceiling on the
  CAD worker), `dwg_samples.check.ts` (nine real LibreDWG DWGs match their DXF).
- **DWG/DXF count, P**: `_shared/doc_read/cad.ts:220` counted every INSERT, so legend samples were counted as work.
  The ZZ DEMO plan read SD 8 and SKT 6 against a true 7 and 5 (this branch's fixture through main's counting rule, measured before the fix).
- **DWG/DXF BOQ PDF, P**: no test drove a CAD take-off to the supplier PDF. `drawing_chain.test.ts:119,142` covers the PDF-set take-off only.
- **DWG/DXF redact, P**: the BOQ was de-identified (`_shared/cad_identity.ts`, `cad_identity.test.ts`), but the
  drawing itself was never shareable. `customer_api/index.ts:859` sent it to `cad_convert`, a paid CloudConvert raster
  with no text layer, so the server could not box it. The model is held. `customer_api/index.ts:847,883` answered
  `drawing_held`. `redactDxf` (`cad.ts:314`) existed but nothing called it.
- **DWG/DXF send, P**: the BOQ only. Production, read-only, 24 Sep: `drawing_redaction_runs` held 6 rows and none was `complete`.
- **dwgToDxf** (`dwg.ts:104-105`) wrote no text position, height, rotation, INSERT scale, paper-space flag or block
  definitions, so a DWG could not be drawn.
- **PDF vector count, S**: `drawing_boq/drawing_set.test.ts:42`. **BOQ PDF EN/AR, S**: `drawing_chain.test.ts:119,142`.
- **PDF redact, P**: box geometry was tested (`drawing_set.test.ts:74`, `drawing_identity_text.test.ts`). The painted
  page was never checked pixel by pixel, and the step lived inside `drawing_redact`'s `Deno.serve`
  (`drawing_redact/index.ts:337-369`), where no test could reach it.
- **PDF scanned**: `doc_read/pdf.ts:24` answers `needs:'ocr'`. `drawing_redact/index.ts:354` holds a page with no text layer.
- **Multi-sheet count, P**: no test with a known count across a set.
- **RVT/DGN**: `doc_read/rvt.ts:48` (the IFC export ask), `doc_read/index.ts:37,67-68` (DGN recognised, export ask).
  The Arabic for each is in `dwg.test.ts:95`.
- **IFC**: `ifc.test.ts:12` (counts per type and storey), `drawing_identity_gate.test.ts` test 4.
- **Image**: `doc_read/index.ts:69` (`needs:'ocr'`, OCR runs in the customer's browser). `drawing_image_ocr.test.ts`
  is ignored in CI (it needs tesseract and a local fixture).
- **Signer**: `_shared/drawing_pages.ts:68` checked only the path prefix. Three live inquiries serve
  `drawings/redacted/founderdemo/…` pages that no redaction run names.
- **Model path**: `drawing_redact/index.ts:373,409,470` records a bare `detect_failed` under the hold, and skipped
  pages carry no reason.
- **CAD worker**: `scripts/cad_read_worker.ts:113-115`. A job that fails for good is logged and raises no finding.

## AFTER (this branch)

| format | read | count | BOQ PDF EN | BOQ PDF AR | redact | send |
|---|---|---|---|---|---|---|
| DWG | S | S | S | S¹ | P⁶ | P² |
| DXF ascii | S | S | S | S¹ | P⁶ | P² |
| DXF binary | S | S | S | S¹ | P⁶ | P² |
| PDF vector | S | S | S | S¹ | S³ | P² |
| PDF scanned | P | P | P | P | P⁵ ⁶ | P² |
| PDF multi-sheet | S | S | S | S¹ | S³ | P² |
| RVT | P | M | M | M | H | M |
| DGN | P | M | M | M | H | M |
| IFC | S | S | P | P | P | P |
| image JPG/PNG | P | P⁴ | P | P | P⁵ | P² |

1. The Arabic document is asserted on its content in CI, where the brand Arabic font is unreachable. The glyphs
   were read back from the rendered PDF once, locally, with Noto Naskh Arabic (OFL) standing in for the brand font:
   heading and quantities 7 and 5 read back, 0 glyphs dropped, no identity. It has not been checked with the brand
   font itself.
2. Wired and proven in process: the page is drawn or boxed, recorded as a run, resolved by create_inquiry and
   signed only with provenance. **It has not run on production**, because nothing in this PR is deployed.
   `scripts/e2e/cad_identity_reaches_no_supplier.mjs`, `every_drawing_format_is_read.mjs` and
   `drawing_reaches_suppliers.mjs` now expect the drawn page and run nightly. The cell becomes S once they pass after deploy.
3. Pixel-level proof: `_shared/drawing_redact_page.check.ts`, in its own CI step with `--allow-net=deno.land`,
   because imagescript's Deno build fetches its codec on import. It was run locally against the npm build of the
   same imagescript 1.2.17, since deno.land is blocked in this sandbox.
4. The counter itself is proven on pixels: 7 smoke detectors and 3 call points against the drawing's own legend.
   The legend's words come from the customer's browser OCR, which the server never re-reads, so the count stays an
   estimate the customer confirms.
6. Downgraded from S after the second independent review (25 Sep 2026, section below). Every case that review
   probed is now a test that passes. Two kinds of case are not proven, so the cells are P:
   - a party whose whole name is trade words ("NORTH GATE"), is not the customer's, and stands outside a title
     block. It is drawn, because nothing tells it apart from a label.
   - a scan the OCR engine misreads as ordinary content at every orientation, with a confidence high enough to
     count as read.

5. **OCR redaction, second commit (founder instruction 579, "OCR for scanned drawings")**:
   `_shared/scan_redact.ts` runs on the CAD worker, with no model and no paid service. The engine is tesseract.js
   7.0.0 with the repository's own eng + ara data (`scripts/lib/scan_ocr.ts`). The steps:
   - OCR the page.
   - Box it with the PDF path's own rules (`titleBlockBoxes` plus `textLayerBoxes`).
   - HOLD if no title block is found, or if its words read below 70% confidence.
   - Paint the boxes, then OCR the painted page again.
   - HOLD if any identity is read back.

   Proof: `_shared/scan_redact.check.ts`, 4 tests with the real engine (eng+ara) on a synthetic ZZ DEMO scan turned
   0.6 degrees and speckled.
   - The title block is more than 99% black. The rooms, the 6000 dimension and the legend are under 20% black.
   - A second OCR reads OFFICE, MEETING, LEGEND, SMOKE DETECTOR and SOCKET, and no identity.
   - A title block speckled at 6% reads at 62% confidence and is held as `title_block_low_confidence`. The clean one
     reads at 83%.
   - A sheet with no title block is held.
   - The worker's own `scanDrawing`, with storage and SQL replaced by a recorder, uploads one page under
     `redacted/<uuid>/`, records one `complete` run naming it, and publishes nothing for a held page.
   - `_shared/scan_redact.test.ts` holds the decisions: an identity read back holds the page, a seed read back holds it.

   Image is **P** because a camera PHOTO of a sheet (perspective, glare) is not tested; the tests cover flat sheet
   rasters. The live path also needs `scripts/sql/a_scanned_drawing_is_queued_for_ocr_redaction.sql` applied (the
   queue reason). Until then the queue insert is refused and the drawing stays held, which is fail closed. Pinned by
   `scripts/checks/a_scanned_drawing_is_redacted_by_ocr_or_held.test.mjs`.

Evidence (AFTER):
- **CAD drawn for suppliers**: `_shared/cad_render.ts` draws model space from the entities (DXF, binary DXF, and a
  DWG through `dwgToDxf`). The title-block INSERT or layer becomes one black box. Paper space, embedded images, xref
  paths, header variables, layer and block names are never drawn. Every TEXT, MTEXT, ATTRIB and dimension is checked
  against the file's own identity terms, the customer's seed terms, and the contact and label patterns. A label takes
  its value with it. Then the drawn words are re-scanned. Proof: `_shared/cad_render.test.ts` (10 tests: content
  drawn, identity not, the title region all-black pixels, less than 35% of the page black, paper space skipped, held
  when too dense).
- **Wiring**: `drawing_redact/index.ts` `mode:'cad'` → `_shared/drawing_redact_page.ts` `cadPage`. `customer_api`
  `redactCad` runs on `analyze_drawing` and on `analyze_document`, and `cad_convert` is no longer called. For a DWG past
  the edge, `scripts/cad_read_worker.ts` `supplierDrawing` draws it with no ceiling, records the run and returns the
  page through `cad_read_status`, and the portal adopts it (`src/components/me/NewRequest.tsx` `pollCad`). Pinned by
  `scripts/checks/a_cad_drawing_reaches_a_supplier_drawn_without_its_identity.test.mjs`.
- **DWG drawn from real files**: LibreDWG's `sample_2000`, `example_2018` and `example_r14` were read and drawn locally
  (197 to 71,448 segments; `example_2018` inserts a block at 3,256×, so its zoom-extents page is dominated by that
  block, as AutoCAD's would be). `dwg_samples.check.ts` still passes on all nine real DWGs after the `dwgToDxf` change.
  It was run locally with the pinned wasm served from the npm package, because jsDelivr is blocked here.
- **Counts**: `doc_read/cad.ts` no longer counts legend samples. An INSERT under a LEGEND, KEY or SYMBOLS heading, with
  its description beside it, is set aside and named in the notes, with the Arabic in `src/lib/boqNotes.ts`. Proof:
  `drawing_boq/every_drawing_format.test.ts` gives SD 7 and SKT 5 for ASCII DXF, binary DXF and DWG; FD-1 7, WC-1 5 and
  FCU 3 for one PDF sheet; the same for the 3-sheet set, where a WC drawn on two plans of the same floor counts 5,
  not 10; and 7 and 3 for the image.
- **BOQ PDF EN+AR per format**: `every_drawing_format.test.ts`, through settleLines, redactBoq, inboxBoq,
  inquiryDocument and renderPdf, then read back. No identity string appears in the BOQ, the English PDF text or the
  Arabic document.
- **PDF redaction, pixel by pixel**: `drawing_redact_page.check.ts`. Every identity run is 100% black, every content
  run is under 50% black, and the JPEG has no APP1 segment and contains no identity or `/Info` metadata bytes. Scans
  and photos are held. The stored path is `redacted/<uuid>/page`, with nothing from the file name or the customer.
- **Signer provenance**: `_shared/drawing_pages.ts` `recordedPaths`. A `redacted/…` page must be named in a
  non-held run's `output_paths`. A `drawings/redacted/<tag>/…` page must belong to a registered E2E run
  (`rehearsal_window`). A failed lookup refuses every page. Proof: `drawing_pages.test.ts` (10 tests) and
  `scripts/checks/only_a_redacted_drawing_page_is_ever_signed.test.mjs`. Production, read-only: 0 stored paths lack
  provenance today, so no live inquiry loses a page.
- **Fail-closed bookkeeping**: `drawing_redact` `publish()` removes uploads whose run could not be recorded. The model
  path reads `llm_hold.modelHeld` first and records `held_model_off_no_deterministic_path` per page. Every skipped page
  now names its reason. `customer_api` `recordHeld` logs a failed hold insert instead of swallowing it. The CAD worker
  raises `cad_read_worker:job_failed` through `fn_it_engineer_finding_upsert` after the third attempt.
- **Nightly**: `.github/workflows/nightly-journey.yml` now walks the three drawing e2e scripts.

## Independent review of #967 (24 Sep 2026): three leaks, fixed and proved

The reviewer ran our own code on crafted inputs and got identity onto a supplier's page. Each case is now a
test, and each guard was broken once locally to confirm its test fails.

1. **Parties no rule recognised were drawn** (CAD). The inputs were:
   - an ATTRIB tagged `CLIENT_NAME` in block `ISO_A1`;
   - the bare firm names "ZZ ORBIT ENGINEERING" and "ORBIT HOLDINGS";
   - a dimension override "BY ZZ ORBIT";
   - "DM LIC 123456";
   - the customer's name letter-spaced, and split one letter per TEXT.

   The fixes are in `_shared/drawing_text_policy.ts`:
   - The default is now **withhold**. A word is drawn only if it reads as drawing content: numbers,
     dimensions, codes, or the trade's vocabulary.
   - A company word, a licence/plot/Makani/DM/TRN number or a party tag is withheld on sight.
   - Every attribute of an INSERT that carries any party-like tag is withheld.
   - Runs on one line are joined and squashed, then matched against the seeds, exactly and with an edit
     distance of up to 2.
   - The re-read of what is drawn now checks the drawn lines as they stand. The old re-read asked the same
     question as the selection and could never fail.

   Proof: `cad_render.test.ts`: every case is withheld, and OFFICE 101, MEETING ROOM 102, CORRIDOR and 6000 are
   drawn. `scan_redact.check.ts` OCRs the rendered PIXELS of that drawing: the rooms are readable and no party is.
2. **A title layer spanning the sheet had its linework drawn.** Nothing on a title layer is drawn now.
   Everything inside its border is blacked out. A title layer that is most of the sheet even inside its border is
   held (`title_unbounded`). Proof: `cad_render.test.ts`. The logo adds no pixel outside the box, the box is
   solid black, no border line is drawn, and a crossing title layer is held.
3. **A firm printed left of a scan's title column was published.** The fixes:
   - The title strip extends to the ruled box's edge (long vertical runs in the raster).
   - A word read below 60% confidence right beside the strip holds the page.
   - Company words, licence numbers and the title block's own names (tokenised) are boxed page-wide.
   - The re-read matches seeds fuzzily.

   Proof: `scan_redact.check.ts`, the review case. It publishes with the firm covered (15 boxes), and a second
   OCR reads neither ORBIT nor ENGINEERING.

The review also found these, now fixed:
- **Legend window.** It is bounded at 1.5 m × 3 m in real units. A sample needs a legend-style description and
  must stand in the legend's column. Test: five detectors beside CORRIDOR tags, plus one 5 m down beside
  "SD - NORTH WALL", are all counted.
- **Edge render cap.** It is now 120k segments, and customer_api queues a denser drawing to the CAD worker.
- **Nightly reporting.** The drawing journeys now run BEFORE the nightly report, and their results reach the
  sales engineer as journey `f-drawings/...`.
- **Demo exemption.** A demo page is signed only while its rehearsal window is open, or for the founder's
  standing demo.

## Second independent review of #967 (25 Sep 2026): fail closed

The second review found identity still reaching a supplier's page, from layouts the rules did not anticipate.
The lesson it drew: a rule that recognises identity keeps losing to new layouts. So the posture is now **fail
closed**. Text that cannot be positively read and cleared is withheld, or the page is held. Over-holding is
accepted; a leak is not. Every probe in the review's evidence (`cad_attack.ts`, `cad2.ts`, `fuzzy.ts`,
`legend.ts`, `over.ts`, `title.ts`, `scan.ts`) is now a test case.

**Blocking, fixed:**
1. **Glyph-per-TEXT sheets** (CAD). A PDF converted to DWG drew "CLIENT: ZZ OMEGA", "TEL 04 123 4567" and
   "DWG NO E-101", and the customer's name was drawn rotated, stacked, or spaced three heights apart.
   - A sheet with more than 20 single-character TEXTs, or more than 30% of its texts single characters (and at
     least 4), is now **held** as `glyph_per_text`. It is never reassembled.
   - Runs are now grouped along their own baseline and angle, not by y alone.
   - Each line is judged spaced by the full policy, and abutting by every identity rule.
   - Two lines stacked within 2.4 heights are also joined, so a phone or an e-mail split over two lines is read whole.
   - Tests (`cad_render.test.ts`): 9 glyph cases are held; a 20-bubble structural grid is not.
2. **Short words passed** ("DAR", "WSP", "ZZ" + "ORB" + "IT", "<> BY DAR"). A word of 3 letters or fewer now passes
   only from a closed list of codes (`_shared/drawing_vocabulary.ts` `CODES`). Tests: 42 of the review's cases on
   an ordinary plan. None is drawn and every room is still drawn.
3. **Rotated and unknown text in scans** (`_shared/scan_redact.ts`):
   - OCR runs at 0, 90, 180 and 270 degrees. The language data has no orientation model, so every quarter turn is
     read.
   - Every line, at any orientation, whose read words are not drawing content is boxed.
   - A reading is set aside only when another orientation reads the same place at least 10 points better.
   - The painted page is read all four ways again.
   - Text-like ink that no read word covers **holds** the page (`unread_ink`).
   - Tests: `scan_redact.test.ts`, 5 new decision tests. `scan_redact.check.ts` runs the real engine on the
     review's six body cases. Each is held, or published unreadable at all four orientations.

**Should-fix, fixed:**
4. **Seed matching.**
   - Matching is on whole tokens (adjacent tokens may run together) after a transliteration fold, so "RASHEED
     KARIM" is "Rashid Kareem".
   - It allows 1 edit at 5 letters and 2 from 6 letters. Two edits also need the same first and last letter.
   - A seed word that is a trade word never matches alone.
   - Test: `drawing_text_policy.test.ts`. All of fuzzy.ts's 27 spellings are caught, and 70 drawing phrases (its 68 and 2 more)
     match none of the 6 customers' seeds.
5. **Over-withholding.** The vocabulary gained rooms, fixtures, MEP terms and instruction phrases. "CONTRACTOR TO
   VERIFY" is an instruction, not a label. `cadIdentityTerms` no longer turns a trade-only view title ("LIGHTING
   LAYOUT", "GROUND FLOOR", "ELECTRICAL WORKS") into a seed. Test: all 49 labels from over.ts plus 4 more are drawn
   beside a title block that prints those titles.
6. **Legend.** The window walks down the legend's column while its description rows continue: the first row within
   1.5 m, each next row within 1.2 m. Test: a 10-row legend at 400 mm and at 600 mm pitch. All 10 samples are set
   aside and the plan counts 4 of each.
7. **Border as LINEs.** A title-layer border drawn as four LINEs, or as loose segments along the outline, is a
   border and is no longer held as `title_unbounded`. A cross through the layer is still held.
- **Nit, phone forms.** `ID_TEXT` now reads "(04) 123-4567", "04.123.4567", "050 1234 567" and "0 5 0 1 2 3 4 5 6 7".

**Broken once to see each fail:** 15 guards were each broken locally, and each broke at least one of the tests
above. They are glyph hold, closed short list, baseline groups, stacked lines, transliteration fold, trade-word
seeds, view-title seeds, legend walk, border outline, phone forms, four orientations, unknown-word boxing,
unread-ink hold, standing readings and the `@` rule.

**Cost:** a scanned page is now OCR'd eight times, about 60 s for the ZZ page. `SCAN_JOB_MS` is 30 minutes (up to
20 pages) and the worker workflow's timeout is 75.

## Still not done, and why

- **Scanned PDF and photo redaction**: built in the second commit (note 5). It is not live until the queue-reason
  SQL is applied and deployed. Camera photos with perspective are untested. Since the second review, text OCR
  cannot read is held, not passed. The residual risk is text OCR misreads as ordinary content, at every orientation
  and with confidence high enough to count as read. The re-read uses the same engine, so that risk remains, and it
  is stated here rather than hidden. More scans will be held than before; that is the accepted cost.
- **Revit (RVT)**: no free library reads Revit geometry or schedules; the format is closed. What is certain is read
  (version, family or project, workshared, the embedded preview), and the customer is asked for an IFC export in
  English and Arabic. IFC is then read fully. No paid Autodesk service is used (instruction 696).
- **DGN**: V7 and V8 are recognised by their bytes and the customer is asked for DWG, DXF or PDF. A V7 element reader
  (GDAL libdgn, MIT) is possible and not built, per instruction 701's order of work.
- **IFC BOQ PDF**: the IFC take-off is gated but not yet rendered in a test.
- **Graphic-only schedule tables** in PDFs are read by OCR only when the customer's browser sends them. Unread cells
  are flagged, never guessed (`drawing_set.ts`).
- **Live sends (²)** turn S only after deploy and a passing nightly.

## Drawing bench, 19 Oct 2026 (founder ledger 31, 580, 1177)

`supabase/functions/drawing_boq/drawing_bench.test.ts` scores every format against a hand-written key,
`drawing_boq/fixtures/bench_truth.json` (the key was written before the first run). Fixtures are in
`drawing_boq/bench.fixtures.ts`. They are a fit-out plan drawn the way AutoCAD writes it, with dynamic-block doors,
a MINSERT window array, sockets nested in a room block, a legend, and identity in a paper-space title block, MTEXT,
XDATA, DWGPROPS and header variables. The same job is also drawn as a vector PDF and as a BOQ in xlsx, PDF and image
form. The real sample sheet (`fixtures/harrogate_court_…png`) is used as a PNG, as a scanned PDF and as a phone photo.

| case | format before → after | count before → after | leaks before → after |
|---|---|---|---|
| DXF ascii | read | 0/4 → 4/4 | 3 → 0 |
| DXF binary | read | 0/4 → 4/4 | 3 → 0 |
| PDF vector | read | 0/4 → 4/4 | 0 → 0 |
| BOQ xlsx | read | 4/4 → 4/4 | 0 → 0 |
| BOQ pdf | read, 0 lines → read | 0/4 → 4/4 | 0 → 0 |
| BOQ image (OCR) | read, 0 lines → read | 0/4 → 3/4 (door line's text misread "210C") | 0 → 0 |
| image PNG (real sheet) | read | 1/7 → 4/7, total error 35 → 6 | 0 → 0 |
| PDF scanned (OCR) | read | 0/7 → 3/7, total error ~230 → 33 | 0 → 0 |
| photo JPG (rotated 1.5°) | read | 0/7 → 1/7 | 0 → 0 |

What changed: `doc_read/cad.ts` resolves dynamic `*U` blocks through `AcDbBlockRepBTag`, counts MINSERT arrays,
counts blocks nested in blocks once per placement, and recognises legend samples described in plain words, with
"beside" measured from the symbol's right edge. `redactDxf` rewrites every XRECORD string, which is where DWGPROPS
keeps author and job number. `cad_identity` ends a label's value at an MTEXT paragraph break, so the sockets note is
no longer treated as part of the site name. `drawing_set.ts` reads W/WN windows and SKT sockets and skips legend
sample tags. `boq_from_text.ts` reads "[item] description unit qty" rows and the unit "nr". `boq_from_document.rowsOf`
rebuilds OCR cells into rows. `symbol_count.ts` scores the inside of each symbol as well as its ring, fixes one plan
scale per sheet, turns directional symbols, crops each template to its own row, and drops JPEG specks.

Still open: raster counts on a rotated or blurred phone photo, where OCR found 4 of the 7 legend rows and template
matching does not handle rotation. Smoke detectors are over-counted on JPEG scans. Raster counts stay estimates the
customer confirms (`to_confirm`). Real DWG files were not re-measured here: `dwg_samples.check.ts` needs the network,
and dynamic-block resolution depends on LibreDWG carrying the BLOCK_RECORD XDATA, which has not been measured.
