# Knowledge audit — product_eng (Platform & Reliability)

Measured 6 Sep 2026 on project htdblwldjkcgjvmqkbeh, read-only, no model calls. Scripts: scratchpad `ka01`–`ka11` (`scripts/phase_c/lib/db.mjs`, 8 s statement timeout, small queries only). Every number below was read from the database or the repository on that date; anything not measured is marked as such. External sources marked **verify** are named from professional knowledge and must be checked for current edition/URL before ingest.

Agents in scope (org_agents.active, department = product_eng): `cto`, `it`, `backend_engineer`, `qa_manager`, `security`, `red_view_alerter` — 6 of the company's 54 active AI employees.

---

## 0. Findings that apply to every agent in this department (mechanism, not content)

These were measured once and change how every per-agent gap table should be read. **Ingesting more knowledge does not help until items 1–4 are fixed** — the knowledge would be written to tables the prompt never carries.

| # | Finding | Evidence (measured) |
|---|---|---|
| 1 | **LAYER 2 — "YOUR PROFESSIONAL EXPERTISE" is structurally empty for all 13 in-scope agents** (both departments). | `fn_agent_context(key, 22000)` returns 30,747–31,280 chars per agent; the section between `# LAYER 2` and `# LAYER 1` is 1 char for every agent. Cause in `fn_agent_context` (2-arg): `own_cap := least(cap/2, 6000)` → a Layer 2 piece is admitted only while `length(out)+length(piece) <= own_cap+2200 = 8,200`, but the identity/genome/risk-register/employee-record blocks emitted before it already total 12,162–13,180 chars. The guard cannot be true. The 52 `agent_knowledge.layer='profession'` rows held by the 13 agents (e.g. `it` has 23, `security` 10, `analytics` 8) never reach the model. |
| 2 | **Query-time layers are thin and partly off-topic.** With a task query (the path `agent_brain` actually uses: `fn_agent_context_capped(key, 24000, msg)`), the added layers measured: 2b dept library 492–607 chars, 2c ops-knowledge keyword hits 65–2,540 chars (700-char truncated snippets), 2d role knowledge 420–1,013 chars, 2f deterministic rules ~2,048, 2g fetch-not-remember ~919. Total task-specific knowledge per turn ≈ 4–7k chars of a ~39k-char prompt. | Probes `ctxq_cto`, `ctxq_it`, `ctxq_analytics`, `ctxq_market_analyst`. Layer 2b for `cto` and `it` returned company FAQ entries "What technology is QuotesDone built on?" and "What does the QuotesDone logo look like?" because **`dept_library` has 0 rows for `product_eng` or `data_intel`** (rows exist only for legal 451, marketplace 361, assurance 318, finance 290, company 36; newest 24 Jul). |
| 3 | **The 2.69M-chunk `kb_chunks` corpus does not reach these agents in a scoped way.** `fn_agent_context_v3` computes a scope-filtered `field_corpus` (category = any(fn_dept_scope)), but the 3-arg `fn_agent_context` never emits it (no "LAYER 2e" in its definition; 0 occurrences in all four probes). `agent_brain.retrieve()` calls `kb_search` **unscoped, k=8** for functional staff — 8 chunks from 356 categories (top categories by volume: aviation-maritime 119,750; marine-safety 77,833; business-consulting 71,492). | `def_fn_agent_context_1.sql`, `def_fn_agent_context_v3_0.sql` lines 186–198, `supabase/functions/agent_brain/index.ts` lines 295–318. kb_chunks: 2,686,026 rows, 356 categories, newest 31 Aug. |
| 4 | **The knowledge exam samples off-remit sources and writes wrong facts back as knowledge.** Of 136 questions held by the 13 agents, 28 come from supplier-category packs (`ops:V2:doc:…category_specialists/routes/086_lifts-and-escalator-suppliers…`, `…050_warehousing-and-3pl-companies…`), e.g. `cto` learned "Warehousing & 3PL Companies — Category Specialist Expertise V2" as Layer-4 experience. Across the 13 agents 76 answers were graded *wrong* and **53 of those were `filled=true`** — the grader's "fact" was inserted into `agent_knowledge` (layer experience) and now appears in LAYER 4. Sample filled gap facts include claims that must be **verified** before being trusted (e.g. "Sensitive PII must be stored on servers physically located within the UAE" — not a general PDPL requirement as written; "The Dubai Economy and Tourism (DET)… CCCP sector" as an authority for a backend question). | `knowledge_exam_questions`, `knowledge_exam_results` (`exam_wrong_filled`, `exam_question_sources`), `supabase/functions/knowledge_exam/index.ts` line 79 (`remitDeep = deepKb(label + ' UAE Dubai key materials…')` — a keyword search over the whole corpus) and line 111 (grader invents `correct_answer`). |
| 5 | **Validation is near zero.** Of the 1,348 `ops_knowledge` records reachable by product_eng agents (via `fn_ops_knowledge_match` scoping: company 200 + external 21 + dept-scoped 711 + role-scoped 416), **44 are `validation_status='validated'`**; corpus-wide: author_verified 5,129, reviewed 3,651, source_verified 302, validated 44. `source_freshness`: stable 1,528 / review_required 209 / current 115; 0 overdue reviews because only 779 of 1,852 in-scope rows carry `review_after`. `agent_knowledge` for the 13 agents: 0 of 147 rows validated. | `ka10_pool.mjs`, `ka04` agent_knowledge. |
| 6 | **The V2 "professional_knowledge" pack rows are template prose, not expertise.** 131 `it` + 13 `engineering` professional_knowledge rows read like: "When work involves disaster recovery, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP…" (2,248 chars, no procedure, no threshold). `SUPABASE_VERCEL_ENGINEERING_PLAYBOOK.md` in the engineering pack is 668 chars. The estate-specific depth that does exist is the **165 it_security_deep rows** (75 dept product_eng + 90 dept assurance, layer `it_security_deep`, 12 Aug) and 9 `org_task_lane` playbooks — all embedded and runtime-eligible, 0 validated. The 565 "deep expert" records of 2–3 Sep went to data_intel 101, marketplace 97, finance 94, customer_experience 92, growth 91, legal 90: **product_eng received none.** | `ops_it_prof_sample`, `it_prof_content`, `itsec_deep`, `deep_records`. |
| 7 | **kb_chunks quality in the engineering-facing categories is mixed.** `it` 55,789 chunks (cert 40,842; standard 13,364) — good sources exist (AWS Well-Architected 1,543; NIST SP 800-53/53A ~2,650; OWASP WSTG 711; NIST SP 800-160) but sampled chunks are 211-char UI click steps from NIST SP 1800-25 ("32. Click Next."). `engineering` 68,418 — PostgreSQL 16 docs 5,908 chunks (useful), but also Deep Learning / Bayesian Data Analysis / Convex Optimization textbooks, and NIST SP 800-34 "5.8 Deactivation" repeated 6× in an 8-row sample. `qa` 11,486 — SWEBOK, ISTQB syllabi, OWASP WSTG (good), arXiv ML-testing papers. Estate-stack coverage by full-text: supabase 98 chunks, vercel 46, pg_cron 24, plpgsql 60, `apply_sql` 264, `fn_kernel` 18, graphify 3. | `kb_sample_*`, `kb_docs_*_sources`, `kb_fts_*`. |
| 8 | **No decision records; ~10 real runbooks.** `decision_record`: 0 rows for product_eng or data_intel. `os_runbooks`: 181 rows, of which 171 are `lesson-N`; the operational runbooks are `site-down`, `cron-failing`, `email-not-sending`, `integration-disconnected`, `data-looks-wrong`, `payment-not-recorded`, `refund-stuck`, `supplier-cant-register`, `agent-bad-content`, `quote-gate-wrong`. Which routine reads `os_runbooks` at runtime was not measured. `decision_policy` has 38 threshold keys (e.g. `auto_action_max_aed`, `confidence_min`, `match_relevance_floor`, `founder_review_gates`). | `runbooks`, `decision_policy`, `decision_record`. |
| 9 | **What these agents actually do today is deterministic lane work, not reasoning.** Latest runs for `backend_engineer`, `it`: "org_task … determined from 4 fact(s) and playbook os.health_changed in product_eng … used_llm:false … ran fn_exec_review_deterministic". `cto`'s 3 skipped runs: "Inference is held (paidProviderGate / kernel K12, founder order)"; its 1 error: "The model returned nothing". `security`'s 168 runs/7d are an hourly sweep (`scanned:35, violations7d:0`). So the exam (LLM-graded, off-remit) is the only place reasoning is currently exercised — and it is the polluted loop in finding 4. | `runs_notes_sample`, `cto_runs_err`, `security_runs_counts`. |

