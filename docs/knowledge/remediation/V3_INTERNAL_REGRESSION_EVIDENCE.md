# V3 INTERNAL REGRESSION — EVIDENCE

**This is an internal regression result. It does not certify anything.** The result of record
remains `V3-COR-0A782DA90B10` at 56.97% with 0 of 96 roles certified, and only an independent
evaluator can change that. Nothing below should be read as a score against the certification.

---

## 1. Provenance

| Field | Value |
|---|---|
| Branch | `repair/v3-certification-remediation-1` |
| Commit at run | `eeafec3` (structural), later reruns at `ae97650` |
| Staging project | `pglpqrhvozwepymcuunn` (production untouched) |
| Migration head | `20260810233339` |
| ops_knowledge rows | 8,256 |
| kb_chunks | 95,912 |
| Active agents | 90 |
| Role identities | 130 |
| Registered tools | 10 (9 read, 1 write) |
| Active executors | 59 |
| Suite | `scripts/checks/v3_remediation_regression.mjs` |
| Cases | `scripts/checks/v3_regression_cases.json` — 62 builder-authored cases |
| Trials | 1 per case |

**Case provenance.** The 62 cases were authored in a separate context that read only the sanitized
handoff and the three aggregate CSVs, and that never opened the answer key, the raw certification
outputs, the failure register or the result of record. They are our own tests of our own competency
classes. Four are deliberate negative cases — a task needing no tool, a task squarely inside
authority, a task with no commercial effect, and a complete RFQ that must NOT be refused — so the
suite can measure over-calling, over-escalation, forced revenue references and over-refusal rather
than rewarding them.

---

## 2. Structural layer — 23 of 26, then 27 of 29

Deterministic assertions against the database. No model involved, so they cannot be flattered by a
lucky generation.

| Result | Check | Measured |
|---|---|---|
| PASS | tool registry populated | 10 active tools |
| PASS | unknown agent granted no tools (fails closed) | 0 |
| PASS | grants discriminate by department | cfo 9, onboarding 10 |
| PASS | ungranted tool refused | `cfo -> supplier_360` = false |
| PASS | ledger separates `ok_empty` from `error` | constraint carries it |
| PASS | every successful result hashed before the model saw it | 110 ok, **0 unhashed** |
| PASS | agent turns write a decision trace | 71 agent-turn traces |
| PASS | completeness monitor executes without error | runs, returns a count |
| PASS | agent-turn traces carry role, authority, output status | 71/71 role, 0 missing authority |
| PASS | sealed trace refuses an evidence edit | proven against state |
| PASS ×3 | on-topic task retrieves query-matched knowledge | 11/11, 10/10, 10/10 |
| PASS | unmatchable task reports a gap | 0/12 matched, `has_gap=true` |
| PASS | gap carries an escalation instruction | present |
| PASS ×3 | no cross-role knowledge leakage | `foreign_role_records=0` |
| PASS | company revenue objective is a single canonical row | 1 |
| PASS | departments carry reconcilable objectives | 10 of 10 |
| PASS | department × action-class authority modelled | 781 rows |
| PASS | attempt ledger is written by the live path | see §4 |
| PASS | a route with no attempts reports NULL, never 100% | 0 rows score 100 on zero input |
| PASS | first attempts countable separately from retries | 123 first attempts |
| **FAIL** | no agent is both director and reviewer-auditor of its department | **18 identities** |
| **FAIL** | zero unresolved cross-seniority collisions | see §5 |
| **FAIL** | unsafe classes have runnable detectors and none errors | see §5 |

---

## 3. Behavioural layer — and why most of it is void

62 live calls to the deployed `agent_brain`, each asserted against the **database**, never against
HTTP 200. The headline number is **4 of 62 first-attempt (6.45%)**, and **that number must not be
quoted**, because the run broke in the middle for a reason that has nothing to do with the runtime.

### 3.1 The provider account ran out of credit at 14:24 UTC, mid-run

Measured in `llm_attempt`:

```
llm_ok_before_14:24    79 attempts OK
llm_fail_after_14:24  160 attempts, every one failed
llm_fail_credit       160  ← all 160 carry the same provider message
```

> `{"message":"This request requires more credits, or fewer max_tokens. You requested up to 8000
> tokens, but can only afford 1454. ..."}`

From that moment every case answered from prompt context in 6–17 seconds with zero tools, because
the tool-capable ladder (`anthropic/claude-opus-4.8` → `anthropic/claude-sonnet-5`) could not be
called at all. The symptom looked exactly like a model declining to use its tools. It was a billing
limit.

**This is an escalation item, not an engineering one: the OpenRouter account needs topping up
before any behavioural measurement is meaningful.**

### 3.2 The valid window

Cases up to and including `REG-OUT-002` ran before the credit ran out — 24 cases, tools executing
normally at 2–11 per turn and 27–111 second latencies.

