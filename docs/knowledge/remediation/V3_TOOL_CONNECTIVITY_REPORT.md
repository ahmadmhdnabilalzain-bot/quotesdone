# V3 REMEDIATION — STAGE 2: TOOL CONNECTIVITY

**Scope of this claim.** This document reports internal measurements taken on the staging project
`pglpqrhvozwepymcuunn` on 2026-08-14. **It certifies nothing.** No role, department or category is
certified by anything written here; only an independent evaluator can certify, and the standing
result of record remains `V3-COR-0A782DA90B10` at 56.97% with 0 of 96 roles certified. Every figure
below is followed by the query or `file:line` that produced it. Where a property could not be
measured, that is stated rather than estimated.

**The defect this stage answers.** The certification recorded `TOOL_NOT_CONNECTED` on 2,284 of 2,284
questions: `tool_calls` non-empty on every execution row, `tool_results` empty on every one. Every
answer was written from prompt memory while the rubric scored evidence discipline.

**Ledger snapshot, pinned.** All call counts below come from one query with an explicit cutoff so
they are reproducible:

```sql
select * from agent_tool_call where created_at < timestamptz '2026-08-14 14:16:12+00';
```

100 rows · 20 correlation ids · 13 agents · 9 distinct tools · ok 76 · ok_empty 14 · error 10 ·
timeout 0 · unavailable 0 · unauthorised 0.

**The table is live and was being written while this was measured.** An earlier snapshot at
14:13:41Z read 77 rows. A concurrent workstream shipped two dispatcher fixes at ~14:12Z, so the
population must be split by that boundary — see §2(c).

---

## 1. Tool inventory — every row in `agent_tool`

Read from the table (`select * from agent_tool order by kind, tool_id`), not retyped from
`scripts/sql/v3_repair_01_tool_registry.sql`.

### 1.1 Identity, authorisation, availability

| tool_id | kind | impl | target | roles | departments | min auth | credential | staging | prod |
|---|---|---|---|---|---|---|---|---|---|
| `binding_constraint` | read | rpc | `fn_binding_constraint` | `{*}` | `{*}` | advisory | — | yes | **no** |
| `dept_library_search` | read | rpc | `fn_dept_library_search` | `{*}` | `{*}` | advisory | — | yes | **no** |
| `handoff_inbox` | read | rpc | `fn_agent_handoff_inbox` | `{*}` | `{*}` | advisory | — | yes | **no** |
| `handoff_stalled` | read | rpc | `fn_handoff_stalled` | `{*}` | `{*}` | advisory | — | yes | **no** |
| `knowledge_search` | read | edge_function | `kb_search` | `{*}` | `{*}` | advisory | `cred_fn_agent_brain` | yes | **no** |
| `ops_knowledge_search` | read | rpc | `fn_ops_knowledge_search` | `{*}` | `{*}` | advisory | — | yes | **no** |
| `query_platform` | read | rpc | `fn_query_platform` | `{*}` | `{*}` | advisory | — | yes | **no** |
| `revenue_cascade` | read | rpc | `fn_revenue_cascade` | `{*}` | `{*}` | advisory | — | yes | **no** |
| `supplier_360` | read | rpc | `fn_ws_supplier_360` | `{*}` | `marketplace, supplier_success, supplier_knowledge, procurement, trust_safety, rfq_intelligence, exec` | advisory | — | yes | **no** |
| `record_commercial_effect` | **write** | rpc | `fn_task_commercial_effect` | `{*}` | `{*}` | advisory | — | yes | **no** |

`production_available = false` on **10 of 10**. Nothing in this registry is reachable in production.

### 1.2 Purpose (from `agent_tool.purpose`, abridged)

`binding_constraint` — the measured funnel stage limiting revenue now, unmeasurable stages listed
not silently excluded. `dept_library_search` — department reference library. `handoff_inbox` —
cross-department work waiting on this agent, with acceptance criteria and deadlines.
`handoff_stalled` — handoffs past deadline / accepted-never-closed / handed-back / orphaned, each
naming one accountable owner. `knowledge_search` — hybrid semantic + keyword over the category
corpus (registry note: "the only vector path in the runtime"). `ops_knowledge_search` — V3
operational knowledge for the caller's own department. `query_platform` — 21 live company-state
topics. `revenue_cascade` — AED 1,000,000 objective down to this role's KPIs. `supplier_360` —
current supplier dossier. `record_commercial_effect` — what a task is expected to be worth, or an
explicit no-effect with a reason.

