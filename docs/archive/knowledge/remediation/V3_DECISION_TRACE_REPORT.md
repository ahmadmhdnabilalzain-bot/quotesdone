> **Archived 16 Nov 2026** (simplification wave B, it_engineer): it describes the V3 certification and remediation programme of Aug 2026; the agent_brain, agent_train and os_api functions it ran on are gone from supabase/functions. 8 of the 10 routines it names are gone from production (SELECT pg_proc, 16 Nov 2026). History, not the build today.

# V3 REMEDIATION — STAGE 3: DECISION TRACE

**Scope of this document.** This is an internal engineering record of what was built and what was
measured on staging (`pglpqrhvozwepymcuunn`). **It certifies nothing.** Only an independent
evaluator can certify a role, a department or a category, and none has re-run since
`V3-COR-0A782DA90B10`. Every claim below that is not backed by a query I ran in this session is
marked as unmeasured.

**Measurement snapshot: 2026-08-14 14:18:18 UTC.** The staging database was being written to by
concurrent work while I measured, so trace counts move. Where a count matters I give the snapshot
time with it.

---

## 1. Baseline: what the certification recorded, and what the database showed

The result of record logged `TRACE_OR_OBSERVABILITY_FAILURE` on **2,284 of 2,284** questions —
`decision_trace_id` null on every execution row, decision-trace completeness 0%.

Measured now, split at the deploy boundary (`select count(*) from decision_trace where created_at <
'2026-08-14 13:38:00+00'` / `>=`):

| | rows |
|---|---|
| `decision_trace` rows written **before** the fix | **1** |
| `decision_trace` rows written **after** the fix | **30** |
| `agent_actions` total | 212 |
| `agent_actions` with `decided_at` set | 18 |

One trace, from 6 August, against 212 action rows. The table existed and the trigger existed. The
table was simply not on any path an agent takes.

---

## 2. Every field the stage requires, and where it comes from

Column list from `select column_name, data_type from information_schema.columns where
table_schema='public' and table_name='decision_trace'` — 46 columns. Population measured over the
23 `decision_type='agent_brain_turn'` rows present at 14:17:31.

| Field the stage requires | Column | Carried? | Source |
|---|---|---|---|
| Who decided (runtime agent) | `agent_key` | **yes**, 23/23 | server-side, `fn_write_decision_trace` rejects a null `agent_key` outright |
| Under which canonical role | `role_id` | **yes**, 23/23 | resolved server-side from `org_role_identity`; the model cannot label its own trace |
| Department / reporting line | `department_id`, `manager_id` | **yes**, 15/15 at the earlier probe | `org_agents` join inside the writer |
| What was decided | `proposed_action` | **yes** | `agent_brain/index.ts:594`, first 2,000 chars of the reply |
| Which tools were asked for | `tools_requested` | **yes**, 20/23 non-empty | `loop.requested`, index.ts:627 |
| Which tools actually ran | `tools_executed` | **yes**, 20/23 non-empty | `loop.executed`, index.ts:628 |
| Tool results, hashed | `tool_result_refs` | **yes** | `loop.refs`, index.ts:629; each entry carries `call_id`, `status`, `rows`, `hash` |
| Evidence | `evidence_refs` | **yes on 20/23** | index.ts:626 — **it is the tool-result list**, see §5 |
| Knowledge retrieved | `knowledge_refs` | **yes** | read back from `agent_context_retrieval`, index.ts:617-625 — recorded, not asserted |
| Confidence | `confidence` | **partial**, 8/15 at probe | only when the model states one |
| Uncertainty basis | `uncertainty` | **yes**, 15/15 | derived from the agent's own stated confidence, index.ts:597 |
| Authority / escalation | `escalation_decision` | **yes**, 23/23 | index.ts:604-613; escalation vs delegation resolved from `org_agents.manager_key`, not guessed |
| Company objective | `company_objective` | **yes**, 15/15 | read from `company_goals.revenue_annual` — "Reach AED 1,000,000 annual revenue (1000000 AED)" |
| Department objective | `department_objective` | **yes**, 15/15 | `org_departments.north_star` |
| Output status | `final_status` | **yes**, 23/23 | `answered` / `tool_loop_exhausted` / `tool_unavailable` / `no_answer` |
| Outcome status | `outcome_status` | **yes** | `blocked` when incomplete, else `pending` |
| Sealed | `sealed_at` | **yes**, 23/23 | `fn_seal_decision_trace`, index.ts:635 |
| Correlation id | `correlation_id` | **yes**, not null by constraint | passed from the turn |
| Alternatives / assumptions | `alternatives`, `assumptions` | **partial**, 5/15 non-empty | only from handoff payloads |
| **Relevant KPI** | `relevant_kpi` | **NO — 0/23** | column exists, writer accepts it, `agent_brain` never sends it |
| **Review date** | `review_date` | **NO — 0/31 rows in the table** | not sent |
| **Expected outcome** / **task id** | `expected_outcome`, `task_id` | **NO — 0/15** | not sent from the chat path |
| **Model / provider / tokens / cost** | `model`, `provider`, `input_tokens`, `output_tokens`, `estimated_cost_aed` | **NO — 0/31** | not sent; cost lives in `llm_attempt` instead |
| `risk`, `authority_result`, `decision`, `knowledge_versions`, `source_freshness` | | **empty on 15/15** | populated only by the `agent_actions` trigger path |

