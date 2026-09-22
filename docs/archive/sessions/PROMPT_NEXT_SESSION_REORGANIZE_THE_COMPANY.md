Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Don't report the
OpenRouter balance, but DO tell me if it's refusing calls.

## HOW THIS SESSION RUNS

Do not stop. Do not ask me a technical question. Do not report progress mid-session. I am
watching the context and will tell you when it is nearly full — until then, take the next item.
The rule is in `.claude/skills/quotesdone-session/SKILL.md` §3. Load that skill first.

Escalate only: Stripe refunds, spending money, the three go-live switches, and facts only I hold.

End with one line — `all verified and fixed and merged and deployed 100%` — or an honest
hand-over naming exactly what is unfinished and why.

## THE JOB: REORGANIZE THE AGENT COMPANY

Reorganize QuotesDone's agent company into a clear, efficient, accountable organizational and
runtime structure. **This is an implementation task, not a planning-only exercise.**

Do not discard existing role knowledge or working runtime components unnecessarily. Preserve
professional capabilities; correct duplicate roles, ambiguous ownership, overlapping
departments, broken reporting lines and inefficient runtime behaviour.

### Why

**Too many overlapping departments.** These groups do closely connected work and the split
produces unclear ownership, excessive handoffs, duplicate KPIs, and management receiving
several conflicting readings of the same problem:

| Current departments | Problem |
|---|---|
| Marketing, Sales & CRM, Business Development, Notification & Communication | four departments share one customer-acquisition and revenue funnel |
| Marketplace, RFQ Intelligence, Supplier Knowledge, Supplier Success, Document Intelligence | five departments jointly own one inquiry-to-quotation workflow |
| AI, Engineering, IT, QA, Evolution | overlap around product, technology, optimisation and release quality |
| Intelligence, Data & Analytics, Knowledge Engineering | all three turn information into decisions and organisational knowledge |
| Finance and Payment | payment is an operating function of finance |
| Legal & Compliance and Trust & Safety | shared responsibility for risk, fraud, policy, disputes, enforcement |
| Administration & Operations and HR | both support internal company operations |

**Department membership and committee membership are mixed together.** A department head who
attends the executive committee should not exist twice. One record, one primary department, a
committee membership field.

**Several agent IDs are too vague** — `brief`, `followup`, `docs`, `it`, `legal`, `analytics`,
`procurement`, `onboarding`, `marketing`, `security`. An autonomous system needs unambiguous
names because agent selection, handoffs, logs, KPIs, permissions and knowledge retrieval all
key on role identity.

**Some ownership roles are missing or unclear** — Chief Revenue Officer, Product Manager, Data
Engineer, Financial Controller, Site Reliability Engineer, Chief of Staff, privacy / data
protection ownership, one accountable Marketplace Director. This does not have to raise the
headcount: merge or repurpose.

**Role, agent and knowledge overlay are being treated as one thing.** They are five things:

| Object | Meaning |
|---|---|
| Department | organisational owner of an outcome |
| Role | responsibilities, authority, KPIs, knowledge |
| Runtime agent | model-backed executor that performs tasks |
| Overlay | specialist knowledge loaded only when relevant |
| Committee membership | cross-functional participation without duplicating the role |

A role does not always need its own continuously running model instance. A manager can own the
final output and invoke bounded specialist agents as tools; a handoff is better when a
specialist genuinely needs to take over the conversation.

### Governing principle

QuotesDone should operate as an autonomous company whose agents behave like accountable
employees. Every role must belong to one primary department; report to one primary manager; own
defined responsibilities; have measurable KPIs; have explicit decision authority; use relevant
knowledge and tools; record evidence and decision traces; learn from validated outcomes; and
contribute to the AED 1,000,000 revenue objective by 31 August 2027.

Department heads own department outcomes, resource allocation, task assignment, KPI diagnosis,
corrective action and reporting to executive management. Specialists own professional execution
within their role. Independent reviewers may block unsafe work but must not approve their own
output.

### Target: 10 primary departments

**1. Executive & Strategy** — from Executive Office plus the strategic roles in Evolution.
CEO · Chief of Staff · Strategy Director · Innovation/Product Strategy where appropriate ·
Organization Design · Corporate Performance.
*Do not duplicate CPO, CFO, CTO, COO or other department heads here merely because they attend
executive meetings.*

