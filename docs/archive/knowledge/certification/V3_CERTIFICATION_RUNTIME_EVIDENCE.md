> **Archived 16 Nov 2026** (simplification wave B, it_engineer): it describes the V3 certification and remediation programme of Aug 2026; the agent_brain, agent_train and os_api functions it ran on are gone from supabase/functions. 3 of the 6 routines it names are gone from production (SELECT pg_proc, 16 Nov 2026). History, not the build today.

# V3 certification — runtime evidence

Independent blind certification run of QuotesDone Agent Knowledge V3 against the deployed
**staging** runtime. This document records **how** the run was executed and **what the runtime
did**. It contains no score, no pass rate, no expected answer and no certification verdict —
those belong to the evaluator, who holds the answer key this session never had.

- **Run id** `14d10b33-357e-4e0d-b6cf-d97271a7820d` (`baseline`)
- **Sealed** 2026-08-14 11:21:16.721687+00 · **Exported** 2026-08-14T12:07:36.552Z
- **Raw output SHA-256** `b54cfa3cda283acbe38defb0e70a42be3872f2549a186eff4cbdef5fc01a9167`

---

## 1. Environment under test

| | |
|---|---|
| Repository | `C:\Users\Opera\quotesdone` |
| Branch | `main` |
| Commit under test | `fff2efdd4f646fda6655b0e730486cfd587007cb` |
| Tracked working tree | clean |
| Staging Supabase project | `pglpqrhvozwepymcuunn` |
| Production project | `htdblwldjkcgjvmqkbeh` — **not touched; synthetic certification refused against it** |
| Migration head | `20260810233339` (719 migrations) |
| Edge functions deployed | 201, all ACTIVE · version-vector SHA-256 `1bf3ac7225a5141a3be5413bb6ebcbe3ca2f2f2f486722ab87633f112f536597` |
| Runtime knowledge version | role package `2026.08.14`, category package `2026.08.14` |
| Knowledge corpus | 8,256 `ops_knowledge` records · 95,912 `kb_chunks` |
| Role crosswalk | 130 `org_role_identity` rows covering the 96 packaged roles; 86 `org_category_identity` routes. 182 distinct expected identities appear across the run (96 roles + 86 `route:opcat-NNN` desks) |
| Active runtime agents | 93 |
| Answer contract | `supabase/functions/agent_train/index.ts::ANSWER_SYS` · SHA-256 `1184a7c775c1e383380f7a9ff1413bfdb637961f32433489bdada22378b16d55` |
| Clock at seal | 2026-08-14 11:21:15.501971 UTC (Dubai UTC+4) |

**Model-routing configuration** as deployed, captured in the sealed manifest
(`code_fingerprint.model_policy`): 61 active `model_policy` rows,
routing tiers `analyst_controller`, `director`, `operations_specialist`, `reviewer_auditor`.

**Staging application URL.** `https://pglpqrhvozwepymcuunn.supabase.co` — the surface this run
actually exercised (`/rest/v1/rpc/*` for retrieval and `/functions/v1/ai_gateway` for the model
call).

**Deployed frontend version.** Vercel project `quotesdone-next`
(`prj_6mNIUbqsbg92IMXgMFmbkMlXBGzS`) has a **single production target and no separate staging
target** — branch builds get preview URLs. The production deployment live during the run is
`dpl_9VUJ4C9wAxtKKwJ6YR2ZAh37fGqg`, built from commit `fff2efdd4f646fda6655b0e730486cfd587007cb` — the same commit
under test — state READY, created 2026-08-14 11:12:18 UTC. It is recorded for completeness and
**was not exercised**: every question in the package is answered server-side by Postgres routines
and the `ai_gateway` edge function, and no frontend build participates in any result below.

---

## 2. Question-package verification

| check | result |
|---|---|
| ZIP SHA-256 | `228f15fcb745f9dfdf07cfff77adfa1112310949daab56452d00a57c7bebab7d` |
| Files verified against `FILE_MANIFEST.sha256.json` | 208 / 208 |
| Checksum mismatches | 0 |
| Files present but absent from the manifest | 0 |
| JSON / JSONL parse failures | 0 |
| Declared question count | 2,284 |
| Actual question count | 2,284 |
| Unique `evaluation_id` | 2,284 · duplicates 0 |
| Answer-key / gold-answer fields | 0 |

