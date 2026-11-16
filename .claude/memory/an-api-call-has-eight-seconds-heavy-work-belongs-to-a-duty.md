---
name: an-api-call-has-eight-seconds-heavy-work-belongs-to-a-duty
description: "Every rpc an edge function makes runs as authenticator with statement_timeout 8 s; a routine that builds a large pack must run in a pg_cron duty (60 s), never on the heartbeat. The CEO's weekly plan was never written for this reason (16 Nov 2026)."
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-16T15:00:00.000Z
---

**What happened, 16 Nov 2026 (ceo, ledger 1448).** The CEO's planning loop went live at 01:49 UTC and resilience_ping
(which called `fn_ceo_plan_due` from its hourly `ceoPlan` step) was deployed at 01:56. No weekly plan was ever opened by the
loop: on a Monday `fn_ceo_plan_due` builds `fn_ceo_planning_pack(7)` (20 sections, ~47k characters) inside the heartbeat's
own `admin.rpc`, and every call through the API is cut at **8 s** (`pg_roles`: authenticator `statement_timeout=8s`,
`lock_timeout=8s`; SET ROLE service_role does not lift it). The only record was arithmetic: `resilience_step.ewma_ms` 5922
after a 1,325 ms tick means the earlier ticks averaged 7,892 ms (ewma = 0.7 old + 0.3 new). The failure was silent because
`ceoPlanTick` nested the loop's `{ok:false}` under `loop` while plan C's `ok` stood at the top.

**The rule.**
- Work that reads many tables (a pack, a report, a measure over all bets) runs in a seat duty: `fn_seat_duty_run` under
  pg_cron sets `statement_timeout = '60s'`. The heartbeat (or any edge function) only asks a light routine what to do next
  and hands it on. For the CEO: the duty opens the plan with its pack; `fn_ceo_plan_handover` names the plan for ceo_agent.
- A result nested inside another step's result must fail that step when it fails (`withLoop` in resilience_ping/steps.ts).
- Before saying a heartbeat path works, read `resilience_step.last_ms`/`ewma_ms` for its step: a step near 8,000 ms is
  being cancelled, whatever `last_ok_at` says.
- A production read never calls an application routine to "see what it returns" (16 Nov: a reviewer's SELECT of
  `fn_ceo_plan_due()` wrote plan id 12). Run it on the local copy.

Files: scripts/sql/the_ceo_writes_its_weekly_plan_with_a_model_and_carries_it_out.sql,
supabase/functions/resilience_ping/ticks/ceo.ts, scripts/checks/the_ceo_writes_its_weekly_plan_with_a_model_and_carries_it_out.test.mjs.
