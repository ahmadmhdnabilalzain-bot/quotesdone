---
name: deploy-the-quarantine-before-the-worker
description: "A delivery worker on a 1-minute cron went live before the migration that quarantined the bad rows, and delivered them within 90 seconds — order the increments by what the queue already contains."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9f1a5f09-0430-4380-80c9-8676a24ac346
  modified: 2026-08-16T11:13:19.350Z
---

16 Aug 2026, Phase C correction. `phase_c_32` deployed `fn_phase_c_outbox_deliver` with a
`* * * * *` cron. `phase_c_38` was the migration that superseded three pre-fix outbox rows carrying
`EV-W01-STARTED` for W20 commands. Applied in that order, six minutes apart. At 10:28 the worker
took all three and created exactly what the quarantine existed to prevent: three W01 workflow runs
accountable to the **CEO**, with tasks for the Chief of Staff, out of three marketing orders.

The rehearsal was clean and gave no warning, because in one aborted transaction both migrations run
before any cron tick can happen. The defect only exists across the *gap between increments*.

**Why:** "deploy incrementally, verify after every increment" says nothing about what a scheduler
does in the seconds between them. A worker's first tick is a live production write, and a queue
whose contents predate the fix is not inert data — it is pending instructions.

**How to apply:** before enabling any consumer, drainer or scheduler, ask what is **already sitting
in the queue it will read**, and land the quarantine or the backfill FIRST. If that is not possible,
create the job inactive and switch it on last. And put the refusal in the consumer, not only in the
data: `fn_phase_c_event_consume` now rejects any event whose payload names a command that selected a
different workflow, so the order of two migrations can never decide it again.

Related: the same delivery exposed a self-feeding queue — the ingress emits because it is the
producer path, and called from the consumer it re-emitted its own input. See
[[connected-is-a-claim-not-a-measurement]] and [[a-rehearsal-proves-creation-not-execution]].
