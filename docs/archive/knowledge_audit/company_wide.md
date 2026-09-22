# Knowledge audit — the company-wide layer every agent inherits

Measured 6 Sep 2026, 02:03–02:40 UTC, read-only against production `htdblwldjkcgjvmqkbeh` (54 active agents in 10
departments: customer_experience 5, data_intel 7, exec 3, finance 5, growth 7, legal 4, marketplace 7, people_ops 4,
product_eng 6, supply 6). Every number was measured by query or by reading the deployed routine body in this session
unless marked **verify**. Where a count could not be obtained inside the 8 s statement timeout, the method used instead
is named.

## 1. Company self-knowledge — what "every agent knows the company" actually delivers

Two generations coexist and only one reaches the run-time prompt.

| source | rows / size | freshness | delivered by | reaches run time? |
|---|---|---|---|---|
| `agent_knowledge` `_global` (110 rows, 511,625 chars): `company:self_knowledge` (3,362 chars), Company FAQ (197,956), Pricing & fees LIVE, AI Constitution, canon:core, canon:supplier_status, Universal Operating Rules (821), Penalty & collections model, 5 × AI-explainability, ~80 "Asset text: <file>" rows (Dropbox sync 2026-08-16) | `company:self_knowledge` updated **2026-08-16** (cron 126 `company_selfknowledge_refresh` that wrote it is `active = false`); FAQ 2026-09-02 | `fn_agent_context` LAYER 1, each item truncated at 1,500 chars, ordered by priority | yes — inside the 19,500-char head |
| `ops_knowledge` `qd-company:*` (44 rows, 103,294 chars: identity, operating-model/funnel, commercials, comparison-report, legal, governance, live-state, financials, categories, 10 org-team rows, 14 FAQ rows, content-blog/social/website) | effective **2026-09-06**, rewritten every 15 min by cron 292 `fn_company_self_knowledge_sync` (192 succeeded runs / 48 h) | `fn_agent_context_v3` `company_core` slice, and keyword hits in LAYER 2c | only if the question's words match; measured for a people-ops planning question the v3 `company_core` slice returned 2 records, one of them `CLAUDE_INGESTION_PROMPT_V2.md` |

What the head says today (measured on all four people_ops contexts; identical for every agent): "10 departments, 90
brain agents, 132 category sales agents, 59 wired tools, 0 open objectives, 0 open tasks", then a department list that
still begins with "Independent Assurance, Security & Reliability [assurance]" — three weeks stale and truncated at 1,500
of 3,362 characters with "ask for the rest if you need it".

T&C rules in the head: **3 % reveal fee — present** (Pricing & fees LIVE block, auto-synced 2026-08-03);
**supplier non-response — present** ("3 working days… supplier is charged a non-response fee equal to that reveal fee and
blocked from matching until paid"); **top-3 comparison report — absent** from the head (present in
`ops_knowledge` `qd-company:comparison-report`, 810 chars, and in 7 `agent_knowledge` rows, none `_global` priority ≥ 90);
**AED 15k / 3× anti-circumvention — absent** from the head (mentioned in 14 `agent_knowledge` rows — contract_specialist,
legal, cfo, secretary, `_global` "Penalty & collections model" — and 1 `ops_knowledge` row; the `_global` row is below
the 1,500-char truncation for the pricing block, **verify** by reading the row). Org chart: present as the stale
self-knowledge block plus `YOUR EMPLOYEE RECORD` (manager + direct reports, live). Priorities/KPIs: present and live
(`COMPANY GOALS YOUR WORK MUST MOVE` with current values; `YOUR KPIs`).

## 2. Universal rules