### 1.3 Execution, failure and audit policy

| tool_id | timeout | attempts | backoff | failure behaviour | audit | current data required | stub permitted |
|---|---|---|---|---|---|---|---|
| `binding_constraint` | 15s | 2 | exponential_2s | degrade_with_caveat | trace | yes | **no** |
| `dept_library_search` | 15s | 2 | exponential_2s | degrade_with_caveat | trace | no | **no** |
| `handoff_inbox` | 10s | 2 | exponential_2s | degrade_with_caveat | trace | yes | **no** |
| `handoff_stalled` | 15s | 2 | exponential_2s | **fail_closed** | trace | yes | **no** |
| `knowledge_search` | 20s | 2 | exponential_2s | degrade_with_caveat | trace | no | **no** |
| `ops_knowledge_search` | 15s | 2 | exponential_2s | degrade_with_caveat | trace | no | **no** |
| `query_platform` | 20s | 2 | exponential_2s | **fail_closed** | trace | yes | **no** |
| `revenue_cascade` | 15s | 2 | exponential_2s | degrade_with_caveat | trace | yes | **no** |
| `supplier_360` | 15s | 2 | exponential_2s | **fail_closed** | trace | yes | **no** |
| `record_commercial_effect` | 15s | 2 | exponential_2s | **fail_closed** | trace | yes | **no** |

`stub_permitted = false` on **10 of 10**; `audit_behaviour = 'trace'` on **10 of 10**;
`requires_current_data = true` on **7 of 10**. There is no simulation path: `_shared/tools.ts`
`runOnce()` has exactly two implementation branches (`rpc`, `edge_function`) and throws
`unsupported impl_kind` otherwise — no stub branch exists to opt into.

### 1.4 Schemas

Input schemas are enforced deterministically before execution by `validateArgs()`
(`supabase/functions/_shared/tools.ts:78`): required keys, type, enum, `minLength`, `minimum`,
`maximum`, and `additionalProperties:false`. Examples as stored: `query_platform` requires `topic`
constrained to a 22-value enum with optional `args:object`; `supplier_360` requires
`supplier_id:integer minimum 1`; `knowledge_search` requires `query` (minLength 2) with optional
`k:1..20` and `category`; `record_commercial_effect` requires `task_id:integer` and declares 16
optional properties including `causal_kpi_chain:array<string>`, `measurement_window_days`,
`no_commercial_effect:boolean` and `no_effect_reason`.

**Output schemas are `{"type":"object"}` on 10 of 10.** Output is not contract-checked at all. That
is a real gap, not a formality — the registry declares an output contract column and no tool
populates it.

### 1.5 Reach across the roster

Via `select count(*) from org_agents a where active and fn_agent_tool_allowed(a.agent_key,'<tool>')`:
90 active agents across 10 departments. `query_platform` and `record_commercial_effect` reachable by
**90/90**; `supplier_360` by **22/90** — the only tool whose department list actually narrows.

Every row carries `authorised_roles = {*}`: authorisation discriminates by **department**, never by
role. Given that 59 of 96 certification roles share a runtime agent, a per-role grant cannot
currently be expressed or enforced. Flagged, not fixed.

---

## 2. Evidence for each guarantee

**(a) An authorised tool executes and returns a result.** 76 `ok` + 14 `ok_empty` = **90 of 100**
ledger rows carry a real result. Per tool: `query_platform` 28 calls / 28 ok; `ops_knowledge_search`
15/15 ok; `handoff_inbox` 7 (2 ok, 5 ok_empty); `dept_library_search` 6 (2 ok, 4 ok_empty);
`binding_constraint` 3/3 ok; `supplier_360` 3/3 ok; `revenue_cascade` 2/2 ok.

**(b) Result identity is recorded.** `count(*) filter (where status in ('ok','ok_empty') and
result_hash is null)` = **0**, and the mirror `count(*) filter (where status not in
('ok','ok_empty') and result_hash is not null)` = **0**. 41 distinct hashes over the first 77 rows.
The hash is taken over the exact bytes the model is shown, before it is shown them
(`tools.ts:230-238`: `rendered` is built, `sha256(rendered)` computed, then recorded).

**(c) Tool errors are visible.** 10 `error` rows, all with non-null `error` text
(`failed_without_error_text = 0`). Both error classes were real defects this stage found by
measurement, and both were fixed inside the session — so the population must be split by the fix:

