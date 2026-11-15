AUDITOR B (customer drawings: R1, R3, R4). Phase 1: I only read code and ran things offline. No calls to production edge functions, no model calls, no writes; the only production access was SELECTs on ai_cost_log and drawing_redaction_runs. The worktree has been removed. Folder: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/anon/B_drawings/ (gen/ holds the drivers, fixtures/ the inputs, out_*/ the outputs, logs/ the logs).

## 1. Leaks and gaps (most harmful first)

**PROVED BY RUNNING**

- **L1 (R1/R3): the CAD file suppliers download keeps the owner's name and area.** In `_shared/cad_file_redact.ts`, `redactCadFile` and `verifyCadRedaction` only remove things on a deny-list. My probe DXF (`gen/cad_probe.ts`) had model-space TEXT "MR ZZ DEMO OWNER", "AL BARSHA 2", "UNIT 1204" and "373 1234". The verifier passed it (`verify true`) and all four strings are still in `fixtures/pool_probe_anonymised.dxf`. With the owner as the account name, "AL BARSHA 2", "UNIT 1204" and "373 1234" are still in the file. The preview picture of the same drawing (`cad_render`, allow-list) withheld the name and the area. Suppliers get this file as `redacted/<uuid>/page_drawing.dxf`, attached by `lib/drawings.ts:128-131 redactCad→redactFile` whenever the preview is complete. **Smallest fix:** blank every TEXT, MTEXT and ATTRIB value that fails `drawing_text_policy.isDrawingContent`, the same rule the preview uses, or require the file's texts to be a subset of the preview's `drawn_texts`.

- **L2 (R1): a key plan or map pasted into a PDF as a picture reaches suppliers.** Text inside an embedded raster image is never read. `anonymise.titleBlockBoxes` (d) only boxes images up to 3% of the sheet, and only outside the title strip. On B1, a key-plan image covering about 15% of the sheet came through readable: "Villa 15", "Al Barsha 2 - 23B Street", "Umm Suqeim Rd" and a red location pin. This happened in both the JPEG preview and the vector-PDF output. The vector output was held for unrelated reasons (see G1); if it had been released it would carry the same map. **Fix:** hold, or OCR, any page with an image larger than logo size outside the strip.

- **L3 (R1): the area name survives when it is not one of the customer's own seed words.** I ran B1 again with a neutral file name ("POOL-101.pdf") and an account name that is not the owner's. Two things came through: the vertical site-plan label "AL BARSHA 2", and the scale-bar note "(Survey by ZZ Demo Surveyors, Al Barsha 2)". Cause: `titleBlockBoxes` uses the title strip's phrases whole ("villa 15 al barsha 2 dubai"), never split into words. `scan_redact.ts` does split them (`seedTerms({extra: stripSeeds})`). When the file name happened to contain "Barsha", both were covered. **Fix:** in `titleBlockBoxes`, add `seedTerms({extra: setSeeds})` the way `scan_redact` does, and add "surveyor(s)" to the firm words.
  - The same split is missing from the CAD-preview and scan-OCR allow-list. `isDrawingContent` returns true for "VILLA 15", "UNIT 1204", "373 1234" and "12345 67890" (a bare Makani number). The CAD preview drew "UNIT 1204" and "373 1234".

- **L4 (losing quoting information): a diagonal watermark blacks out about 28% of the sheet.** The box drawn around the rotated watermark run is 66% × 42% of the page. On B1 it destroyed Section A-A (depths, wall and raft specification), the site plan and the scale bar. The page is still published.
  - The CAD preview also withheld "SHALLOW END FFL -1.20" and "DEEP END FFL -1.80". These are levels a pool contractor needs, but the words are missing from the vocabulary.

- **G1 (R3 works; the vector file never gets out): the anonymised vector PDF was held on all three of my sheets, by false positives.**
  - The embedded font's licence URL (`dejavu.sourceforge.net`) is read as "url / email".
  - Content-stream coordinates containing "971" (e.g. "1129.323 17.00787") are read as a UAE phone number (`identity_text.PHONE_UAE_INTL`).
  - Any CAD-exported PDF with embedded fonts will probably be held the same way, so suppliers get only the 2600 px JPEG. The text-cut output itself was good: /Info, XMP, annotations and title-strip paths (vector logo, QR, stamp, signature) were all gone, and the file name is neutral.