**What could not be measured:** which runtime routine (if any) reads `os_runbooks`; the reader of `agent_context_retrieval` (only 1 row in 7 days, `cto`, 57 records / 40,956 chars on 3 Sep); `artifact_review` — 0 rows for these agents; live production reasoning quality (paid inference is held). `knowledge_exam` and `agent_train` were **not** invoked (they make paid calls).

---

## 1. `cto` — Chief Product & Technology Officer

**What it does today.** Runs/7d: 22 ok, 1 error, 3 skipped (26 total since 3 Sep; every skip/error is the K12 paid-provider hold). Exam: 5/20 correct (25%), grader confidence 0.42, 15 gap facts, 7 filled (4 of them from *wrong* verdicts). Retrievals/30d: 7 (last 3 Sep; queries such as "run agent action objective step"). Review chain as reviewer: 98 approve / 124 owned / 1 request_revision (223 decisions, 0.4% revision rate); as author 114 approve / 22 owned / 38 undecided. Incidents resolved: 0. KPIs: 9 (7 measured) — primary objectives 100%; "Ideas captured" 0 of 10; "Cost per reasoning call" AED 0.0000 (held); "Production changes behind a failing-first check" — *NEEDS AN INSTRUMENT THAT DOES NOT EXIST*. Authority: `execute_medium`, budget AED 100,000, department head inheriting `code_selfheal`/`incident_fix`/`security_review`/`uptime_verify` autonomous; `agent_action_kind_policy` authority for `backup_alert=notify`, `prompt_approval=officer`, `security_incident=notify`. Forbidden: certifying its own release, overriding an assurance stop, changing production data directly. Holds 8 packaged role identities (engineering-director, it-sre-and-cybersecurity-director, ai-and-model-operations-director, qa-and-testing-reviewer-auditor, strategy-performance-and-evolution-director …). Workflows: change_deployment, employee_task (approver), improvement_lifecycle, incident_response.

**Knowledge inventory (measured).**

| Source | What it holds for `cto` | Reaches the prompt? |
|---|---|---|
| `agent_knowledge` profession | 1 row: "Platform and engineering leadership", 717 chars, priority 74, unvalidated, 6 Aug | No (finding 0.1) |
| `agent_knowledge` experience | 7 rows: Kernel K12 paid gate (1,469), Phase A freeze guard (1,665), action-authority tiers (1,733), OTP sign-in / qa_mint (1,487) — good; plus "Warehousing & 3PL Companies specialist expertise" (1,560), `quote_comparison_contract.yaml` (737), `06_CATEGORY_REMEDIATION…V3.yaml` (791) — off-remit exam fills | Yes, LAYER 4 (3,500-char cap, newest 12) |
| `employee_knowledge` curriculum | 13 domains: ai_engineering/cybersecurity/data_analytics/engineering expert L1; company/goals/constitution/priority/universal expert L2; operations, pdpl awareness L4; quotesdone_os working L5; communication working L8 | Declarative only — binds no content |
| `ops_knowledge` reachable pool | 1,348 records (it 443, company 200, assurance 90, product_eng 84, engineering 33, ai_dept 31, qa 30, external 21, + role-scoped 416); 165 it_security_deep + 9 org_task_lane playbooks are the estate-specific core; 44 validated | Only via keyword (2c, ≤2,540 chars) or 8 cosine matches per turn |
| `kb_chunks` in scope (`it`,`engineering`,`qa`,`assurance`,`ai_dept`,`product_eng`) | it 55,789; engineering 68,418; qa 11,486 (no `assurance`/`ai_dept`/`product_eng` categories measured) | Not scoped (finding 0.3) |
| Estate self-knowledge | ops_knowledge (eng depts): MANIFEST 188 mentions, kernel 34, fn_kernel 13, apply_sql 4, pg_cron 10, RLS 47, Vercel 28, Next.js 11, Stripe 43, graphify 1; `agent_knowledge` (13 agents): MANIFEST 6, graphify 1, pg_cron 5. Repo has `graphify-out/GRAPH_REPORT.md` + `graph.json`, `scripts/sql/MANIFEST.txt` (1,669 lines) + DROPPED/SUPERSEDED/PENDING, 4 GitHub workflows, 205 edge functions, 1,337 files in `scripts/sql` — none ingested as a curated set | Partly (it_security_deep names CI gates, apply_sql, K12, the manifest) |
| `skills_matrix` | 13 skills avg 4.2/5 (self-asserted; PDPL 2, Operations & Quality 2, OS & Tooling 3) | — |
| `fn_agent_context('cto',22000)` | 30,747 chars; 42 headings; LAYER 2 = 1 char; LAYER 1 company = 8,496; LAYER 3 live = 2,602; LAYER 4 = 3,437 | — |

**Senior-staff standard — CTO of a Supabase/Next.js/Vercel/Deno estate in the UAE.**