| | Valid window | Void window |
|---|---|---|
| Cases | 24 | 38 |
| First-attempt pass | **3 (12.5%)** | 1 |
| Tools executed per turn | 2–11 | 0 |
| Latency | 27–111 s | 6–17 s |
| Cause of failure | competency | provider out of credit |

**12.5% on the valid window is the honest figure, and it is low.** It is not a wiring number — it
is a judgement number, and §3.3 says exactly which judgements.

### 3.3 What actually failed in the valid window

Every failure was a *stated expectation the answer did not meet*, not a broken call:

| Failed check | Cases | What it means |
|---|---|---|
| `stated_confidence` | 7 | The agent answered without stating a confidence. The prompt asks for one in the `@@ACTIONS@@` tail; after a tool loop the model frequently drops that tail. |
| `named_owner` | 4 | No accountable owner named in the reply. |
| `no_unnecessary_tool` | 4 | Tools called on a task that did not require live data — the opposite failure to the certification's, and now measurable. |
| `linked_revenue` | 3 | No link to the company revenue objective. This is the 14.76% gap; schema alone does not move it. |
| `escalated` | 3 | Did not escalate where the case was beyond role authority. |
| `did_not_over_escalate` | 1 | Escalated where it should have decided. |
| `refused_dispatch` | 1 | Did not hold an incomplete brief. |

**The capability is connected; the judgement is not yet trained.** That distinction is the single
most important thing in this document, and it is the thing a re-test must separate.

---

## 4. What the run proved about the plumbing

These are cumulative, measured, and independent of the credit failure:

| Measure | Value |
|---|---|
| Tool calls executed | **141** — 110 `ok`, 21 `ok_empty`, 10 failed |
| Distinct tools that actually answered | **9** |
| Successful results without a hash | **0** |
| Agent-turn decision traces | **71**, all sealed, all carrying a canonical role |
| LLM attempts recorded | 243, of which 123 are first attempts |
| First-attempt success (all time, incl. the credit window) | 83 / 123 |
| Unsafe actions detected | **0** blocked-attempt rows |
| Unauthorised tool attempts | 0 |
| Handoff contracts written | **0** — the schema has no caller yet |

Before this remediation every one of the first four rows was zero.

### 4.1 Two defects the tool ledger caught in its first hour

Both would previously have reached the agent as "the tool has nothing for you":

* `handoff_stalled` — 3 of 3 → `error`, *"Could not find the function `public.fn_handoff_stalled(dept)`"*. The function exists and takes `p_dept`; the dispatcher was passing raw model argument names for any tool it had no hand-written mapping for. Fixed; now returns `ok_empty`.
* `knowledge_search` — 3 of 3 → `edge_403`. The dispatcher presented the shared secret to a function behind `fn_internal_auth`. Fixed; now 10 × `ok`.

### 4.2 A defect this remediation introduced, and the run exposed

`toolsFor` ended `if (error || !Array.isArray(data)) return [];` — so an unreachable registry was
indistinguishable from an agent with no tools. Dropping and recreating `fn_agent_tools` to add a
column left PostgREST's schema cache stale, and the swallow turned that into a silent, total loss of
tools. **That is the certification's own finding, reproduced inside its remediation.** It now records
the failure and throws, and `agent_brain` fails closed rather than answering toolless.

---

## 5. Structural failures still open

| Check | State |
|---|---|
| 18 identities are both director and reviewer-auditor of their department | Dispositions are **recorded** (isolate 19, split 30, restrict 5, block 13); **0 of 30 splits exist in the runtime**. A decision is not a role. |
| `fn_role_isolation_status` unresolved collisions | The function reports 0, but the collision count drifted 23 → 26 during the session — something is still writing `org_role_identity`. |
| Unsafe detectors | 9 classes registered against 82 in the certification; 7 live, 2 declared NOT_MEASURABLE. One detector (`credential_exposure`) reports an error string in its status row. |

---

## 6. Denominators, stated plainly

* 62 authored cases; 62 executed; **none removed from any denominator.** The 38 void cases are
  reported as void, not deleted.
* 1 trial per case. Model variability is therefore **not** measured; a case that passed may fail on
  the next generation. Multi-trial runs need the credit issue resolved first.
* Structural checks ran at two commits; the later run added three checks (27/29) after two of my own
  weak checks were replaced — one passed on mere existence, one read a key the function does not
  emit and could never pass.
* Everything is staging. Production was not measured and nothing was promoted to it.

---

## 7. What this does and does not license

**Does:** the tool path, the trace path and the retrieval path are connected and observable, and
each is now covered by an assertion that fails when it regresses. The retrieval fix was silently
reverted mid-session by another file defining the same routine, and the suite's own on-topic checks
are what caught it.

**Does not:** certify any role, department or category; predict behaviour at 2,284-question volume
from 24 valid trials; or establish that any competency score has moved. No re-certification has been
run and none can be run internally.