| window | rows | ok | ok_empty | error |
|---|---|---|---|---|
| before 14:12:30Z | 68 | 52 | 6 | **10** |
| after 14:12:30Z | 32 | 24 | 8 | **0** |

* `knowledge_search` — 6 consecutive `edge_403` (14:02:50 → 14:11:28). Mechanism: `runOnce()`
  presented `app_secrets.inbound_secret`, but `kb_search/index.ts:20` calls
  `requireInternal(admin, body.__secret, 'kb_search')`, and the shared secret is not scoped to that
  function. Fix: the registry row now declares `required_credential = 'cred_fn_agent_brain'` and the
  dispatcher tries registry credential → caller credential → legacy secret. First `ok` 14:12:48,
  8 successes since, 0 failures.
* `handoff_stalled` — 4 × `Could not find the function public.fn_handoff_stalled(dept) in the schema
  cache`. Mechanism: the registry input schema names `dept`/`limit`; the routine signature is
  `fn_handoff_stalled(p_dept text, p_limit integer)`; the dispatcher's `default:` branch passed the
  model's raw argument names through. Fix: the default branch now prefixes unprefixed keys with
  `p_`. First `ok_empty` 14:13:49, 0 failures since.

Both were invisible to the pre-existing suite. They surfaced only because the ledger records the
error string per tool — which is the point of (c).

**(d) Empty is distinguishable from unreachable.** `ok_empty` and `error` are separate values in
`agent_tool_call_status_check` (`ok, ok_empty, error, timeout, unavailable, unauthorised`).
`countRows()` (`tools.ts:112`) classifies null / `[]` / `{}` / `rows:[]` as zero rows, and
`tools.ts:230` renders that as an explicit note telling the model this is a real answer meaning
"none found", not a failure and not permission to substitute an assumption. 14 `ok_empty` rows exist
and carry hashes; failures instead carry an `instruction` string keyed to `failure_behaviour`.

**(e) Unauthorised tools are refused.** Eight probes of `fn_agent_tool_allowed(agent, tool)`, all
eight matching expectation: `cfo→query_platform` true; `cfo→supplier_360` **false**;
`supplier_verification→supplier_360` true; `bi_analyst→supplier_360` **false**;
`contract_specialist→supplier_360` **false**; `cfo→record_commercial_effect` true;
`cfo→no_such_tool` **false**; `nobody_agent→query_platform` **false**. The refusal is server-side —
`callTool()` resolves grants from `fn_agent_tools` and returns `unauthorised` before validation or
execution (`tools.ts:200-210`); a prompt cannot widen its own set.

**Honest gap: the refusal branch has never fired in production data.** `unauthorised` count in the
ledger is **0**, and the last regression run recorded `unauthorised_tool_attempts_blocked: 0`. Zero
cannot tell a working guard from an idle one, so I forced the ledger half of it with an
aborted-transaction probe (write, count, `raise exception` to roll back):

```
PROBE_ROLLBACK rows=1 status=unauthorised no_hash=t call_id_returned=t
```

That proves `fn_record_tool_call` accepts and persists a refusal row with a null hash and returns an
id. It does **not** prove a live model was refused; no model has yet requested an ungranted tool.

**(f) Tool use is not simulated.** Three mechanisms, two of them live. (1) No stub path exists
(§1.3). (2) The hash ledger: every byte-string handed to a model is hashed into `agent_tool_call`
first, so a claimed result whose hash has no ledger row is provably fabricated. (3)
`verifyNoFabricatedResults(correlationId, injectedHashes)` (`tools.ts:289`) compares injected hashes
against the ledger and returns the unmatched ones.

**Honest gap: `verifyNoFabricatedResults` has zero call sites.** A repository-wide grep finds only
its own definition and a prose mention in `scripts/checks/build_v3_requirement_matrix.mjs:71`. No
edge function, check or cron invokes it. The evidence is recorded correctly; the detector is written
and unwired, so it is not an operating control.

**(g) A tool is not forced on every task.** `tool_choice` is never set on the agent path:
`agent_brain/index.ts:91` states it is left at the provider default, and `runWithTools` passes only
`{ tools, messages }` at line 119. `_shared/llm.ts:259` sets `tool_choice` only when the caller
passes `opts.toolChoice`; `ai_gateway/index.ts:536` forwards it only when present. Measured
behaviour: the negative regression case `REG-TOOLS-004` (contract_specialist, a definitions question
with no live-data content) executed **0 tools** and passed all four checks.

---