| Domain | Depth |
|---|---|
| THIS estate's architecture: kernel (fn_kernel_*, K1–K12 gates, two-door write guard, `kernel_write_authority`), canonical routine manifest (`scripts/sql/MANIFEST.txt`, DROPPED/SUPERSEDED/PENDING), `apply_sql.mjs` dry-run/apply/promote read-back, CI gates (`checks.yml`, `project-parity.yml`, `deploy-functions.yml`, `resilience-ping.yml`), org_phase_baseline, 205 edge functions, 216 cron rows / 24 active | expert |
| Postgres 16 internals as used here: plpgsql semantics (SELECT INTO nulling, RECORD assignment, deferred triggers running as the transaction role, SECURITY DEFINER + `current_user`, `= any(subquery)` traps), EXPLAIN/plan reading, locking, statement_timeout, vacuum/bloat | expert |
| Supabase platform: RLS design and testing with two identities, PostgREST exposure of definer views/RPCs, pg_cron/pg_net, storage, PITR/backups, edge-function JWT posture, service-role boundaries | expert |
| Next.js/Vercel: App Router, ISR/caching, preview vs production deploy, env/secret scoping, rollbacks, build/runtime logs | working |
| Deno edge runtime: cold starts, WORKER_RESOURCE_LIMIT, `Supabase.ai.Session('gte-small')`, timeouts (8 s statement timeout, ~56 s brain timeout) | working |
| AI-layer economics and governance: OpenRouter/ai_gateway routing, prompt caching (`prompt_tokens_details`), ~900-token output cap, cost per call, K12 paid gate, hallucination controls, OWASP LLM Top 10 | expert |
| Release engineering: PR-only-to-main, failing-first check per change, rollback paths, canary/rehearsal windows (`withRun`, `rehearsal_window`), staging-less operation | expert |
| SRE: golden signals, SLO/error budget for a cron-driven estate, silent-failure detection (edge_health_watchdog), incident command | working |
| Security architecture: OWASP ASVS L2, secrets rotation, WI-001 inbound-secret separation, Stripe webhook HMAC, PCI-DSS SAQ A posture | working |
| UAE regulatory context for the platform: PDPL (Federal Decree-Law 45/2021) duties incl. breach notification and DPO, TDRA/NESA-IA controls (**verify** applicability to a private marketplace), Stripe/VAT invoicing constraints | aware→working |
| Marketplace product architecture: RFQ→match→quote→reveal (3% fee) flow, one-confirmed-supplier gate, capability matching (`use_capability_matching`, `match_relevance_floor`), anti-circumvention rules | expert |
| Data platform: metric_definition/company_goals instrumentation, kb_chunks/ops_knowledge/agent_knowledge retrieval stack and its budgets (the four layers, 2b–2g) | expert |
| Engineering management: prioritisation against the AED 1M / Aug 2027 goal, technical-debt ledger, evolution proposals (48 pending in the errored run), idea capture (KPI 0/10) | working |
| Vendor/API knowledge: Resend, Twilio/WhatsApp Business (template approval), Meta Marketing API, Stripe, Apify (paused) | working |
| Cost governance (FinOps): Supabase/Vercel/OpenRouter bills, `ai_cost_30d` AED 172 vs 7,700 target, `avoidable_ai_pct` 39.8 vs 10 | working |
| Backup/DR: `backup_success` goal, `dr_restore`/`dr_drill` functions, RTO goal "under 30 min" (unmeasured: NO INSTRUMENT EXISTS) | working |
| Decision hygiene: decision_record discipline (0 rows today), the ~200 memory lessons ("guarded by a condition that cannot occur", "a verifier that reads what it expects") as worked examples | expert |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Estate architecture (kernel, manifest, gates, deploy path) | expert | **partial** — 165 it_security_deep rows name K12, apply_sql, CI gates, PCCR gates; no curated map of the 205 functions, 24 active crons, the MANIFEST or graphify graph; `graphify` appears once in ops_knowledge | Curate `graphify-out/GRAPH_REPORT.md` god-nodes + community summaries, `scripts/sql/MANIFEST.txt` structure (canonical/dropped/superseded rules), `.github/workflows/*.yml` gate semantics, `docs/OS.md`, `docs/UPGRADE_PLAN.md` → `ops_knowledge` dept_key=product_eng, layer `it_security_deep`-style `kernel-and-app-controls` records (record_type reference/decision_playbook) so they are cosine-reachable | ~60 records × 1.5k chars | **P1** |
| Postgres/plpgsql internals (estate traps) | expert | **partial** — PostgreSQL 16 docs 5,908 chunks in kb_chunks (`engineering`) but unscoped retrieval; the plpgsql traps live only in `MEMORY.md` topic files, not in any table | Convert the ~40 Postgres/plpgsql lessons in `~/.claude/projects/…/memory/*.md` (SELECT INTO nulls, deferred trigger role, definer views, `= any(subquery)`, xmin attribution, `\m` transport) into `ops_knowledge` failure_mode records (product_eng); keep PostgreSQL 16 docs but add a `kb_chunks` scoped route (fix 0.3) | ~40 records × 1k | **P1** |
| Supabase RLS/PostgREST/definer surface | expert | **present** (estate-specific) — it_security_deep: "7 JWT-reachable SECURITY DEFINER RPCs", "175 definer views, zero PostgREST-exposed", JWT posture of ~202 functions; generic Supabase docs: 98 chunks | Ingest Supabase docs sections (RLS, `auth.uid()` patterns, pg_cron, pg_net, storage policies, PITR) as `kb_chunks` category `it`, source_kind `guide`, citation "Supabase Docs (**verify** version date)" | ~300 pages | P2 |
| Next.js/Vercel deploy & rollback | working | **missing** — Vercel 46 chunks, Next.js 11 ops_knowledge mentions; no rollback runbook | `kb_chunks` category `engineering`: Vercel docs (deployments, rollbacks, env vars, logs) + Next.js App Router caching/ISR chapters (**verify** edition); `os_runbooks` "vercel-rollback" with steps | ~150 pages + 1 runbook | P2 |
| AI-layer economics & governance | expert | **partial** — K12 gate, ai_gateway surface, "the tier is the bill" lessons in memory only; OWASP LLM Top 10 mentioned in docs/step3 README, 0 rows measured for "prompt cache" in ops_knowledge | `ops_knowledge` product_eng policy records: routing tiers and their cost, cache-prefix byte-stability rule, 900-token cap, out-of-credit signature, hold semantics; `kb_chunks` `ai_dept`: OWASP Top 10 for LLM Applications (**verify** 2025 edition) | ~20 records + ~60 pages | **P1** |
| Release engineering (failing-first check, PR-only) | expert | **partial** — apply_sql read-back rule present; KPI "changes behind failing-first check" unmeasurable | Decision playbook: "what is a check that fails on the defect it claims to catch" with 5 worked examples from `scripts/sql/*` names (e.g. `a_budget_guard_that_could_never_fire.sql`); instrument the KPI | ~10 records | **P1** |
| SRE golden signals / SLOs | working | **partial** — `it` agent holds "Adopted SLOs" (881 chars, 24 Jul, unvalidated, unreachable); error budget mentioned 4× | Google SRE Book ch. 4 (SLOs), ch. 6 (monitoring) and SRE Workbook ch. 2–5 (**verify** free online edition) → `kb_chunks` `it`; an estate SLO table (`ops_knowledge` kpi records) | ~120 pages + 8 records | P2 |
| Security architecture & ASVS | working | **partial** — OWASP WSTG 711 chunks, NIST SP 800-53; ASVS 0 mentions in ops_knowledge; WI-001 runbook in repo not ingested | `kb_chunks` `it`: OWASP ASVS 4.0.3 (**verify** vs 5.0) chapters V2–V4, V14; ingest `docs/security/WI-001-runbook.md`, `STRIPE_WEBHOOK_SETUP.md` as `ops_knowledge` sop | ~80 pages + 2 sops | P2 |
| UAE PDPL / TDRA-IA | aware→working | **partial** — PDPL 392 mentions across eng-dept ops_knowledge (mostly V2 template prose), 207 kb_chunks; NESA 0 in ops_knowledge, 44 kb_chunks; the exam filled a *wrong* data-localisation claim | `kb_chunks` `it`, source_kind `standard`: Federal Decree-Law 45/2021 (PDPL) full text + Executive Regulations when issued (**verify** status), UAE IA Regulation v1.1 (TDRA) control list (**verify**); quarantine the filled fact | ~150 pages | P2 |
| Marketplace product architecture | expert | **present** — company layer (LAYER 1, 8,496 chars incl. pricing LIVE, RFQ completeness rule), 9 org_task_lane playbooks, decision_policy keys | Add a single "how a reveal happens end to end" reference naming the routines (`fn_workflow_start`, one-spine promoter, reveal notify both parties) → `ops_knowledge` product_eng reference | 5 records | P3 |
| Data platform / retrieval stack self-knowledge | expert | **missing** — nothing tells the CTO that LAYER 2 is empty, dept_library is empty for its dept, or how fn_agent_context budgets work | Ingest `docs/expertise/AGENT_KNOWLEDGE_PATH.md`, `CORPUS_INGESTION.md`, `SEMANTIC_RETRIEVAL_STATE.md` + this audit's finding 0 → `ops_knowledge` product_eng reference | 6 records | **P1** |
| Vendor APIs (Resend, Twilio/WhatsApp, Meta, Stripe) | working | **partial** — Stripe webhook HMAC + surfaces present; Resend 11, Twilio 23, WhatsApp 115 mentions (template prose) | `kb_chunks` `engineering`: Stripe webhooks/idempotency docs, Twilio WhatsApp template & signature docs, Resend API + deliverability, Meta Marketing API budget/ceiling docs (**verify** versions) | ~200 pages | P3 |
| FinOps | working | **partial** — `it` profession row (981 chars, unreachable); metrics `ai_cost_30d`, `avoidable_ai_pct` exist | Policy record: monthly bill composition and the "30-day total is not a run rate" rule → `ops_knowledge` kpi/policy | 4 records | P3 |
| Backup/DR & RTO | working | **partial** — DR listed in V2 prose; `backup_success` measured; RTO unmeasured | `os_runbooks` restore runbook (Supabase PITR steps, verification query, comms); instrument RTO from `dr_restore` | 1 runbook + 1 instrument | P2 |
| Decision hygiene / worked examples | expert | **partial** — 7 LAYER-4 lessons; the ~200 memory lessons not in any table; decision_record 0 rows | Bulk-load MEMORY topic files as `ops_knowledge` failure_mode/remediation (dept product_eng, source_authority "session lesson", validation reviewed) | ~200 records × 800 chars | **P1** |
| Deno edge runtime limits | working | **partial** — Deno 96 mentions; WORKER_RESOURCE_LIMIT known only in docs/expertise | 3 reference records (batch limits, timeouts, gte-small edge-only) | 3 records | P3 |

**Reasoning gap.** Runbooks: 0 in tables for the CTO's own decisions (release go/no-go is qa_manager's; rollback runbook absent). Thresholds: present only in `decision_policy` (38 keys) and KPI targets; no threshold for "when does an evolution proposal get approved" (48 sat pending in the errored run). Decision trees: none — the 9 org_task_lane playbooks are lane determinations, not engineering decisions. Worked examples: 4 good ones in LAYER 4 (K12, freeze guard, authority tiers, OTP) and 3 off-remit; the repository's ~200 lessons are the missing corpus. **P1 count: 6.**

---

## 2. `it` — IT Operations & Site Reliability Engineer

