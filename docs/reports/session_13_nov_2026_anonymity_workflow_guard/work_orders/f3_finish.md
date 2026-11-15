# Brief: f3_finish — finish round 3 of the drawings fix
Read `SP/briefs/COMMON.md` first. You are the FIX author (commit prefix `sales_engineer:`). Your predecessor was killed
by a restart after pushing 64509bca4 ("the model reads every tile, the server checks the released pages, CAD strings are
read whole and once") and left NO hand-back.
Branch: `sales_engineer-a-drawing-reaches-a-supplier-with-no-owner-no-area-no-map`. Worktree (exists, clean, at the
head): /tmp/claude-0/fix-anon-drawings (`git fetch && git status` first; recreate from origin if broken).
Read: `SP/anon/FIX_COMMON.md` (the founder's ruling); `SP/anon/REPORT_B.md`; REVIEW.md sections "ANONYMITY F3 DRAWINGS 1"
and "2" (the second review's items 0–9 are your list); `git log origin/main..HEAD` and the last commit's diff.
The design decided: nothing drawn reaches a supplier until a vision model of ANOTHER family has read the final pixels
(tiled so 6 pt text is at least 12 px high); CAD strings are classified by ONE text-model call; code is the floor that
holds when the model is lazy. No paid call here: the model is a stub in every test.
FOR EACH ITEM 0–9 of the second review decide DONE-AND-PROVEN (name the test) or finish it:
0 tiles (every tile read; 6 pt ≥ 12 px); 1 the SERVER checks the released page count against what the model read (a page
never read is never released); 2 the three gate rules each have a test; 3 block-name rename map (a block named after the
owner or the project is renamed in the output, references intact); 4 `locationBelowEmirate(t,{drawing:true})` is used in
union with the default (the option lives on the text branch: `origin/sales_engineer-nothing-below-the-emirate-and-no-name-crosses-in-text`;
if it is not on your base, feature-detect or state the merge order: do NOT copy the file); 5 long strings are chunked,
none truncated; 6 false holds on the 20 ordinary sheets = 0; 7 the v02 shape rows are covered; 8 CAD strings are read
once, not per page; 9 the stale comment; and the e-mail rule uses the lookbehind `(?<![A-Za-z0-9._%+-])` ONLY (no
broader change).
PROVE with three stub models over the auditor's corpus (`SP/anon/B_drawings/`, 19 identity cases + the 20 ordinary
sheets): FAITHFUL (reports what is there): 19 of 19 withheld or cleaned, 0 false holds; LAZY (reports nothing): the code
floor still catches every case code claims (name which it cannot: those are HELD, not released); ALWAYS-CLEAN (says
"clean" to everything, reads no tile): nothing is released, because the server sees tiles unread. Write the
after-outputs as files named "Round 3 - <case>.pdf|png" under `SP/for_founder_drawings/round3/` (small; no videos).
Deno suites of every folder touched; the node checks you touched.
Push small commits. HAND-BACK (under 55 lines): items 0–9 each DONE (file:line, test) / NOT DONE; the three stub tables
(case | faithful | lazy | always-clean); legitimate drawing text wrongly removed (list; 0 expected); SQL to apply and
functions to deploy in order; what the portal/customer side still needs (`verify_released_file`, customer confirm step,
`seed_terms` pass-through); what you are unsure of. Also write it to `SP/handbacks/F3_AUTHOR.md`.

## State found at 20:10 UTC (read this before anything else)
The branch head is now 95a9feec9, not 64509bca4: a predecessor pushed five more commits between 11:44 and 12:14 UTC and
was killed with no hand-back: 53dbe4b20 (tiles fit every provider's resize limit; a released page must carry 12 px for
6 pt; the budget hold is said), 7573d5e3b (the budget hold rides on the redaction answer, so the merge with the text
branch does not conflict), c08bba1c6 (the read-once rule is a function with its own test), 5fd1979ed (a person named
after an honorific is identity on every drawing route: v03 released "MR ZZ DEMO RASHID"), 95a9feec9 (the code floor reads
what every sheet's strip names; a strip label is not a seed). The worktree /tmp/claude-0/fix-anon-drawings is at that
head and clean. So several items may be done: for EACH item decide DONE-AND-PROVEN by running its test, or finish it.
Trust nothing by its commit title. The three-stub tables and the "Round 3 - …" outputs are probably NOT done.
