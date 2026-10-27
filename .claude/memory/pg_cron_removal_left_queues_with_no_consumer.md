---
name: pg_cron_removal_left_queues_with_no_consumer
description: "Deleting pg_cron on 7 Sep orphaned every queue its 234 jobs drained; check for consumers, not just producers"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T04:53:53.668Z
---

9 Sep 2026. Found while checking why `send_outbox` reported `skipped=1` on every flush:

`public.notifications` id 20879 — channel `whatsapp`, to the founder's number, **queued since
7 Sep 18:15, attempts 0**. `agent_runs` for `send_whatsapp`: **zero rows, ever**. Nothing in the
repository called it. It had been drained by the pg_cron job `wa_flush`, and pg_cron was removed on
7 Sep — the same day the message stopped moving. WhatsApp is the founder's command channel.

**The lens:** removing a scheduler removes CONSUMERS, and a queue with no consumer is invisible —
`status='queued'` with `attempts=0` looks exactly like a row waiting its turn. Producers keep
working and nothing reports the gap. After any scheduler change, enumerate what USED to drain each
queue, not just what still writes to it.

**Fixed:** `resilience_ping` gained a `whatsappTick` on the live Vercel-cron path, `send_whatsapp`
gained the staleness bar `send_outbox` has had since July (`app_secrets.wa_stale_hours`, default 24),
and `internal_credential` context `fn.resilience_ping` was widened to include `send_whatsapp` — a
missing scope entry fails closed and silently, so widening scope is part of wiring a call, never an
afterthought. Proved: the live scheduler drained it on its own and HELD the 35h-old alert rather
than paging him about an outage that had already ended.

**Still open, same shape, not chased:** `exec_reports` holds 318 rows at `new`, oldest ~65 days.
Also `invite_schedule` 5 pending (128h). Scan recipe:
`scratchpad/queues_with_no_consumer.mjs` — every public table with a text `status`/`state` column,
counted in a pending-ish state and aged on its own timestamp column.

Related: [[zero-cannot-tell-a-dead-guard-from-an-idle-system]],
[[finished-capability-with-no-entry-point]], [[a-status-column-is-not-a-delivery-record]],
[[no-job-or-task-without-an-agent]].
