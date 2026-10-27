---
name: checkpoint-8-sep-the-sweep-is-prepared-not-run
description: "State at 8 Sep 2026 06:20 — the CEO owns its own machine and Phase C is no longer load-bearing, but no pre-7-September deletion has run yet"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-08T02:45:34.601Z
---

Session paused mid-sweep when the founder closed the laptop. Full checkpoint:
**`docs/CHECKPOINT_2026-09-08.md`** (PR #534). Read that first on resume.

**Measured at 06:15 GST, still present:** 96 phase/kernel tables, 37 org/workflow/dept/OS tables,
11 decision tables, 227 old-machinery routines, 716 application routines. **None of the
pre-7-September deletion has run.**

**What the session actually bought:** Phase C is no longer load-bearing.
`founder_command.state` → `ceo_command_state`, and `refunds.refund_decision_id` → `ceo_approval`.
Those two were the only things making the phase programme undroppable.

**Built and merged (PRs #530–#533 plus a4ae78d):** the CEO's own machine — `ceo_command_state`,
`ceo_command_transition`, `ceo_command`, `ceo_command_intent`, `ceo_command_rule`, `ceo_task`,
`ceo_task_state`, `ceo_identity`, `ceo_approval`; and `v_support_corpus` +
`fn_support_corpus_search(query, public, limit)` wired into `site_assistant`.

**Resume in this order:**
1. Re-launch the two drop-script agents (targets:
   `scripts/sql/the_phase_programme_and_its_kernel_are_removed.sql`,
   `scripts/sql/the_organisation_that_was_removed_leaves_the_database.sql`).
2. **Build the CEO's edge function in front of `fn_ceo_command_submit` BEFORE deleting `os_api`** —
   `os_api` is the founder's only working command channel, and WhatsApp's fallback POSTs to
   `agent_brain`, which is not deployed and 404s. See [[the-ceo-seat-has-tools-but-no-runtime]].
3. Apply drops in waves with an aborted-transaction probe after each; regenerate the schema mirror
   as the LAST step before each push.

**Defects measured and NOT fixed:** WhatsApp founder channel 404s; cron has one inactive job and
nothing has been scheduled since 7 Sep 17:51; 496 internal knowledge records still name the founder
as approver (one dated record supersedes them); the corpus has no public Arabic at all; ~61 local
test assertions fail, none from this session — see [[ci-green-does-not-mean-npm-test-green]].

**The incident to remember:** PR #530 deleted the eight edge functions that ARE the customer and
supplier portals (`customer_api`, `supplier_api`, `supplier_portal`, `messages_api`,
`inquiry_intake`, `quote_compare`, `supplier_onboard`, `supplier_catalog_ingest`); `/me` and
`/portal` 404'd on every action for ~90 minutes. Restored in PR #532. Cause:
[[a-mention-is-not-a-reference]] — `function_owner` was built by READING THE LIVE DEPLOYMENT LIST, so
it could not see what was missing from that list.