**2. Growth & Revenue** — merge Marketing, Sales & CRM, Business Development, growth-oriented
communications. Chief Revenue Officer · Marketing Director · Brand & Creative · Content Strategy
and Copy · Visual Design · Social Media and Community · Marketing Performance · Sales Director ·
Account Management · CRM and Revenue Operations · Business Development · Partnerships and
Government Relations.
*Merge the inactive `marketing_copy` into `marketing_content` unless source tracing proves two
genuinely independent roles.*

**3. Customer Experience & Communications** — merge Customer Success, customer lifecycle
communication, notification/channel operations. Customer Success Director · Onboarding · Support ·
Retention · RFQ Success · Communications · Lifecycle Channel Operations.
*Consider merging `channel_specialist` and `notification_ops`.*

**4. Marketplace & Supplier Network** — merge Marketplace & Procurement, RFQ & Inquiry
Intelligence, Supplier Success, Supplier Knowledge, Document Intelligence. Marketplace Director ·
Marketplace Operations · RFQ Qualification · Inquiry Routing · Inquiry Quality/Scoring · Quote
Evaluation · Supplier Verification · Supplier Onboarding · Supplier Coverage and Liquidity ·
Supplier Retention · Supplier Taxonomy · Supplier Intelligence · Document Intelligence · BOQ
Analysis · Drawing Analysis.
*Convert `spec_commercial`, `spec_construction`, `spec_fitout`, `spec_industrial`, `spec_mep`
into on-demand functional specialist overlays unless runtime evidence proves they need
independent standing-agent state.*

**5. Product, Engineering & AI** — merge Engineering, AI Department, product and technical
Evolution roles. CPO · Product Manager · CTO · Engineering Manager · Solution Architect · Backend ·
Frontend · AI Director · AI Architect · Agent/Prompt Engineer · Model Evaluator · Product
Optimization.
*`innovation_mgr` could become Product Manager if its actual responsibilities already match
product discovery, prioritisation and experimentation.*

**6. Data, Intelligence & Knowledge** — merge Intelligence, Data & Analytics, Knowledge
Engineering, shared supplier/category intelligence. Data and Intelligence Director · Data
Engineer · Business Intelligence · Forecasting · Market Intelligence · Supplier Intelligence ·
Knowledge Director · Knowledge Engineer · Knowledge Validator · Taxonomy/Category Curation.
*Evaluate: `intel_director` + `analytics_director`; `supplier_analyst` + `supplier_intel_analyst`.
Merge only where responsibilities AND callers genuinely overlap. Keep `taxonomy_manager` and
`category_curator` separate only if one owns taxonomy governance and the other ongoing curation.*

**7. Finance & Payments** — merge Finance and Payment. CFO · Financial Controller · Accounting ·
Accounts Payable · FP&A · Collections and Revenue Assurance · Payments and Billing.
*Replace the vague `bookkeeper` identity with an accountable accounting/control role. Bookkeeping
alone is not enough for a department responsible for revenue recognition, reconciliation,
controls, runway, forecasts and investor reporting.*

**8. Legal, Compliance, Risk & Trust** — merge Legal & Compliance and Trust & Safety. General
Counsel · Compliance and Privacy · Contract Management · Risk and Governance · Trust and Safety ·
Fraud · Moderation.
*Assign explicit data-protection ownership.*

**9. People & Company Operations** — merge Administration & Operations and HR. COO · Operations
Management · Document Operations · Process Improvement · Project Coordination/PMO · HR ·
Recruitment · Learning and Development · Culture and Performance.
*Decide whether `ops_director` should become COO based on its existing authority.*

**10. Independent Assurance, Security & Reliability** — merge the control-oriented functions of
QA & Testing, IT & Cybersecurity, AI quality, production reliability. QA and Release Management ·
Test Automation · AI Quality Assurance · IT Operations · Site Reliability · Cybersecurity.
*Independent stop authority over critical security failures, privacy violations, failed release
gates, unsafe model regressions, corrupt migrations and unreconciled financial integrity defects.
It must not be measured only by release speed.*

### Renaming

