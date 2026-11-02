-- THE FOUR NOVEMBER-PLAN REVISIONS ARE RE-DRIVEN AFTER THE CPU KILL (27 Oct 2026, it_engineer, release of #1678).
--
-- A data repair, not a schema change; it defines no routine.
--
-- Held questions 28985-28988 (the *.ceo_revision rows fn_ceo_revision_refile filed together) failed after 3
-- claims at 01:17, 01:47 and 02:16 UTC on 27 Oct. The model never answered them: the itlater replay worker was
-- killed at the 2 s CPU cap (function_logs: shutdown reason CPUTime, 2,091-2,160 ms) before
-- fn_reason_held_resolve ran, so result stayed null. #1678 moves gte-small out of that worker (heartbeatDeps).
-- A fresh refile would carry the same qhash and fn_reason_held_sweep would close it as failed_with its twin
-- inside 7 days, so the rows themselves are re-opened once. Handoff 163352 (ceo.revise, marketing, pending since
-- 12 Oct) points at them through evidence.held_id.
--
-- Measured before the run, 20:27Z: all four rows had status failed, attempts 3, last_attempt_at 02:16:39Z and result null.
-- Idempotent: the guard (status failed, result null) matches nothing once the rows are re-opened.
update public.reasoning_held_question
   set status = 'held', attempts = 0, last_attempt_at = null,
       result = jsonb_build_object('redriven_at', now(), 'why', 'the replay worker was killed at the 2 s CPU cap before it recorded a result; fixed by #1678')
 where id in (28985, 28986, 28987, 28988) and status = 'failed' and result is null;   -- expect 4

select case when count(*) filter (where status = 'held' and result ? 'redriven_at') = 4 then 'PROBE OK'
            else 'PROBE FAILED: ' || count(*) filter (where status = 'held' and result ? 'redriven_at') || ' of 4 re-opened' end as verdict
  from public.reasoning_held_question where id in (28985, 28986, 28987, 28988);
