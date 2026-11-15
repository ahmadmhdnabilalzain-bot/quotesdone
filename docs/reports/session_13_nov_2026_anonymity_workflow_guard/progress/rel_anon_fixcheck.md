# rel_anon_fixcheck progress
- Worktree /tmp/claude-0/review-rel-anon at e2d78a0f3 created (node_modules symlinked). Output folder SP/fixcheck/.
- Next: step 1 re-run drivers in SP/relrev and SP/relanon.
- STEP 1 DONE (outputs SP/fixcheck/{head,base}/*.out; base worktree /tmp/claude-0/review-rel-anon-base at 1f450d57d to remove at end):
  C 2 same; A 0/62 identical json; p40 1, p60 1; relrev/new30 7->6 (tab row closed; Noor site rows closed, nosite+clarify still leak (no spec)); relanon/new30 13->10 (BOQ arabic/dirhams, plot closed; email row lost the e-mail leak)
  fix1 all 5 closed; s1 tab row closed all doors; fresh 0 / 5(brand) same; 654: falcon 3=3, bluestar 1=1, grace 3->1 (chiller rows pass).
  FINDING: BOQ "بلاط بورسلين ٦٠×٦٠ السعر ٨٥ درهم للمتر" inbox -> "بلاط بورسلين ٦٠× للمتر" (gate leaves درهم; supplierCopy re-gates and eats "٦٠ درهم"). Arabic label alt lacks trailing CUR.
- Next: step 2 attacks (SP/fixcheck/attack.ts).
- STEP 2 DONE (SP/fixcheck/attack.ts, extra.ts; outputs attack.{head,base}.out). Findings:
  F3 REGRESSION: "05\t4\t250\t1000\t50.00" erased as mobile at every door (base kept): MOB_ANY SP includes \t + new (?=\t) bypasses guards. identity_text.ts:75.
  F5 REOPENED: "Almansoori Villa", "Mohammedali", "Binzayed" pass inbox (base withheld); drawing residual "Almansoori"/"Owner:Almansoori" [] (base held).
  F2: Arabic label السعر lacks trailing CUR -> double gate eats "60 درهم" of "60×60" (pre-existing ASCII, now Arabic digits too); breaks idempotency claim quotation_gate.ts:188.
  F4: "Gate 3-4 pm" -> "the site-4 pm" (backtrack; same on base). F1: "Haddad & Co" leaks (1 word, by design), "Delta Pumps Est." seeds Pumps (pre-existing).
- Next: trial fixes in /tmp/claude-0/review-rel-anon-trial (remove at end), then step 3 callers, 4 timing, 5 suites.
- Trial tree /tmp/claude-0/review-rel-anon-trial (4 edits): closes F3 regression, F5 reopened names, F2 double gate, F4 Gate 3-4 pm; drivers unchanged otherwise; 654 grace 1, falcon 3, bluestar 1.
- STEP 3 DONE (draw.ts): gateDrawingBoq still drops Almansoori via ocrMisreads; pdf_vector_redact/cad_file_redact/scan_redact/cad_render rely on residualScan(+literal/seedHit) -> mixed-case joined names no longer held (READ).
- Next: step 4 timing, step 5 suites.
- STEP 4 DONE: adversarial 25s ok, review_cpu_budget 359ms ok. NEW: fix 5 token scan quadratic: residualScan('xrami'x20000 =100KB) 43.7s (base 0.3s); supplierField 50KB 14.0s (base 3.3s). Bound 48 chars in trial -> 1.3s.
- Next: step 5 suites running -> SP/fixcheck/suite_*.txt
- Trial diff saved SP/fixcheck/trial_fixes.diff. NBSP opinion: "Tel: 052 765 4321 3,250.00" (space or NBSP) crosses save+door (pre-existing; label should override guard).
- Waiting for suites (SP/fixcheck/suite_status.txt), then append REVIEW.md, remove 3 worktrees (review-rel-anon, -base, -trial).
- DONE: REVIEW.md appended, worktrees removed.
