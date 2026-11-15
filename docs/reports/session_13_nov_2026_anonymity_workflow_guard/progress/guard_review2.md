# guard_review2 progress
step0: worktree /tmp/claude-0/review-guard2 at 8502c8d5a. Reading.
step0b: local_pg16 start from clean OK 12 s, 808/2175/374/403/110(0 active). Cluster /tmp/pg-qd:55433 RUNNING (stop at end).
step2-3 prep: 25 attack files in SP/guard_review2/attack, 4 tx-timeout offline in tt/, 15 pass files in pass/. local setup objects zz_dom, zz_domtab, zz_mv, zz_seq committed in local db. Next: harness.
step2 done: 25 attacks: 21 PASS guard (16 take strong locks LOCAL), 4 refused; lock_timeout lifted by quoted GUC / DO execute / E'' set_config (LOCAL); transaction_timeout lifted 4 ways (offline decision). step3 running.
step4 partial: applyLockTimeout('--lock-timeout=0.4') -> '0ms' (= no limit) DEFECT. dry run needs token.
step6 done: pending file+probe PROBE OK LOCAL x2; mutants test 6/6 LOCAL.
step4/5/7 done: 0.4 lock-timeout bug; settleUnknown 120s fallthrough; compliance_archive lost-response retry deletes own cert (READ); uncovered writes list (quote_acceptance submitted, quote_items delete/insert, kyc email verify, tos_sha256...). observe OK (no throw, fast; date masked cosmetic). deno check 4 fns OK. Next: step 8 memory/runbook, step 9 node scripts/lib tests.
step8 done: memory/runbook overclaim ('whatever it locks and however it says it', 'refuses any file...'); quotesdone-session SKILL:134 + apply-discipline SKILL:108 still recommend aborted-tx probes unqualified. compliance_archive own-cert-deletion simulated (deno, ca_sim.ts) CONFIRMED. step9 node tests running bg (b280sqcvm) -> SP/guard_review2/node.log
step9 running: branch node.log (local db, QD_OFFLINE=1), main baseline node_main.log on /tmp/claude-0/gate (QD_OFFLINE=1).
step9: branch node 45 files done (138/67/11 with QD_OFFLINE=1 + local db); main baseline running (bqnm08be2). REVIEW_SECTION.md drafted in SP/guard_review2; next: compare, append to SP/show/REVIEW.md, stop cluster, remove worktree, handback.