Class counts matched the declaration exactly: **1,152 operational-role**, **192 department**,
**860 category-specialist**, **80 cross-company management**.

Every distinct key path in every question row was enumerated and checked against an
answer-key vocabulary (`answer`, `gold`, `expected`, `rubric`, `correct`, `solution`,
`ideal`, `ground_truth`, `verdict`, `grading`, `evaluator` and others). The only match was
`route_key` — the `opcat-NNN` routing identifier, not an answer. **No expected answer exists
anywhere in the attached package.**

---

## 3. The runtime path exercised

```
certification question
  -> mapped agent identity          org_role_identity / org_category_identity
  -> role + department resolution   fn_agent_context_v3 -> identity{packaged_role_ids,
                                    department, authority, readiness, manager}
  -> runtime context assembly       fn_agent_context_capped(agent_key, 8000, task_text)
  -> authorised knowledge retrieval fn_agent_context_v3 -> knowledge_ids      (role/dept/cross)
                                    fn_category_checklist -> knowledge_ids    (category)
  -> authorised tools / live data   fn_category_checklist, fn_category_quote_ready,
                                    fn_agent_context_v3 -> tools, live_data_required
  -> agent response                 ai_gateway  (fn_ai_route: model_policy,
                                    model_policy_by_identity, org_agents.routing_tier,
                                    department budget halt, ai_cost_log)
  -> decision trace                 recorded from what the runtime itself wrote
```

No model was called directly to simulate an agent. Every question passed through the deployed
router and the deployed retrieval. **Nothing in the runtime was modified before or during the
run** — no prompt, no role, no tool, no retrieval rule, no model-routing row, no knowledge
record, no application code.

### Two decisions that shaped the path, and the measurements behind them

**1. `agent_brain` was not used, deliberately.** It is the other employee entry point and it
carries conversation state: it reads the last `agent_chats` turns for the agent, writes
`agent_chats` and `agent_memory` after every reply, promotes messages matching
*remember / always / never* to permanent instructions, and can dispatch `kb_deepen` to research
the internet and **ingest the result into permanent knowledge**. Each of those breaks a rule this
run is bound by — per-question isolation, "one question's output must not become training
knowledge for later questions", and "do not modify runtime knowledge during the run". The path
actually used is stateless by construction: one fresh gateway call per question, no history read,
no memory written, no ingestion triggered.

**2. The answer contract was not written by this session.** It is read verbatim at run time out
of `supabase/functions/agent_train/index.ts` — the runtime's own runner for driving an employee
through a packaged case — and its SHA-256 is sealed in the manifest. The gateway was called with
`fn: 'agent_train'`, the mapped `agent_key`, and **no explicit `task_class`**, so
`fn_ai_route` resolves the model the way it does for that runtime path rather than the way this
session might have preferred.

### Identity resolution per class

| class | mapped identity | resolution |
|---|---|---|
| role (1,152) | `org_role_identity.agent_key` | 1,152 executed; all 96 packaged roles resolve to at least one **active** agent |
| department (192) | the department's `archetype='director'` identity | 192 executed; all 24 packaged departments have a director identity |
| cross_company (80) | `executive-office-chief-of-staff-director` -> `ceo` | 80 executed |
| category (860) | `route:opcat-NNN` -> `cat:<category_key>` | 860 executed; route resolved by `fn_category_checklist` in 860 of 860 |

Where a packaged role maps to more than one runtime agent, the alphabetically-first **active**
agent was used and **every candidate is recorded** in `mapped_agent_candidates`, so a composite
mapping is visible in the evidence rather than silently collapsed. 243 executions
had more than one candidate.

---

## 4. Isolation

Each question ran in its own gateway call with no shared conversational state. Between
questions nothing persisted: no chat row, no memory row, no cache key tied to a prior answer.

**Withheld from the agent on every question** — exactly three keys, stripped before send:

| withheld | why |
|---|---|
| `evaluation_id` | certification metadata |
| `scoring_dimensions` | scoring criteria |
| `automatic_fail_categories` | scoring criteria |

Everything else was sent **verbatim** — not edited, not paraphrased, not summarised, no hint
added. The exact bytes sent are preserved per row in `question_sent`.

The agent never received: an answer key, an evaluator rubric, another agent's answer, a previous
attempt on the same question, or any indication that it was being certified.

