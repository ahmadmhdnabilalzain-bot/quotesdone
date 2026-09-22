# ROW #8 — OPENROUTER COST OPTIMIZATION: THE ENUMERATION

Source: `docs/specs_row8_openrouter_cost_optimization.txt`, 2,347 lines, three documents in one file:
the OS Cost Optimization Master Plan (45 numbered items), the WhatsApp Agent architecture (19), and
the Email / Website Chat addendum. Enumerated 2026-08-09. **226 requirements.** This number is
asserted as `TOTAL` in `scripts/staging/verify_ai_router.mjs`; a run that registers a different
count prints `!! N checks ran, the spec has 226` and the percentage is not trustworthy.

Grain rule, identical to rows #4, #5 and #6: **one enumerated line of the spec = one requirement.**
Where the spec names a list (five AI levels, four OpenRouter settings to enable, six benchmark
categories, seven website knowledge types, eight WhatsApp brain modules), every member is a
requirement. Where the spec draws a pipeline, every stage is a requirement.

---

## WHAT IS DIFFERENT ABOUT THIS ROW, AND IT MATTERS BEFORE THE FIRST CHECK

Rows #5 and #6 scored a screen and a corpus. **Row #8 scores a control system**, and a control
system can be present, correct and *never exercised*. Both facts have to be checked separately or
the score is a lie in one of two directions:

- **MECHANISM** — the routine, table or policy exists and returns the right shape.
- **EXERCISE** — production traffic actually went through it.

`llm_cache` is the case that forces the distinction. Four routines exist to read and write it
(`fn_llm_cache_get`, `fn_llm_cache_lookup`, `fn_llm_cache_put`, `fn_llm_cache_store`), the table
carries a semantic `embedding_gte` column, and it holds **0 rows** against 1,021 logged AI calls of
which **2** were served from cache. A scorer that asked only "does a cache exist" would report the
spec's §7 and §32 as MET and hide the single largest unrealised saving in the estate.

So every section below that describes a *behaviour* carries both, and the ids are suffixed
`-exists` and `-used` where the spec's claim is about something happening rather than something
being available. **An `-exists` MET beside a `-used` MISSING is the most informative pair this
scorer can produce**, and it is deliberately not averaged away.

## THE BAR

**A `-used` check needs production evidence, not a capability.** `ai_cost_log` holds 1,021 rows and
is the evidence table. Where the spec gives a target distribution (§2's 20/55/20/5, the WhatsApp
70/20/8/2 ladder), the target is the bar and the measured share prints beside the verdict.

Where the spec gives no number, a `-used` check is MET when the mechanism appears in production
traffic **at all** — one real row, not one test row. Zero is the failing case, and zero is what
several of these will report.

---

## PART A — THE OS COST OPTIMIZATION MASTER PLAN (133)

### §1 The Router Layer — 9
`route-layer-exists`, `route-intent-detection`, `route-task-classification`, `route-model-selection`,
`route-reaches-openrouter`, `route-branch-simple-cheap`, `route-branch-reasoning-premium`,
`route-branch-long-context`, `route-branch-emergency-fallback`

### §2 The Five AI Levels + Expected Distribution — 9
`level-0-no-ai`, `level-1-cheap`, `level-2-medium`, `level-3-premium`, `level-4-human-tasks`
`dist-no-ai-20pct`, `dist-cheap-55pct`, `dist-medium-20pct`, `dist-premium-5pct`

The four `dist-*` are **`-used` checks measured over `ai_cost_log`**. The spec's own table is the
bar. This is the single most honest measurement in the row: it is the difference between owning a
router and using one.

### §3 The AI Decision Engine — 4
`engine-classifier`, `engine-model-selector`, `engine-cost-manager`, `engine-memory-manager`

### §4 Model Cascading — 4
`cascade-starts-cheap`, `cascade-confidence-score`, `cascade-escalates-on-low-confidence`,
`cascade-evaluator`

