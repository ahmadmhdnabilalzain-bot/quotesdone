# rel_anon_review progress (second run, started 20:14 UTC 13 Nov)
- Step 0 done: worktree /tmp/claude-0/review-rel-anon at 1f450d57d (unchanged). NOTE: REVIEW.md already has a
  "ANONYMITY RELEASE (TEXT + DOORS) FINAL" section (lines 2837-2969) by an earlier run on the SAME head (verdict FIX 1-3,
  drivers in SP/relrev/). This run re-verifies independently with new probes; my drivers in SP/relanon/.
- Next: step 1 blockers.
- Step 1 done (relanon/s1.ts, s1b.ts): blocker row removed on every door; 2 spaces, 3 tabs, 3 NBSP, mixed, leading tab CLOSED;
  ONE tab and ONE NBSP LEAK at save/door/qa/redact/shared (inbox withholds). Same on origin/main (pre-existing). Drawing option OK.
- Next: step 2 over-redaction.
- Step 2 done (relanon/fresh60.ts, over.ts): fresh 60: 0 changed by anonymity code; brand generaliser (main, by design) 5,
  one wrong: "1.5 HP" -> "1.5 premium American brand" (pre-existing on main). 654 corpus x2 pairs (Falcon/Omar Haddad,
  Marina Glass Works/Grace Hill): only Falcon grey x2 + villas row; Grace Hill pair: "chiller"/"Chilled" WITHHELD at inbox
  (seed "hill" substring) - identical on main, pre-existing.
- Next: step 3 leaks (reuse relrev c3/amerged/p_l40/p_l60 which already point at /tmp/claude-0/review-rel-anon).
- Step 3 done (relanon/new30.ts, fix1.ts, chk.ts; a_out.json): C 46 -> 2 (Rashid, Falcolux); A 0/62 identity (old price
  "AED 32,816" in free text stays); p60 1 Cedre; p40 1 Khannour. My 31: 13 LEAK rows. NEW + FIX: (i) old supplier name w/o
  legal form (Noor Interiors / Blue Lagoon / Qasr Al Fan) - confirms prior FIX1; (ii) Arabic-digit and "dirhams" prices on
  BOQ + email (prior FIX2 confirmed); (iii) NEW: accessText site_location.ts PREMISES_NO leaves "-2290" of "Plot 681-2290"
  ("the site-2290"), "Villa 12-3" -> "the site-3". Known list: lower-case area, Arabic bare area المزهر, unlisted project,
  one-word Arabic name, free-text old price.
- Next: step 4 timing.
- Step 4 done: adversarial test ok 22 s; review_cpu_budget x3 while the adversarial test ran: 290/286/390 ms, pass.
- Next: step 5 suites (logs relanon/suite_*.txt).
- Step 6 done: local PG16 /tmp/pg-relanon:55501 full mirror (808 tables). Locks: CREATE OR REPLACE x2 = AccessShare on
  documents/inquiries/inquiry_matches/messages/quotes/transactions (+leads, supplier_capabilities), RowExclusive pg_proc toast;
  REVOKE x2 catalog only. Production bodies (SELECT pg_get_functiondef) = file minus intended changes only. Applied locally,
  seeded ZZ rows (relanon/seed.sql), PROBE OK (4 entries, 2 files). Revealed supplier still sees old "existing quote AED
  32,816.70" in title (pre-existing). Either order safe; deploy supplier_portal first (recommend is TS-only).
  Suites first run invalid (ran from functions dir; read perms) -> rerun from root in background (suite2_*.txt).
- Next: step 7 deploy list, step 5 rest (tsc, node checks).
- Step 7 done (relanon/graph.mjs): 22 functions (same list as the earlier run). Node checks 3/30/2(prod SELECT half)/5/155 pass.
- Next: wait suite2_* and tsc; step 8 texts; then write review.
- Step 8 texts gathered. Extra finding: residualScan substring seeds (anonymise.ts:212, pre-existing) now SURFACE to customers:
  Rami+"Ceramic", Tom Hall+"Hallway", Sara Ward+"Wardrobes", Grace Hill+"chiller" -> summary withheld, and NEW edit refusal
  'because of "rami"' (edit_summary.ts:31-36) / kept notice naming "rami". (relanon/held*.ts)
- Suites from root: customer_api 98/0, drawing_boq 99/0, inquiry_intake 120/0, supplier_api 275/0; tsc 0. _shared pending.
- Cluster /tmp/pg-relanon deleted; base worktree removed; draft review in relanon/REVIEW_APPEND.md (awaiting _shared).
- DONE: review appended to show/REVIEW.md; worktrees removed.
