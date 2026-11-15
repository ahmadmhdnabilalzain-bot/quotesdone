# Brief: rel_anon_fixcheck — independent check of the five fixes on the combined anonymity release
Read `SP/briefs/COMMON.md` first. You are an INDEPENDENT reviewer; the coordinating session wrote these five fixes, so
assume they are wrong until you have run them.
Worktree: /tmp/claude-0/review-rel-anon (create it at this exact path: the earlier reviewers' drivers import from it) from
`origin/sales_engineer-anonymity-text-and-doors-released-together`, head e2d78a0f3. The fix commit is the last one:
`git show HEAD` (8 files). Base before it: 1f450d57d.
Context: REVIEW.md sections "ANONYMITY RELEASE (TEXT + DOORS) FINAL" and "… second independent run" (two reviews of
1f450d57d, both: fix items 1–4 then MERGE; item 5 optional). Their drivers: `SP/relrev/` (new30.ts, c3.ts, amerged.ts,
p_l40.ts, p_l60.ts, corpus654.ts, fresh.ts, over.ts) and `SP/relanon/` (new30.ts, fix1.ts, fix4.ts, fresh60.ts, over.ts, s1.ts).
The five fixes: (1) `requestSeeds` also seeds the old supplier's name without its legal-form tail when 2+ words remain;
(2) quotation_gate money shapes read Arabic-Indic/Persian digits and "dirham(s)", a labelled figure also takes a trailing
currency; (3) identity_text: a TAB is a cell boundary: it ends a number and never joins one (`SEP_IN`); a single
no-break space is deliberately left as a space (the BOQ-row guard's design; say if you disagree, with rows); (4)
site_location PREMISES_NO takes a hyphenated or slashed number whole, Arabic too; (5) anonymise `seedRanges` loose scan: a
Latin name inside a longer word counts only at a lower-to-upper join or in an all-capitals word.
DO:
1. Re-run both reviewers' drivers on this head and compare with the numbers they reported on 1f450d57d: C 46 → 2;
   A 0 of 62; p60 1; p40 1; relrev/new30 and relanon/new30 row by row (which rows changed, each change right or wrong);
   fix1.ts and fix4.ts all closed; fresh 60 ×2: 0 changed; the 654 corpus ×2 name pairs: only the rows they named, and
   the "chiller" rows of the second reviewer now pass.
2. ATTACK each fix with 12 new inputs of your own (60 total), half that must be removed and half that must survive:
   (1) trade-named firms ("Steel Trading LLC" must not seed "steel"), three-word names, Arabic legal forms (ذ.م.م, ش.ذ.م.م),
   "Est.", "& Co"; (2) quantities in Arabic digits that are NOT money (٨٥ م٢, ٦٠×٦٠, ١٢ قطعة), "Dirham" as part of another
   word, "AED 120/m2", "120 dhs", a model number with ٫; (3) tab-separated rows: a BOQ row of pure figures, a row with a
   phone cell, a landline cell, an international number cell, a date cell, a part number cell, cells with one space
   inside ("600 600 10"), leading tab, tab then newline; (4) "Plot 681-2290", "Villa 12/3", "Gate 3-4 pm" (must keep the
   time), "Unit 12-14 mm glass"?? (decide what is right and say), "Road 6-8 m wide", Arabic; (5) names inside words in
   lower, Title, UPPER and mixed case; joined names (ramiVilla, VillaRami, RAMIVILLA, rami_villa, rami15); possessive;
   hyphenated ("Al-Rami"); a two-word name; Arabic names unaffected; the drawing route (all capitals) still held.
   For each fix: leaks reopened (must be 0) and legitimate text damaged (must be 0); name every exception.
3. Does fix 5 weaken any DRAWING hold or the residual scan of a page? Find every caller of the loose scan
   (`residualScan`, `seedRanges(..., true)`), and say for each what changes. Run the drawing suites that exercise it.
4. Timing: `_shared/identity_scrubbers_finish_on_adversarial_input.test.ts` and `review_cpu_budget.test.ts` on this head
   (the phone shapes gained a look-ahead per separator).
5. Suites: deno `_shared`, supplier_api, drawing_boq, customer_api (from the repository root, flags in COMMON.md).
VERDICT: MERGE or FIX (numbered: file:line, the input, the smallest fix), most harmful first; under 40 lines. Append to
`SP/show/REVIEW.md` under "ANONYMITY RELEASE (TEXT + DOORS) — check of the five fixes". Progress notes:
`SP/progress/rel_anon_fixcheck.md`. Remove the worktree at the end. No local database is needed.