Review and normally replace: `brief`→`chief_of_staff` · `followup`→`customer_success_director` ·
`procurement`→`marketplace_director` · `marketing`→`marketing_director` · `legal`→`general_counsel` ·
`analytics`→`business_intelligence_analyst` · `it`→`it_operations_engineer` ·
`security`→`cybersecurity_engineer` · `onboarding`→`supplier_onboarding_specialist` ·
`docs`→`document_operations_specialist`.

**Do not rename blindly.** First find every caller, foreign key, task assignment, log, policy,
knowledge mapping, KPI and tool permission using the old ID. Create backward-compatible aliases
during migration. Leave no orphaned historical records.

### Category specialists

Keep all 86 as on-demand knowledge overlays. They are not departments and do not report to the
CEO individually.

Operational chain: Marketplace Director → RFQ Qualification Manager → Inquiry Router → the
relevant Category Specialist overlay.
Knowledge governance: Knowledge Director / Taxonomy Manager → category source quality, freshness,
aliases, rules, evaluations.

Each overlay owns route and subcategory knowledge, minimum sufficient questions, mandatory and
optional fields, never-infer rules, pricing drivers, required documents, technical comparison
fields, regulatory triggers, quote-readiness criteria and escalation rules.

No overlay may independently dispatch, approve a supplier, expose customer identity, make
unsupported legal conclusions, or override privacy/authority/regulatory gates.

The inquiry-facing manager should normally keep control of the customer conversation and invoke
the specialist internally — the customer should not visibly bounce between agents.

### Runtime modes

Assign every role exactly one of: `persistent_manager` · `scheduled_manager` ·
`event_driven_operator` · `on_demand_specialist` · `knowledge_overlay` · `independent_reviewer`.

Target — a target, not a forced count; derive the finals from actual responsibilities and cost:
~10–12 management agents · ~30–40 event-driven core operators · the rest on demand · 86 overlays.

Runtime context carries only the smallest relevant combination of company, department, role,
task, category and live data — never the whole employee knowledge library.

### Canonical role schema

`role_id` · `display_name` · `primary_department_id` · `manager_role_id` ·
`committee_memberships` · `runtime_mode` · `responsibilities` · `owned_decisions` ·
`forbidden_decisions` · `activation_conditions` · `required_inputs` · `output_contracts` ·
`tools` · `knowledge_scopes` · `kpis` · `authority_level` · `budget_limit` · `handoff_targets` ·
`escalation_targets` · `model_policy` · `evaluation_suite` · `status`.

Enforce: unique role IDs · exactly one primary department · exactly one primary manager (except
the CEO/founder boundary) · no reporting cycles · no duplicated role for committee membership ·
no active role without a runtime caller · without KPIs · without knowledge · without authority ·
without evaluations · and no role approving its own consequential work · no department reporting
success only from activity metrics.

Evaluation must inspect actual traces, tool calls, state changes and outcomes — not whether the
agent produced plausible text. Cover both when a behaviour SHOULD occur and when it should NOT,
and use multiple trials, because agent behaviour varies across runs.

### Stages

1. **Crosswalk.** `docs/agents/CURRENT_TO_TARGET_AGENT_CROSSWALK.csv` — per current role: current
   ID, current department, runtime callers, tasks, tools, knowledge mappings, KPIs, manager,
   target role ID, target department, target manager, runtime mode, action
   (keep/rename/merge/split/convert_to_overlay/deactivate/create), compatibility strategy,
   rationale. **Do not stop after the crosswalk.**
2. **Canonical organisation.** Department, role, reporting, committee and runtime-mode records,
   with constraints for unique canonical role, one primary department, valid manager, no
   self-management, no duplicate active alias, no broken role mapping.
3. **Compatibility migration.** Agent records, task assignments, workflow ownership, KPI
   ownership, knowledge mappings, tool permissions, authority rules, decision traces, historical
   logs, manager relationships. Old IDs keep working through aliases or a compatibility resolver
   until every caller uses canonical IDs.
4. **Runtime orchestration.** Management assignment, event-driven operators, on-demand
   specialists, category overlays, specialist-as-tool invocation, structured handoff metadata,
   manager accountability, cross-department workflows, independent review gates. No task
   broadcast to many agents without one accountable owner.
