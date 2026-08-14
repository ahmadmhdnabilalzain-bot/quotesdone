# V3 runtime connection report

14 August 2026. What is connected to a real caller, and what is not.

The rule this document is written against: **a role is not integrated because its knowledge
exists in Supabase.** Every path below names the caller that actually runs it.

## The path

```
task / event / customer request
  → exec_agents · dept_plan · agent_brain · action_worker      (the runners that already existed)
  → fn_agent_context_capped(agent_key, budget, query)          (the path they already called)
  → fn_agent_context(agent_key, budget, query)                 (extended: layers 2d, 2f, 2g)
  → fn_agent_context_v3(...)                                   (identity, rules, role, category, live-data)
  → fn_record_context_retrieval(...)                           (what was actually read)
  → agent_actions                                              (the decision)
  → z90_agent_action_decision_trace                            (trace naming those knowledge ids)
```

## Connected paths and their callers

| path | caller proved | evidence |
|---|---|---|
| `fn_agent_context_v3` | `fn_agent_context(text,integer,text)` | 50/50 behavioural tests |
| `fn_agent_context(text,integer,text)` | `fn_agent_context_capped` | already called by `agent_brain`, `action_worker`, `dept_plan`, `agent_act`, `blog_weekly`, `boost_recommend`, `content_revise`, `designer`, `knowledge_exam` |
| `fn_record_context_retrieval` | `fn_agent_context(text,integer,text)` | one row per assembly; measured 63 knowledge ids for `cfo` |
| `z90_agent_action_decision_trace` | any decided `agent_actions` row | probe: 1 trace, knowledge ids carried through |
| `fn_category_checklist` | `inquiry_ai` (deployed v23 on both) | all 86 routes return their own corpus |
| `fn_category_quote_ready` | `fn_category_checklist` consumers | blocks and names the missing mandatory fields |
| `fn_artifact_publish_blocked` | `postiz_publish` | refuses to upload an image with no passing review of those bytes |
| `artifact_review` edge function | `org_action_executor` class `artifact.review`, invoked by `cos_execute` | measured a real 1859×460 PNG and failed it for an Instagram feed slot |
| `fn_propose_lesson` / `fn_validate_lesson` | learning loop; retrieval reads `validated` only | proposed lesson invisible, validated lesson retrievable |
| `fn_assign_training` / `fn_remediation_step` | `agent_train` edge function | 5 practice + 5 retest cases, 0 overlap |
| `agent_train` edge function | `org_action_executor` class `agent.train`, invoked by `cos_execute` | ran on both projects: real answers, real scores, real cost |
| `fn_role_readiness_recompute` | cron `v3_role_readiness_daily` | readiness derived from evidence daily |
| `fn_knowledge_freshness_sweep` | cron `v3_knowledge_freshness_daily` | stale records labelled, not hidden |

## What this fixed

**`decision_trace` had four rows.** All four written on 6 August by `fn_decide`, a
20,000-character decision engine with **no caller in any function, edge function or script**.
576 agent actions were decided in the seven days before this session and not one left a trace.
The schema was right; there was no entry point. There is one now, and it carries the knowledge
record ids the assembly actually returned rather than a prose summary.

**`playbook_for` has no callers either** — it is read by nothing at runtime, and
`qualification_playbooks` covers 29 of 86 categories. It was left alone: the packaged question
bank now reaches the estimator through `fn_category_checklist`, which is on the path
`inquiry_ai` already runs.

**The category checklist was keyed on a vocabulary that could not see the routes.**
`category_specs` holds 56 customer-facing trade slugs; `kb_operational_route` holds the 86
catalogue routes. **Zero of the 56 matched a route key.** So 30 routes had no checklist at all
and the estimator was told the reference list was empty. All 86 now return a question bank, a
mandatory-field list and a never-infer list.

**A filter on a value nothing writes.** The first version of the context assembler read the
company objective with `where horizon = 'company'`. `company_goals` holds `year_1` and
`quarter` and has never held `company`, so every context reported the objective as `[]`. Found
by the behavioural test, not by reading the code.

## Not connected

| thing | status | why |
|---|---|---|
| `fn_decide` | `not_connected` | the 20k-char engine still has no caller. The trace it was written to fill is now filled by the trigger; wiring `fn_decide` itself is a separate change with its own behavioural evidence. |
| `playbook_for` | `not_connected` | superseded in practice by `fn_category_checklist`; left in place rather than deleted in the same session that replaced its function |
| `cert.*` | empty by design | the evaluator loads it; see `V3_CERTIFICATION_HANDOFF.md` |
| vision review of video | `connected` | `artifact_review` reads MP4/MOV duration and display size from the container with no decoder (verified: 320x176, 10.027s on a known sample), and reviews supplied frames in playback order for per-frame defects AND broken transitions. A video with no frames is blocked, never passed. |
| frame production | `not_connected` | the reviewer needs frames and nothing in the repository produces them yet. The producing pipeline must send `frames: [url, ...]` — poster plus 3 to 8 stills in playback order. Until it does, every video is blocked, which is the correct state. |
| training at scale | `connected, not exercised` | `agent_train` drives an agent through unseen cases and scores them, proven on both projects. It has been run for five agents, not ninety-three: every case is two model calls, so it runs on demand and not on a cron. No role has completed a remediation cycle yet, which is why none is `training_passed`. |
| 25.6% of the training corpus | `not_scorable` | 4,574 of 17,890 cases state no requirement this grader can read. Coverage went 55.8% → 74.4% once the extractor learned the twenty key names the families actually use; the rest carry only a situation and a task. |

## Readiness

Derived from evidence by `fn_role_readiness_recompute()`, never declared.

| readiness | production | staging |
|---|---|---|
| `restricted_to_advisory` | 47 | 47 |
| `runtime_mapped` | 36 | 36 |
| `knowledge_imported` | 34 | 34 |
| `live_data_connected` | 7 | 8 |
| `decision_trace_connected` | 5 | 4 |
| `blocked` | 1 | 1 |
| `certified_for_defined_role_scope` | **0** | **0** |

The two projects differ by one row because readiness is computed from live evidence —
retrievals and actions — and the projects have different traffic. The function is byte-identical
on both.

47 roles are `restricted_to_advisory`: their department holds consequential executors and no
agent in it has passed training. That is the correct state, and it is the reason the
consequential-autonomy switches stay off.

All 86 category identities are `decision_trace_connected`: their route resolves and their
corpus is retrievable.
