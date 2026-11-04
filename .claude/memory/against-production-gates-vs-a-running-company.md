---
name: against-production-gates-vs-a-running-company
description: "why the Phase C/D \"against production\" kernel gates keep reddening as the company is turned back on, and the honest fix"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-02T20:35:12.686Z
---

The founder noticed (2 Sep 2026) that the Phase C and Phase D kernel gates "keep" failing — "seems
like a consistent issue." The diagnosis, grounded:

These two gates run **against live production** (not a fixture) and enforce zero-tolerance invariants
over the whole running company. One of them — `a_failed_scheduled_run_has_a_reader.test.mjs` — asserts
"**no agent run has errored since the 16 Aug stand-down except an explicitly disclosed list**"
(WATERMARK `2026-08-16 06:15:00Z`). That was trivially green while the company was stood down (166
crons off — nothing ran). As the company is turned back ON (Step 1 crons, Step 2 dispatch/approval
runtime), each re-enabled worker's FIRST real production error changes "the set of errored agents,"
which the gate flags. It is not flaky and not one bug — it is the same structural fact each time.

The deepest cause: **the company's core function (an agent reasoning) requires the paid model
(OpenRouter), which is deliberately OFF until launch.** So any cron that drives an agent errors until
then. Measured example: `workflow_dispatch` claimed a workflow step every 10 min and called the model
to write the deliverable; `fn_kernel_paid_provider_gate` returns allowed:false (rule `founder_hold`, 8
of 8 routes open-circuit), so the model returned nothing and it logged "the model returned nothing".

**Why:** a stand-down-era "zero errors" invariant is at odds with a running company; running software
errors (held provider, transient, surfaced stalls).

**How to apply:** the honest fix is NOT to weaken the gate. It is (1) make an LLM-dependent worker
IDLE CLEANLY when the paid gate denies — check `paidProviderGate(admin, SONNET_FIRST[0])` before doing
work; if `!allowed`, do nothing and return ok (workflow_dispatch v12 does this, resumes at launch); and
(2) disclose the historical rows in the test's `DISCLOSED_AFTER_THE_WATERMARK` with their real
held-provider cause (the same mechanism resend_inbound uses). Never delete the error rows, never move
the watermark. The gate still catches any NEW undisclosed errored agent. Expect to repeat this for
every LLM worker a step re-enables until OpenRouter is switched on at launch. See
[[the-tier-is-the-bill-not-the-prompt]], [[out-of-credit-looks-like-model-judgement]].