5. **KPI and management hierarchy.** AED 1,000,000 → company objectives → department objectives →
   role KPIs → assigned work → execution → outcomes → management review → corrective action.
   Category-specialist performance must aggregate into routing accuracy, mandatory-field
   completeness, duplicate-question rate, supplier quoteability, supplier response rate, valid
   quotations, customer conversion, revenue contribution and escalation accuracy.
6. **Behavioural testing** through the actual runtime: unique role resolution · manager chains ·
   no cycles · correct department ownership · correct agent selection · specialist invocation ·
   overlay invocation · cross-department handoff · manager review · KPI reporting · authority
   refusal · independent QA rejection · knowledge retrieval · cost/model routing · no orphaned
   tasks · no broken old role IDs · no unowned role · no active dead-code agent.
   Realistic workflows: customer inquiry → supplier-ready brief; supplier acquisition and
   verification; social campaign creation → visual review → publishing → performance learning;
   revenue underperformance diagnosis; refund or financial exception; legal/compliance
   escalation; production incident; knowledge-gap discovery and remediation.

### Required outputs

`docs/agents/TARGET_AGENT_ORGANIZATION.md` · `CURRENT_TO_TARGET_AGENT_CROSSWALK.csv` ·
`CANONICAL_ROLE_REGISTRY.csv` · `REPORTING_AND_COMMITTEE_GRAPH.md` ·
`RUNTIME_MODE_ASSIGNMENTS.csv` · `AGENT_REORGANIZATION_MIGRATION_REPORT.md` ·
`AGENT_ORCHESTRATION_TEST_EVIDENCE.md`.

### Completion standard

Every current role resolved · every target role implemented or deliberately deferred · every
active role has a caller, a manager, tools, knowledge, KPIs, authority and evaluations ·
category specialists on demand · duplicate identities removed · old IDs compatible during
migration · management can assign and monitor work · department outcomes trace to the revenue
objective · realistic runtime tests pass · no production data or history silently lost.

**Do not report success merely because new tables or role rows exist. Implement, migrate, test
and commit the working organization.**

## CORRECTIONS TO THE BRIEF — MEASURED 14 AUG 2026, TRUST THESE OVER THE TEXT ABOVE

The brief's *counts* are right. Two of its *diagnoses* are not — verify before building the fix
either one implies.

1. **`cpo` is NOT duplicated.** It has exactly one `org_agents` row, department `exec`. Zero
   agents anywhere have two department rows. What exists is `org_departments.evolution.lead_agent
   = 'cpo'` — cpo is the named LEAD of Evolution while being a MEMBER of Executive Office. That
   is the committee/leadership pattern the brief asks for, already present, not a duplicate.
   Evolution's three members are `innovation_mgr`, `optimisation_eng`, `org_designer`.
   **Do not "de-duplicate" cpo. Model cross-department leadership explicitly instead.**
2. **93 active agents, not 93 unique standing roles.** 130 `org_role_identity` rows map 93 agents
   onto 96 packaged roles: where a department has no separate analyst or reviewer, its director
   carries that archetype as a second identity. Read `org_role_identity` before concluding a role
   is missing — it may already be held as a second hat.

## PENDING FROM THE V3 SESSION (14 Aug 2026)

**Mine, not yours to answer:**