**What it does today.** Runs/7d: 14 ok (19 since 10 Aug); latest run "org_task … os.health_changed … used_llm:false … fn_exec_review_deterministic". Exam: 6/20 (30%), confidence 0.49, 14 gaps, 6 filled (4 from wrong verdicts). Retrievals/30d: 13 (last 5 Sep; all "run agent action incident"). Author of 174 review-chain rows (108 approve, 1 revision); reviewer of none. Incidents owned: 1 resolved. KPIs: "Agent run reliability" 97.68% vs 97 (met); primary objective 100%. Authority `execute_medium`, budget AED 1,000; `incident_fix`/`code_selfheal` advisory (execution needs the department head); owns "backup and restore verdicts", "migration safety", "reliability targets and error budgets"; forbidden: approving its own migration, bypassing a release gate. Role identity: it-sre-and-cybersecurity-operations-specialist. Workflows: employee_task (owner), incident_response (step actor).

**Knowledge inventory.**

| Source | Holds | Reaches prompt? |
|---|---|---|
| `agent_knowledge` profession | 23 rows, avg 649 chars, newest 24 Jul, all unvalidated: cloud_data_residency_pdpl (613), platform_uptime_safe_change (598), secure_sdlc_appsec, incident_response_continuity (529), release_discipline (448), cyber_governance, api_security, network_identity_security, qa_real_browser, data_engineering_governance, code_review_adversarial, engineering_principles, it_procurement_outsourcing, web_arabic_accessibility, tech_stack_evaluation, uae_digital_economy_context, "Professional standard (Google SRE)" 574, "Verified references & key standards" 1,446, "Adopted SLOs" 881, "FinOps" 981, "Deepened professional playbook" 1,403 | **No** (finding 0.1) — the largest profession set in the department and none of it is in the prompt |
| `agent_knowledge` experience | 12: Stripe webhook HMAC/600 s replay (1,479), WI-001 autonomy brake (1,662), CI gates + canonical_routine_manifest (1,671), org_authority_guard (1,707) — good; `qualification_playbook.md` (2,206), `06_CATEGORY_REMEDIATION…` (791) — off-remit; 6 org lessons ~200 chars | Yes, LAYER 4 |
| `ops_knowledge` pool | same 1,348 as cto; probe "backup overdue alert and edge function 5xx spike; incident response runbook and RTO" returned 2c = 2,538 chars: "Incident response = the inc…", "Machine-to-edge auth", "Edge-function auth posture" | keyword/cosine only |
| `os_runbooks` operational | site-down, cron-failing, integration-disconnected, email-not-sending, payment-not-recorded, refund-stuck, data-looks-wrong | reader not measured |
| `founder_alerts` 7d (what it must act on) | 120 alerts: runner_silent 39, cron_silent 22, "Scheduled runs failed" 10, "Security drift: public data reachable by anon" 7, "Backup may have failed or is overdue" 1 | LAYER 3 live state |
| `fn_agent_context('it',22000)` | 31,015 chars; LAYER 2 = 1; LAYER 4 = 3,502 | — |

**Senior-staff standard — SRE/IT operations for this estate.**

| Domain | Depth |
|---|---|
| Incident response: severity matrix, on-call runbooks for the 10 alert families above, comms template, post-incident review (NIST SP 800-61 r2/r3 **verify** revision) | expert |
| Silent-failure detection: edge_health_watchdog semantics, "produced no effect for N minutes" vs dormant-by-design (16 Aug stand-down list), runner_silent/cron_silent meaning | expert |
| pg_cron operations: job table, `cron.job_run_details`, deactivation vs death, wrapping a cron with `accountable_role_id`, the 22-of-23 jobs that dispatch `fn_kernel_cron_*` | expert |
| Backup/DR: Supabase PITR/daily backups, restore drill procedure, RTO/RPO targets, `dr_restore`/`dr_drill`, Dropbox backup path | expert |
| SLOs and error budgets for a cron-driven platform; `failed_runs_24h` target 0; run reliability 97% | expert |
| Edge function operations: deploy-functions gate, cold starts, 5xx triage, log query (`query_logs`), secrets (`cred_fn_*`, `cred_cron_*`, `__secret` convention), WI-001 | expert |
| Postgres operations: connection limits, statement_timeout=8 s on the management API, long transactions, bloat, index health, `pg_stat_statements` | working |
| Change safety: apply_sql dry-run/apply/promote, read-back, migration verdicts, manifest line for every new SQL file, down scripts in `scripts/sql/down/` | expert |
| Vercel operations: deployment status, build failures, rollback, domain/DNS, env drift | working |
| Observability: golden signals mapped to estate tables (`health_checks`, `health_state`, `error_events`, `edge_health_probe`) | expert |
| Security operations (joint with `security`): drift alerts ("public data reachable by anon"), secrets rotation cadence, access review | working |
| Cost operations: Supabase compute/egress, Vercel, OpenRouter credit exhaustion (reads like model judgement), Meta balance | working |
| Messaging providers: Resend bounce/complaint handling, Twilio/WhatsApp delivery errors, outbox semantics ("the outbox does not send") | working |
| UAE PDPL operational duties: breach clock, erasure (`pdpl_erase`), data-subject requests handoff | working |
| Capacity: worker resource limits, batch sizes (kb_embed 5–8 rows), queue depth (`dispatch_max_batch`) | working |
| Estate map: 205 functions, 24 active crons, which are heartbeats (4 dominate ~276 runs/day) | expert |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Incident response runbooks (10 alert families) | expert | **partial** — 7 generic os_runbooks (steps present, reader unmeasured); `incident_response_continuity` 529 chars unreachable; W29 workflow doc in repo only | Author one `os_runbooks` row per alert family (runner_silent, cron_silent, scheduled-runs-failed, security-drift-anon, backup-overdue, edge 5xx, stalled handoff, action-queue swept) with detection query, decision, fix, verify, comms; mirror each as `ops_knowledge` product_eng `remediation` (embedded) | 8 runbooks × 1.5k | **P1** |
| Silent-failure semantics / dormant list | expert | **partial** — resolutions cite "16 Aug stand-down / OpenRouter hold" but the dormant list is not a knowledge record | `ops_knowledge` policy: the stand-down list, what "no effect" means per function, re-enable procedure (memory: "deactivation is not death", "re-opening loops needs his session") | 3 records | **P1** |
| pg_cron operations | expert | **present** (estate) — "Cron scheduler: pg_cron, 216 job rows / 24 active" record; pg_cron 24 kb_chunks | Add `cron.job_run_details` triage SQL and the wrap-a-cron rule (`accountable_role_id` must resolve) as a `remediation` record | 2 records | P2 |
| Backup/DR procedure | expert | **partial** — DR is V2 template prose; backup alert exists; no restore runbook; RTO unmeasured | `os_runbooks` "restore-from-pitr" + "dr-drill"; Supabase backups/PITR docs → `kb_chunks` `it` (**verify** plan features) | 2 runbooks + ~30 pages | **P1** |
| SLOs / error budgets | expert | **partial** — "Adopted SLOs" 881 chars unreachable; KPI 97% | Promote "Adopted SLOs" to `ops_knowledge` kpi records (one per SLO with measure SQL) once Layer 2 is fixed or regardless; SRE Book ch. 4/6 → `kb_chunks` `it` | 6 records + 60 pages | P2 |
| Edge-function ops & secrets | expert | **present** — it_security_deep covers auth posture, `__secret` convention, WI-001; LAYER 4 has CI gates | Ingest `docs/security/WI-001-runbook.md` verbatim as sop | 1 record | P3 |
| Postgres operations | working | **partial** — PostgreSQL 16 docs in kb_chunks (unscoped); no estate-specific ops queries | `ops_knowledge` reference: 10 canned diagnostics (locks, long tx, bloat, top statements, cron failures) | 10 records | P2 |
| Change safety (apply_sql, manifest, down scripts) | expert | **present** — "Change safety: apply_sql.mjs applies then READS THE DEFINITION BACK OUT" (1,450 chars) and CI gates in LAYER 4 | Add "new SQL file needs a MANIFEST line", "regenerate the mirror after the LAST apply", "two files one routine one commit" lessons | 3 records | P3 |
| Vercel operations | working | **missing** — 46 chunks; no runbook | Vercel deployments/rollback/logs docs → `kb_chunks` `it`; 1 runbook | ~40 pages | P2 |
| Observability mapping | expert | **partial** — live_data_candidates lists table names (health_checks, health_state, error_events…) with no queries | Reference record per table: what a red value means and the query | 8 records | P2 |
| Security drift alert handling | working | **partial** — alert fires 7×/7d; no playbook for "public data reachable by anon" | Remediation record: how to find the offending grant/policy, revoke, verify (memory: "a definer view hands back what the table withheld") | 2 records | **P1** |
| Cost operations | working | **partial** — FinOps 981 chars unreachable; metrics exist | Policy record on credit exhaustion signature ("out of credit looks like model judgement") and the hold | 2 records | P3 |
| Messaging providers | working | **partial** — provider playbook 613 chars | Resend/Twilio error-code tables → `kb_chunks` `it` (**verify**) | ~30 pages | P3 |
| PDPL operational duties | working | **partial** — PDPL breach duties held by `security` (unreachable); pdpl_erase function exists | Shared sop with `security` (see §5) | shared | P2 |
| Capacity limits | working | **partial** — docs/expertise only | 2 reference records | 2 records | P3 |
| Estate map | expert | **partial** — "agent_runs baseline ~276 runs/day, four heartbeats" present | Curated function/cron inventory (from graphify + `cron.job`) | 1 record ~4k | P2 |

