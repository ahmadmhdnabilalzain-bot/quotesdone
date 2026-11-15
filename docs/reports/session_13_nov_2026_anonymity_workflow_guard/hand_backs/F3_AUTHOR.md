F3_AUTHOR hand-back (f3_finish). Branch sales_engineer-a-drawing-reaches-a-supplier-with-no-owner-no-area-no-map, head 1f08602b7 (pushed; 3 new commits on 95a9feec9: 11a4208f4, 6201d12e8, 1f08602b7). Worktree removed.
ITEMS 0-9 (each checked by running its test; R = from code, LOCAL = run offline)
0 DONE  tiles: drawing_pixel_gate.ts planTiles; test the_model_reads_every_tile.test.ts 'the tiling' (6 pt = 12 px in every view, band included). NEW: a READING MARK. Each view gets a random 6-digit number, 14 px tall, in a band under the drawing (drawing_redact_page.ts:85 withMarkBand, drawing_pixel_gate.ts:63 markCells/:74 newMark). An answer without it is held (drawing_pixel_gate.ts:246). Tile mode refuses a call without a mark (index.ts:399). Test: drawing_redact/a_view_not_read_is_no_answer.test.ts. A0 is now 10x4; A1 is USD 0.0844 a look.
1 DONE  server page count, shape, density and ink before any model call: index.ts verify_file; test 'verify_file: the server counts...'
2 DONE  the three gate rules: every_cad_string_is_read_once_and_whole.test.ts 'the gate rules HOLD'; first-look rule = fileMayBeShared ('a FILE is released only when...')
3 DONE  block rename: 'a marked BLOCK name is renamed and the file is still released' (+ layer-case test)
4 DONE  union, feature-detected (drawing_location.ts:22-33); no copied file. Merge order: either. LOCAL proof: a throwaway merge with origin/...-in-text was clean and 143/0 passed, including the merge-only test at a_drawing_reaches...test.ts:252.
5 DONE  chunked, none truncated: 'a long string is read in overlapping pieces to its END'
6 DONE  false holds: 0 of 23 ordinary sheets (20 o + 3 q) with FAITHFUL or LAZY. Planted quoting strings: 23 sheets x 4 outputs all survive (SP/f3fin/o20_quoting2.txt)
7 DONE  v02 rows boxed in the band (anonymise.ts:486-500); the 3-stub run shows v02 clean
8 DONE  read once: 'READ ONCE...' tests (index.ts, lib/drawings.ts, wa_inbound)
9 DONE  stale comment fixed (index.ts:734); EMAIL_RE lookbehind only (drawing_boq/boq_from_text.ts:33)
NEW RULE (LAZY): pdf_text_positions flags runs in an undecodable font (TextRun.unread). drawing_code_floor.ts:33 unreadAreas and :47 unreadTextHold hold a page when code sees text it cannot read, the find model boxed nothing and the checker was clean on its first look. Wired on the model path (index.ts:758) and the manual path (:647). It flags v01 (7 areas) and v12 (1), and 0 on the 23 ordinary sheets, v00, v02 and the pool fixtures.
ALSO FIXED: quote_review_corpus.test.ts failed on this branch only. The branch had added colour/color to drawing_vocabulary, so "HP Color LaserJet" showed "LaserJet". Both words are removed (drawing_vocabulary.ts); "COLOUR BLUE MIX" is still kept on drawings.
THREE STUBS, LOCAL (SP/f3fin/run3.ts; logs run3_identity.txt, run3_ordinary.txt; FAITHFUL = tesseract reading of each view + the mark read from the JPEG, 609/609 marks legible)
case | faithful | lazy | always-clean   (pv = preview, f = released vector file)
v00 control, v02-v10, v13-v15, v18 (16 sheets) | pv clean, f RELEASED clean | pv clean, f RELEASED clean | pv HELD unread, f HELD unread
v01 outlined labels | pv clean, f HELD code | pv HELD unread_text_unclaimed | pv HELD unread
v11 2 pages, p2 no strip | p1+p2 clean, f HELD code | p1+p2 clean (floor + set seeds) | HELD unread
v12 Type3 | pv clean, f HELD code | pv HELD unread_text_unclaimed | HELD unread
v17 key plan over pool | pv clean, f HELD code | pv clean | HELD unread
=> FAITHFUL 21/21 identity sheets withheld or cleaned, 0 published with identity. LAZY: 0 with identity; the code floor covers 19 and code cannot claim v01 and v12, so those 2 are HELD. ALWAYS-CLEAN: nothing released (every view counted unread).
Ordinary (o00-o19, q1-q3): FAITHFUL 23/23 published, files released; LAZY the same; ALWAYS-CLEAN all held (as designed). The corpus is 21 identity sheets + v00, not 19.
Outputs: SP/for_founder_drawings/round3/ "Round 3 - <case>.png" (FAITHFUL preview) and ".pdf" (released file), 41 files, 3.4 MB.
LEGITIMATE DRAWING TEXT WRONGLY REMOVED: 0 (23 sheets x preview / vector PDF / CAD preview / CAD file).
TESTS, LOCAL: deno _shared + drawing_redact + customer_api + drawing_boq + wa_inbound: 2729 pass / 1 fail (catalogue_read, the known one) / 2 ignored. Node checks touching drawings: 7 files, 22/22 (two others need a production token, not run). tsc --noEmit exit 0. deno check drawing_redact/index.ts ok.
SQL TO APPLY: none (no scripts/sql in this branch).
DEPLOY, in order: drawing_redact first (the mark is made and checked inside it), then customer_api, wa_inbound, drawing_boq. Then every function whose import graph reaches a changed _shared file (deno info): accountant doc_extract inbound_email license_extract public_site quote_compare quote_extract resend_inbound reveal_invoice sales_engineer stripe_checkout stripe_confirm supplier_api supplier_catalog_ingest supplier_portal. The CAD worker script (scripts/cad_read_worker.ts) only calls mode 'gate', so it needs no change.
PORTAL / CUSTOMER SIDE STILL NEEDED (R)
- customer_api action verify_released_file does not exist. It should take a run_id plus the pending file's pages, which the browser renders with pdfRaster (annotations off) at pxNeeded density; drawing_redact verify_file then does the count, shape, density and ink checks. Until then every vector PDF file is held and its previews go.
- NewRequest's confirm step, so the customer sees the exact pages.
- seed_terms pass-through (R): the portal route sends setSeeds as floorSeeds (customer_api/actions/documents.ts:244). The CAD/file routes (lib/drawings.ts:118,144) send o.seeds; whether those include setSeeds is not checked. wa_inbound has no setSeeds.
UNSURE
- The mark proves a view was read, not that it was read well. A model that copies the digits and reports nothing is LAZY, and only the code floor plus the unread rule stop it.
- The unread rule will hold a real SHX-outlined sheet whose models name nothing at all (fail closed). It never fired on the 23 ordinary sheets.
- Scans and photos have no code floor, so LAZY rests on the models there.
- FAITHFUL is tesseract, not a vision model. A first run of my driver keyed its OCR cache on the first 400 KB of each bitmap and misreported v11 p2. That was fixed and everything was rerun; the tables above are from the rerun.