- **The training loop has been run but never completed a cycle.** `agent_train` works on both
  projects (cfo 0.875, quote_evaluation 0.85–0.95, spec_fitout 0.525, spec_mep 0.625 against
  their own cases' required moves). No role reached `training_passed`, because that rung needs a
  remediation opened on a failure and closed on a passing retest. Open one for `spec_fitout` and
  `spec_mep` — the two lowest, and the two that qualify the fit-out and MEP inquiries that are
  the core product — and drive it to `passed`. 25.6% of the corpus (4,574 of 17,890 cases) states
  no requirement the grader can read and is recorded `case_states_no_requirements`, not scored 0.
- **Row #3 is 135/152.** It read 136/152 on the morning of 14 Aug and the check that moved was
  unrecoverable, because the scorer kept no history. It does now: every run writes one row per
  check to `os_blueprint_result`, and `fn_blueprint_regressions('row3_executive_ui', ref)` diffs
  the last two runs. **Run the scorer early, and the diff will name what moved.**
- **Nothing produces video frames.** `artifact_review` reviews frames in playback order and
  blocks any video with none. `video_produce` generates, reviews and rewrites its own prompt from
  the named failures. The producing pipeline must send `frames: [url, ...]` — poster plus 3–8
  stills. Until it does, every video is blocked, which is correct.

**Yours — I cannot do these:**

- **`app_secrets.openart_api_key`.** Video generation is built and returns a 503 naming this key,
  the model (`grok-imagine-1-5`) and the mode (`text2video`). Add the key and the produce →
  review → adjust loop runs end to end.
- **The tier decision.** `model_policy.routine_employee_reasoning` exists at medium tier and
  nothing points at it. ~AED 80–120/month against a ~660/month run rate. Costed and staged in
  `docs/audits/AI_SPEND_2026_08_14.md` §7.
- **71 duplicate + 244 six-August `org_tasks`** proposed for deletion, not deleted. Mass-closing
  work rows is your call.
- **1-hour prompt-cache TTL.** 72.7% callback vs 52.6% break-even, ~AED 6/month more. Left a week
  to accumulate real hit-rate data first — that week is up on 21 Aug.

**Also open:**

- **199 pending `agent_actions` vs `org_tasks`** — two queues, two vocabularies, no bridge.
- **`kb_embed` reports "done" while unembedded chunks remain** — it could not read its target
  table (agent_runs error, 13–14 Aug). Embedding coverage is 77.8% production / 63.5% staging.
- **Row #3's remaining NOT MET:** several are held open by pre-fix rows inside a rolling window
  (check the date, build nothing), four are blocked on `max_open_tasks`, the rest need real trade,
  are unmeasurable, or are the Apify pause.

## STANDING DECISIONS — DO NOT RE-ASK

- GO-LIVE SWITCHES: not until you are 100% sure the code and the upgrades are done.
- HEALTH JOBS BELONG IN CODE and the system should be healthy essentially all the time. Not green
  is the job, not a question.
- PHONE VERIFICATION WORKS. djzaino@outlook.com, +971509319355, `phone_verified = true`, 13 Aug.
- `max_open_tasks`: still mine.
- Apify stays paused until ~Feb 2027. `s26-discover-suppliers` must NOT be "fixed".
- **Both Supabase projects are mine.** `pglpqrhvozwepymcuunn` is a Supabase BRANCH of
  `htdblwldjkcgjvmqkbeh`, which is why it 404s on `/v1/projects/{ref}` while its database endpoint
  answers. Deploy to both; this is settled, do not re-raise it.
- Do not ask me technical questions. If answering needs codebase knowledge, decide it yourself.

## STATE (14 Aug 2026, after PRs #376–#379, all merged, both projects verified)

**V3 knowledge runtime is live on both projects.** 7,825 knowledge records in `ops_knowledge`
(extended in place, no second corpus) · 17,890 training cases in `agent_training_case` · 130
`org_role_identity` rows covering 93 active agents and all 96 packaged roles · 25
`org_department_alias` rows · 86 `org_category_identity` rows · 16 `category_route_map` rows ·
`cert` schema empty with RLS on and zero policies, unreachable by `anon`, `authenticated` AND
`service_role`.

Importer re-run on each project: **0 inserted, 0 updated, 25,715 unchanged, 0 errors.** Rollback
by ingestion run exists (`fn_knowledge_rollback`) and was rehearsed in an aborted transaction.

**Key routines:** `fn_agent_context_v3` (identity, deterministic rules, department, role,
category, validated experience, live-data bindings, tools, company objective) reached through
`fn_agent_context_capped`, which `agent_brain`, `action_worker`, `dept_plan`, `agent_act`,
`exec_agents` and six others already call · `fn_record_context_retrieval` (writes
`agent_context_retrieval` AND `kb_usage_log`) · `z90_agent_action_decision_trace` (every decided
action leaves a trace naming the knowledge ids) · `fn_category_checklist` /
`fn_category_quote_ready` · `fn_propose_lesson` / `fn_validate_lesson` · `fn_assign_training` /
`fn_remediation_step` / `fn_agent_autonomy_blocked` · `fn_role_readiness_recompute` ·
`fn_knowledge_freshness_sweep` · `fn_blueprint_regressions`.

**Edge functions added/changed:** `artifact_review` (images and video, deterministic + vision) ·
`agent_train` · `video_produce` · `inquiry_ai` (packaged question bank) · `postiz_publish`
(publish gate on the artifact digest) · `exec_agents` (officers assemble their own context).

**Readiness:** 47 `restricted_to_advisory` · 36 `runtime_mapped` · 34 `knowledge_imported` ·
7 `live_data_connected` · 5 `decision_trace_connected` · 1 `blocked` · **0 certified.**

**Green:** 234 tests 0 failures · `BOTH PROJECTS IN SYNC` · route tests 344/344 both · portal
gates 23/23 both · Row #4 146/147 (only red is the founder-approved docked assistant `<aside>` —
do not touch) · pack scorecard INGESTED 100% of 27 scorable, IN USE 37/37 both · 0 cron
failures/24h both · Vercel 0 runtime errors · main CI green.

