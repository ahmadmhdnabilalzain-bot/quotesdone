---
name: rehearsals-and-probes-page-the-founder
description: every agent_runs error row on production is read hourly by fn_watch_failed_runs and paged to the founder; a sandbox rehearsal or a hand probe with the wrong credential emails him — run inside withRun (declares a rehearsal_window) and check the credential scope before any probe
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T06:39:20.801Z
---

3 Sep 2026: the founder received three emails in one morning. Two were this session's own work —
the revenue-loop rehearsal (52 enrich_capability rows, 1 quote_compare 401) and later hand probes
(an enrich_capability auth 403, two send_outbox 422s) — because `fn_watch_failed_runs` pages once per
new failure signature per day and `alert_founder`'s dedupe key was broken (fixed: stored on the row).

**Why:** the failed-run watcher cannot tell an operator's probe from a customer's failure, and the
founder's promised inbound signal must stay credible — noise trains him to ignore it.

**How to apply:**
- Run every fixture exercise inside `demo_factory.withRun` (it opens and closes a
  `public.rehearsal_window`; the watcher counts rows inside a declared window and never pages on
  them) — or, for a standalone rehearsal, insert/close the window yourself as
  `scripts/staging/rehearse_ad_spend.mjs` does.
- Before a hand probe of an edge function, read `internal_credential.scope` for the callee: a
  credential named `cred_fn_<x>` is x's OUTBOUND credential, not the key to call x. Refusals are logged
  as `agent_runs` errors and paged. `cred_fn_cos_execute` (id 53) is scoped to most marketplace
  executors; `cred_fn_agent_act` (id 32) to meta_ads; `cred_ops_wa_template_setup` to wa_template_setup.
- A held model is never an error: the pattern is `paidProviderGate` → `logRun('skipped')` → return 200
  `{held:true}`; the action collector parks `{held:true}` as status=held (no retry, no dead letter,
  `fn_action_release_held()` re-queues them). Five functions were fixed to this shape today
  (agent_brain, kb_deepen, route_inquiry, enrich_capability, analytics_recommend).
- A reserved test domain (example.com/.invalid/.test) is refused by send_outbox as a clean skip.
Related: [[a-refusal-that-is-not-an-error]], [[an-audit-can-mint-its-own-session]],
[[instruments-report-on-the-wrong-subject]].
