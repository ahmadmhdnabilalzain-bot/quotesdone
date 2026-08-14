# V3 — INDEPENDENT RETEST HANDOFF

**For:** an independent evaluator who has not seen the remediation session.
**Written by:** the remediation builder. **Date:** 2026-08-14.
**Status of the system: NOT CERTIFIED.** Nothing in this document certifies any role, department or
category. Internal work cannot certify itself. Only an independent evaluator, running a sealed form
the builder never saw, can say a role is certified — and none has.

---

## 1. The prior result is immutable

The result of record is **`V3-COR-0A782DA90B10`**, sealed 2026-08-14T12:34:51Z, overall **56.97%**,
0 of 96 roles / 0 of 24 departments / 0 of 86 categories certified.

That record **must not be overwritten, re-scored, amended or superseded in place.** Its artefacts sit
in `C:\Users\Opera\quotesdone\docs\knowledge\certification\` with `V3_CERTIFICATION_RESULT.sha256`
and `V3_CERTIFICATION_RAW_OUTPUTS.sha256` as the seals; verify both digests before you begin and
again when you finish. **Every later run gets a NEW result id.** A retest is a second data point next
to the first, never a replacement for it. If a later run scores worse, that is the finding.

## 2. What the evaluator must NOT be given — and what the builder did not receive

Withhold from the runtime, from the repository, and from anyone who can edit either: answer keys,
gold answers, gold reasoning, expected-answer text, hidden question text, scoring thresholds beyond
the published pass bars, and the unsafe-class list.

**The builder did not receive any of these.** The remediation worked from
`V3_CERTIFICATION_REMEDIATION_HANDOFF.md`, a sanitized document that names competency codes and
behaviours only, plus the three aggregate CSVs (`_BY_ROLE`, `_BY_DEPARTMENT`, `_BY_CATEGORY`). The
raw-output JSONL and the failure register were off-limits and were not opened. One consequence is
recorded honestly in the system itself: `fn_unsafe_guard_status()` returns a row
`classes_withheld_by_sanitization` with status `NOT_MEASURABLE`, because inventing plausible class
names would have produced a register that looked complete and was not.

## 3. Environment fingerprint — measured 2026-08-14T14:16:42Z

Every figure below came from one snapshot query against staging `pglpqrhvozwepymcuunn`, or from a
command shown beside it. Nothing here is estimated.

| Item | Value | How measured |
|---|---|---|
| Git commit | `50a534acdadd28c39cf2aad4412508b3e6b9f2e4` | `git rev-parse HEAD` |
| Branch | `repair/v3-certification-remediation-1` | `git rev-parse --abbrev-ref HEAD` |
| **Tracked tree dirty** | **yes — see §6** | `git diff --stat` |
| Migration head | `20260810233339` (719 rows) | `max(version)` on `supabase_migrations.schema_migrations` |
| ops_knowledge | 8,256 | `count(*)` |
| kb_chunks | 95,912 | `count(*)` |
| Agents | 94 total, **90 active** | `org_agents` |
| Role identities | 133 rows over 94 distinct agent keys | `org_role_identity` |
| Registered tools | **10 active** (9 read, 1 write) | `agent_tool where active` |
| Active executors | 59 | `org_action_executor where active` |
| `agent_brain` deployed | **v51**, ACTIVE, 2026-08-14T14:01:43.813Z | Supabase function list |
| `ai_gateway` deployed | **v33**, ACTIVE, 2026-08-14T14:05:55.316Z | Supabase function list |

**Migration head is not the deploy marker.** This repository ships routines through
`scripts/apply_sql.mjs` and the management API, not the migration ledger; 558 of 562 SECURITY DEFINER
`fn_*` routines appear in none of the 719 migration bodies. Use `pg_proc`, not the ledger, to check
what is installed. All 30 remediation routines named in §4 were confirmed present in `pg_proc`.

**The tables are live and counts move.** In four minutes of measurement `decision_trace` went 22→30,
`agent_tool_call` 76→102 and `llm_attempt` 24→48. Take your own baseline snapshot at the moment your
run starts; do not reuse the numbers above as a fixed denominator.

## 4. What changed since the sealed run

Each line was verified by reading the file named.

| Runtime capability | File that carries it |
|---|---|
| Tool registry, per-role grants, call ledger, `fn_record_tool_call` | `scripts/sql/v3_repair_01_tool_registry.sql` |
| `decision_trace` columns, write/seal routines, immutability trigger, management review | `scripts/sql/v3_repair_02_decision_trace.sql` |
| Context slice rewrite, `fn_knowledge_gap`, retrieval probe, cross-role leak check | `scripts/sql/v3_repair_03_retrieval.sql` |
| Task text → tsquery | `scripts/sql/v3_repair_04_task_query.sql` |
| `fn_agent_context_v3` patched onto it | `scripts/sql/v3_repair_05_ctx_v3_query.sql` |
| Role isolation decisions, collision view, identity guard, readiness recompute | `scripts/sql/v3_repair_06_role_isolation.sql` |
| Handoff contract table, open/respond/amend/close, guards, stalled view | `scripts/sql/v3_repair_07_handoff_contract.sql` |
| Revenue cascade, `fn_metric_class`, commercial effect, binding constraint | `scripts/sql/v3_repair_08_revenue_cascade.sql` |
| Unsafe classes, block ledger, 7 live detectors, eligibility trigger | `scripts/sql/v3_repair_09_unsafe_safeguards.sql` |
| LLM failure classes, attempt ledger, route health, preflight, retry policy, reliability report | `scripts/sql/v3_repair_10_infra_reliability.sql` |
| Trace convergence / view type guard / edit probe | `scripts/sql/v3_repair_11_*.sql`, `_12_*.sql`, `_13_*.sql` |
| Tool credential resolution in `fn_agent_tools` | `scripts/sql/v3_repair_14_tool_credential.sql` *(untracked — see §6)* |
| `makeLlmRich`: exposes `tools`, `finish_reason`, `truncated` | `supabase/functions/_shared/llm.ts` |
| Registry-driven tool dispatcher, argument validation, result hashing, fail-visible statuses | `supabase/functions/_shared/tools.ts` |
| `runWithTools` loop, fail-closed on a failed fail-closed tool, trace write + seal | `supabase/functions/agent_brain/index.ts` (L93–L145, L588–L635) |
| Preflight filters the model ladder; every attempt recorded server-side | `supabase/functions/ai_gateway/index.ts` (L461, L478) |
| Internal regression harness (builder-authored, certifies nothing) | `scripts/checks/v3_remediation_regression.mjs` |

## 5. The two recommended independent measurements

**Option 1 — evaluator-controlled rerun of the original sealed form.** Cheap, and the only way to get
a like-for-like delta against 56.97%. **Valid only if those questions stayed inaccessible to runtime
agents and to the repository throughout.**

> **Contamination flag, stated plainly:** the scoring session and this remediation session ran in the
> **same conversation**. The builder side therefore had prior sight of the rubric's vocabulary —
> competency names, dimension names, failure-class names — even though no answer key, gold answer or
> question text was read. That is enough to bias wording toward the rubric. **Treat Option 1 as
> diagnostic only.**

**Option 2 — a newly authored sealed certification form.** More expensive and not directly comparable
to the 56.97%. It is the uncontaminated measurement, and **it is the one that should carry the
certification decision.** Author it independently, seal it before any part of this repository sees
it, and publish a new result id.

Run both if budget allows; if only one, run Option 2.

## 6. Where the builder thinks it stands — look hardest at the right column

**Believed fixed (verify, do not assume):** tools now execute and return — 102 calls, 92 answered, 10
failed, every successful result hashed into `agent_tool_call` before the model saw it. Traces are
written and sealed — 30 rows, 25 sealed, 20 carrying executed tools; a sealed row refuses an evidence
edit (proven against state). Truncation is now detectable at the caller (`truncated` on the envelope).
LLM attempts are recorded server-side, 48 rows.

**Still open or unverified — the weak spots:**

1. **The deployed `agent_brain` predates the tool-credential fix.** `_shared/tools.ts` was last
   modified 14:11:21Z; `agent_brain` v51 was deployed 14:01:43Z. The bundle is stale. Consistent with
   this, `knowledge_search` failed 6 of 10 calls and `handoff_stalled` — which is `fail_closed` —
   failed 4 of 5. **Redeploy before you measure, or you will measure the old bundle.**
2. **Uncommitted work.** `tools.ts` (+30/−4) and `agent_brain/index.ts` (+17/−1) are uncommitted, and
   `v3_repair_14_tool_credential.sql` is untracked. Commit `50a534a` does not reproduce the runtime.
3. **`relevant_kpi` is null on 30 of 30 traces.** `agent_brain` never populates it. Revenue linkage
   (`CMP-BZ-01`, 14.76%) is *not* demonstrated at trace level.
4. **Revenue cascade reaches 13 of 24 departments**; 10 of 263 department objectives sit on the
   revenue target. `task_commercial_effect` has 0 rows and its write tool `record_commercial_effect`
   has never been called.
5. **Role isolation is decided, not delivered.** 67 decisions exist (30 split, 19 isolate, 13 block,
   5 restrict-to-advisory) but 26 collisions remain, 65 roles are still in collision, 1 cross-seniority
   collision is unresolved, and only **14 of 96 certification role ids** have a disposition.
6. **Guards with no firing evidence.** `handoff_contract` 0 rows, `unsafe_block` 0 rows,
   `llm_attempt` failures 0, unauthorised tool attempts blocked 0. Zero cannot distinguish a dead
   guard from an idle system — force each path to fire before believing it.
7. **Unsafe coverage is partial.** 9 classes registered, 7 with live detectors, 2 NOT_MEASURABLE. The
   certification reported 47 of 82 classes undetected; roughly 40 remain, and the class list is
   withheld. `fail_open_authorization` currently reports **5 hits**.
8. **Internal regression (certifies nothing):** structural **23/26 (88.46%)**, behavioural
   first-attempt **1/4 (25%)** — over-escalation failed 3 of 4 live cases. Recorded at commit
   `eeafec3`, which is older than HEAD.

## 7. Thresholds

**Do not weaken any acceptance threshold.** Not the pass bars, not the unsafe-action bar, not the
first-attempt rule (a retry must never overwrite a first attempt). The preserved strengths — 99.65%
incomplete-brief refusal and 0 unsafe dispatches in 860 — are regression targets: a completeness gain
bought by loosening the dispatch or authority gate is a failure, and should be scored as one.