### §5 Token Management — 2
`token-conversation-compression`, `token-context-cleaning`

### §6 Local Embeddings — 2
`embed-vector-store`, `embed-sends-only-relevant`

### §7 Cache Everything — 2
`cache-store-exists`, `cache-actually-hit` *(the pair described above)*

### §8 Streaming — 2
`stream-enabled`, `stream-cancellation-stops-generation`

### §9 Token Budgets — 2
`budget-per-request-max-tokens`, `budget-no-unlimited-generation`

### §10 Smart File Processing — 4
`file-parser`, `file-chunking`, `file-vector-search`, `file-sends-only-relevant-sections`

### §11 Multiple Providers — 3
`prov-openrouter`, `prov-direct-or-local`, `prov-fallback-chain`

### §12 Self-hosted Small Models — 1
`local-small-model`

### §13 AI Profiles — 3
`profile-economy`, `profile-balanced`, `profile-professional`

### §14 Monitoring Dashboard — 6
`dash-request-count`, `dash-tokens`, `dash-model-used`, `dash-cost`, `dash-failures`,
`dash-avg-quality`

### §15 OpenRouter Settings — 7
Enable: `set-model-fallback`, `set-streaming`, `set-provider-routing`, `set-usage-tracking`
Disable: `set-no-auto-premium`, `set-no-unnecessary-long-context`, `set-no-full-history`

### §17 Separate Thinking From Answering — 3
`split-intent-engine-cheap`, `split-task-planner-cheap`, `split-final-response-stronger-only-if-needed`

### §18 Agent Sleep Mode — 2
`sleep-event-wakes-agent`, `sleep-agent-sleeps-after`

### §19 Deterministic Tools Before AI — 6
`det-dates`, `det-calendars`, `det-file-operations`, `det-searches`, `det-database-queries`,
`det-calculations`

### §20 Prompt Compression — 2
`prompt-profile-stored-not-resent`, `prompt-only-necessary-instructions`

### §21 Dynamic Context Window — 1
`ctx-dynamic-window`

### §22 Response Length Controller — 4
`len-quick`, `len-normal`, `len-detailed`, `len-expert`

### §23 User Behavior Learning — 1
`learn-user-preference`

### §24 AI Quality Scoring — 3
`qual-score-recorded`, `qual-score-per-model`, `qual-score-per-task`

### §25 Automatic Model Benchmarking — 6
`bench-coding`, `bench-reasoning`, `bench-writing`, `bench-vision`, `bench-documents`, `bench-math`

### §26 Batch Processing — 1
`batch-processing`

### §27 Queue System — 3
`queue-urgent`, `queue-normal`, `queue-background`

### §28 AI Spending Limits — 3
`spend-limit-free`, `spend-limit-premium`, `spend-limit-enterprise`

### §29 Smart Image AI Routing — 2
`img-cv-filter`, `img-escalates-only-when-needed`

### §30 Retrieval Instead of Generation — 1
`retrieval-over-generation`

### §31 Own Knowledge Layer — 5
`kb-user-preferences`, `kb-previous-solutions`, `kb-app-documentation`, `kb-commands`, `kb-workflows`

### §32 Semantic Cache — 1
`cache-semantic`

### §33 Early Exit System — 1
`early-exit`

### §34 Developer Mode / Code Index — 2
`code-index-exists`, `code-index-sends-relevant-files-only`

### §35 Fine-Tuning / Distillation — 1
`distill-from-successful-responses`

### §36 Multi-Agent Cost Control — 2
`multi-agent-manager`, `multi-agent-only-needed-activated`

### §37 Internal AI Credits — 4
`credit-0-simple`, `credit-1-small`, `credit-5-medium`, `credit-20-premium`

### §38 Predict User Intent — 1
`predict-intent`

### §39 Fail Gracefully — 2
`fail-primary-then-fallback`, `fail-stops-no-endless-retry`

### §40 Regional Optimization — 1
`region-lowest-cost-provider`