### Isolation verified by measurement

Counted after the run against rows written since the first seal (11:19:00 UTC):

| table | rows written by this run | meaning |
|---|---|---|
| `agent_chats` | **0** | no conversational state was created; nothing carries between questions |
| `agent_memory` | **0** | nothing the agents answered became memory, instruction or learned knowledge |
| `agent_training_attempt` | **0** | no training attempt was opened; no remediation cycle touched |
| `ops_knowledge` | **0** | the knowledge corpus is byte-for-byte what it was |
| `kb_chunks` | **0** | no embedding or ingestion was triggered |
| `cert.certification_answer_key` | **0 rows total** | the answer key was never loaded and does not exist on this project |
| `cert.certification_question` | **0 rows total** | the questions were not ingested into runtime-reachable storage either |

The last two matter: the package manifest carries `runtime_ingestion_prohibited: true`, and the
questions were held on disk and streamed per call rather than loaded anywhere an agent could reach.

### Side effects that did occur, stated plainly

The run is not side-effect-free, and claiming otherwise would be false. Answering through the
real runtime fires the runtime's own instrumentation exactly as any agent call does:

| table | written | what it is |
|---|---|---|
| `agent_context_retrieval` | one row per context assembly | the retrieval recorder — *which* knowledge ids were read |
| `kb_usage_log` | one row per knowledge record used | knowledge-usage instrumentation |
| `ai_cost_log` | one row per gateway call | cost accounting, and the input to the budget halt |

None of these changes knowledge, prompts, roles, retrieval rules or routing. They are read-side
telemetry, they are what makes the retrieval auditable, and suppressing them would have required
modifying the runtime — which is forbidden. `decision_trace` gained **no** rows, and
`agent_runs` gained only rows written by unrelated scheduled jobs that ran on their own cadence
during the window.

---

## 5. Immutability of the evidence

Isolated schema `certrun_v3` on staging only. Verified by measurement, not by assertion:

| role | `USAGE` on schema | `SELECT` on `raw_result` | `INSERT` |
|---|---|---|---|
| `anon` | false | false | false |
| `authenticated` | false | false | false |
| `service_role` | false | false | false |
| `postgres` (owner) | true | true | true |

Every edge function runs as `service_role`, and `service_role` bypasses RLS — so the
schema-level revoke, not RLS, is the boundary that matters. **No runtime agent can read its own
certification evidence.**

The append-only guarantees were **tested by execution** inside an aborted transaction, so the
attempt was real and left nothing behind. Verbatim result:

```
UPDATE_BLOCKED: certrun_v3.raw_result is append-only
DELETE_BLOCKED: certrun_v3.raw_result is append-only
SEAL_PROTECTED: certrun_v3.run_manifest is sealed; the seal cannot be rewritten
MANIFEST_DELETE_BLOCKED: certrun_v3.run_manifest is append-only
```

- The manifest was **sealed before any result was reviewed**; the seal fields cannot be rewritten
  and `raw_output_sha256` is write-once.
- Rows in the evidence store: 2,407; lines in the exported JSONL:
  2,407; **reconciled: yes**.

---

## 6. Execution controls

| control | how it was honoured |
|---|---|
| each question run exactly once in the baseline | 2,284 distinct questions, 2,407 rows written |
| no retry of a failed reasoning answer | only `INFRASTRUCTURE_FAILURE` was retried, once, and **both attempts preserved** |
| no question edited or paraphrased | `question_sent` holds the exact bytes |
| no hints, no scoring criteria exposed | three keys withheld, listed above |
| no silent role substitution | every candidate recorded; unresolvable -> `RUNTIME_NOT_CONNECTED` |
| no question removed for a missing capability | all 2,284 attempted |
| nothing marked passed or failed | no score field exists in the schema or the export |
| failed and empty executions kept | recorded with their runtime status and error detail |

---

## 7. What the runtime did — measured, not judged

These are properties of the deployed system observed during execution. **None of them is a
judgement about answer quality**, which this session is not permitted to form.

### Runtime status

| status | executions |
|---|---|
| `OK` | 2,190 |
| `INFRASTRUCTURE_FAILURE` | 217 |

### Models and providers actually used

