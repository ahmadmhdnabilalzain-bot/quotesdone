# w3_fix progress (fix author, branch ceo-every-seat-reads-one-pool-and-every-hand-over-comes-back)
- 20:40 step 0 done: worktree /tmp/claude-0/fix-w3-r3 @eed8432be; PG16 /tmp/pg-w3-r3:55521 (dbs: w3base = mirror+seed_ref; w3sib = +money 5747d5f62 + sales 5acacfaf2; w3 = work).
  Scripts: SP/w3fix/apply_sibs.sh <db>, SP/w3fix/pool.sh <db> (apply + probe). Baseline: pool applies twice, PROBE OK.
- next: items 1-11 + tests (a)-(d) in the SQL file; then probe, scenarios, docs.
- 21:2x step 1 committed+pushed (part 1): SQL items 1-8,10,11 + (a)-(d) written; file applies on w3sib. Probe still old (fails on new formats: B options, C wording).
  New pieces: fn_handoff_owing_seat, fn_seat_pool_waiting rewrite, escalate (superior of silent), ceo.order + fn_ceo_orders_reported + fn_seat_reports_done,
  ceo.authority + ceo_grant_once + fn_agent_may_act(5-arg) + fn_reason_apply_ceo__authority, cap counts plan.rearmed_at, customer.verified trigger z41, approved_by,
  tail = create or replace trigger; dispatcher drop in the_department_dispatcher_trigger_goes_once_its_body_is_a_no_op.sql (+pending note).
- next: rewrite probe (items 9 + tests a-d), run scenarios SP/w3r2 adapted into SP/w3fix/, locks, bench, deno/node, docs.
- 21:4x step 2 committed+pushed: probe rewritten, PROBE OK LOCAL (w3 = w3sib + pool). next: mutants, scenarios, locks, bench, tests, docs.
- 22:0x step 3 committed: scenarios done, 16/16 mutants. next: bench, locks, tests, docs, final proof
- 22:2x step 4 committed+pushed: lock-safe apply (guards; section 1 DDL moved between agent_actions and company_event triggers). Locks: SP/w3fix/locks_first.out, locks_rerun.out; concurrency SP/w3fix/conc.out; bench SP/w3fix/bench.out. next: deno+node checks, docs, re-fetch siblings, final proof, handback.
- 22:4x step 5 committed+pushed: docs + checks updated; node: pool 8/1skip, handoff 6/6, gaps 5/12 (none mine), manifest 0, routines checks pass. deno running (/tmp/pg-w3-r3/deno.log). next: refetch siblings, final proof, cleanup, handback.
- 23:0x DONE: final proof on re-fetched siblings (ea9c25c62, 75f60e2d3) PROBE OK x2; deno 2275/1 known/1 ign; handback SP/handbacks/W3_FIX.md; cluster + worktree removed.
