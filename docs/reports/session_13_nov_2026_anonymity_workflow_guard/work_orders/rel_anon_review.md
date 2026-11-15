# Brief: rel_anon_review — FINAL independent review of the combined anonymity release
Read `SP/briefs/COMMON.md` first. You are an INDEPENDENT reviewer; you wrote none of this.
Worktree: /tmp/claude-0/review-rel-anon from `origin/sales_engineer-anonymity-text-and-doors-released-together`
(head 1f450d57d = origin/main + the text-side branch at f8086debc + the customer-to-supplier "doors" branch at ad932e645).
Its offline gate passed 17 steps, 0 failed, on this head.
Context: the founder's ruling in `SP/anon/FIX_COMMON.md` (nothing below the emirate reaches a supplier; a supplier's
identity never reaches a customer before a paid reveal; an old supplier's PRICES never reach new suppliers; item names,
descriptions, quantities, specifications, warranty, country of origin may cross). Earlier reviews: REVIEW.md sections
"ANONYMITY F1 TEXT 1/2/3" and "ANONYMITY F2 DOORS 1/2/3" (doors: MERGE in round 3, only together with text; text:
"fix two blockers, then MERGE" in round 3). The text author's account of its round 4: `SP/handbacks/F1_AUTHOR.md`.
Earlier drivers and corpora: `SP/rv/`, `SP/f2rev/`; auditors' probes: `SP/anon/A_customer_to_supplier/`,
`SP/anon/C_supplier_to_customer/`.
Round 4 claims to verify: (1) runs of 3+ blanks after text are cut to TWO spaces (`capBlanks`), leading indent kept:
"Sales contact    050 123 4567    12,500.00" is removed on every door again; (2) `placeSpans/locationBelowEmirate(text,
{drawing:true})` count a cue-only name in capitals or alone on its line; default unchanged ("Arjan model chair" passes);
(3) the five wrong changes fixed ("Greens 4 trays microgreens", "Meadows 2 bags seed mix", "MBZ-1 panel", "Deira 3 piece
set", "Industrial Area lighting fixture"); "villas no. 40 to 45 on the drawing" now removed whole; a removal no longer
eats the following space; "at Villa 15, Al Barsha 2, Dubai" reads "in Dubai"; permanent corpus 654 sentences.
DO, on the combined tree:
1. The two blockers by running, plus three column-spaced variants of your own (two spaces, tabs, non-breaking space).
2. Over-redaction with FRESH text: 60 new ordinary quoting sentences (mixed trades, 12 Arabic): count wrongly changed
   (0 expected; name each). The 654 corpus with two name pairs.
3. Leaks: auditor C's 46 probes at the customer door (expected 2: "Contact Rashid Khan", "Falcolux"); auditor A's 31 on
   the combined tree (expected 0 of 62 with and without a stored site); the earlier 60 + 40 place probes (expected 1 + 1);
   30 NEW leak probes of your own in both directions (area in free text, access note with an area and no number, a
   project name, an old supplier's name with no legal form, his prices in three shapes, a phone in words, a spaced
   e-mail, an Arabic owner name, a plot number, coordinates). For each: CLOSED or LEAKS; a leak is either on the known
   second-reader list (unlabelled person, house brand, unlisted sub-community, landmark with no cue, place in prose,
   prices in words) or NEW; a NEW leak of a shape the code claims to handle is a FIX.
4. Timing: `_shared/identity_scrubbers_finish_on_adversarial_input.test.ts` as written; `review_cpu_budget.test.ts`
   while another deno test runs.
5. Suites of every folder the diff touches (`git diff --stat origin/main...HEAD`), `npx tsc --noEmit`, and the node
   checks the two branches added or edited, one file at a time (offline halves; a production half only if it is
   SELECT-only: read it first).
6. The ONE SQL file: `scripts/sql/before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate.sql` + probe: its
   lock table for the real apply (statement, table, lock mode); run file + probe on the LOCAL database (/tmp/pg-relanon,
   port 55501); is it safe to apply BEFORE the functions deploy and AFTER (old function + new routine; new function + old
   routine)?
7. The deploy list: every edge function whose bundle changes (anything importing a changed `_shared` file): derive it
   from the import graph (`scripts/verify_deploy_parity.mjs`, `scripts/deploy_functions.mjs` show how bundles are
   computed) and give the exact list.
8. What a real customer and supplier will notice in the first hour that differs from today, with the exact texts
   (a withheld field, the kept-private notice, portal titles "Trade work in Emirate · Job N", an edit refused).
VERDICT: MERGE or FIX (numbered: file:line, the input, the smallest fix), most harmful first; then the release steps in
order; under 55 lines. Append the full review to `SP/show/REVIEW.md` under "ANONYMITY RELEASE (TEXT + DOORS) FINAL"
(shell append; if refused, everything in the hand-back).
