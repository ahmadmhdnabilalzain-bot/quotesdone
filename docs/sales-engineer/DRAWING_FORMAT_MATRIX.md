# Drawing format matrix — what the sales engineer reads, counts, prices and shares

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
| DWG | S | S | S | S¹ | S | P² |
| DXF ascii | S | S | S | S¹ | S | P² |
| DXF binary | S | S | S | S¹ | S | P² |
| PDF vector | S | S | S | S¹ | S³ | P² |
| PDF scanned | P | P | P | P | S⁵ | P² |
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

## Still not done, and why

- **Scanned PDF and photo redaction**: built in the second commit (note 5). It is not live until the queue-reason
  SQL is applied and deployed. Camera photos with perspective are untested. A scan whose identity sits outside the
  title block in a form OCR misreads both times would pass. The re-read uses the same engine, so that residual risk
  remains, and it is stated here rather than hidden.
- **Revit (RVT)**: no free library reads Revit geometry or schedules; the format is closed. What is certain is read
  (version, family or project, workshared, the embedded preview), and the customer is asked for an IFC export in
  English and Arabic. IFC is then read fully. No paid Autodesk service is used (instruction 696).
- **DGN**: V7 and V8 are recognised by their bytes and the customer is asked for DWG, DXF or PDF. A V7 element reader
  (GDAL libdgn, MIT) is possible and not built, per instruction 701's order of work.
- **IFC BOQ PDF**: the IFC take-off is gated but not yet rendered in a test.
- **Graphic-only schedule tables** in PDFs are read by OCR only when the customer's browser sends them. Unread cells
  are flagged, never guessed (`drawing_set.ts`).
- **Live sends (²)** turn S only after deploy and a passing nightly.
