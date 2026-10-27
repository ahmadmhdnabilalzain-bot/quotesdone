---
name: two-sessions-are-available-and-the-outbox-does-not-send
description: "The management API gives two concurrent backends, and outbox delivery is an in-database projection — both halves of the old concurrency blocker were wrong."
metadata: 
  node_type: memory
  type: project
  originSessionId: e6dadb80-c71d-4c71-8e4c-a23e7cde9d86
  modified: 2026-08-24T03:44:37.440Z
---

Two claims blocked every concurrency test in the Phase D catalogue. Both were measured wrong on
24 Aug 2026.

**1. Two concurrent sessions ARE available.** The Supabase management endpoint runs each POST in its
own transaction on its own backend, so two statements issued together (`Promise.all`) genuinely
overlap. Measured: pids 1719034 and 1719035, both live 00:48:42→00:48:46 UTC. A statement that takes
a lock and `pg_sleep`s holds it while the other tries to take it. That is a real race — no `pg`
driver, no connection string, no local database. `scripts/tmp_diag/conc_probe.mjs` proves the
mechanism in ~6 seconds.

**2. Outbox "delivery" does not send anything.** Neither `fn_kernel_outbox_deliver` nor
`fn_kernel_event_consume` contains `net.`, `http`, or any external call — grep the live bodies. The
consumer PROJECTS onto the downstream subject and creates nothing, by construction, because
`fn_kernel_step_complete` is the single authoritative progression path. So the recorded blocker "a
committed row there is delivered for real by cron 278 within 60s" was wrong: the worst a cron tick
does to a canary is project it and mark it delivered.

Consequences, both used to close cases:

* `fn_kernel_event_consume(outbox_id)` can be called **inside an aborted transaction** to observe
  the consumer half of an event. That is how all 347 events reached `OBSERVED_SUCCESS`.
* A committed canary in `phase_c_event_outbox` can be raced safely — but **create it inside a clear
  second-window**, not before waiting for one. The first run created it, waited, and cron
  `phase_c_outbox_deliver_1min` claimed and dead-lettered it before the race started.
* Always run the **alone** control afterwards: a second claimant reading 0 rows proves nothing
  without proof the row was claimable. See [[zero-cannot-tell-a-dead-guard-from-an-idle-system]].

Docker Desktop on this machine cannot start — stale unix-socket entries under `AppData\Local` in
two directories that Windows refuses to delete — so a local ephemeral Postgres is not available.
Renaming the directories got it one stage further each time and it failed on the next.

Related: [[a-blocker-is-a-claim-too]], [[deploy-the-quarantine-before-the-worker]].