| model | calls |
|---|---|
| `~anthropic/claude-haiku-latest` | 1,872 |
| `anthropic/claude-sonnet-5` | 174 |
| `google/gemini-3.1-flash-lite` | 144 |

| task class resolved by the router | calls |
|---|---|
| `general_drafting` | 2,407 |

**The per-role routing is live and it varies.** `model_policy_by_identity` fired on
1,338 executions and `org_agents.routing_tier` on 1,069;
`fn_ai_route` resolved **4 distinct models**
across the run: `~anthropic/claude-haiku-latest`, `qwen/qwen3.7-plus`, `google/gemini-3.1-flash-lite`, `anthropic/claude-sonnet-5`. Across the 93 active agents the router
resolves `~anthropic/claude-haiku-latest` for 57, `google/gemini-3.1-flash-lite` for 22,
`anthropic/claude-sonnet-5` for 12 and `qwen/qwen3.7-plus` for 2 — so the four-role routing
taxonomy V3 installed does reach the model choice. The full router decision, including
`identity_policy`, `routing_tier` and the router's own `why`, is recorded per question in
`routing`.

**`ai_gateway` returned HTTP 502 on 216 executions, and the error body is a valid
upstream answer.** 217 failure rows cover
**123 distinct questions**
(5.4% of the
2,284 executed). In every 502 the `error_detail` field holds a well-formed
`chat.completion` object from the provider — **the model answered and the gateway did not hand
the answer back**.

It is not confined to one route or one agent:

| route | failure rows |
|---|---|
| `qwen/qwen3.7-plus` | 152 |
| `anthropic/claude-sonnet-5` | 64 |
| `~anthropic/claude-haiku-latest` | 1 |

| mapped agent | failure rows |
|---|---|
| `followup` | 88 |
| `marketing` | 64 |
| `qa_manager` | 22 |
| `legal` | 16 |
| `trust_safety_mgr` | 12 |
| `supplier_verification` | 5 |
| `ai_qa_specialist` | 3 |
| `fraud_analyst` | 3 |
| `brief` | 2 |
| `analytics_director` | 1 |
| `security` | 1 |

**It is partly transient.** Of 123 second attempts,
94 failed again and
**29 succeeded** — a retry failure rate of
76.4%. So this is neither clean
infrastructure flakiness nor a hard per-route capability gap: it reproduces most of the time,
across at least 3 different model routes
and 11 agents, including
`anthropic/claude-sonnet-5`.

Both attempts are preserved for every retried question, so the evaluator can see the pair.
**This was not diagnosed and not fixed** — the brief forbids both, and an earlier reading of this
same failure from a partial sample ("one bad provider route") turned out to be wrong once the full
run was in, which is reason enough not to offer a cause here.

### Retrieval

- 2,407 of 2,407 executions retrieved at
  least one knowledge record; 111,000 record ids recorded in total
  (mean 46.12 per execution).
- `fn_agent_context_v3` **does not honour `p_budget_chars`**: asked for 24,000 characters it
  returned a median of 248,257 across 1,547 non-category executions, over budget in
  1,547 of them. The bulk is `deterministic_rules` and `live_data_required`. Because of
  this the context **sent** to the model came from `fn_agent_context_capped` at 8,000 characters —
  the renderer every deployed agent path actually uses, and the exact budget `agent_train` uses —
  while `fn_agent_context_v3` supplied the identity, knowledge ids, tools and live-data
  requirements recorded as evidence. Both calls are recorded per row in `tool_calls`.
- `fn_agent_context_v3` has **no caller in any deployed edge function**. The certification handoff
  prescribes it for running a candidate; no shipped runtime path invokes it. Stated as an
  observation; nothing was changed.

### Category desks

- All 860 category executions resolved a route through `fn_category_checklist`
  (860 with `route_resolved: true`), and the checklist returned its own
  `knowledge_ids` — so the category knowledge retrieval is real and traceable.
- `org_category_identity.owner_agent` is **NULL for all 86 routes**, and no `cat:` row exists in
  `org_agents`; 860 category executions therefore ran with **no named runtime agent**,
  against the on-demand desk identity `route:opcat-NNN`. The manager named by the crosswalk,
  `category-intelligence-director`, does not exist as an agent either. The tools work; the
  identity is unowned.
- Every one of these 86 routes nevertheless carries `readiness = 'decision_trace_connected'`.

### Output shape

