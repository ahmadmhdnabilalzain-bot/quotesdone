-- THE COMPANY DECIDES SEVENTY TIMES A DAY AND LEARNS FROM FIVE A WEEK.
--
-- Found while chasing Row #3's `s33-replay-six-tracks`, which reports "5 of 6 track(s) have rows on
-- 2026-08-11 (missing: outcomes)". The missing track is outcome_record, and the reason it is empty
-- on that day is not a reporting bug. MEASURED, decisions against outcomes opened, same days:
--
--     6 Aug   67 decisions    1 outcome        10 Aug   82 decisions   15 outcomes
--     7 Aug   29 decisions    0 outcomes       11 Aug  142 decisions    0 outcomes
--     8 Aug   61 decisions    0 outcomes       12 Aug   62 decisions   17 outcomes
--     9 Aug   70 decisions    0 outcomes
--
-- 513 decisions in seven days. 33 outcome records. On the busiest day of the week, none.
--
-- WHY. fn_outcome_open is the only writer of outcome_record, and it has exactly two callers -
-- fn_kpi_review and fn_os_improve. Both are weekly crons. So the company's entire outcome ledger is
-- produced by two Monday jobs, and every one of the ~70 decisions it makes on an ordinary day
-- passes through decision_log and is never followed up.
--
-- This is the founder's operating model failing at its own centre: "learn from performance,
-- failures, outcomes and new information... determine what is working, what is failing, why it is
-- happening, and what should change." A company that cannot say whether last Tuesday's decision
-- worked is not learning from outcomes; it is keeping minutes.
--
-- WHY THIS FILE RECORDS THE GAP INSTEAD OF CLOSING IT, and the reasoning is the point:
--
-- fn_outcome_open's signature requires p_expected_kpi_id, p_direction and p_measure_after. That is
-- correct - an outcome you cannot measure against a declared expectation is not an outcome, it is a
-- diary entry. But decision_log has no such column: its shape is
-- (actor, kind, ctx, decision, confidence, reasons, sources, route_to, alternatives). A decision is
-- recorded WITHOUT any statement of what it was expected to move.
--
-- So closing this by inferring the KPI from the decision text would fabricate a causal claim - it
-- would put "this decision was expected to move KPI 47" into the learning ledger on the strength of
-- a keyword match, and every downstream lesson, promotion and rollback would inherit that guess. On
-- a table whose whole purpose is to tell the company what actually worked, a plausible wrong
-- attribution is worse than an empty row.
--
-- The real fix is a contract change: decision_log gains expected_kpi_id / expected_direction /
-- measure_after, the ~20 routines that write to it supply them for decisions that claim an effect,
-- and outcome_record opens automatically from that. That is a change across many writers and it
-- needs to be done deliberately, not squeezed in behind a Row #3 checkbox.
--
-- Recorded in spec_backlog so the company carries it rather than a session hand-over: this is
-- exactly the kind of problem the operating model says management should detect and assign.
insert into public.spec_backlog (source_doc, area, item, spec_ref, status, verdict_at_audit, evidence, priority, notes, updated_at)
select 'OS 2.txt (Row #3) + founder operating model',
       'learning loop',
       'decision_log must carry the effect a decision claims, so outcome_record can open for every '
       'decision that claims one - not only for the two weekly KPI-review paths',
       's33-replay-six-tracks',
       'open',
       'MISSING',
       '513 decisions across 2026-08-06..12 against 33 outcome_record rows; 142 decisions on 11 Aug '
       'produced 0. fn_outcome_open is the only writer of outcome_record and its only callers are '
       'fn_kpi_review and fn_os_improve, both weekly. decision_log has no expected_kpi_id / '
       'expected_direction / measure_after, and fn_outcome_open requires all three, so no general '
       'decision path can open an outcome without inventing the expectation.',
       1,
       'Do NOT close this by inferring the KPI from decision text - that writes a fabricated causal '
       'claim into the ledger the company uses to decide what worked. The fix is the contract: add '
       'the three columns to decision_log, have the routines that write it supply them where the '
       'decision genuinely claims an effect, leave them null where it does not, and open '
       'outcome_record from that. Measured and written up 12 Aug 2026.',
       now()
where not exists (select 1 from public.spec_backlog where spec_ref = 's33-replay-six-tracks');