- **G2 (fail-closed, but suppliers get no drawing): scanned A1 sheets are always held by the OCR route.**
  - Both my noisy scan and a clean 2600 px raster of B1 were held: title_block_low_confidence, 58 and 59 against the 70 needed.
  - A PDF whose streams use the ASCII85+Flate filter chain reads as 0 words (`pdf_text_positions.decodeStream` only handles Flate). It is then treated as a scan.

**INFERRED BY READING**

- **I1 (R1): for scans and photos, the vision models alone decide what is published.** On a scan or photo, a vision model names the regions to black out, then a second model of another family checks the result. If the AI models are switched on (`modelHeld` false), the page is published when that check says "clean" (`drawing_redact/index.ts:442-555`). JPG/PNG photos are accepted here: `drawing_format.ts` does not refuse them, and NewRequest sends images to `analyze_drawing`. The code itself adds only the AI's boxes with a 3% margin. I ran that code with a stand-in "title strip only" answer (`B2 output…pdf`): area, villa, street, watermark firm name, rotated edge text, Arabic owner line and the contact paragraph all remain. So the second model is the only thing that catches them. Its prompt does name villa and area, and every failure counts as "not clean".

- **I2:** `drawing_boq` sends the original, unredacted drawing images and the PDF text layer to OpenRouter models (`openai/gpt-6-luna-pro`). That is not a supplier leak, but it is a third-party processor seeing the title block.

- **I3:** A drawing sent by WhatsApp writes `drawing_redacted_paths` straight onto an already-open inquiry (`wa_inbound/customer_files.ts:115`). The PDF and scan branches never call `drawing_redact`; only CAD does, and that goes through L1's file path only via the portal. The WhatsApp CAD branch writes the preview only.

## 2. What holds
- **Title block on a vector PDF:** fully covered, including vector logo, monogram, QR, stamp, signature, revision table with names, Arabic in the block, and the vertical edge text.
- **Patterns outside the strip:** Arabic owner line, contact paragraph, site-plan "VILLA 15" and "STREET 23B" were covered.
- **The JPEG preview:** carries no text layer and no EXIF or metadata.
- **Signing and gating:**
  - Only paths a recorded redaction run produced are signed (`drawing_pages.ts`).
  - All-or-nothing across a multi-sheet set (`resolveRedactedPaths`, `drawingHandoff`).
  - A ZIP is refused with advice.
  - The BOQ is re-gated at Send from the stored file (`drawing_send_gate.ts`); its seeds are split into words, so "barsha" is caught there.
  - File names reaching suppliers are neutral: `Job_<n>_drawing_pNN.jpg`.
- **Tests and checks I ran (all offline):**
  - Gate step `redact-page`: 6/6 pass. Gate step `scan-redact`: 7/7 pass (14m49s).
  - 16 Deno unit-test files: 99 pass.
  - `scripts/checks` drawing checks: 27/29 pass. The 2 failures are the production-only half of `only_a_redacted_drawing_page_is_ever_signed`, which needs a credential (HTTP 401), not a defect.
  - Gate step `dwg`: not run. It needs raw.githubusercontent.com.
- **Gaps in the test fixtures** (`zz_demo_drawings.fixtures.ts`): no case for area or community name, a key-plan raster, a watermark, a vector logo, a QR code, an owner name that differs from the account name, model-space location text in a DXF, an embedded-font PDF in `pdf_vector_redact`, or an ASCII85 stream. The raster in the redact-page gate is synthetic grey stripes, not a real pdf.js render.

## 3. Is each document a supplier receives in our template?
| What | How it reaches the supplier | Template? |
|---|---|---|
| Redacted page JPEG(s) | Signed link in the portal | Pass-through image |
| Anonymised vector PDF or DXF | Signed link | Pass-through, redacted |
| BOQ | Inline in the portal | — |
| `Job_X_BOQ.csv` | Download | Not a PDF in our template (ruling 1672) |
| Inquiry PDF (`supplier_api inquiry_pdf`) | Download | Template |

