---
name: the-deterministic-close-documents-rather-than-performs
description: fn_workflow_step_deterministic_done writes used_llm:false as an unconditional literal and closes a step advisory while recording that its executor never ran; the step-1 deliverable is byte-identical across 27 change_deployment runs with 27 different inputs
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-04T11:49:06.389Z
---

Found by an adversarial verification pass on 4 Sep 2026 that refuted five of six claims about the
revived loop. Verified by hand afterwards; every number below is measured.

- `fn_workflow_step_deterministic_done` writes `jsonb_build_object('used_llm', false, 'disposition',
  'deterministic_low_confidence', ...)` **unconditionally**. The flag is therefore true of that path
  by construction and is NOT evidence that the loop is model-free — quoting it as proof is circular
  ([[an-expectation-typed-into-its-own-check]], [[a-committed-constant-beat-the-record-it-described]]).
  The same literal disposition lands on all 219 `review_queue` rows company-wide, so the escalation
  flag cannot discriminate a step that needs narrative from one that does not.
- A step closed this way carries `mode='advisory'` and `stranded_reason='executor runs on the held
  paid model; not queued'` — the row is honest, but **done means documented, not performed**.
- **27 change_deployment step-1 rows carry exactly 1 distinct deliverable** across 27 distinct
  inputs. The applier renders the playbook's own text; it does not determine anything from the step.
- change_deployment has **never completed a run**: 27 runs, 0 done, ever; step 9 has never finished.
  Steps completing is not runs completing.
- 30 of metric_lifecycle's 43 done runs (the August cohorts) were model-ON and carry no `used_llm`
  key at all; only the 13 newest are model-off.
- 8 org_tasks closed to done on 4 Sep with `result` NULL, `decided_by` NULL, 0 attempts: a **second,
  unguarded closing path** exists beside the spine. All-time 656 done, 36 through the spine.

**How to apply:** to claim the loop runs model-free, measure the provider ledgers
(`llm_attempt`, `ai_cost_log`) and the gate, never the step's own flag. To claim a step was WORKED,
require a deliverable that varies with the input and an executor invocation, not a close.