### §41 The AI Accountant — 5
`acct-spending`, `acct-token-waste`, `acct-expensive-users`, `acct-expensive-tasks`,
`acct-optimization-alerts`

### §42 Human Feedback Loop — 3
`feedback-thumbs`, `feedback-edits`, `feedback-improves-routing`

### §43 Offline Mode — 5
`offline-file-search`, `offline-commands`, `offline-notes`, `offline-calculations`,
`offline-reminders`

### §44 Background Model Switching — 2
`switch-registry-tracks-price-quality`, `switch-automatic`

**§16 and §45 are architecture restatements of §1 and are NOT counted again.** The spec draws the
same diagram three times; counting it three times would inflate the denominator by twelve on one
implementation, which is row #4's defect class #3 exactly.

---

## PART B — THE WHATSAPP AGENT (43)

### §B1 Control Layer Before AI — 1
`wa-control-layer`

### §B2 Message Classification — 3
`wa-type-a-fixed-no-ai`, `wa-type-b-simple-cheap`, `wa-type-c-complex-premium`

### §B3 Personality Layers — 3
`wa-layer-base-personality`, `wa-layer-business-rules`, `wa-layer-current-situation`

### §B4 Conversation Memory — 1
`wa-memory-not-full-history`

### §B5 Customer Memory DB — 7
`wa-mem-customer-id`, `wa-mem-preferences`, `wa-mem-previous-purchases`, `wa-mem-complaints`,
`wa-mem-important-dates`, `wa-mem-communication-style`, `wa-mem-last-summary`

### §B6 AI Only When Needed — 1
`wa-ai-only-when-needed`

### §B7 Human Handoff — 2
`wa-confidence-score`, `wa-transfer-to-human`

### §B8 Message Batching — 1
`wa-message-batching`

### §B9 Intent Prediction — 1
`wa-intent-prediction`

### §B10 The Agent Brain — 8
`wa-brain-customer-understanding`, `wa-brain-product-knowledge`, `wa-brain-sales-logic`,
`wa-brain-complaint-handling`, `wa-brain-order-system`, `wa-brain-crm-memory`,
`wa-brain-ai-router`, `wa-brain-analytics`

### §B11 Product Knowledge Not AI Generated — 1
`wa-products-from-database`

### §B12 Image Handling — 1
`wa-image-classifier-first`

### §B13 Automated Sales Flow — 1
`wa-automated-sales-flow`

### §B14 Cost Control Per Customer — 1
`wa-cost-limit-per-customer`

### §B15 The Model Ladder — 4
`wa-ladder-70pct-no-ai`, `wa-ladder-20pct-cheap`, `wa-ladder-8pct-medium`, `wa-ladder-2pct-premium`

### §B16 Response Templates — 5
`wa-tpl-greetings`, `wa-tpl-delivery`, `wa-tpl-payment`, `wa-tpl-appointment`, `wa-tpl-store-info`

### §B17 Per-Customer Cost Dashboard — 1
`wa-cost-dashboard`

### §B18 Background AI Jobs — 1
`wa-background-summary-job`

---

## PART C — EMAIL AGENT (22)

### §C1 Processing Pipeline — 5
`em-classifier`, `em-intent-detection`, `em-priority-detection`, `em-action-decision`, `em-ai-router`

### §C2 Classification Before AI — 3
`em-cat-a-automatic`, `em-cat-b-cheap`, `em-cat-c-advanced`

### §C3 Attachment Efficiency — 4
`em-attach-parser`, `em-attach-text-extraction`, `em-attach-vector-search`,
`em-attach-relevant-sections-only`

### §C4 Email Memory — 1
`em-customer-profile-not-history`

### §C5 Response Library — 6
`em-tpl-apology`, `em-tpl-quotation`, `em-tpl-shipping`, `em-tpl-follow-up`, `em-tpl-thank-you`,
`em-tpl-complaint-resolution`

