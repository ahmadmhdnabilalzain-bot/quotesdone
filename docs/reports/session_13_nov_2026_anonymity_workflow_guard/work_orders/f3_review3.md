# Brief: f3_review3 — third independent review of the drawings fix
Read `SP/briefs/COMMON.md` first. You are an INDEPENDENT reviewer; you wrote none of this. No local database is needed.
Worktree: /tmp/claude-0/review-f3-3 from `origin/sales_engineer-a-drawing-reaches-a-supplier-with-no-owner-no-area-no-map`
(head 1f08602b7). Its text sibling will be on main before it:
`origin/sales_engineer-anonymity-text-and-doors-released-together` (head c3ac7bdbd): ALSO make a throwaway merge of the
two (/tmp/claude-0/review-f3-3-merged) and run the drawing suites there, because that is the tree that will be live.
Read: `SP/anon/FIX_COMMON.md` (the founder's ruling 1683: "all the project details, the customer details that are there
in those drawings are removed"; the emirate may stay); `SP/anon/REPORT_B.md`; REVIEW.md "ANONYMITY F3 DRAWINGS 1" and
"2" (the second review: 10 of 19 identity cases published; items 0–9); the work order `SP/briefs/f3_finish.md`; the
author's account `SP/handbacks/F3_AUTHOR.md`; the driver and logs in `SP/f3fin/`; the outputs in
`SP/for_founder_drawings/round3/`; the corpus in `SP/anon/B_drawings/`.
The design: nothing drawn reaches a supplier until a vision model of ANOTHER family has read the final pixels (tiled so
6 pt text is at least 12 px high; each view carries a random mark the answer must repeat); CAD strings are classified
by one text-model call; code is the floor when the model is lazy; a page with text code cannot read and no model claim
is held. No paid call: every model is a stub.
VERIFY:
1. Items 0–9 at the head: DONE-AND-PROVEN / NOT, by running each named test and reading what it really asserts.
2. LOOK at the outputs yourself: open at least 12 of the "Round 3 - *.png" previews (the Read tool shows images) and
   the text of the matching PDFs (pdftotext or the repo's own reader): for each, list ANY owner, project, plot, area,
   consultant, contractor, phone, e-mail, logo text, key plan, north-arrow location note or map fragment still visible.
   The stub tables are claims; the pictures are the evidence.
3. Re-run the three stubs (FAITHFUL / LAZY / ALWAYS-CLEAN) over the 22 identity sheets and the 23 ordinary sheets with
   the author's driver, then with a FOURTH stub of your own: COPYCAT (repeats the mark correctly, reports nothing): what
   is released? Every sheet whose identity code cannot find must be HELD; a release with identity is a FIX. And a FIFTH:
   OVER-EAGER (boxes everything it sees, including dimensions and the title block's scale and sheet number): what
   survives for a supplier to price from (the over-redaction side)?
4. 12 NEW identity sheets of your own (generate small PDFs/PNGs with the repo's fixture generator in
   `SP/anon/B_drawings/gen` or pdf-lib if present in node_modules; keep them small): owner in a rotated title block; a
   project name as a watermark; a plot number in a dimension-like string; an Arabic owner; a consultant logo as an
   image; a location plan inset; text as outlines; white text on white; a tiny 4 pt note; an XREF/block name; a
   hyperlink annotation; PDF metadata (Title/Author/Subject/Keywords, XMP). For each × FAITHFUL / LAZY / COPYCAT:
   released clean / held / RELEASED WITH IDENTITY.
5. 12 NEW ordinary sheets: false holds and legitimate text removed (dimensions, levels, grid letters, room names,
   material notes, standards, scale, sheet number, revision table). Must be 0 or named.
6. The reading mark: can a view's mark leak into what the supplier receives (the band must not be in the released file
   or preview)? Is the mark compared exactly, per view, per run (no reuse)? What if the model returns another view's mark?
7. The released FILE: metadata, annotations, embedded files, optional content (layers), JavaScript, incremental-save
   history (earlier revisions recoverable from the bytes?), fonts' names carrying the firm's name, XMP: read the bytes
   of three released PDFs.
8. Cost and latency: tiles per sheet for A4/A3/A1/A0 and the price per look the code computes (the author says an A1
   look is USD 0.0844); the budget hold: what a customer with a 20-sheet A1 set experiences and pays for nothing; what
   the supplier and customer are TOLD when a page is held (exact texts), and who can release a held page (nobody? then
   say what the customer can do next).
9. The quote-reading regression the author fixed (colour/color in drawing_vocabulary): run `quote_review_corpus.test.ts`
   and the drawing vocabulary tests on the head AND on the merged tree.
10. Suites on the merged tree: deno `_shared`, drawing_redact, drawing_boq, customer_api, wa_inbound, supplier_api; tsc
    (symlink node_modules as COMMON.md says); the node checks on drawings (offline halves).
11. The deploy list from the import graph of the merged tree, and what is still NOT wired (customer_api
    `verify_released_file`, the customer's confirm step, `seed_terms` on the CAD/file and WhatsApp routes): for each,
    what a real customer and supplier experience on Monday if it ships as is (the author says every vector PDF file is
    then held and only previews go: confirm by reading the code path end to end).
VERDICT: MERGE or FIX (numbered: file:line, the sheet, the smallest fix), most harmful first; what must be wired before
it is useful and what can follow; under 55 lines. Append the full review to `SP/show/REVIEW.md` under "ANONYMITY F3
DRAWINGS 3". Progress notes: `SP/progress/f3_review3.md`. Remove your worktrees and generated sheets at the end (keep
your 24 new sheets' small sources in `SP/f3rev3/`).