- 2,027 of 2,407 executions returned parseable structured output;
  2,027 carried a self-reported confidence.
- Authority classification returned by the agent: `escalate` 1,485 · `within` 459 · `refuse` 82 · `supervised` 1.
- Escalation decision: `escalated` 1,485 · `none` 459 · `refused` 82.
- 163 responses hit the gateway's output ceiling (`finish_reason: length`).

### Decision trace

`decision_trace_id` is **null on every row**, and that is correct rather than missing: only
`fn_decide` writes `decision_trace`, and it writes one when an agent **action is executed**. A
certification answer is a decision record, not an executed action, so no trace row is created by
answering. The traceable evidence that does exist per question — retrieved knowledge record ids,
tool calls with result hashes, the router's decision, model, tokens and cost — is recorded in
full.

### Cost and latency

| | |
|---|---|
| Total tokens | 6,797,575 (5,872,636 in / 924,939 out) |
| Total estimated cost | **AED 42.2038** (USD 11.4918) |
| Latency mean | 10,815 ms |
| Latency p50 | 7,857 ms |
| Latency p95 | 34,385 ms |
| Latency max | 47,762 ms |

---

## 8. Integrity disclosures

**A concurrent session moved the repository during this session.** At session start `HEAD` was
`98854ba75dd1db9d970b988bf066c804bf54e4d9`. At 11:12 UTC a `git pull` fast-forwarded `main` to
`fff2efdd4f646fda6655b0e730486cfd587007cb` (PR #379), and at **11:08:39 UTC** a `video.produce` row was inserted into
`org_action_executor` on staging. Neither change was made by this session.

Both changes landed **before the first certification question executed** (first seal 11:19:01 UTC).
The entire run therefore measured one consistent state — the state recorded in the sealed
manifest, `fff2efdd4f646fda6655b0e730486cfd587007cb` — and no question straddles the change. What is **not** true is that
the run measured the state at the exact moment the session opened; it measured the state as of
11:19 UTC, one commit later. Stated rather than smoothed over.

**Runtime drift during the run.** 2 snapshots were taken across the run
(`mid_run_t1`, `post_run_t2`). **Values that changed mid-run: `git_head`.** Recorded in the manifest under `runtime_drift_snapshots`.

**A pilot preceded the baseline.** 8 questions (2 per class) were executed as a smoke test under
run `065ddd7a-c0f8-4065-82c0-e38b0d74813b`, marked `run_kind='pilot'`, to prove the path before
committing to the full run. Those 8 questions were consequently executed twice: once in the pilot
and once in this baseline. The pilot rows remain in the evidence store, immutable and separately
identified. No pilot answer was reused, inspected for quality, or allowed to influence the
baseline.

---

## 9. Artefacts

| file | SHA-256 |
|---|---|
| `V3_CERTIFICATION_RAW_OUTPUTS.jsonl` | `b54cfa3cda283acbe38defb0e70a42be3872f2549a186eff4cbdef5fc01a9167` |
| `V3_CERTIFICATION_RUN_MANIFEST.json` | see `V3_CERTIFICATION_RAW_OUTPUTS.sha256` for the raw-output digest |
| `V3_CERTIFICATION_RUNTIME_EVIDENCE.md` | this document |
| `V3_CERTIFICATION_RAW_OUTPUTS.sha256` | the digest above, in `sha256sum` format |

Evidence also persists in `certrun_v3.raw_result` on `pglpqrhvozwepymcuunn`, append-only, with the
run manifest sealed and `raw_output_sha256` written once.

---

## 10. What this session did not do

- Did not access, search for, request or open the answer-key archive
  (`QD_AGENT_V3_CERTIFICATION_ANSWER_KEY_EVALUATOR_ONLY_v2026.08.14.zip`), any evaluator rubric
  beyond the questions package, any previous certification result, or any hidden expected answer.
  `cert.certification_answer_key` was and remains **empty**.
- Did not score, grade, rank, mark passed or failed, or form a verdict.
- Did not modify runtime knowledge, prompts, tools, roles, retrieval, model routing or
  application code.
- Did not fix any defect observed during the run, and did not help an agent after it answered.
- Did not deploy to production, did not activate any disabled route, agent, executor or cron job,
  and refused to run synthetic certification against `htdblwldjkcgjvmqkbeh`.
- Did not retry a reasoning answer.