**Reasoning gap.** Runbooks: 7 generic present, 0 for the alert families that actually fire (runner_silent 39, cron_silent 22 in 7 days). Thresholds: run reliability 97, failed_runs_24h 0 — no per-alert severity thresholds. Decision trees: none ("is this silence dormant-by-design or a failure?" is decided by prose in resolutions). Worked examples: 4 good LAYER-4 items. **P1 count: 4.**

---

## 3. `backend_engineer` — Backend Engineer

**What it does today.** Runs/7d: 15 ok (all since 5 Sep, deterministic lane: "os.health_changed … fn_exec_review_deterministic"). Exam: **2/26 correct (8%)** — lowest in scope; confidence 0.53; 24 gaps, 4 filled; 6 wrong, 12 partial. Retrievals/30d: 0. Author of 105 review rows (63 approve). Incidents: 0. KPI: primary objective 100% (1 KPI). Authority `execute_low`, budget 0; `code_selfheal`/`incident_fix` advisory. Owns "backend implementation approach within the agreed architecture"; forbidden: deploying unreviewed, changing authority/RLS without security review. Tools: code_selfheal, evolution_scan, incident_fix. Outputs: implementation_plan, change_set.

**Knowledge inventory.** `agent_knowledge` profession: 1 real row "Backend engineering in this codebase" (758 chars, priority 74, unvalidated) + 2 exam stubs of ~140 chars (unreachable anyway). Experience: "Retired 410 surfaces" (1,277, good) and `specialist_manifest.yaml` (4,000 chars — an IT-services *supplier category* manifest, off-remit). `employee_knowledge`: same 13-domain curriculum as cto. `v_knowledge_matrix`: profession 3 topics avg 345 chars, spec_modules_present 0. Reachable ops_knowledge pool: same 1,348 as the department, but its packaged role is engineering-operations-specialist → 27 role-scoped `engineering` records. Exam questions: 3 itsec_deep, 3 "domain", 1 category-pack. Sample wrong/partial gap facts: "The ai_cost_log module, which performs real-time telemetry…" (wrong), "Sensitive PII must be stored on servers physically located within the UAE" (partial — **verify**, likely over-claimed), "DET… CCCP sector" (wrong).

**Senior-staff standard — backend engineer on this estate.**

| Domain | Depth |
|---|---|
| plpgsql authoring: routines, triggers (BEFORE returning NULL = refusal, firing-order prefixes), RECORD/SELECT INTO semantics, exception blocks, `format()` and `%I`, SECURITY DEFINER hygiene, `search_path` | expert |
| Schema/RLS: policy authoring for customer/supplier/founder principals (email is the identity), grants vs policies, definer views, PostgREST exposure | expert |
| Edge functions (Deno): handler shape, `_shared/paid_gate.ts` (K12), `__secret` auth, idempotency, error propagation ("error and empty must not return the same value"), timeouts | expert |
| The kernel: workflow_start/step_complete, one-spine promoter, org_task lanes, action_execution, decision_trace — where a change must be made and what guards it | expert |
| Canonical manifest discipline: one file per routine, MANIFEST line, down script, `apply_sql` read-back, `sql_files_match_live` | expert |
| Postgres performance: indexes, EXPLAIN ANALYZE, HNSW/pgvector (`hnsw.ef_search`), tsvector/GIN, batching within 8 s | working |
| API design: PostgREST RPC contracts, JSON shapes, versioning, PDPL-safe payloads (redact before truncate) | working |
| Payments: Stripe checkout/webhook/refund surfaces, idempotency keys, three externally issued refund originators | working |
| Messaging: outbox tables, Resend/Twilio adapters, template constraints | working |
| Testing: failing-first checks, fixture conventions (ZZ DEMO / example.invalid), rehearsal windows, `withRun`, e2e harness limits ("harness seeds an order reality cannot produce") | expert |
| Retrieval stack: kb_chunks/ops_knowledge schema, embedding via kb_embed, fn_agent_context layers/budgets | working |
| Security coding: OWASP Top 10 mapped to Deno/Postgres, secrets handling, SSRF/injection in `net.http_post` | working |
| Git/PR flow: branch, PR-only-to-main, stage paths never `add -A`, CI gates | expert |
| Observability hooks: agent_runs/counts, error_events, decision_trace | working |
| Next.js server actions/route handlers calling Supabase (portal surfaces) | working |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| plpgsql authoring & traps | expert | **missing** in tables (758-char profession row unreachable; traps only in memory files; plpgsql 4 mentions in eng ops_knowledge, 60 kb_chunks) | ~30 memory lessons → `ops_knowledge` product_eng failure_mode (SELECT INTO nulls, unassigned RECORD raises, BEFORE trigger NULL refusal, deferred trigger role, `least()` ignores nulls, `= any(subquery)`); PostgreSQL 16 "PL/pgSQL" chapter kept in kb_chunks with scoped retrieval | 30 records + ~100 pages | **P1** |
| Schema/RLS/definer surface | expert | **partial** — it_security_deep covers the *surface* (7 RPCs, 175 views) not *how to author* a policy; Supabase 98 chunks | Supabase RLS docs + 5 estate policy exemplars (customer/supplier/founder) as reference records | 5 records + 40 pages | **P1** |
| Edge-function patterns | expert | **partial** — K12 gate, auth posture present; no handler template, no idempotency/error rules | Reference: canonical handler skeleton from `_shared/`, error-vs-empty rule, timeout/retry rules (db.mjs 429 backoff) | 4 records | **P1** |
| Kernel write path | expert | **partial** — "two-door kernel write guard", "org_phase_baseline append-only" present; no map of workflow_start/step_complete/promoter | Reference set from `fn_kernel_*` definitions + memory lessons ("two creators for one object", "Phase D dispatch fires at step OPEN", "no open step means handoff unaccepted") | 8 records | **P1** |
| Manifest discipline | expert | **present** (apply_sql record, CI gates in LAYER 4 of `it`, not of backend_engineer) | Copy the 3 change-safety records into backend scope (role-scoped engineering) | 3 records | P2 |
| Postgres performance / pgvector | working | **partial** — PostgreSQL docs unscoped; hnsw settings visible only in function bodies | pgvector README (HNSW params) + PostgreSQL 16 "Performance Tips" chapter → `kb_chunks` `engineering` (**verify** pgvector 0.8.0 docs) | ~60 pages | P3 |
| API/PostgREST contracts | working | **partial** — PostgREST exposure counted; no contract guide | PostgREST docs (RPC, computed fields, errors) → `kb_chunks` `engineering` | ~40 pages | P3 |
| Stripe surfaces | working | **present** — Stripe payment/refund surface records, webhook HMAC | Add refund originator rule (memory: "an externally issued refund is a fact") | 1 record | P3 |
| Messaging adapters | working | **partial** — 613-char provider playbook | Outbox semantics + adapter map (3 records) | 3 records | P3 |
| Testing & fixtures | expert | **partial** — "Fixtures and demo data must be excluded by default" is a *data_intel* record; ZZ DEMO convention in memory | Policy: fixture convention, rehearsal_window, HTTP probes commit → pick safe tables, harness limits | 5 records | P2 |
| Retrieval stack | working | **missing** | as cto row | shared | P2 |
| Security coding | working | **partial** — OWASP WSTG in kb_chunks (unscoped); "Retired 410 surfaces" in LAYER 4 | OWASP Cheat Sheet Series: SQL injection, SSRF, secrets (**verify**) → `kb_chunks` `it` | ~50 pages | P2 |
| Git/PR flow | expert | **partial** — PR-only rule in it_security_deep ("Production-direct deploys and the apply→merge window") | "Stage paths, never git add -A" + PR body rules | 2 records | P3 |
| Observability hooks | working | **partial** — counts jsonb shapes visible in runs; not documented | 2 reference records | 2 records | P3 |
| Next.js/Supabase client | working | **missing** — Next.js 11 mentions | Supabase JS + Next.js App Router auth docs → `kb_chunks` `engineering` (**verify**) | ~40 pages | P3 |
| Off-remit pollution | — | 4,000-char `specialist_manifest.yaml` (IT-services supplier category) sits in its LAYER 4 | Quarantine that row (`validation_status='quarantined'`) | — | **P1** |

