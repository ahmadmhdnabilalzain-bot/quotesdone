# Knowledge retrieval coverage

Measured 14 Aug 2026 on production `htdblwldjkcgjvmqkbeh` · blueprint
`runtime_blueprint/KNOWLEDGE_RETRIEVAL_CONTRACT.md`.

## Status: `EXISTING_BETTER_KEEP`, after two repairs today

Measured through `fn_agent_context_v3` — the assembler the runtime actually calls, not a
re-implementation of it — for all 90 accountable roles:

| | roles |
|---|---|
| retrieve **role** knowledge | **90 / 90** |
| retrieve **department** knowledge | **90 / 90** |
| retrieve **company core** | **90 / 90** |
| errored | **0** |
| average records assembled per role | 70 |

8,256 runtime-eligible current records across 11 layers: `company_core`, `department_shared`,
`role_specific`, `category_specialist`, `decision_playbook`, `policy`, `authority`, `kpi`,
`failure_mode`, `remediation`, `source_reference`.

## Two things that were broken this morning

**1. Production was retrieving with the filter switched off.** `fn_context_slice` on production
ended `tsv @@ p_q or true` — a tautology that disabled lexical filtering entirely, so every task
retrieved from the whole corpus rather than from what matched it. Confirmed by testing the predicate
with comments stripped, because a substring search for `or true` also matches the comment saying it
was removed. Fixed and promoted, with its four helper routines, in dependency order.

**2. The assembler answered to one spelling only.** `fn_agent_context_v3('chief_of_staff')` returned
`{"error":"unknown agent"}` — and `chief_of_staff` is `brief`'s own `role_id`. An employee addressed
by its canonical role id, a merged-away key, a packaged role id or a job title assembled **no
context at all**: not an error the caller sees, an empty prompt, on the hottest path in the company.
It now resolves before assembly.

## Why the merge did not orphan 5,775 records

5,775 `ops_knowledge` rows are tagged with the 22 department keys that stopped existing when 25
departments became 10. Retrieval matches `dept_key = any(fn_dept_scope(p_dept))` rather than
`dept_key = p_dept`, so a department that absorbed another reaches its predecessor's knowledge
without a single row being rewritten. Orphaned runtime-eligible records: **0**.

## An instrument fault worth recording

A first pass at this report asked "how many roles have `ops_knowledge` at layer `role_specific` with
`role_key = org_role.role_id`?" and got **90 of 90 missing** — which, by the rule that a check
failing for an entire population is measuring the wrong thing, was the check being wrong.
`role_key` holds the **packaged** role id (`administration-and-operations-director`), which is
exactly what `fn_agent_context_v3` passes after resolving the agent's identities from
`org_role_identity`. 576 role-layer rows across the 96 packaged roles. The retrieval was correct;
the question was not.

## Open

- **Retrieval is keyword, not vector, on five of six paths.** `kb_match` is the only vector path and
  agents reach it through the `kb_search` edge function (hybrid keyword + vector, RRF). 81.2% of
  `kb_chunks` on production carry an embedding; the rest are reachable by keyword only.
- Category knowledge for the 86 overlays is present for all 86 (see
  `CATEGORY_OVERLAY_SMOKE_RESULTS.csv`), but the *behavioural* half — minimum-sufficient questioning,
  refusing to infer — needs the model and is covered by Gate B/C rather than here.