Nine required fields are structurally present and never written. `review_date` is the one that
matters most: `CMP-LN-01` ("set a dated review and say what evidence will be read at it") scored
39.93%, and the trace cannot evidence it while every row reads `no review date`.

---

## 3. A real agent turn

`select ... from decision_trace where decision_type='agent_brain_turn' and final_status='answered'
and cardinality(tools_executed)>0 order by created_at desc limit 1`:

```
id                   fbc99908-4634-4d91-b31c-0c0b0b382634
correlation_id       f32145c4-e013-4719-96f3-546d588c04f2
created_at           2026-08-14 14:16:21.963961+00
agent_key            bi_analyst
role_id              data-analytics-and-intelligence-analyst-controller
department_id        data_intel        manager_id  intel_director
task_class           agent_reasoning
company_objective    Reach AED 1,000,000 annual revenue (1000000 AED)
department_objective Every company goal has a measured actual, and every agent
                     retrieves knowledge that is current
tools_requested      [ops_knowledge_search, knowledge_search, query_platform,
                      query_platform, ops_knowledge_search, ops_knowledge_search]
tools_executed       (identical, 6/6)
tool_result_refs[0]  {"tool":"ops_knowledge_search","status":"ok","rows":5,
                      "call_id":"a3d51624-4d59-4d68-88af-bdd1285b96bf",
                      "hash":"c8010aff788471e81de1c95118716232c0cee2ebe01b9d652e6e53a2eba178c6"}
evidence_refs        6 entries, same hashes
knowledge_refs       0            confidence 0.75
uncertainty          had the facts and the expertise
escalation_decision  delegated    review_date  NULL   relevant_kpi NULL
final_status         answered     sealed_at    2026-08-14 14:16:22.070691+00
model/provider/tokens/cost  all NULL
```