**Reasoning gap.** No runbook for "implement a change safely" beyond the apply_sql record; no worked example of a backend change end to end (branch → SQL file → MANIFEST → check → PR → apply → read-back). Thresholds: none of its own. Decision tree: "is this a kernel write or an app write?" exists only as the two-door guard record. **P1 count: 5.**

---

## 4. `qa_manager` — QA & Release Management Director

**What it does today.** Runs/7d: 15 ok (deterministic lane since 5 Sep). Exam: 8/20 (40%) — best in scope; confidence 0.55; 12 gaps, 6 filled (4 from wrong). Retrievals/30d: 0. Author of 160 review rows (96 approve); reviewer of none — although its role is `stop_authority` ("final release go/no-go", "blocking a release on any gate"). KPIs: 4 — primary objective 100%; "Regressions caught before production", "RFQ qualification accuracy", "Task classes with a measured benchmark": all *NEEDS AN INSTRUMENT / FIXTURE THAT DOES NOT EXIST*. Authority `stop_authority`, budget AED 1,000; `capability_exam`/`qa_gate` autonomous. Holds qa-and-testing-director/operations-specialist/analyst-controller + ai-and-model-operations-operations-specialist. Workflows: change_deployment (step actor), employee_task, rfq_handling (participant). Forbidden: writing the tests it rules on; offline model evaluation (belongs to Model Evaluation Reviewer); approving a release for a change it authored.

**Knowledge inventory.** Profession: 1 row "Quality assurance for an AI-operated company" (688 chars, unreachable). Experience 6: ai_gateway surface (1,478), Retired 410 surfaces (1,277), trigger-prefix/guard-is-LIVE lesson (1,578), agent_runs baseline (1,399) — good; `quote_comparison_contract.yaml` (737), `rfq_quality_gate.yaml` (742) — category-pack items (arguably relevant to "RFQ qualification accuracy" but not QA method). `employee_knowledge`: operations expert L1, customer_success/engineering/procurement awareness L4 — *no cybersecurity or engineering expert layer* although it rules on releases. `skills_matrix`: Software Engineering 2, Operations & Quality 4. kb_chunks `qa`: 11,486 (SWEBOK v3/v4 ~1,560, ISTQB syllabi ~700, OWASP WSTG 711, NIST 800-160, arXiv ML-testing papers) — unscoped at retrieval. Exam sources: 6 itsec_deep, 3 category-pack, 1 ops.

**Senior-staff standard — QA & release director for an AI-operated marketplace.**

