---
name: an-open-invitation-day-runs-on-its-own-clock
description: "28 Oct 2026: the first open invitation day queued 0 because the tick ran under resilience_ping's 8 s RPC limit (open day 13.4 s) and the a07 guard still demanded a portal link the approved copy no longer has; fix moves the tick to its own 60 s seat-duty job and lets the guard take the link-less copy"
metadata:
  node_type: memory
  type: project
  modified: 2026-10-28T06:40:00.000Z
---

**What happened.** Invitations were resumed at 03:51Z on 28 Oct (ledger 1377): verdict recorded (Google open), window
end 17, `invite_enabled=true`. By 06:13Z: 0 `supplier_invite` rows. Two defects, both invisible while invitations were
held, because the held path never reaches them:

1. `fn_sales_engineer_supplier_outreach_tick` ran only as resilience_ping's step `supplierOutreach`, through PostgREST,
   where `authenticator` has `statement_timeout=8s`. Held path ~5.8 s; open day: pool count 5.8 s + candidates 5.5 s,
   `enqueue_supplier_invites` 13.4 s. Every beat from 05:16Z was cancelled (finding `duty:heartbeat:supplierOutreach`),
   the cancel rolled back the day's `agent_runs` row, so it retried and failed every 30 min.
2. `a07_notifications_supplier_invite_is_whole` still required `/(en|ar)/portal?t=<uuid>` in the body. #1614 made the
   approved copy link-less but did not change this trigger: every row refused, "carries no portal link".

**Fix (PR from `sales_engineer/the-invitation-batch-runs-on-its-own-clock-and-the-guard-takes-the-link-less-copy`):**
seat duty `sales_engineer.supplier_outreach` on its own pg_cron job (60 s), `resilience_step` row deleted, step removed
from STEP_RUN; guard refuses an empty body or an unfilled `{{placeholder}}` instead. Rehearsed rolled back: 20 queued,
all Google-hosted, 13.4 s, app_secrets unchanged.

**Lessons.**
- A routine called through `admin.rpc` has 8 s. Time the OPEN path, not just the held one, before relying on a step.
- When a resume is the first real run of a path, replay the real enqueue in a rolled-back probe BEFORE the window opens.
- A copy change must be checked against every trigger on the table it writes (`pg_trigger` on `notifications`).

Prevented by: `scripts/checks/the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.test.mjs`.
Related: [[the-invitation-gate-reads-the-glockapps-verdict]], [[invitations-resume-only-at-80-percent-outlook-inbox]]