No drawing travels by e-mail or WhatsApp to suppliers.

## 4. Phase-2 plan and the PDFs for you
Files in /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/anon/pdfs/:
- `B1 input - pool drawing with full title block.pdf`
- `B1 output - as a supplier would receive it (nothing stubbed, no model; the vector PDF copy was held, so this page is all).pdf`
- `B1b output - same sheet without watermark, neutral file name (nothing stubbed) - area and surveyor survive.pdf`
- `B2 input - scanned pool sheet.pdf`
- `B2 output - scan via the vision-model path with a STUBBED lazy model answer (title strip only) - what publishes if find and verify both pass it.pdf`
- There is no B3 (see section 5).

Live run, one at a time, ZZ DEMO only:
1. **Inputs:** upload B1, then the B1b variant (`fixtures/b1b_nowm.pdf` renamed POOL-101.pdf), then `fixtures/pool_probe.dxf`, then B2.
2. **Route:** through the portal composer, or a `--drawing <file>` flag added to `scripts/e2e/drawing_reaches_suppliers.mjs`. That script and `cad_identity_reaches_no_supplier.mjs` already walk this route but take no custom input.
3. **Capture:** the matched ZZ supplier's inbox `drawing_pages` files (download each JPEG, PDF and DXF), plus the `inquiry_pdf`. Do it in a clean browser context, because the harness intercepts `/functions/v1` calls.
4. **Cost** (from `ai_cost_log`, last 75 days):

   | Call | Model | Average | Highest |
   |---|---|---|---|
   | `drawing_boq` | gpt-6-luna-pro | USD 0.009 | USD 0.095 |
   | `drawing_redact` find | — | USD 0.0012 per sheet | — |
   | `drawing_redact_verify` | sonnet-5.5 | USD 0.0087 | — |

   A vector PDF uses no redaction model. A scan or photo costs about USD 0.01–0.03 per sheet. B1 + B1b + DXF + B2 come to about USD 0.05–0.25 in total, plus the confirm calls. That fits the USD 0.60.
5. **Judging it:** run the sales engineer's sufficiency reading (`drawing_boq`; prompt at `drawing_boq/index.ts:96`) once on B1 and compare against the estimator list in section 5.

## 5. Sufficiency (R4), and what I could not determine
- **R4 has no explicit "is this enough to quote?" step.** `drawing_boq` returns `missing_info` and `assumptions`, written freely by the model. The supplier sees them as notes (`RfqParts.tsx:137`). The customer sees them only when no lines were read (`NewRequest.tsx:381`). The intake asks only "confirm our counts" (`boq_open_lines`). Nothing checks a drawing against what each trade needs.
- **For a pool, an estimator needs:** pool length, width and depth profile, plus volume; shell structure (RC or shotcrete, wall and raft thickness, reinforcement); waterproofing; interior finish and coping; filtration (pump, filter, turnover rate); heating; chlorination; lights, skimmers, inlets, main drain; balance tank and overflow; plant-room location and pipe runs; electrical supply and bonding; soil report and dewatering; site access and excavation spoil route; and the timeline.
- **The real published sample (B3) could not be obtained:**
  - The egress proxy refused the downloads with 403 CONNECT. URLs tried: swf-wc.usace.army.mil "Sample Pool Design.pdf", and uca.edu/procurement/files/2026/01/T-Rec-Swimming-Pool-Drawings.pdf.
  - WebFetch failed too: ENOTFOUND, meaning the host is not allowed in this session.
  - Those hosts would have to be allowed in the session's network settings. I used my own synthetic B1 instead.
- **Not determined:**
  - What pdf.js in the customer's browser actually rasterises; I used pdftoppm in its place.
  - The DWG route; the `dwg` gate step needs a host that is not allowed.
  - Whether the live verify model would refuse the B2 stand-in page.
  - Production volume: only 4 redaction runs in the last 60 days, none published.