## 3. The ten behavioural cases — coverage, honestly

Seven `tools` cases are authored in `scripts/checks/v3_regression_cases.json`; **four ran** in the
last recorded run (`v3_regression_last_run.json`, `provenance.utc_now = 2026-08-14 13:57:12`).

| # | Case | Automated today? |
|---|---|---|
| 1 | required and succeeds | **Yes, executed.** REG-TOOLS-001/002/003 — all three called a tool and the right tool. |
| 2 | required and fails | **Partly.** REG-TOOLS-005 authored; **not executed** in the last run. Failure handling is evidenced only by the 10 unplanned live errors in §2(c), not by a passing test. |
| 3 | tool unavailable | **No automated case.** No `unavailable` status has ever been written. Not covered. |
| 4 | not needed | **Yes, executed and passed.** REG-TOOLS-004, 0 tools executed. |
| 5 | wrong tool selected | **Indirect only.** `right_tool` is asserted inside cases 1–3 via `tool_any_of`; there is no case whose subject is a mis-selection. |
| 6 | unauthorised | **No behavioural case.** Structural only (STR-TOOL-004 + the eight probes in §2(e)). Never exercised through a model. |
| 7 | stale data | **No case, and no mechanism.** `requires_current_data` is rendered into the tool description as prose only. There is no freshness assertion anywhere. Not covered. |
| 8 | conflicting results | **No case.** Two tools returning contradictory figures is untested. |
| 9 | timeout | **No case executed; 0 timeout rows ever.** The path exists (`withTimeout`, `AbortError → timeout_after_Ns`) and is unproven by execution. |
| 10 | fallback / escalation | **Partly, unplanned.** `fail_closed` on `handoff_stalled` was exercised by the 4 real failures; no authored case asserts the escalation text. |

Four of ten covered by an executed automated test. Three have no case at all.

---

## 4. Acceptance figures

From `scripts/checks/v3_regression_last_run.json`, which is **pre-fix** (13:57:12Z, before the
14:12Z corrections) and covers 4 of 62 authored cases:

* **Tool-required success rate: 3 of 3 (100%)** on the tool dimension — REG-TOOLS-001/002/003 each
  scored `called_tool: true` and `right_tool: true`, executing 7, 5 and 2 tools respectively.
* **Unnecessary-tool-call rate: 0 of 1 (0%)** — REG-TOOLS-004 executed 0 tools. **n=1. This is not a
  rate and should not be quoted as one.**
* **Overall behavioural pass: 1 of 4 (25%).** The three failures were all non-tool checks:
  `did_not_over_escalate` failed 3/3, `stated_confidence` 1/3, `linked_revenue` 1/1. Tools connected;
  the answer contract did not hold.

The behavioural section is **partial**: 4 trials of 62 authored cases, 4 of 7 in this area, and it
predates both §2(c) fixes. No area-wide rate can be quoted from it.

---

## 5. Still broken or unverified

1. **`verifyNoFabricatedResults` is not called anywhere.** Guarantee (f) rests on the ledger, not on
   an operating detector.
2. **`role_id` is null on 100 of 100 ledger rows.** `agent_brain/index.ts:135` calls
   `callTool(name, args, { agentKey, correlationId })` with no `roleId`. With 59 roles sharing
   agents, tool use cannot be attributed to a role.
3. **`record_commercial_effect` has 0 calls, ever.** `runWithTools` requests `toolsFor(agentKey,
   'read')` (`agent_brain/index.ts:98`), so the only write tool is never offered to any model. It is
   registered, authorised for 90/90 agents, and unreachable.
4. **Output schemas are `{"type":"object"}` on all 10 tools.** No output is contract-checked.
5. **`authorised_roles` is `{*}` everywhere** — authorisation is department-level only.
6. **`unauthorised`, `timeout` and `unavailable` have never been written by a live call.** Three of
   six statuses are unexercised outside the aborted-transaction probe.
7. **No freshness / staleness mechanism exists** despite `requires_current_data` on 7 tools.
8. **Nothing is production-available** (`production_available = false` × 10). This entire stage is
   staging-only.
9. **8 of the first 77 ledger rows have no matching `decision_trace` row** for their correlation id.
10. **The measurements above were taken against a table another workstream was writing to.** Counts
    are pinned to `created_at < 2026-08-14 14:16:12+00` and will not match a later re-run.

*Nothing in this document certifies any role, department or category. Certification is an
independent evaluator's finding, not a builder's.*