Six tools requested, six executed, six results hashed before the model saw them, sealed 107 ms after
the row was written. `knowledge_refs` is 0 here because that turn's context assembly failed — the
agent said so in its own answer ("My context load failed this turn, so I'm working only from live
tool queries"), and the trace agrees with it rather than papering over it.

---

## 4. Management can read the traces

`select * from fn_management_decision_review(null, 7, 8)` returned 8 rows carrying `trace_id`,
`agent_key`, `role_id`, `department_id`, `manager_id`, `tools_executed`, `knowledge_count`,
`evidence_count`, `sealed`, and a `gap` string naming what is missing rather than presenting an
incomplete trace as complete. Gaps returned: `no review date`, `no confidence; no review date`,
`no evidence; no review date`. `security definer`, revoked from `public`, `service_role` only.

---

## 5. The completeness gate

`select count(*) from v_decision_trace_incomplete` → **7** at 14:17:31. Not zero. All seven,
listed and characterised:

| # | created | agent | type | what is missing | what it actually is |
|---|---|---|---|---|---|
| 1 | 06 Aug | *(null)* | `route_category` | role, authority, output status | the single pre-remediation trace. Its `entity_id` is `10`, which matches no `agent_actions` row, so the repair-11 backfill correctly left it alone rather than inventing an identity |
| 2-3 | 14 Aug 13:38 | `cfo` | `handoff` | evidence | `evidence_refs` is a JSON **object** (`{"kind":"handoff","basis":"deterministic rule from live platform data"}`), not an array. Counted as zero evidence — see defect 2 |
| 4-5 | 14 Aug 14:14 | `ops_director` | `coverage_gap` | evidence | same shape, same reason |
| 6-7 | 14 Aug 14:00 / 14:04 | `contract_specialist` | `agent_brain_turn` | evidence | **genuine.** Both are pure-knowledge legal questions answered with `tools_executed = []`. Zero tools means zero evidence |

Measured across all 23 brain turns: `jsonb_array_length(evidence_refs) = jsonb_array_length(tool_result_refs)`
on **23 of 23**; 20 turns with tools all have evidence; 2 turns with no tools have none. So
`evidence_refs` is exactly the tool-result manifest. Retrieved knowledge (`knowledge_refs`, 63
records on most turns) does **not** count as evidence. That is a defensible definition, but it means
a correct, well-sourced answer from the knowledge base alone will always fail this gate. Either
`knowledge_refs` should count, or the answer contract must require a citation. **Not decided, not
built.**

---

## 6. A runtime agent cannot alter completed evidence

`select public.fn_trace_edit_is_blocked(id)` run on the newest sealed and newest unsealed trace:

| trace | sealed | `edit_blocked` |
|---|---|---|
| `74b6abb7…` `agent_brain_turn` | true | **true** |
| `0a3e0369…` `coverage_gap` | false | false |

The probe attempts the forbidden `confidence` edit inside its own subtransaction and answers from
state. `false` on the unsealed row is correct behaviour, not a failure: an unsealed trace is meant to
be editable. I re-read that row afterwards — `confidence` is still `0.9`, so the probe left nothing
behind.

---

## 7. The two defects

**Defect 1 — a trigger that could not fire.** The only writer was
`AFTER UPDATE OF decided_at ON agent_actions ... WHEN (old.decided_at IS NULL AND new.decided_at IS
NOT NULL)`. `os_api` INSERTs action rows with `decided_at` **already set**. An UPDATE-of trigger
never sees an INSERT, so on that path it could not fire at all — not "fires rarely", cannot fire.
The trigger looked healthy in every schema listing while the table stayed at one row.

Fixed by adding `z90_agent_action_decision_trace_ins AFTER INSERT ... WHEN (new.decided_at IS NOT
NULL)` (`v3_repair_02_decision_trace.sql:193-197`). Both triggers exist now, confirmed in
`pg_get_triggerdef`. Proven with an aborted-transaction probe: a `DO` block inserted one
`agent_actions` row with `decided_at = now()`, counted the traces, then raised, rolling the whole
thing back —

```
PROBE_RESULT action_id=522 traces_written=1 agent_key=cfo
             role_id=finance-director dept=finance final_status=proposed
```

`select count(*) from agent_actions where id=522` → **0**. The probe row is gone.

Repair 11 then repointed the *old* UPDATE-path function at the same shared row builder, so both
paths produce one trace shape. Evidence that this worked: traces `da9c10e8` and `164480b6` point at
actions 370 and 369, created 12 August and decided 14 August 13:38 — the UPDATE path — and they now
carry `agent_key=cfo, role_id=finance-director`, which the original body never wrote.

**Defect 2 — the monitor raised instead of reporting.** `v_decision_trace_incomplete` and
`fn_management_decision_review` both called `jsonb_array_length(evidence_refs)` unguarded. The column
defaults to `'[]'` but pre-remediation writers stored a jsonb **object** there (visible above on the
`handoff` and `coverage_gap` rows), and `jsonb_array_length` raises `22023: cannot get array length
of a non-array`. The completeness gate therefore *errored out* rather than returning rows — and an
erroring check reads exactly like a passing one to anything that counts rows. Guarded with
`jsonb_typeof(...) is distinct from 'array'` in `v3_repair_12_trace_view_typeguard.sql:19-27`; a
non-array now counts as zero evidence, which is the honest reading. The view executes cleanly now —
that is what produced the 7 rows in §5.

A third, smaller one is worth recording: the regression harness first reported the seal guard as
dead because it string-matched the exception text coming back through the API wrapper. The guard was
working. `fn_trace_edit_is_blocked` (`v3_repair_13`) replaced the string match with a state check.

---

## 8. What the traces are connected to — and what they are not

Measured by scanning `pg_get_functiondef` for every `public` function mentioning `decision_trace`,
by `Grep` over `src/` and `supabase/functions/`, and by querying `cron.job`.

**Connected today:**
- **Written** by `agent_brain/index.ts:588` on every turn, sealed at :635. 23 turns so far.
- **Written** by both `agent_actions` triggers via `fn_agent_action_trace_row`.
- **Readable** by `fn_management_decision_review` — returns rows, `service_role` only.
- **Read** by `fn_decision_outcomes`, `fn_ws_supplier_360` (the supplier 360 panel surfaces
  `decision_trace` rows where `entity_id` matches the supplier), and by
  `fn_unsafe_check_unstated_assumption` / `fn_unsafe_check_credential_exposure` from stage 9.
- **Guarded** by `a00_decision_trace_immutable` on every UPDATE.

**Not connected:**
- **Nothing in `src/` reads `decision_trace`.** Grep over the whole `src/` tree: zero matches. There
  is no founder-facing screen for this.
- **`os_api` does not expose it.** Zero matches for `decision_trace` or `decision_review` in
  `supabase/functions/os_api/index.ts`. `fn_management_decision_review` is a finished capability
  with no entry point — nobody can click it.
- **No cron job reads it.** `cron.job` has one trace-named job, `approval_trace_audit_weekly`, and it
  calls `fn_approval_trace_audit()` against a different table. The two cron jobs that mention
  `decision_trace` (`v3_role_readiness_daily`, `v3_category_readiness_daily`) only emit the *string*
  `'decision_trace_connected'` as a status label — they do not read the table.
- **No KPI review, no remediation loop and no future certification harness reads it.** Not built.
- **There is no `decision_trace_id` column anywhere in the schema** — `information_schema.columns`
  returns zero rows for `column_name ilike '%decision_trace%'`. The certification measured
  `decision_trace_id` on its own execution rows; nothing on our side persists the returned id, so
  "100% non-null trace ids for consequential runs" **cannot be measured from stored state**. What
  can be, and is: 23 of 23 `agent_brain_turn` rows carry role, authority decision and output status,
  and all 23 are sealed.

---

## 9. Still broken or unverified

1. `v_decision_trace_incomplete` is **7, not 0**. Five are the jsonb-object evidence shape from
   non-brain writers; two are real turns that used no tools. The gate is honest; it is not green.
2. Nine schema fields are never written: `review_date`, `relevant_kpi`, `expected_outcome`,
   `task_id`, `model`, `provider`, `input_tokens`, `output_tokens`, `estimated_cost_aed`.
3. `confidence` is null on 7 of 15 turns measured — every one of them a `blocked` turn.
4. The `handoff` and `coverage_gap` writers still store an object in `evidence_refs`. Not fixed;
   only made non-fatal.
5. **Staging only.** Nothing in this stage has been promoted to production, and `--promote` carries
   the routine body without the `REVOKE`/`GRANT` lines — the grants on `fn_write_decision_trace`,
   `fn_seal_decision_trace`, `fn_management_decision_review` and `fn_trace_edit_is_blocked` must be
   applied to production separately or those functions land anon-executable.
6. The measured population is **23 turns**, from one afternoon, on staging. The certification ran
   2,284. Nothing here predicts behaviour at that volume.
7. **No independent evaluator has re-run.** Nothing in this document is a certification result.