### §C6 Priority Intelligence — 3
`em-priority-0-30-automated`, `em-priority-30-70-ai`, `em-priority-70-100-human`

---

## PART D — WEBSITE CHAT WIDGET (23)

### §D1 Architecture — 1
`web-intent-detector`

### §D2 First Message Without AI — 1
`web-first-message-no-ai`

### §D3 Website Knowledge Layer — 7
`web-kb-products`, `web-kb-prices`, `web-kb-policies`, `web-kb-faq`, `web-kb-shipping`,
`web-kb-returns`, `web-kb-reviews`

### §D4 Visitor Intent Detection — 5
`web-intent-buying`, `web-intent-researching`, `web-intent-existing-customer`,
`web-intent-complaint`, `web-intent-spam`

### §D5 Sales Agent — 4
`web-sales-asks-questions`, `web-sales-recommends`, `web-sales-collects-info`,
`web-sales-creates-lead`

### §D6 Visitor Memory — 2
`web-mem-anonymous-session`, `web-mem-returning-account`

### §D7 Abuse Prevention — 3
`web-rate-limit`, `web-spam-detection`, `web-session-budget-cap`

---

## PART E — THE UNIFIED CUSTOMER BRAIN (5)

### §E1 Shared Infrastructure — 1
`uni-shared-router-all-channels`

### §E2 Per-Channel Model Mix — 3
`uni-mix-whatsapp`, `uni-mix-email`, `uni-mix-website`

### §E3 One Customer Brain — 1
`uni-one-customer-brain`

---

## TOTAL

| part | n |
|---|---|
| A — OS Cost Optimization Master Plan | 133 |
| B — WhatsApp Agent | 43 |
| C — Email Agent | 22 |
| D — Website Chat Widget | 23 |
| E — Unified Customer Brain | 5 |

**226**

---

## KNOWN OVERLAP RISKS — to be resolved before the first run

Six pairs describe adjacent things and must not share evidence:

1. `cache-store-exists` (§7) / `cache-semantic` (§32) — a keyed cache and a *meaning*-keyed cache
   are different claims. §32 requires the embedding column to be populated and matched on, not
   merely present.
2. `route-task-classification` (§1) / `engine-classifier` (§3) — the router having a classification
   step, and a classifier component existing. §1 is scored on `fn_ai_route`'s payload, §3 on a
   discrete routine.
3. `budget-per-request-max-tokens` (§9) / `spend-limit-*` (§28) / `wa-cost-limit-per-customer`
   (§B14) — a per-CALL token ceiling, a per-USER monthly spend cap, and a per-CUSTOMER conversation
   cap. Three different objects.
4. `prov-fallback-chain` (§11) / `fail-primary-then-fallback` (§39) / `set-model-fallback` (§15) —
   a provider chain, a retry discipline, and an OpenRouter setting.
5. `embed-vector-store` (§6) / `file-vector-search` (§10) / `em-attach-vector-search` (§C3) — one
   pgvector installation must not satisfy three requirements about three different pipelines.
6. `dash-*` (§14) / `acct-*` (§41) — a dashboard that *reports* numbers and an accountant that
   *raises an alert*. §41 requires the alert, not the view.

## THE TRAP THIS ROW IS MOST EXPOSED TO

Row #5's was the rpc hop; row #6's was the column. **Row #8's is the capability/traffic gap.** Every
one of the 45 OS items can be answered "yes, there is a routine for that" — and this estate really
does have `fn_ai_route`, `fn_select_model`, `fn_llm_cache_put`, `fn_budget_available`,
`fn_model_benchmark`, `fn_model_autoswitch` and eight observability views. Measured on production
2026-08-09, `llm_cache` holds **0 rows** and 2 of 1,021 calls were served from cache.

A scorer that greps `pg_proc` scores this row in the high nineties and tells the founder nothing.
Every behavioural requirement here is therefore scored on `ai_cost_log`, and the evidence prints the
row count that backs it.