| Domain | Depth |
|---|---|
| Release gating: go/no-go criteria, the 4 CI gates and what each proves, "green PR does not mean deployable", edge typecheck vs deploy | expert |
| Test strategy (ISTQB CTFL v4 / Advanced Test Manager): risk-based testing, test levels, entry/exit criteria, defect classification | expert |
| Failing-first checks: how to judge that a check fails on the defect it claims to catch; the estate's `scripts/sql/*` check naming; "a check held open by pre-fix rows", "freeze the population before the write" | expert |
| Regression detection instruments: what would record "regression caught before production" (none exists) — designing the instrument | expert |
| E2E/browser testing on Next.js portals (Playwright), fixture identities (never a fixture identity), rehearsal windows, `withRun` | expert |
| AI-output quality: negation-blind detectors, vision reviewers that read what they expect, hallucination-rate instrument (goal unmeasured), evaluation holdouts vs the Model Evaluation Reviewer boundary | expert |
| RFQ qualification accuracy: holdout set design, qualification playbooks (`qualification_playbooks` table), 70/100 quality gate | working |
| Security testing baseline (OWASP WSTG) and when to escalate to `security` | working |
| Data-quality gates for releases touching metrics (definition drift, denominator traps) | working |
| Incident declaration: what makes an incident release-blocking; severity matrix shared with `it` | expert |
| Rollback decision: criteria and who executes | expert |
| Benchmarks per task class (KPI): what a benchmark is, how to store it | working |
| Kernel invariants (58/58 invariant suite, 257 effects, W12 withheld) as the acceptance surface | expert |
| Accessibility/Arabic RTL basics for portal releases (WCAG 2.2 AA) | aware |
| PDPL-safe test data (no real personal data in fixtures) | working |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Release gating criteria | expert | **partial** — CI gates are in `it`'s LAYER 4, not qa_manager's; "green PR ≠ deployable" only in memory | `ops_knowledge` product_eng decision_playbook "release go/no-go": inputs (checks.yml, project-parity, deploy-functions, invariant suite), stop conditions, who can override; role-scope it to qa-and-testing-director | 3 records | **P1** |
| Test strategy (ISTQB) | expert | **partial** — ISTQB CTFL 174 chunks + Advanced syllabi ~700 chunks in kb_chunks `qa`; proven retrievable via v3 field_corpus but that layer is not emitted (0.3) | Keep; fix emission; add ISTQB CTFL v4.0.1 (**verify**) whole syllabus if only ~50 pages were loaded | ~100 pages | P2 |
| Failing-first checks | expert | **missing** in tables — the doctrine lives in memory files and `scripts/sql` names | 10 worked examples (check name → defect → why it fails first) as `ops_knowledge` reference; the 5 memory lessons on checks | 15 records | **P1** |
| Regression instrument | expert | **missing** — KPI says no instrument | Design note + measure SQL proposal (which table records a pre-prod catch: review_chain `request_revision`? `qa_results`?) — a `metric_definition` owned by product_eng | 1 record + 1 metric | **P1** |
| E2E/browser & fixtures | expert | **partial** — `qa_real_browser` (415 chars, `it`'s row, unreachable); harness lessons in memory | Policy records: fixture identity rule, rehearsal_window, safe-table rule for HTTP probes; Playwright basics → `kb_chunks` `qa` (**verify** docs version) | 4 records + 30 pages | P2 |
| AI-output quality | expert | **partial** — hallucination goal unmeasured; lessons ("a guard that fires on the correct refusal", "a verifier that reads what it expects") in memory only | Convert those lessons → failure_mode records; OWASP LLM Top 10 testing guidance → `kb_chunks` `ai_dept` | 6 records + 40 pages | **P1** |
| RFQ qualification accuracy | working | **partial** — `qualification_playbooks` table exists; rfq_quality_gate.yaml in LAYER 4; no holdout set | Reference: how a holdout set is built from revealed outcomes (data_intel deep record "revealed outcomes are the labels" — cross-scope) | 2 records | P2 |
| Security testing baseline | working | **present** — OWASP WSTG 711 chunks (unscoped) | none beyond scoped retrieval | — | P3 |
| Data-quality gates | working | **missing** in scope — the definitions live in data_intel deep records (not reachable from product_eng) | Copy 3 data_intel records (definition drift, denominator, fixtures) into a `company` scope or cross-scope `qa` | 3 records | P2 |
| Incident declaration | expert | **partial** — declared in org_role owned_decisions; no severity matrix | Shared severity matrix record with `it` | 1 record | P2 |
| Rollback decision | expert | **partial** — `rollback.required` org_task_lane playbook exists (2,272 chars) | Add criteria + executor | 1 record | P2 |
| Benchmarks per task class | working | **missing** — KPI unmeasured | Definition + storage proposal | 1 record | P3 |
| Kernel invariant suite | expert | **partial** — "a rehearsal proves creation, not execution", "the harness withholds only W12" in memory | Reference record describing the suite and its blind spots | 2 records | P2 |
| WCAG/RTL | aware | **partial** — `web_arabic_accessibility` 597 chars (it's row) | WCAG 2.2 quick reference → `kb_chunks` `qa` (**verify**) | ~20 pages | P3 |
| PDPL-safe test data | working | **missing** | 1 policy record | 1 record | P3 |

**Reasoning gap.** Runbooks: none for go/no-go. Thresholds: 3 of 4 KPIs unmeasurable; no defect-severity thresholds. Decision tree: absent. Worked examples: 4 relevant LAYER-4 items; the check-naming corpus in `scripts/sql` (1,337 files) is an unexploited source of worked examples. **P1 count: 4.**

---

## 5. `security` — Cybersecurity Engineer

**What it does today.** Runs/7d: 168 ok (hourly sweep, `scanned:35, suspicious:0, violations7d:0`; 1,784 runs since 23 Jun). Exam: 5/20 (25%), 0 wrong, 12 partial, 3 not_covered; confidence 0.48. Retrievals/30d: 5 (last 4 Sep, "run agent action backup alert"). Reviewer: 38 approve (0 revisions). Incidents: resolved 22 (owner of 30) — every sampled resolution is the deterministic "Dormant function (X): its cron is intentionally inactive (16 Aug stand-down / OpenRouter hold)" text, resolved in 0.2 h. KPI: primary objective 100%. Authority `stop_authority`, budget AED 1,000; owns security verdicts, blocking a critical failure, access and secret policy, incident containment; forbidden: approving a change it authored, granting itself access. Tools: event_dispatch, health_report, recommend, secops_pattern_test, security_review, uptime_verify. Role identity: it-sre-and-cybersecurity-reviewer-auditor.

**Knowledge inventory.** Profession 10 rows, avg 1,010 chars, newest 24 Jul, unvalidated, **unreachable**: Incident response runbook (1,393), Personal-data breach duties PDPL (1,165), Vendor security assessment checklist (979), Secrets lifecycle policy (945), Vulnerability management SLA (871), Deepened professional playbook (1,422), Verified references (1,498), Professional standard CISSP/OWASP/ISO 27001 (624), QuotesDone threat model (577), Role (622). Experience 3: all category-pack documents (`06_CATEGORY_REMEDIATION…`, `01_EXPERT_QUALIFICATION_STRATEGY_V3.md`, `source_route_manifest.json`) — off-remit. Reachable ops_knowledge: the 165 it_security_deep records are its strongest asset (edge-function attack surface 14, database-security-rls-grants 14, auth-identity-baseline 15, kernel-and-app-controls 16, infra-integrations-incident 16 in product_eng; 90 more in assurance). `docs/step3/README.md` documents the intended four dimensions (internal mastery, OWASP, MITRE ATT&CK + CVE snapshot, OWASP LLM Top 10); only the internal-mastery dimension was found in tables (MITRE/CVE not measured by keyword — **not measured**). kb_chunks `it`: NIST 800-53/53A, AWS WAF, OWASP WSTG, NIST 800-160, 800-82, RFC 4949 (unscoped). PDPL: 207 kb_chunks; NESA: 44 chunks; ASVS: 0; ISO 27001: 2 mentions.

**Senior-staff standard — security engineer for this estate in the UAE.**

| Domain | Depth |
|---|---|
| Estate attack surface: 205 edge functions (13 JWT-gated), 7 JWT-reachable definer RPCs, 175 definer views, retired 410 surfaces, OTP/qa_mint primitives | expert |
| Secrets: WI-001 separation, `cred_*` conventions, rotation cadence, Stripe two-secret HMAC, Twilio signature gap on WhatsApp inbound | expert |
| Incident response (NIST SP 800-61): containment/eradication/recovery, evidence, PDPL breach notification clock (**verify** 72 h in Executive Regulations), founder notification (`security_incident=notify`) | expert |
| Access control: RLS as the boundary, grants vs policies, service-role usage, `org_authority_guard`, authority tiers | expert |
| AppSec: OWASP Top 10 (2021), ASVS L2 verification, WSTG test cases mapped to Deno/Postgres/Next.js | expert |
| LLM security: OWASP Top 10 for LLM apps, prompt injection via marketplace content, excessive agency (autonomous actions), poisoned knowledge (the exam-fill loop *is* a poisoning vector) | expert |
| Threat intelligence: MITRE ATT&CK for SaaS, CVE watch for Deno/Postgres/pgvector/Next.js/Supabase CLI (dated snapshot, never static) | working |
| Compliance mapping: PCI-DSS SAQ A (Stripe-hosted), ISO 27001:2022 Annex A, SOC 2 CC, UAE IA Regulation (TDRA) and NESA/SIA controls (**verify** applicability), Dubai Electronic Security Center (**verify**) | working |
| Security monitoring: security_events, security_audit_log, drift alert "public data reachable by anon", secops_rule patterns, the hourly sweep semantics | expert |
| Vendor security assessment (Resend, Twilio, Stripe, Meta, OpenRouter, Apify): DPA, data location, sub-processors | working |
| Data protection engineering: PDPL principles, data minimisation, retention, erasure (`pdpl_erase`), redaction before truncation, cross-border transfer rules | expert |
| Backup integrity & ransomware resilience (NIST SP 1800-25/26 concepts) | working |
| Secure SDLC: review of RLS/authority changes (forbidden for backend without security review), failing-first security checks | expert |
| Fraud/abuse on the marketplace: anti-circumvention (AED 15k / 3×), fraud_score_max, supplier identity spoofing, phone-may-confirm-never-select | working |
| Communication: incident comms to founder via WhatsApp channel; what not to send (secrets, PII) | working |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Estate attack surface | expert | **present** — 165 it_security_deep records (0 validated) | Validate (set `validation_status='validated'` after review) and add `review_after`; refresh counts (202→205 functions) | — | P2 |
| Secrets & rotation | expert | **partial** — "Secrets lifecycle policy" 945 chars unreachable; WI-001 records present | Promote the policy to `ops_knowledge` policy; ingest `docs/security/WI-001-runbook.md` | 2 records | **P1** |
| Incident response + PDPL breach | expert | **partial** — IR runbook (1,393) and PDPL breach duties (1,165) exist but unreachable; incidents today are all dormant-function auto-closes | Promote both to `ops_knowledge` remediation/policy (product_eng, role reviewer-auditor); add PDPL breach clock with source citation (**verify**); `os_runbooks` "security-incident" | 3 records + 1 runbook | **P1** |
| Access control | expert | **present** — RLS/grants module (14), authority tiers in LAYER 4 (cto) | none | — | P3 |
| AppSec / ASVS | expert | **partial** — WSTG 711 chunks unscoped; ASVS absent | OWASP ASVS (**verify** 4.0.3/5.0) → `kb_chunks` `it` source_kind standard; OWASP Top 10 2021 | ~120 pages | P2 |
| LLM security | expert | **missing** in tables (docs/step3 intent only; 0 rows measured for "OWASP LLM") | OWASP Top 10 for LLM Applications 2025 (**verify**) + a policy record naming the exam-fill loop and marketplace-content injection as live vectors | ~60 pages + 2 records | **P1** |
| Threat intel / CVE | working | **not measured** (no MITRE/CVE keyword census run) | Dated CVE snapshot record for Deno, PostgreSQL 16, pgvector, Next.js, Supabase — refreshed monthly (**verify** each advisory) | 1 record, recurring | P2 |
| Compliance mapping | working | **partial** — NESA 44 chunks, ISO 27001 2 mentions, PCI SAQ A in docs/step3 only | Control-mapping table (ISO 27001:2022 Annex A ↔ estate controls) as reference; UAE IA Regulation control list (**verify**) → `kb_chunks` `it` | ~40 pages + 1 record | P3 |
| Security monitoring | expert | **partial** — sweep semantics undocumented; drift alert has no playbook | Remediation record for "public data reachable by anon"; reference for the hourly sweep (what `scanned:35` covers) | 2 records | **P1** |
| Vendor assessment | working | **partial** — checklist 979 chars unreachable | Promote to `ops_knowledge` policy | 1 record | P3 |
| Data protection engineering | expert | **partial** — PDPL prose everywhere (392 mentions) but the statute text is not in scope; wrong localisation fact filled for backend_engineer | PDPL statute (**verify** consolidated text) → `kb_chunks` `it`; quarantine the localisation fact | ~80 pages | P2 |
| Backup integrity | working | **present** in kb_chunks (NIST SP 1800-25) but as click-step chunks | Re-chunk the executive summary/architecture sections only | ~20 pages | P3 |
| Secure SDLC | expert | **partial** — "changing authority or RLS without security review" is a forbidden decision, no review checklist | Review checklist record (RLS diff, grant diff, definer routines, secrets) | 1 record | P2 |
| Marketplace fraud/abuse | working | **partial** — decision_policy keys (`fraud_score_max`, anti-circumvention in T&C) | Reference record linking the T&C rules to detection queries | 2 records | P3 |
| Off-remit pollution | — | 3 category-pack experience rows | Quarantine | — | P2 |

**Reasoning gap.** Runbooks: the IR runbook exists (unreachable). Thresholds: none for severity/breach notification. Decision tree: "is this alert a drift, a dormant function, or an intrusion?" is not written; all 30 owned incidents were resolved with one canned sentence. Worked examples: 0 security incidents of substance in LAYER 4. **P1 count: 4.**

---

## 6. `red_view_alerter` — Red-view Alerter

**What it does today.** Runs/7d: 14 ok (deterministic; `fn_exception_alerts`, `fn_emit_metric_alerts`, `fn_alert_severe`). Exam: 2/10 (20%), confidence 0.32, 8 gaps, 5 filled (3 from wrong). Retrievals: 0. Author of 100 review rows (60 approve). KPI: red-to-alert latency 26.5 min vs 60 target (met). `founder_alerts` 7 days: 120 rows — critical 2, error 13, high 44, info 10, warn 51; top events runner_silent 39, cron_silent 22; **`dedupe_key` is null on all 44 high, 2 critical and 10 info alerts** (distinct keys 0) — dedupe, one of its three owned decisions, is not applied to those levels. `employee_knowledge`: **0 rows** (layers_bound 0 of 12). Authority `execute_low`; owns raising/levelling/deduping founder alerts; forbidden: resolving the incident, changing a threshold without the platform lead, alerting on non-red views.

**Knowledge inventory.** Profession: 0 rows. Experience 5: Twilio SMS auth / WhatsApp signature (1,403), `rollback.required` lane (2,272) — relevant; `retrieval_policy.yaml`, "Knowledge acquisition… failed handoff" (179), `06_CATEGORY_REMEDIATION…` — off-remit. Reachable ops_knowledge: department pool; 9 org_task_lane playbooks (metric.alert, health.degraded, os.health_changed, kpi.missed…) are directly relevant. `skills_matrix`: no rows. Exam sources: 5 ops (lane playbooks), 3 itsec, 2 category-pack.

**Senior-staff standard — alerting/on-call engineer (a narrow, deterministic role).**

| Domain | Depth |
|---|---|
| Alert design: precision over recall, dedupe keys, levels (critical/error/high/warn/info), suppression windows, escalation path | expert |
| The monitored-view catalogue: every view/metric that can turn red, its threshold, owner, and the routine that evaluates it (`fn_emit_metric_alerts`, `fn_exception_alerts`, `fn_alert_severe`) | expert |
| Founder channel constraints: WhatsApp as the command channel, quiet hours, digest types (`alert_digest_types`), what must never be sent (secrets/PII) | expert |
| Handoff to SRE: incident creation, owner assignment, SLA (`due_at`, escalation) | expert |
| Latency measurement: red-to-alert KPI definition and its measure SQL | working |
| Distinguishing dormant-by-design silence from failure (stand-down list) | expert |
| Threshold governance: who may change a threshold (platform lead), change log | working |
| Rehearsal/probe awareness: `rehearsal_window` suppresses paging | expert |
| Alert fatigue metrics: alerts/day, ack rate, repeated events | working |
| Twilio/WhatsApp delivery failure handling for the alert itself | working |
| Basic reading of the estate health tables (LAYER 3) | working |
| PDPL: no personal data in alert bodies | aware |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Alert design & dedupe | expert | **partial** — data_intel holds "Alert design: precision over recall" (not in product_eng scope); dedupe_key null on 56/120 alerts | `ops_knowledge` product_eng policy: level definitions, dedupe-key rule per event family, suppression window; then fix the emitter | 3 records | **P1** |
| Monitored-view catalogue | expert | **missing** — no record lists the red-capable views/metrics with thresholds | Generate from `metric_definition` (14) + `company_goals` (63) + the three alert routines' bodies → 1 reference record + per-family rows | ~20 records | **P1** |
| Founder channel constraints | expert | **partial** — decision_policy `alert_digest_types`; WhatsApp channel rule in memory | Policy record (quiet hours, digest, redaction) | 1 record | P2 |
| Handoff to SRE | expert | **present** — os_incidents fields (owner, due_at, escalated_at), lane playbooks | none | — | P3 |
| Latency KPI | working | **present** — measured 26.5 min | none | — | P3 |
| Dormant-vs-failure | expert | **partial** — stand-down list not a record (see `it`) | shared with `it` | shared | **P1** |
| Threshold governance | working | **missing** | 1 policy record | 1 record | P2 |
| Rehearsal awareness | expert | **partial** — memory only ("rehearsals and probes page the founder") | 1 policy record | 1 record | P2 |
| Alert fatigue metrics | working | **missing** — 120 alerts/7d, no ack metric | 1 metric_definition + 1 record | 1 metric | P3 |
| Twilio/WhatsApp failures | working | **present** — Twilio SMS/WhatsApp signature record in LAYER 4 | none | — | P3 |
| Curriculum binding | — | `employee_knowledge` 0 rows, layers_bound 0/12 | Bind the standard curriculum (engineering/operations/quotesdone_os) so `v_employee_knowledge_compliance` is meaningful | 8 rows | P2 |
| Off-remit pollution | — | 2 category-pack rows in LAYER 4 | Quarantine | — | P2 |

**Reasoning gap.** This role is deterministic by design (three SQL routines); the reasoning it needs is a threshold/dedupe table, which does not exist as knowledge. Runbooks: none. Thresholds: only in routine bodies. Decision tree: absent. **P1 count: 3.**

---

## Department summary — product_eng

| Agent | Exam (correct/n) | Runs/7d ok/err/skip | Retrievals/30d | P1 | P2 | P3 |
|---|---|---|---|---|---|---|
| cto | 5/20 (25%) | 22/1/3 | 7 | 6 | 6 | 4 |
| it | 6/20 (30%) | 14/0/0 | 13 | 4 | 7 | 5 |
| backend_engineer | 2/26 (8%) | 15/0/0 | 0 | 5 | 4 | 7 |
| qa_manager | 8/20 (40%) | 15/0/0 | 0 | 4 | 7 | 4 |
| security | 5/20 (25%) | 168/0/0 | 5 | 4 | 6 | 5 |
| red_view_alerter | 2/10 (20%) | 14/0/0 | 0 | 3 | 5 | 4 |
| **Total** | 28/116 (24%) | | | **26** | **35** | **29** |

**Top 5 ingest items (after the mechanism fixes in §0, which are prerequisites, not ingest):**

1. **Fix delivery before content**: make LAYER 2 admit profession rows (the 8,200 guard vs a 12–13k head), seed `dept_library` for `product_eng`, emit `field_corpus` (LAYER 2e) or scope `kb_search` by `fn_dept_scope`, and stop the exam from filling `wrong` verdicts / off-remit sources. Until then every item below is written to tables the prompt does not carry except via the 8-record cosine match.
2. **Estate self-knowledge pack** (P1 for cto, backend_engineer, it): curated graphify god-nodes/communities, MANIFEST rules, CI gate semantics, kernel write path (`fn_kernel_*`), 24 active crons, 205 functions — ~80 `ops_knowledge` product_eng records, embedded.
3. **The ~200 session lessons in MEMORY topic files** as `ops_knowledge` failure_mode/remediation records (Postgres/plpgsql traps, checks doctrine, harness limits) — the only worked-example corpus a 20-year veteran of this estate would carry; ~200 × 800 chars.
4. **Alert-family runbooks + monitored-view catalogue** (it, red_view_alerter, security): 8 `os_runbooks` with detection SQL, the stand-down/dormant list, the security-drift playbook, dedupe-key rules — ~30 records.
5. **Promote the unreachable profession rows** (it 23, security 10) to reviewed `ops_knowledge` policy/remediation records with citations — IR runbook, PDPL breach duties, secrets lifecycle, adopted SLOs, FinOps — and quarantine the 9 off-remit category-pack experience rows sitting in these six agents' LAYER 4.

External-standard ingests (ASVS, OWASP LLM Top 10, PDPL statute, UAE IA Regulation, Supabase/Vercel/Next.js docs, SRE Book, ISTQB) are P2 and should go to `kb_chunks` categories inside `fn_dept_scope('product_eng')` (`it`, `engineering`, `qa`, `ai_dept`) with real citations — after the scoped retrieval path is emitting.
