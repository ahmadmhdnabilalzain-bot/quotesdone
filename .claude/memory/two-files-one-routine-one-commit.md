---
name: two-files-one-routine-one-commit
description: "sql_files_match_live picks the newest file by git COMMIT time; two files defining one routine in the same commit means it certifies whichever it picked, so a correction can be absent from production at 0 drift."
metadata: 
  node_type: memory
  type: project
  originSessionId: 953dddc0-0434-4402-8342-dd32e9bf3929
  modified: 2026-08-16T18:58:09.365Z
---

`scripts/checks/sql_files_match_live.test.mjs` resolves each routine to the **newest file by git
commit time**. When two `scripts/sql/*.sql` files define the same routine and land in the **same
commit**, that is a tie — it silently picks one and compares production against it.

Measured 16 Aug 2026: `phase_c_31_autonomous_entry_creates_work.sql` and
`phase_c_39_consumer_must_not_reemit.sql` both define `fn_phase_c_event_ingress` and were both in
commit `8eebbec`. Production carried phase_c_31's body (emit unconditional); phase_c_39's fix
(`v_emit := coalesce((p_ctx->>'emit')::boolean, true)` … `if v_emit then`) was never live. The check
reported **439 routines, 0 not present, 0 drifted**. The instrument agreed with the regression.

**Why:** apply order within a session decides which body survives, and the check has no way to know
a later file in the same commit was meant to supersede an earlier one.

**How to apply:** before believing any Phase C / Phase B parity result, run
`grep -l "function public.<name>" scripts/sql/*.sql` for the routines a correction touched. More
than one hit means the drift check is not evidence for that routine — diff the live `prosrc` against
each candidate file by hand. Never redefine one routine in two files of the same PR; supersede by
editing the original file, or land the superseding file in its own commit.

Sibling lens: the consumer's `'emit', false` was passed in a `jsonb` context and **never read** by
the callee — a parameter threaded but not consumed reads exactly like a fix. Grep the callee for the
key, not the caller for the argument. See [[green-pr-does-not-mean-deployable]],
[[an-assertion-written-with-the-same-mistake]], [[deploy-the-quarantine-before-the-worker]].

**UPDATE 3 Sep 2026 — re-applying a multi-routine file re-deploys its SUPERSEDED bodies.** I edited
fn_agent_silence_watch inside cron_watchdogs_stop_timing_out.sql and re-applied the whole file; it also
defines fn_os_health, whose canonical file is a LATER manifest entry, so production got the older
fn_os_health back and CI reported repository->production drift 1. The dry run prints "defines N
routine(s)": when N > 1, check that THIS file is canonical for every one of them
(docs/phase-c-final-kernel/CANONICAL_ROUTINE_MANIFEST.csv) before applying, or move the edited routine
into a new later file and apply only that. Recovery: re-apply the canonical file of the clobbered routine.
