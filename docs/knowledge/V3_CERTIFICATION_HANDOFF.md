# V3 certification handoff

14 August 2026. For the independent evaluator. Written by the builder session, which holds no
certification questions and no answer key.

## What the builder session did and did not receive

The package it was given —
`QuotesDone_AGENT_KNOWLEDGE_V3_RUNTIME_TRAINING_ONLY_v2026.08.14` — intentionally excludes
both certification archives. `SHA256SUMS.txt` lists them and they are not in the bundle:

- `QD_AGENT_V3_CERTIFICATION_QUESTIONS_ONLY_v2026.08.14.zip` — `228f15fc…` — **absent**
- `QD_AGENT_V3_CERTIFICATION_ANSWER_KEY_EVALUATOR_ONLY_v2026.08.14.zip` — `f2905a51…` — **absent**

**Confirmation: no evaluator package or answer key was accessed, searched for, opened,
imported, embedded or exposed during this session.** No local folder, repository history,
other conversation, Dropbox or connected storage was searched for evaluator material.

The V2 delivery embedded in the runtime bundle *does* contain 4,550 certification and
evaluation records with their expected answers, across 389 files. They were counted and left
on disk. They are not in `ops_knowledge`, not in `agent_training_case`, and not in `cert.*`.
Loading them is the evaluator's decision, not the builder's.

## The interface

Schema `cert`, created empty on both projects, with `USAGE` granted to nobody. Row-level
security is enabled on all three tables with **zero policies**, which denies every non-owner
role. Measured on both projects: `anon`, `authenticated` and — the one that matters —
`service_role` have no `USAGE` on the schema and no SELECT on the answer key. Every edge
function runs as `service_role` and `service_role` bypasses RLS, so a grant there would have
made the RLS boundary decorative. Only the `postgres` owner can reach it.

### `cert.certification_question`
```
question_id      text primary key
scope_type       text          -- role | department | category | cross_company
scope_key        text
package_version  text
payload          jsonb
loaded_at        timestamptz
```

### `cert.certification_answer_key`
```
question_id      text primary key
package_version  text
payload          jsonb
loaded_at        timestamptz
```
Empty, and it must stay empty until the immutable first result exists. **The builder must not
receive the answer key before that result is recorded.**

### `cert.certification_result` — append-only
```
result_id        uuid primary key
question_id      text
agent_key        text
packaged_role_id text
answered_at      timestamptz
raw_output       text
score            numeric
passed           boolean
environment      jsonb
evaluator        text
```
`UPDATE` and `DELETE` raise `cert.certification_result is append-only`. Tested.

## Running a candidate

The agent under test is exercised through the same runtime path production uses. Nothing
special is switched on for the exam.

```sql
-- what the agent knows about itself and its task, and which records it read
select fn_agent_context_v3(
  p_agent_key    => 'cfo',
  p_task_class   => 'finance_decision',
  p_task_text    => '<the question text>',
  p_category_key => null,
  p_budget_chars => 24000);
```

The returned object carries `identity` (agent, department, manager, packaged role ids,
authority, readiness), `deterministic_rules`, `company_core`, `department_knowledge`,
`role_knowledge`, `category_knowledge`, `validated_experience`, `live_data_required`, `tools`,
`company_objective`, and `knowledge_ids` — the ids to record in `environment` alongside the
model and prompt versions.

For a category specialist:

```sql
select fn_category_checklist('<route slug or trade slug>', '<label>', '<inquiry text>');
select fn_category_quote_ready('<route slug>', '<spec jsonb>');
```

## Environment fingerprint to record with each result

| field | where it comes from |
|---|---|
| knowledge package version | `2026.08.14` |
| ingestion run | `knowledge_ingestion_run.run_id` for the run that loaded the corpus |
| knowledge record ids used | `knowledge_ids` from `fn_agent_context_v3` |
| role identity | `org_role_identity` rows for the agent |
| readiness at test time | `org_role_identity.readiness` |
| model and provider | the gateway's own response fields |
| code version | git SHA of `feature/agent-knowledge-v3-runtime` at merge |

## Readiness at handoff

| readiness | production | staging |
|---|---|---|
| `restricted_to_advisory` | 47 | 47 |
| `runtime_mapped` | 36 | 36 |
| `knowledge_imported` | 34 | 34 |
| `live_data_connected` | 7 | 8 |
| `decision_trace_connected` | 5 | 4 |
| `blocked` | 1 | 1 |
| `independent_certification_pending` | 0 | 0 |
| `certified_for_defined_role_scope` | **0** | **0** |

**No role reached `independent_certification_pending`.** That rung requires `training_passed`,
and no agent has yet been driven through a training case by a runner — the loop is built,
tested and gated, but it has not been run in anger. Claiming the rung would be claiming a
result nobody produced.

`fn_role_readiness_recompute()` raises if `certified_for_defined_role_scope` ever appears, so
the one word that belongs to the evaluator cannot be set by a build.

## What must be true before consequential autonomy

1. `cert.certification_result` holds an immutable first result per role under test.
2. The evaluator, not the builder, holds the answer key at that moment.
3. Zero critical-boundary failures for the role.
4. `fn_agent_autonomy_blocked(agent_key)` returns `blocked: false`.
5. Readiness reaches `certified_for_defined_role_scope`, set by the evaluator.

Until then the three go-live switches stay off, and the 47 roles whose departments hold
consequential executors stay advisory.

## No role is certified

**No role has been labelled human-equivalent, expert, or independently certified by this
session.** The corpus is imported, the runtime retrieves it, the traces name it, the loops
gate on it, and 42 behavioural tests pass on both projects. That is a system ready to be
examined — not a system that has passed one.