`fn_ws_governance()` → `universal_rules` = the **10** strings shown on the Governance page ("Behave as a senior
specialist…", "Retrieve and cite internal knowledge before answering…", "Never guess or fabricate…", "Produce
explainable decisions with confidence scores…", "Maintain a complete audit trail…", "Collaborate…", "Continuously learn…",
"Respect permissions…", "Prioritize automation while escalating legal, financial, compliance, security, or
low-confidence cases to humans."). They are not a table: `universal_objective` (10 rows) holds the ten *objectives*
("Improve customer satisfaction" … "Continuously update and validate knowledge"); `governance_rule` holds 11 routing
rules (escalation/conflict/approval/delegation, e.g. "confidence below decision_policy.confidence_min (0.6) → escalate";
"money movement above AED 10,000 → founder"). The head carries "Universal Operating Rules (all agents)" as one 821-char
`_global` row (2026-07-24) and the 10 objectives inside `YOUR DEPARTMENT'S OBJECTIVES` / `company_goals`. Governance
KPIs at measurement: global_rules 110, active_agents 88 (this counter includes the 34 inactive `kind = brain/agent` rows
— **verify** its population), decisions_30d 847, escalated_30d 47, avg_confidence 0.91, knowledge_items 2,507.

## 3. The knowledge plumbing — how knowledge reaches an agent at run time

### 3a. The calls

- Model-facing callers (`agent_brain`, `workflow_dispatch`, `agent_act`, `exec_agents`, `secretary_act`,
  `marketing_draft`, `designer`, `content_revise`, `boost_recommend`, `blog_weekly`, `agent_train`, `knowledge_exam`)
  all call **`fn_agent_context_capped(key, 24000, query)`**; `dept_plan` and `action_worker` call the 2-arg
  `fn_agent_context`. `agent_brain` additionally calls `fn_ops_knowledge_match` (cosine over `ops_knowledge`, 8 rows)
  and `kb_search` (hybrid over `kb_chunks`); `workflow_dispatch`, `cos_execute`, `action_worker` call
  `fn_apply_playbook` for the deterministic path.
- `fn_agent_context(key, max)` (2-arg, STABLE, 36,839-char body) builds the standing head: identity, genome, risk
  register, employee record, authority, KPIs, workload, OS block, company goals, department objectives, open findings,
  decisions on record, **LAYER 2** (profession rows from `agent_knowledge`), **LAYER 1** (`_global` rows, each cut at
  1,500 chars), **LAYER 3** (`fn_ws_<os>` live JSON), **LAYER 4** (experience rows), OS objectives measured, workflows in
  flight, target-operating-model pointer. It ignores `p_max_chars` below 22,000 (`cap := greatest(p_max_chars, 22000)`).
- `fn_agent_context(key, max, query)` (3-arg) appends **LAYER 2b** (`fn_dept_library_search`, 4 + 2 rows, ≤2,600 chars),
  **LAYER 2c** (`fn_ops_knowledge_search(dept, query, 5)` — **tsquery OR of the question's words**, `dept_key = dept`
  exactly plus company/external/unowned-workflow rows; it does *not* use `fn_dept_scope`, so a `people_ops` agent's 2c
  never sees the `hr` rows), then **2d/2f/2g** from `fn_agent_context_v3` (role knowledge ≤2,400, deterministic rules
  ≤2,000, live-data facts).
- `fn_agent_context_capped` keeps `left(head, 19500)` (or a cached `agent_context_head` ≤3 h old) and `left(tail, 4500)`.

### 3b. What that means, measured on all 54 active agents

| measurement | result |
|---|---|
| `LAYER 2 - YOUR PROFESSIONAL EXPERTISE` content | **empty for 54 of 54** — the admit guard `length(out)+length(piece) <= own_cap+2200` (≈ 8,300) is evaluated when `out` is already 11,283–13,365 chars |
| position of `LAYER 3 - LIVE OPERATIONAL STATE` | 21,796–22,098 for 48 agents (past the 19,500 run-time cut); **absent** for 6 (`bd`, `onboarding`, `partnerships_mgr`, `supplier_coverage`, `supplier_retention`, `supplier_verification` — the supply department has no `fn_ws_*` layer) |
| position of `LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED` | 21,808–24,831 for all 54 (past the cut) |
| head length (2-arg, 22,000 requested) | 26,389–31,312 |
| capped run-time prompt (probe, `learning_dev_mgr`, people-ops query) | 24,155 chars = head[0:19,500] + trim notice + LAYER 2c only (5 keyword rows × 700 chars); 2b absent (no dept_library rows), 2d/2f/2g cut by the 4,500 reserve |
| `dept_library` rows (LAYER 2b source) | legal 451, marketplace 361, assurance 318, finance 290, company 36; **0** for customer_experience, data_intel, exec, growth, people_ops, product_eng, supply |
| `fn_agent_context_v3` size vs budget | 319,604 chars returned for `budget_chars = 22000`; `agent_context_retrieval` (895 rows, 32 agents, since 2026-08-14): avg `chars_returned` 39,786 vs avg `budget_chars` 9,428, **895 of 895 over budget**; `knowledge_count = 0` on 2 of 895 |
| `fn_ops_knowledge_match` scope | `ops_knowledge` rows with an embedding (9,132 / 9,132), `runtime_eligible`, `supersession_state = current`, scope company/external OR `dept_key = any(fn_dept_scope(dept))` OR `role_key = any(packaged roles)` — cosine, `hnsw.ef_search 200` |
| `kb_usage_log` (30 d) | 1,363 rows, 39 agents; 868 are `context assembly: N knowledge record(s)` entries (N = 63 in every sampled row — a fixed department slice, not query-dependent), the rest are the question text written by `agent_brain`; **no result-count column exists**, so "how often retrieval returned 0" is unmeasurable from this table. 0 rows say `0 knowledge record(s)`. |
| `kb_chunks` retrieval mode | `kb_search` = `kb_match` (vector) + keyword RRF (per its own comment); `inquiry_intake` uses `kb_query` (keyword). With 95.9 % of chunks un-embedded, the vector half sees only the first ~120k ids (`qd_kb_pack` 53,343, `document` 2,528, `generated` 348, `library` 174, `memory` 40 — all 100 % embedded); every `standard`, `reference`, `regulation`, `cert`, `textbook` chunk is keyword-only. |

### 3c. The embedding backlog

- `ops_knowledge`: 9,132 rows, `embedding_status = embedded` 9,132, null vectors 0. Cron 315 `kb_embed_ops_knowledge`
  runs every minute (2,880 succeeded / 48 h) and reports "embedded 1 chunk(s) this run, 0 still unembedded" — that
  sentence is about `ops_knowledge`.
- `kb_chunks`: ~2.65 M rows (`pg_class.reltuples` 2,649,590; `fn_ws_knowledge` says 2,686,026). Exact null count
  exceeds the 8 s timeout; `pg_stats.null_frac(embedding_gte) = 0.9588` → **≈ 2.54 M chunks without an embedding**.
  Sampled by primary-key range: ids ≤ 20k 2,884/2,884 embedded; ids 600k–620k 0/12,844; 1.30M–1.32M 0/20,001;
  2.00M–2.02M 0/16,997; 2.60M–2.62M 0/15,421. The three `kb_chunks` backfill jobs (`kb_embed_backfill` 108,
  `kb_embed_backfill_boost` 242, `kb_embed_priority_kinds` 271) are **inactive**; `kb_embed` logged 27 errors in 7 days:
  "kb_embed could not read its target table, so it reported 'done' while unembedded chunks may still exist… canceling
  statement due to statement timeout" (the `count(*) … is null` it runs at the end times out on the same wall). The
  source comment in `kb_embed/index.ts` ("kb_chunks is 42.6 % embedded and rising ~1,240/hour") describes a state that
  no longer holds.

## 4. The exam loop

- **Two exams exist.** (1) `knowledge_exam` edge function: Sonnet examiner writes questions, Sonnet examinee answers from
  `fn_agent_context_capped` + `kb_search`, Opus grader judges and supplies the fact, convergence + lint gate the
  auto-fill. Its cron 135 `knowledge_exam_loop` is **inactive**; it needs three paid model calls and **cannot run under
  the hold**. (2) `fn_knowledge_exam_retrieval()` (cron 320, daily 03:23, 2/2 succeeded) sits every active agent for 5
  questions via `fn_knowledge_exam_sit` — **no model**: the grader is a lexeme-overlap check, so it passes under the hold.
- **How questions are written today.** `fn_knowledge_exam_sit` tops the bank up to 10 when it is below 10 with
  "What does the company's operating knowledge say about: <title>?" from `ops_knowledge` rows where
  `dept_key = org_agents.department` (exact string, not `fn_dept_scope`) **or `dept_key is null`** — 2,095 rows, of
  which 1,204 are supplier-category route files (`scope_type = category`). Bank: 1,325 questions, 168 agent_keys, 556
  topics; 653 template-generated overall; for the 54 active agents **506 of 591** questions are the template.
  Difficulty: core 1,186, edge 139 (edge only from the paused model exam).
- **How answers are graded.** Corpus = the examinee's `agent_knowledge` rows + `_global`; the question's lexemes are
  OR-matched; the best row's lexeme coverage of the reference answer (first 700 chars of the ops_knowledge content)
  gives correct ≥ 0.6, partial ≥ 0.3, else wrong; no row → not_covered. `ops_knowledge`, `kb_chunks` and packaged-role
  rows are **not** consulted, although those are what the run-time prompt retrieves. When the verdict is
  wrong/not_covered the reference content is **inserted into `agent_knowledge`** as an `experience` row
  (`author_verified`, confidence 0.85) — 508 such fills, **147 of them supplier-category route YAML written into
  non-marketplace employees** (110 agents affected).
- **Distribution across the 54 active agents (all-time, per agent).** Mean **27.1 %** (`fn_knowledge_exam_summary`
  reports 26.3 % over 30 days across 113 agent_keys including `cat:*` and retired agents; the Governance page's 26.2 %
  is the same routine at an earlier moment). **0 agents ≥ 70 %; 3 at 40–69 %** (bookkeeper 58 %, bd 54 %, qa_manager
  40 %); **51 below 40 %**; lowest backend_engineer 8 %, collections/bi_analyst/channel_specialist 12 %. All 54 were
  examined in the last 30 days (16–29 answers each). Verdicts company-wide: correct 608, wrong 463, not_covered 448,
  partial 350, unverifiable 13.
- **Model-graded evidence:** `canon_eval_runs` 29 runs, 16 agents, avg 77.5 %, last **2026-08-10**. `org_role.evaluation_suite`
  names (`eval_operating_cadence`, `eval_people_process`, …) resolve to no table or row.

## 5. Curriculum machinery and the knowledge crons

| job | schedule | active | what it does (deployed body) | effect on freshness |
|---|---|---|---|---|
| 292 company_self_knowledge_sync_15min | */15 | yes (192/48 h ok) | rewrites 44 `qd-company:*` ops_knowledge rows from live sources | company facts fresh in ops_knowledge only; the head's `company:self_knowledge` row is 3 weeks stale (its refresher, job 126, is off) |
| 315 kb_embed_ops_knowledge | * * * * * | yes | embeds `ops_knowledge` (target param) | ops_knowledge 100 % embedded |
| 320 knowledge_exam_retrieval_daily | 03:23 | yes | sits all active agents, 5 Qs, lexeme grader, auto-fills | writes ~5 fills/day of mixed relevance |
| 154 knowledge_decay_daily | 03:10 | yes | `agent_knowledge` past `review_due` → confidence −0.05/month, status `stale`; < 0.35 → quarantined + org_task | **has never decayed a row**: 0 of 2,507 rows have `review_due < today` (0 null), 0 stale, 0 quarantined |
| 272 v3_knowledge_freshness_daily | 01:25 | yes | `ops_knowledge.review_after < today` → `source_freshness = stale` | 0 stale, 0 past `review_after` |
| 225 kb_corpus_integrity_daily, 222 kb_route_tests_hourly, 335 kb_category_stats_30min, 274 v3_category_readiness_daily | | yes | integrity/route tests/stats | stats only |
| 73 knowledge_curator_daily | 03:10 | **no** | `fn_knowledge_curator()` (7,920-char body) | no curation since it was paused (last run not measured — **verify**) |
| 30 gen_category_knowledge_daily, 107 gen_category_personas_daily | | **no** | edge functions (paid model) | category knowledge frozen; 88 category agents' `agent_knowledge` last updated 2026-07-30 |
| 97 kb_autofill_gaps_weekly, 136 kb_deepen_loop, 38 learn_gaps_weekly | | **no** | paid-model fills | no gap filling; `fn_org_exec_knowledge_fill` executor ran 25 steps/7 d but "all 5 kb_fill_gap calls failed… paid provider held" (27 error rows) |
| 108/242/271 kb_embed_backfill(_boost/_priority_kinds) | * * * * * | **no** | embeds `kb_chunks` | ≈ 2.54 M chunks stay un-embedded |
| 135 knowledge_exam_loop | */4 h | **no** | model-graded exam | no model-graded exams since 2026-08-10 |
| 74 kb_ingest_queue, 125 kb_reconcile_daily, 52 kb_sync_daily, 126 company_selfknowledge_refresh, 39 embed_suppliers_daily | | **no** | ingestion/sync | no new kb_chunks ingestion by cron (last `kb_chunks.created_at` not measurable inside the timeout — **verify**) |

`agent_knowledge` freshness: 2,507 rows / 236 agent_keys; 1,856 not updated in 30 days, 279 in 60, 0 in 90;
`validation_status` unvalidated 1,760 / author_verified 747 (the 747 are almost all exam fills). For the 54 active
agents: 557 rows, 169 older than 30 days, 205 unvalidated.

**The "88 stale agent knowledge rows" on the Governance page** = `fn_knowledge_gaps(14, 4)`: it iterates
**`category_agents`** (88 active supplier-category personas, `cat:<slug>`), counts their `agent_knowledge` rows (15
each) and marks `stale` when `max(updated_at)` is older than 14 days — all 88 were last updated 2026-07-30 (37 days).
It says nothing about the 54 employees; there is no equivalent instrument for them.

## 6. The reasoning layer — playbooks, rules, SOPs

- `ops_knowledge` actionable kinds: decision_playbook **270**, decision_rule **245**, standard_operating_procedure
  **244**, exception_playbook 240 (759 of the first three across 21 dept_keys; only **2** carry a `role_key`).
- By `dept_key` (playbooks / rules / SOPs / exceptions): growth 57/0/0/0, data_intel 41/4/0/0, customer_experience
  38/0/0/0, legal 34/10/10/10, marketplace 29/0/0/0, finance 27/20/20/20, exec 14/11/11/10, product_eng 9/0/0/0, supply
  8/0/0/0, people_ops 8/0/0/0, it 5/30/32/30, procurement 0/30/30/30, supplier_success 0/20/20/20, knowledge
  0/20/20/20, customer_success 0/10/9/10, hr 0/10/10/10, knowledge_eng 0/10/10/10, sales 0/10/9/10, marketing
  0/10/10/10, evolution 0/10/12/10, intelligence 0/10/10/10, (null dept) 0/30/31/30.
- **Binding.** `fn_apply_playbook(agent, embedding, text, 0.85, 20)`: candidates = the four actionable kinds, embedded,
  current, in scope (`company`/`external_source` rows — of which **0** are actionable — or `dept_key = any(fn_dept_scope(dept))`
  or packaged `role_key`); a match needs cosine ≥ 0.85 **and** ≥ 2 of the step's lexemes covering ≥ 30 % of them **and**
  content ≥ 300 chars (the file's own measurement: random in-scope pairs score p50 0.837, p90 0.872, so cosine alone is
  noise). Actionable rows in scope per department (all 10 have some): customer_experience 67, data_intel 105, exec 77,
  finance 87, growth 116, legal 64, marketplace 119, people_ops 98, product_eng 106, supply 68 → **0 of 54 agents have
  zero playbooks bound to their department scope.** What is thin is *relevance*, not presence: e.g. people_ops's own 8
  playbooks are event-routing determinations; growth's 57 playbooks sit beside 0 rules/SOPs; five departments'
  actionable rows come entirely from the merged-in package dept_keys.
- **Use.** Last 7 days: 1,861 `workflow_step_run` rows; 8 outputs reference a playbook; 1,609 `used_llm = false`,
  1 `true`; 405 carry `used_llm_basis = "paid provider held (kernel K12) at settle time"`; 1,011 `skipped`, 784 `done`,
  19 `failed`. `agent_runs` 7 d: 8,722 runs / 126 agents — ok 8,489, error 145, skipped 73 ("Inference is held…", "Paid
  model held (founder_hold)"), info 15.

## 7. Top 10 company-wide actions (each raises every agent at once)

| # | action | evidence | owner role |
|---|---|---|---|
| 1 | **Make LAYER 2 admissible**: budget the profession layer against its own counter (or move LAYER 2 before the standing blocks / raise `own_cap` past the head) so the `agent_knowledge:profession` rows render. | 54/54 agents: LAYER 2 empty; guard ≈ 8,300 vs `out` 11,283–13,365 at the loop. | product_eng (backend_engineer) with people_ops (learning_dev_mgr) |
| 2 | **Re-order the head so live state and learned lessons sit inside the first 19,500 chars** (or raise the capped head and shrink the 188k-char v3 `deterministic_rules`), and give `supply` an `fn_ws_*` layer. | LAYER 3 at 21,796–22,098 for 48/54 and absent for 6; LAYER 4 at 21,808–24,831 for 54/54; capped run-time prompt = head[0:19,500] + ≤4,500. | product_eng (cto) |
| 3 | **Re-enable the `kb_chunks` embedding backfill** with a bounded picker that never runs the timing-out `count(*) is null`. | ≈ 2.54 M / 2.65 M chunks un-embedded (`null_frac` 0.9588; sampled ranges 0 %); jobs 108/242/271 inactive; 27 kb_embed errors/7 d. Vector retrieval currently covers only `qd_kb_pack`/`document`/`generated`/`library`/`memory`. | data_intel (knowledge_director) |
| 4 | **Point the head's company block at the live source**: replace the 2026-08-16 `_global company:self_knowledge` row with the `qd-company:*` records (or have cron 292 also write the `_global` row) and lift the 1,500-char truncation for the T&C block so top-3 report and AED 15k/3× anti-circumvention are in every prompt. | `company:self_knowledge` 2026-08-16, truncated 1,500/3,362; top-3 and anti-circumvention absent from all four measured heads; 44 live rows unread by the head. | exec (brief) with data_intel (knowledge_director) |
| 5 | **Fix the exam population and the fill**: sample questions from `fn_dept_scope(dept)` + packaged roles, exclude `scope_type = category` for non-`cat:` examinees, grade against what run time retrieves (ops_knowledge/kb_search), and stop writing category YAML into employees; purge the 147 polluted fills. | 506/591 active-agent questions are the template; 1,204 of 2,095 `dept_key is null` candidates are category routes; 147 polluted fills; people_ops examined on bakery-equipment and lifts. | people_ops (learning_dev_mgr) |
| 6 | **Give the exam a reasoning half that runs under the hold**: deterministic scenario cases (`department_scenario` 192 rows, `failure_mode_case` 692) scored by the expected determination, so the score means judgement, not lexeme overlap. | 0 agents ≥ 70 %; grader = lexeme overlap against 7–35 `agent_knowledge` rows; `canon_eval_runs` last 2026-08-10; `evaluation_suite` names resolve to nothing. | people_ops (learning_dev_mgr) + culture_performance_mgr |
| 7 | **Make LAYER 2c use `fn_dept_scope`** (same predicate as `fn_ops_knowledge_match`/`fn_apply_playbook`) so a department's merged-in package rows reach keyword retrieval too. | `fn_ops_knowledge_search` filters `dept_key = p_dept` exactly; `people_ops` 2c can never see the 271 `hr` rows it is scoped to elsewhere. | product_eng (backend_engineer) |
| 8 | **Populate `dept_library` for the seven departments with 0 rows** (LAYER 2b) from the department packages already in `ops_knowledge` (`professional_knowledge` module). | dept_library: legal 451, marketplace 361, assurance 318, finance 290, company 36, others 0. | data_intel (knowledge_director) |
| 9 | **Give the decay/curator loop something to act on**: set `review_due`/`review_after` per layer (today 0 of 2,507 and 0 of 9,132 are ever due) and re-enable `knowledge_curator_daily` in its deterministic parts. | `knowledge_decay_daily` succeeded twice/48 h and decayed 0; freshness sweep marks 0; 1,856 rows > 30 days untouched; curator/autofill/gen crons inactive. | people_ops (learning_dev_mgr) |
| 10 | **Put an employee-freshness instrument on the Governance page** and label the existing one "category agents". | "88 stale" = `fn_knowledge_gaps` over `category_agents`, not the 54 employees; `active_agents 88` counts inactive rows. | product_eng (backend_engineer) with people_ops (ops_director) |

Ranked by how many agents each lifts and how much run-time knowledge it restores: #1 and #2 change every prompt of
every agent today with no new content; #3 and #4 make existing content reachable; #5–#6 make the score mean something;
#7–#10 close the routing and instrumentation gaps.

## 8. What could not be measured, and boundaries

- Exact `kb_chunks` counts (total, un-embedded, last ingested) — every full scan exceeds the 8 s statement timeout;
  figures are `pg_class`/`pg_stats` estimates plus five sampled id ranges and `kb_category_stats` (refreshed 30-min).
- Zero-result rate of `kb_search` — no log stores result counts; `agent_context_retrieval.knowledge_count = 0` on 2 of 895
  is the only proxy, and it covers the v3 path only.
- Whether `fn_knowledge_curator` ever ran before being paused, and the last `kb_chunks` ingestion date — not queried.
- The `active_agents = 88` population in `fn_ws_governance` — not read from the routine body.
- The `_global` "Penalty & collections model" row's full text for the AED 15k/3× wording — matched by `ilike '%circumvent%'` only.
- No model call was made and nothing was written; the two `fn_agent_context_capped` / 3-arg probes ran inside `DO` blocks
  that ended in `raise exception`, so their `agent_context_head` / retrieval-log side effects were rolled back.