**AI spend:** plot the DAILY series, never a window total. Was ~AED 29.7/day before 14 Aug,
~22/day after.

## TRAPS

`apply_sql --promote` carries the DEFINITION not the GRANTS — use `--promote --ddl` for anything
that is not a routine body, and run `project_parity` immediately after every deploy · **two files
must never define the same routine**: `sql_files_match_live` picks the newest by commit order and
a squash merge leaves two same-commit files unordered · `project_parity` is a SHAPE check — hash
`pg_get_functiondef` and the deployed edge bundles when parity actually matters · **the ai_gateway
returns ~900 output tokens whatever `max` asks for**, and names its fields `prompt_tokens` /
`output_tokens` / `cost_usd`, not `input_tokens` / `cost_aed` · **a checksum over a source file
cannot deliver a parser fix** — mix the parser version in · CREATE OR REPLACE preserves the ACL ·
a new table gets RLS on production by event trigger and NOT on staging — enable it explicitly ·
READ THE DATES before calling anything a live failure · split any red per-row universal by its
deploy timestamp BEFORE building · a mass of "on production" test failures with staging passing is
a 429 throttle · group per class, never in aggregate · does every KIND have a runner · ask whether
a condition can ever NOT fire, and whether it can ever fire at all · **a new guard returning 0
proves nothing — construct the input that MUST take the branch and assert it did** · a scorer
whose input vanished reports perfection · **an extractor that knows eight key names in a corpus
that uses twenty reports 44% of it as empty** · do not reconstruct a large routine from memory,
dump it with `pg_get_functiondef` and patch tokens · `pg_get_functiondef` omits the trailing
semicolon · `least()`/`greatest()` ignore NULLs · `_` is a word character in Postgres regex ·
BEFORE triggers fire in NAME order · a cron reporting succeeded for `net.http_post` only means
QUEUED · os_api classifies actions in TWO places · `qd_guard` refuses any file containing the
production ref literal, and refuses ALL production writes — `mgmtWriteData` is INSERT-only ·
Arabic `alias_norm` strips hamza and folds ta-marbuta — match the raw `alias` column · kb_embed
returns HTTP 546 above a batch of 5 · a CI failure reading "rate limit exceeded" or "Failed
caching npm package" is infrastructure, re-run it · **CI runs `npm test` with no
SUPABASE_ACCESS_TOKEN — a DB-touching check must `t.skip` when the token is absent, or it fails
with a 401 that looks like a data failure** · **stage explicit paths, never `git add -A`: this
working tree permanently carries session debris** · **NEVER push to main.**

## THE BAR

Deploy to BOTH Supabase projects (`htdblwldjkcgjvmqkbeh` production, `pglpqrhvozwepymcuunn`
staging), merge via PR, verify by execution in the same turn, aborted-transaction probes for
writes, never fabricate or back-date data to turn a gate green, never weaken a check.

End-of-session sweep: GitHub Actions · Vercel · both Supabase · Row #3
(`verify_os2_blueprint.mjs`) · Row #4 (`verify_portal_blueprint.mjs`) · pack scorecard both
(`--packs=knowledge-import/all86_full`) · `fn_os_portals_gates()` both · `fn_kb_route_test_run(400)`
both · `node scripts/checks/project_parity.mjs` → BOTH PROJECTS IN SYNC. Then the one line.
