# Knowledge audit — Growth department (7 active agents)

Measured 6 Sep 2026, 02:03–02:30 UTC, read-only against production `htdblwldjkcgjvmqkbeh`. Every number below was
returned by a query in that window; nothing was written, no paid model was called. Scope: `org_agents.active = true and
department = 'growth'` — `brand_mgr`, `marketing_analyst`, `marketing_content`, `marketing_design`, `marketing_social`,
`optimisation_eng`, `sales_director`. Founder's bar: knowledge equal to top senior staff in the role, enough to run 90% of
the time without going to the internet, and the reasoning (decision rules, thresholds, worked examples) to match.

## 0. What could and could not be measured

Measured: `org_agents`, `org_role`, `employee_authority`, `agent_action_kind_policy`, `ops_knowledge`, `agent_knowledge`,
`employee_knowledge` + `knowledge_domain`, `kb_chunks` (by `category_norm`, full-text term hits, citations),
`dept_library`, `company_faq`, `blog_posts`, `social_posts`, `content_drafts`, `outreach`, `seo_categories`,
`brand_assets`, `brand_signal`, `ad_spend_policy`, `ad_campaign_state`, `ad_decision`, `meta_insights`,
`fn_ads_manage` / `fn_ads_autospend_state` / `fn_ad_spend_daily_ceiling` bodies, `knowledge_exam_questions` /
`knowledge_exam_results`, `kb_usage_log` (30 d), `agent_runs` (7 d and 30 d), `review_chain`, `artifact_review`,
`phase_b_business_rule`, `phase_b_sla_policy`, `decision_policy`, `policy_rules`, `collaboration_rule`,
`delegation_rule`, `company_constitution` titles, `fn_agent_context(agent, 22000)` once per agent (the 2-argument
routine is STABLE; it writes nothing), and `fn_agent_context_v3(agent, null, <role-typical task>, null, 24000)` once per
agent (STABLE). The 3-argument `fn_agent_context(agent, chars, query)` was NOT called: it is VOLATILE and inserts a
retrieval-trace row (`fn_record_context_retrieval`).

Not measured / not measurable: there is no `decision_playbook`, `decision_rule` or `standard_operating_procedure` table —
those exist only as `ops_knowledge.record_type` values, which is what was measured. "FAQ answer rate" has no log table
(`kb_usage_log` has 0 FAQ rows) and `fn_faq_answer` is VOLATILE (it updates `response_template.used_count`), so it was not
executed. Content quality was measured by counts, dates, titles, duplication and Arabic presence, not by reading the 32
blog bodies. Term-hit counts are full-text (`fts @@ plainto_tsquery`) on `kb_chunks` and `ilike` on the smaller stores;
a hit proves the phrase occurs, not that the passage is correct or UAE-specific. Anything marked **verify** is a standard I
state from domain knowledge and did not confirm against a primary source in this session.

## 1. Findings that apply to all seven agents (measured once, cited per agent below)

**G1 — The employee context delivers zero professional expertise.** `fn_agent_context(agent, 22000)` returns 27,902–28,124
chars for each growth agent. The section `# LAYER 2 - YOUR PROFESSIONAL EXPERTISE` is 40 chars for all 7 (the heading and
two newlines). Mechanism, read from the routine body: a profession row is admitted only while
`length(out)+length(piece) <= own_cap + 2200`, with `own_cap = least(cap/2, 6000) = 6000`; but by the time Layer 2 starts,
`out` already holds identity (≈1.4k) + company genome (2,653) + risk register (3,041) + the employee block (≤6,200) ≈
12.9–13.4k chars, so the 8,200-char admission test can never pass. Every profession row in `agent_knowledge` is unreachable
through this path for every employee. (Same defect for the 5 CX agents.)

**G2 — The task-time context (v3) carries generic role docs and drops the rules that matter.** `fn_agent_context_v3` for a
growth agent returns 68–70 knowledge ids: `role_knowledge` = 2–4 records, each truncated to 1,800 chars, and for
`brand_mgr`, `marketing_content`, `marketing_design`, `marketing_social` they are the SAME four documents
(`01_ROLE_EXPERTISE_V2.md`, `role_charter.md`, `senior_judgment.md`, `Marketing Operations Specialist`) — four different
jobs mapped to one V2 pack role. `deterministic_rules` = 60 records (153k chars) but the 3-argument context routine emits
them as titles only, in alphabetical order, under a 2,000-char cap: 11 of 60 survive. For `marketing_content` planning an
editorial calendar and `sales_director` deciding a Meta go/no-go, the survivors are `Attribution`, `Brand Strategy`,
`Campaign Analytics`, `Competitor Analysis`, `Content Creation`, `Content Pillars`, `Copywriting`, `Corporate Identity`,
`Customer Personas`, `Email Marketing`, `Linkedin Advertising` ("— controls and boundaries" each); dropped: `Seo —
controls and boundaries`, `Consent And Communications — controls and boundaries`, `Authority: ad-spend caps require
exec/founder approval before increase`, `Authority: brand statements, PR, and public content require approval`,
`Authority: discounts, subsidies, and free reveals are bounded and logged`, `Policy: consent, anti-spam, and channel
compliance for outreach and messaging`. `validated_experience` = 0 items for all 7 (no `agent_knowledge` row in scope
has `validation_status = 'validated'`; they are `author_verified` or `unvalidated`). `live_data_required` = 22 items /
39k chars, capped to 900 chars of titles (19 survive).

**G3 — The department library is empty for growth.** `dept_library` holds 36 rows, all `department = 'company'`; 0 rows for
`growth` or `marketing`. `fn_dept_library_search(v_dept, …)` (Layer 2b) therefore returns nothing department-specific.

**G4 — The reference corpus is generic, Western, textbook material.** `kb_chunks` `category_norm = 'marketing'`: 39,472
chunks, newest 31 Aug 2026; top sources OpenStax *Principles of Marketing* (3,108 chunks), OpenStax *Organizational
Behavior* (2,926), *Entrepreneurship* (2,874), *Principles of Management* (2,868), Kotler & Keller *Marketing Management*
(2,571), *Introduction to Business 2e* (1,571), LibreTexts, Saylor, UNCTAD *Digital Economy Report 2024*. Chunks whose
citation names the UAE/Dubai/GCC/TDRA/PDPL: 81 of 39,472 (17 distinct citations, 0.2%). Term hits inside the marketing
category: attribution 2,630 · Google Ads 404 · Facebook ads 233 · cost per lead 103 · LinkedIn ads 93 · Meta ads 55 ·
Arabic 110 · UAE 97 · Dubai 44 · Ramadan 40 · PDPL 36 · TDRA 19 · Federal Decree-Law 22 · content pillar 28 · brand
guidelines 81 · reveal fee 6. `category_norm = 'regulatory'` (476 chunks, newest 10 Jul 2026): consumer protection 25,
TDRA 19, PDPL 15, cybercrime 12, advertising 10. `_global` (592 chunks): PDPL 24, WhatsApp 16, advertising 3. The v3
`field_corpus` (12 chunks) served to `sales_director` for a Meta go/no-go included "UAE Media Council Advertiser Permit",
"paid_media_hard_rules" and "Domain Scope and UAE Relevance" — so UAE material exists but is thin.

**G5 — `ops_knowledge` for the department is real but has no numbers.** `dept_key = 'growth'`: 97 records (57
decision_playbook, 14 failure_mode, 13 kpi, 4 authority, 4 reference, 3 remediation, 2 policy; jurisdiction AE 52 / INTL 44
/ GCC 1; all `runtime_eligible`, all embedded; 6 deterministic). `dept_key = 'marketing'` (the V2/V3 pack): 279 records
(67 yaml, 32 failure_mode_case, 25 md, 20 each of knowledge_domain / control_requirements / data_and_evidence /
operational_application, 11 live_data_binding, 10 exception_playbook, 10 decision_rule, 10 SOP, 9 metric_definition, 8
department_scenario …; 35 flagged `review_required`; role_keys `marketing-director`, `-operations-specialist`,
`-analyst-controller`, `-reviewer-auditor` at 27 each). Content with a number attached to a unit (`[0-9]+ ?(%|AED|hours|
days|minutes)`): growth 7/97, marketing 0/279. Content with an if/then decision arm: growth 0/97, marketing 18/279.
Content containing a worked example (`worked example|example:|for example`): 0/97 and 0/279. `structured_data`
populated: growth 6/97. Term hits across growth+marketing: Meta 111 · SEO 145 · PDPL 90 · persona 54 · attribution 40 ·
content pillar 19 · LinkedIn 17 · Arabic 14 · reveal fee 13 · referral 9 · Ramadan 4 · UTM 1 · contractor 1 · **0** for
TDRA, Google Ads, cost per lead, CPL, consumer protection, UAE Media Council, National Media Council, Dubai Economy /
DET, Federal Decree-Law No. 45, Federal Law No. 15, anti-circumvention, AED 15, facility manager, brand guideline.

**G6 — Curriculum bindings cover 5 of the 12 required layers.** `employee_knowledge_standard` requires layers 1–12.
Each growth agent has 13 rows: layer 1 `marketing` (the ONE functional domain "Marketing & Growth" — `knowledge_domain`
has 13 functional domains total, no paid-media / SEO / brand / social sub-domains), layer 2 five company domains at
expert, layer 4 `data_analytics`, `finance`, `legal_uae`, `pdpl`, `sales_crm` at awareness, layer 5 `quotesdone_os`
working, layer 8 `communication` working. Layers 3, 6, 7, 9, 10, 11, 12 have no binding.

**G7 — Exams do not measure the job, and gap-fill writes rows nobody validates.** `knowledge_exam_questions`: 10 per agent
(11 for `brand_mgr`, incl. `edge`), 3–4 exam days, latest 5 Sep 2026 (5 questions). Most questions are of the form "What
does the company's operating knowledge say about: <random ops_knowledge record>", including category-specialist pack
files (`rfq_quality_gate.yaml`, `01_EXPERT_QUALIFICATION_STRATEGY_V3.md`, `PACKAGE_MANIFEST_V3.json`,
`specialist_manifest.yaml`). Only `brand_mgr` was asked role-relevant UAE questions (DET permit for promotional
contests, PDPL consent for lead-gen, Arabic in advertising, Q4 CPM drivers, agency lead-source red flag) — wrong on all
five. Filled gaps become `agent_knowledge` `experience` rows (`exam:NNN …`), 0 validated, and Layer 4 "what this
organisation has learned" then shows a `marketing_content` agent `specialist_manifest.yaml` and `rfq_quality_gate.yaml`.

**G8 — No agent in scope retrieved knowledge on its own in 30 days.** `kb_usage_log` categories in 30 d are only
`context_assembly` (868), `_global` (309), `agent_context` (186) — all automatic assembly. Rows by growth agent:
`optimisation_eng` 101, `sales_director` 2, the other five 0.

**G9 — Runs are lane-routing, not domain work; the brand authority has never rejected anything.** Every `ok` run note in 7 d
reads "org_task NNN determined from playbook campaign.launched / content.published / kpi.missed in growth — the org_task
lane determination (cosine 0.90–0.92, corroborated 4/8)". `review_chain` author decisions for the 7 agents: approve /
owned / null only, except 1 `reject` (`marketing_social`, 26 Jul) and 1 `request_revision` (`sales_director`, 6 Aug);
`sales_director` as reviewer: 60 approve, 81 owned, 1 revision, 0 reject. `artifact_review`: 0 rows for any agent in
scope. `brand_signal`: 0 rows. `phase_b_business_rule` BR-036 requires "Visual/video/file review must inspect the actual
final artifact" — no artifact has ever been reviewed.

**G10 — The content the OS shows.** `blog_posts`: 32 published, 26 Jun–20 Jul 2026, authors "QuotesDone" / "QuotesDone
Team", avg 3,630 chars of HTML, categories `Cost guides` 25 + `Cost Guides` 4 (case-duplicate) + `Buyer guides` 2 + `Trade
guides` 1; every sampled title is "How much does X cost in the UAE? (2026 price guide)"; the CCTV title is published
twice (28 Jun and 13 Jul). `social_posts`: 10 rows, all `status='sent'`, `mode='draft'` (3 `marketing_agent` 24 Jun, 6
`postiz_sync` 6 Aug, 1 `selftest`); `content_drafts`: 1 approved blog draft (11 Aug). `outreach`: 20 rows, all
`queued`, channel email, batch 1 Jul, 0 sent. `seo_categories`: 24 pages, all generated 21 Jun with intro + FAQs.
`brand_assets`: 30 files (11 avatars, 5 covers, 7 logos, 4 templates) — files, not a guideline; written brand rules found
only in `company_constitution` art. 17 "Brand personality" (428 chars) and the Layer 1 topics "Brand essentials (every
employee)" and "Brand wording: say 'smart engine', not 'AI'". **Arabic characters: 0 of 32 blogs, 0 of 24 SEO pages, 0 of
874 in-scope `ops_knowledge` records, 1 of 108 in-scope `agent_knowledge` rows.**

**G11 — Ad-spend rules exist as code, not as knowledge.** `ad_spend_policy.default`: daily cap 200 AED, target CPL 150
AED, kill multiplier 3×, learning phase 3 days / 100 AED, scale step 20%, per-campaign 20–100 AED/day, monthly cap null,
month spent 0. `fn_ads_manage` paces down / pauses by CPL from `meta_insights` (2 rows); `fn_ads_autospend_state`
requires `meta_autospend_golive`, `meta_access_token`, `meta_daily_budget_cap_aed`. `ad_campaign_state` 0 rows,
`ad_decision` 0 rows. No record in any store states where 150 AED came from or what a UAE B2B CPL range is (ops term hits
"cost per lead"/"CPL" = 0). `agent_action_kind_policy`: `chief_revenue_officer` is authority for
`finance_marketing_budget`; `decision_policy.founder_review_gates` = refunds only.

**Company rules that ARE present and reach the agents (Layer 1, 9.3–10.6k chars per agent):** pricing & fees live block
(3% reveal fee), "Company FAQ (canonical answers)", RFQ completeness rule, AI Constitution, explainability topics, brand
essentials, `canon:core`. `policy_rules` (7 regex guards: old 2% fee / AED 250 cap, supplier commission, vague launch
terms). `collaboration_rule`: marketing "Publishing anything externally" must involve legal, exec reviews, blocking.
`delegation_rule`: `sales_director` → `brand_mgr` standing deputy. Ops playbooks with UAE content that exist but are
dropped by G2: "UAE seasonality: plan spend and expectations around Ramadan, summer, and Q4 budget flush", "Arabic and
English SEO: two audiences, not one translated site", "Local SEO for UAE B2B: Google Business, free zones, and area-level
pages", "WhatsApp as a UAE B2B growth channel", "Policy: advertising claims and competitor comparisons in the UAE",
"Policy: consent, anti-spam, and channel compliance", "Uae Advertising And Data-Use Rules — operating knowledge".

Depth key used below: **expert** = can set the standard and decide edge cases unaided; **working** = executes correctly
against a written rule; **aware** = knows it exists and when to hand off. Priority: **P1** blocks a correct decision the
agent is asked to make today; **P2** needed to reach senior quality; **P3** completeness.

---

## 2. `sales_director` — Chief Revenue Officer

**What it does today.** `org_role.chief_revenue_officer`: scheduled_manager, execute_medium, budget 10,000 AED; owns
"funnel priority across marketing sales and business development", "pricing and discount within policy", "campaign
go/no-go", "pipeline forecast the company plans on"; forbidden: approving own creative, spend above budget, overriding
compliance. `employee_authority`: `outreach_draft` autonomous, `outreach_send` gated (10,000 AED). Authority role for
`finance_marketing_budget`. Runs 7 d: 3 ok (30 d: 4). Exam latest 5 Sep: 3 correct, 1 wrong, 1 not covered (conf 0.62);
all-time 6/20 correct. Retrievals 30 d: 2 (both automatic). Reviews: as reviewer 60 approve / 81 owned / 1 revision.
`agent_knowledge` 10 rows (1 profession "Selling a marketplace that has not launched", 9 exam-derived), none validated.
The CRM & RevOps role and Account Manager role are `retired` in `org_role`, so stage definitions, forecast mechanics and
named-account plans have no other owner. `outreach`: 20 queued, 0 sent.

**Knowledge inventory**

| Source | Scoped to this agent | Count / freshness | Note |
|---|---|---|---|
| org_role / org_agents | yes | responsibilities 1 sentence; knowledge_scopes 16 keys | tools list is the marketing tool set |
| agent_knowledge | agent_key | 10 rows, 9 exam-derived, 0 validated, avg 1,738 chars, 3 with numbers | unreachable via Layer 2 (G1) |
| employee_knowledge | agent_key | 13 rows, 5 of 12 layers (G6) | `sales_crm` at awareness only |
| ops_knowledge growth / marketing / sales | dept | 97 / 279 / 266 (sales pack: 4 role keys × 25) | v3 maps it to `Marketing Director` + `Sales & CRM Director` docs, 1,800 chars each |
| kb_chunks marketing / sales | category | 39,472 / 53,589 | generic textbooks (G4); `sales` not sampled |
| fn_agent_context | — | 28,008 chars; Layer 2 = 40 chars; Layer 4 = 3 exam rows incl. "Offshore & Marine Construction Companies — Inquiry Qualification Playbook" | |
| fn_agent_context_v3 | — | 70 ids; 11/60 rules survive; task-relevant 3/9 | drops ad-spend-cap authority and consent policy |
| decision_policy | company | `financial_review_aed` 10,000; `founder_review_gates` refunds only; `legal_triggers` list | live, structured |
| phase_b_business_rule | W20 etc. | BR-034 consent/suppression, BR-035 approved revision only, BR-041 activity ≠ outcome | titles + one sentence |

**Senior-staff standard (CRO, UAE B2B RFQ marketplace)**

| # | Domain | Depth |
|---|---|---|
| 1 | UAE B2B buyer segments & economics: main/sub-contractors, FM companies (AMC/PPM cycles), developers, SMEs (mainland vs free zone), corporate/government procurement; deal sizes and RFQ frequency per segment | expert |
| 2 | Marketplace growth loops: supply-first liquidity, single-player value, referral K-factor, cold-start concentration | expert |
| 3 | Reveal-fee unit economics: 3% uncapped fee, reveals × fee × retention LTV, payback vs CAC, discount/subsidy bounds | expert |
| 4 | Company T&C commercial rules: 3% fee, top-3 report, 3% supplier non-response charge, AED 15k / 3× anti-circumvention, no supplier commission, VAT 5% on fee | expert |
| 5 | Paid-media go/no-go: Meta / Google / LinkedIn UAE B2B benchmarks (CPM, CPC, CPL ranges by segment), learning-phase rules, kill/scale thresholds, the autopilot's own ceilings | expert |
| 6 | Outreach compliance: PDPL (Federal Decree-Law 45/2021) consent & opt-out, Cybercrime Law (FDL 34/2021) unsolicited e-marketing, TDRA anti-spam policy, UAE telemarketing regulation (Cabinet Res. 56/2024 — **verify** details), B2B e-mail norms | expert |
| 7 | Pipeline & forecast mechanics: stage definitions, conversion rates, weighted forecast, CRM hygiene (role retired → CRO owns) | expert |
| 8 | Pricing & discount policy: what may be offered, by whom, logging; free-reveal bounds | expert |
| 9 | Attribution & reporting: UTM taxonomy, first/last/multi-touch, incrementality, canonical metric definitions (BR-040) | working |
| 10 | Partnerships / ABM: chambers, associations, free-zone authorities, enterprise procurement portals (Dubai eSupply, ADNOC ICV — **verify**) | working |
| 11 | UAE seasonality: Ramadan, Eid, summer, Q4 budget flush, National Day, Mon–Fri working week | working |
| 12 | Brand & claims compliance: advertising claims, comparative claims, UAE Media Council advertiser permit (**verify** scope) | working |
| 13 | Arabic/English market communication norms | working |
| 14 | Competitor landscape (UAE RFQ/tender platforms, directories) | aware |
| 15 | Supplier economics & supply health (moved to Supply dept) | aware |
| 16 | Stripe payment flows, refund policy (founder-only) | aware |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Buyer segments | expert | **missing** — ops hits: contractor 1, facility manager 0, persona 54 (generic "Customer Personas — operating knowledge"); no segment economics record | Persona pack: 5 UAE buyer personas with licence type, procurement cadence, typical RFQ value bands, decision-maker titles, objections, channels → `ops_knowledge` dept `growth` record_type `reference` + `structured_data` (value bands) | 5 × 2k chars | P1 |
| 2 Growth loops | expert | **present** — growth playbooks "Referral loops…", "Single-player value…", "Cold-start…", "Concentrate the cold-start…" (read in full: sound, but no numbers) | Add K-factor / referral-CAC thresholds as `structured_data`; worked example on a 30-reveal month | 4 × 500 chars | P2 |
| 3 Unit economics | expert | **partial** — "Reference: reveal-fee unit economics worked through" exists (exam: `marketing_content` wrong); pricing live block present; 0 worked-example regex hits | Worked examples: 3 scenarios (SME, contractor, FM) of fee, LTV, CAC, payback with AED numbers → `ops_knowledge` growth `reference` + `agent_knowledge` profession (validated) | 3 × 1.5k | P1 |
| 4 T&C commercial rules | expert | **partial** — 3% fee live; FAQ; `policy_rules` guard old terms; ops hits anti-circumvention 0, "AED 15" 0 | One deterministic record "Commercial rules the CRO enforces" with each rule, its T&C clause ref, and the decision it constrains → `ops_knowledge` growth `authority`, `deterministic=true`, `structured_data` | 1 × 3k | P1 |
| 5 Paid-media go/no-go | expert | **missing** — CPL/cost-per-lead 0 hits in ops; `ad_spend_policy` target 150 AED with no source; Meta benchmarks 0; Google Ads 0 | UAE B2B paid-media benchmark sheet (Meta lead/traffic, Google Search B2B services, LinkedIn Sponsored/Lead Gen: CPM, CPC, CTR, CPL ranges, learning phase 50 events/7 days, budget change ±20% rule) with sources and date; plus a plain-language copy of the autopilot rules (`ad_spend_policy` fields) → `ops_knowledge` growth `decision_playbook` + `kpi`, `structured_data` | 4 × 2k | P1 |
| 6 Outreach compliance | expert | **partial** — "Policy: consent, anti-spam, and channel compliance" exists but is dropped by the cap (G2); PDPL 90 hits; TDRA 0; telemarketing 0; cybercrime 0 | Regulation digest: FDL 45/2021 arts. on consent/direct marketing/DSAR; FDL 34/2021 unsolicited marketing article; TDRA spam policy; Cabinet Res. 56/2024 telemarketing (hours, licensed numbers, DNCR) — each with a "so the CRO may / may not" line → `kb_chunks` category `regulatory` (source_kind `regulation`) + one `ops_knowledge` growth `policy` deterministic record | 6 × 3k | P1 |
| 7 Pipeline & forecast | expert | **missing** — CRM role retired; ops hits for "forecast" not measured; `sales` pack is generic role yaml | Stage definitions (lead → RFQ → quotes → reveal → repeat), stage conversion targets, weekly forecast method → `ops_knowledge` growth `kpi` + `standard_operating_procedure` | 2 × 2k | P1 |
| 8 Pricing/discount policy | expert | **partial** — "Authority: discounts, subsidies, and free reveals are bounded and logged" (gated) exists, dropped by cap; no thresholds (numbers 7/97) | Threshold table: who may offer what (AED / %), logging field, founder gate → `structured_data` on the existing authority record | 1 × 800 | P1 |
| 9 Attribution & metrics | working | **partial** — "Attribution for a marketplace: last-click lies, so triangulate"; BR-040; UTM 1 hit | UTM/event taxonomy + canonical metric definitions (CPL, CAC, reveal rate, payback) → `ops_knowledge` growth `kpi` `structured_data` | 1 × 2k | P2 |
| 10 Partnerships/ABM | working | **present** — "Partnership channels…", "Enterprise procurement ABM…" | add named UAE bodies list (**verify** each) → `reference` | 1 × 1.5k | P3 |
| 11 Seasonality | working | **present** — "UAE seasonality…" (dropped by cap); Ramadan 4 hits | none beyond G2 fix; add 2026/2027 calendar dates → `structured_data` | 300 | P3 |
| 12 Claims compliance | working | **present** (gated) — "Policy: advertising claims and competitor comparisons in the UAE" | see brand_mgr row 2 | — | P2 |
| 13 Arabic/English norms | working | **missing** — 0 Arabic anywhere (G10) | Bilingual outreach standard (when Arabic-first, honorifics, formal register) → `agent_knowledge` profession + `response_template` Arabic variants | 1 × 2k | P2 |
| 14 Competitors | aware | **present** — "Competitor and SERP intelligence…" (advisory) | none | — | P3 |
| 15 Supply health | aware | **present** — "Supplier tiering…", "Demand and supply must scale in lockstep" | none | — | P3 |
| 16 Payments/refunds | aware | **present** — decision_policy refund keys; founder-only | none | — | P3 |

**Reasoning check.** Decision rules: 0 if/then arms in the 97 growth records; the CRO's owned decisions ("campaign
go/no-go", "pricing within policy") have no threshold anywhere except the autopilot's code. Thresholds: only in
`ad_spend_policy` / `decision_policy`, which are live data not knowledge. Worked examples: 0. The agent's own profession
row is never delivered (G1). P1 = 7.

---

## 3. `brand_mgr` — Brand & Creative Manager

**What it does today.** `org_role.brand_and_creative`: event_driven_operator, execute_low, budget 1,000 AED; owns "brand
guidelines and their application", "accepting or rejecting creative on brand grounds"; forbidden: approving own
creative, legal/regulatory claims. `employee_authority`: `boost_recommend` autonomous; content_calendar / draft / revise /
seo_produce advisory. Standing deputy for `sales_director`. Runs 7 d: 2 ok. Exam latest: 1 correct, 1 partial, 3 wrong
(conf 0.34); all-time 5/26 correct, 10 wrong, 7 not covered — the weakest in the department, and its wrong answers were the
role-relevant ones (DET promotions permit, PDPL lead-gen consent, Arabic in ads, Q4 CPM drivers, agency lead source).
Retrievals 30 d: 0. Reviews authored: 24 approve / 8 owned / 8 null; 0 rejects; `artifact_review` 0; `brand_signal` 0.
`agent_knowledge` 5 rows (1 profession "Brand for a marketplace whose product is anonymity"), 0 validated.

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge | 5 rows, avg 1,131 chars, 0 validated | not delivered (G1) |
| employee_knowledge | 13 rows; `pdpl`, `legal_uae` at awareness | no brand sub-domain exists in `knowledge_domain` |
| ops_knowledge marketing | "Brand Strategy — operating knowledge" (2,343 chars), "Corporate Identity —", "Tone Of Voice —", "Uae Advertising And Data-Use Rules —", SOP 03 Brand Review, control_requirements "Brand Strategy — controls and boundaries" | generic V2 pack prose; 0 numbers |
| brand_assets | 30 files: 11 avatars, 5 covers, 7 logos, 4 templates | no colour/typography/tone spec table |
| company_constitution | art. 17 Brand personality 428 chars; Layer 1 "Brand essentials", "smart engine not AI", "Document branding standard" | reaches every employee |
| kb_chunks marketing | brand guidelines 81 hits (Kotler/OpenStax) | generic |
| fn_agent_context | 27,961 chars; Layer 2 = 40; Layer 4: "Failure mode: optimizing paid campaigns to leads instead of reveals", "Reducing RFQ-form friction…" | neither is a brand topic |
| fn_agent_context_v3 | role_knowledge = `Marketing Operations Specialist` pack (shared with 3 other agents) | |

**Senior-staff standard (Brand & Creative Manager, UAE B2B)**

| # | Domain | Depth |
|---|---|---|
| 1 | Written brand guideline: positioning, personality, tone of voice (EN + AR), logo clear-space/min size, colour palette (hex/CMYK), typography (Latin + Arabic typefaces), imagery rules, do/don't examples | expert |
| 2 | UAE advertising content law: UAE Media Council rules (advertiser permit, content standards, Arabic use), misleading/comparative claims, DET (Dubai Economy & Tourism) permits for promotions/raffles, Federal Law 15/2020 truthful advertising provisions — each **verify** against current text | expert |
| 3 | PDPL for marketing creative & lead-gen (consent wording, retargeting disclosures, cookie/tracking notices) | expert |
| 4 | Creative acceptance checklist: objective reject criteria, BR-036 actual-artifact inspection, severity ladder, revision loop | expert |
| 5 | Anonymity-first brand rules: never imply supplier identity pre-reveal; "smart engine" wording; no commission claims | expert |
| 6 | Bilingual creative craft: Arabic typography, RTL layout, transcreation vs translation, register for B2B | working |
| 7 | Platform creative specs & policies: Meta, LinkedIn, Instagram, TikTok, X, YouTube, WhatsApp (sizes, safe zones, text limits, ad policy restrictions) | working |
| 8 | Buyer & supplier personas (from CRO row 1) applied to creative | working |
| 9 | Brand measurement: share of voice, brand search, sentiment; `brand_signal` taxonomy | working |
| 10 | Copyright / image licensing / trademark basics in the UAE (Federal Decree-Law 38/2021 copyright, 36/2021 trademarks — **verify**) | aware |
| 11 | Accessibility & contrast (WCAG 2.2 AA) | aware |
| 12 | Cultural sensitivity: religion, national symbols, gender depiction, holiday timing | working |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Brand guideline | expert | **partial** — assets only (30 files); constitution art. 17 (428 chars); no palette/typography/tone table; ops "brand guideline" 0 hits | The QuotesDone Brand Guideline v1 (EN/AR): tone, palette hex, type stack incl. Arabic face, logo rules with the 7 logo files referenced by `brand_assets.id`, 10 do/don't pairs → `ops_knowledge` marketing `policy` deterministic + `structured_data` (palette, fonts) + `agent_knowledge` profession validated | 1 × 8k + JSON | P1 |
| 2 UAE ad content law | expert | **missing** — exam wrong ×3; ops UAE Media Council 0, DET 0, National Media Council 0; "Policy: advertising claims…" exists but generic and dropped by cap | Digest of UAE Media Council advertising standards + advertiser-permit scope, DET promotion-permit rule, FL 15/2020 advertising articles, with a 12-line "reject if" checklist → `kb_chunks` regulatory + `ops_knowledge` marketing `policy` deterministic | 4 × 3k | P1 |
| 3 PDPL in creative | expert | **partial** — PDPL 90 ops hits (generic control text); exam wrong | Consent wording standards, retargeting disclosure text (EN/AR), cookie notice → `ops_knowledge` marketing `operational_template` | 2 × 1.5k | P1 |
| 4 Acceptance checklist | expert | **missing as a rule** — SOP 03 Brand Review is prose; 0 rejects, 0 artifact reviews, 0 brand signals; BR-036 unmet | Objective checklist (logo, colour ΔE, type, claim, anonymity, Arabic, platform spec) with pass/fail and severity → `ops_knowledge` marketing `decision_rule` deterministic; wire to `artifact_review.deterministic` | 1 × 3k | P1 |
| 5 Anonymity rules | expert | **present** — Layer 1 brand essentials, "smart engine", policy_rules regex, profession row | none beyond G1 | — | P3 |
| 6 Bilingual craft | working | **missing** — 0 Arabic in any store | Arabic typography/RTL/transcreation guide with 5 EN→AR headline examples → `agent_knowledge` profession validated | 1 × 3k | P2 |
| 7 Platform specs | working | **partial** — brand_assets templates ×4; ops LinkedIn 17, Meta 111 (generic) | Spec sheet per platform (dimensions, text %, safe zones, policy no-gos) dated → `ops_knowledge` marketing `reference` `structured_data` | 1 × 3k | P2 |
| 8 Personas in creative | working | **missing** (CRO row 1) | reuse persona pack | — | P2 |
| 9 Brand measurement | working | **missing** — `brand_signal` 0 rows, no taxonomy | signal taxonomy + weekly measure → `kpi` | 1 × 1.5k | P3 |
| 10 IP basics | aware | **missing** — not in `legal_uae` domain at awareness (binding exists, content not measured) | 1-page digest (**verify**) → `kb_chunks` regulatory | 1 × 2k | P3 |
| 11 Accessibility | aware | **present** — "Accessibility — controls and boundaries" (CS pack), not marketing | link/copy → marketing dept | — | P3 |
| 12 Cultural sensitivity | working | **partial** — "operating support around UAE holidays, Ramadan…" (CX) | creative calendar & sensitivity rules → `policy` | 1 × 1.5k | P2 |

**Reasoning check.** Owned decision "accept or reject creative" has no reject criterion in any store, and the record of
decisions (0 rejects in 40 reviews, 0 artifact reviews) shows the authority is not exercised. No thresholds, no worked
examples. P1 = 4.

---

## 4. `marketing_analyst` — Marketing Performance Analyst

**What it does today.** `org_role` (not separately listed — v3 maps to `Marketing Analyst / Controller`); routing tier
analyst_controller; `employee_authority`: `boost_recommend` autonomous, `recommend` advisory, content actions advisory.
Runs 7 d: 3 ok. Exam latest: 3 correct, 2 partial (conf 0.71); all-time 6/20. Retrievals 30 d: 0. Reviews authored 24
approve / 8 owned / 8 null. `agent_knowledge` 8 rows (1 profession "Attribution for a marketplace with no attribution
data yet"), 0 validated. Live inputs available: `meta_insights` 2 rows, `ad_decision` 0, `ad_campaign_state` 0,
`goal_period` (referenced by the context routine).

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge | 8 rows, avg 1,944 chars, 0 with numbers, 0 examples | not delivered (G1) |
| employee_knowledge | 13 rows; `data_analytics` at awareness | analyst has analytics at *awareness* |
| ops_knowledge | "Attribution — operating knowledge", "Campaign Analytics —", metric_definition ×9 (marketing), kpi ×13 (growth: "Payback period…", "Time-to-first-quote…", "Supplier win rate…"), "Measuring organic SEO's true contribution to reveals", "Experiment design: power the test on reveals, not clicks", "The RFQ-to-reveal funnel: instrument every arrow separately" | prose; 0 numbers, 0 examples |
| kb_chunks marketing | attribution 2,630 hits; UTM 80 | textbook |
| fn_agent_context | 27,934 chars; Layer 2 = 40 | |
| fn_agent_context_v3 | role_knowledge `Marketing Analyst / Controller` yaml (competency levels 1–5, generic evidence-of-mastery) | |

**Senior-staff standard (Marketing Performance Analyst)**

| # | Domain | Depth |
|---|---|---|
| 1 | Attribution design: UTM & event taxonomy, first/last/position/multi-touch, incrementality & holdouts, B2B 30–90 day windows | expert |
| 2 | Canonical metric definitions & benchmarks: CPL, CAC, reveal rate, cost per RFQ, payback, LTV; UAE B2B paid benchmarks by channel | expert |
| 3 | The company's own instruments: `fn_ws_marketing`, `goal_period`, `meta_insights`, `ad_decision`, `kb_usage_log`, GA4/Meta Pixel/CAPI events (**verify** which exist) | expert |
| 4 | Ad-spend autopilot rules (`ad_spend_policy` semantics, pace_down/pause logic) so reports explain decisions | expert |
| 5 | Experiment design & statistics: power on reveals, MDE, peeking, sequential tests | expert |
| 6 | Reveal-fee unit economics & cohort analysis | expert |
| 7 | Reporting standards: BR-040 metric consistency, BR-041 activity ≠ outcome, BR-042 fact/assumption/confidence | working |
| 8 | SEO measurement: Search Console, branded vs non-branded, rank tracking | working |
| 9 | PDPL constraints on analytics (consent-based tracking, data minimisation) | working |
| 10 | Seasonality adjustment for UAE calendar | working |
| 11 | Spreadsheet/SQL competence on the OS schema (which tables hold reveals, inquiries, quotes) | working |
| 12 | Competitor benchmarking sources | aware |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Attribution design | expert | **partial** — playbook "last-click lies, so triangulate"; profession row admits "no attribution data yet"; UTM 1 ops hit; no taxonomy | UTM/event taxonomy (source/medium/campaign/content naming, reveal & RFQ events), window rules, model choice per question → `ops_knowledge` growth `standard_operating_procedure` + `structured_data` | 1 × 3k | P1 |
| 2 Metric definitions & benchmarks | expert | **partial** — kpi records without numbers; CPL 0 hits; benchmarks "are hypotheses" reference exists | Metric dictionary with formula, source table, target and UAE benchmark range per channel → `ops_knowledge` growth `kpi` `structured_data` (formula, target, range, source, date) | 12 × 600 | P1 |
| 3 Own instruments | expert | **partial** — Layer 3 live state from `fn_ws_marketing` (974 chars); `live_data_required` 22 items (titles) | Instrument map: each report → function/table/column; GA4/Pixel status (**verify**) → `ops_knowledge` growth `live_data_binding` | 1 × 2.5k | P1 |
| 4 Autopilot rules | expert | **missing as knowledge** — rules only in `fn_ads_manage` / `ad_spend_policy` (G11) | Plain-language rule sheet mirrored from `ad_spend_policy` (cap 200, target CPL 150, kill 3×, learning 3 d/100 AED, ±20%) with rationale → `ops_knowledge` growth `decision_playbook` deterministic | 1 × 1.5k | P1 |
| 5 Experiment stats | expert | **present** — "Experiment design: power the test on reveals", "Failure mode: peeking, p-hacking…" (exam: content wrong) | add MDE/sample-size worked example → `structured_data` | 1 × 800 | P2 |
| 6 Unit economics | expert | **partial** — see CRO row 3 | shared worked examples | — | P2 |
| 7 Reporting standards | working | **present** — BR-040/041/042 titles reach via rules list | none | — | P3 |
| 8 SEO measurement | working | **present** — "Measuring organic SEO's true contribution to reveals" | Search Console access facts (**verify**) | — | P3 |
| 9 PDPL in analytics | working | **missing** — PDPL records are policy prose, not analytics-specific | 1 record: consent-gated events, retention periods → `policy` | 1 × 1k | P2 |
| 10 Seasonality | working | **present** (dropped by cap) | none | — | P3 |
| 11 Schema competence | working | **partial** — `quotesdone_os` domain at working; table map not measured | data dictionary for reveals/inquiries/quotes/transactions → `live_data_binding` | 1 × 2k | P2 |
| 12 Competitor sources | aware | **present** (advisory) | none | — | P3 |

**Reasoning check.** Metric records carry no formulas or targets (0/13 growth kpi records with numbers); the analyst's
one profession row says the attribution data does not exist yet; no worked example anywhere. P1 = 4.

---

## 5. `marketing_content` — Content Strategy & Copy Specialist

**What it does today.** `org_role.content_strategy_and_copy`: on_demand_specialist, execute_low; owns "editorial plan and
pillars", "SEO topic selection", "copy for an approved brief"; forbidden: publishing without review, unsupported
product/legal claims. `employee_authority`: `content_calendar` autonomous, `content_draft` / `revise` / `seo_produce`
advisory. Runs 7 d: 3 ok. Exam latest: 3 correct, 2 not covered (conf 0.58); all-time 6/20, 8 wrong (unit economics,
LTV, pricing experiments, partnership channels, time-to-first-quote). Retrievals 30 d: 0. Reviews authored 30 approve /
8 owned / 10 null. `agent_knowledge` 11 rows (1 profession "Content and SEO for UAE B2B procurement buyers" — read in
full: good direction, AED pricing, Mon–Fri, evidence rule; 1,632 chars avg), 0 validated. Output: 32 blogs (Jun–Jul),
24 SEO pages (21 Jun), 1 draft since (11 Aug); nothing published since 20 Jul.

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge | 11 rows, 1 with numbers, 0 examples | not delivered (G1) |
| ops_knowledge | "Content Pillars — operating knowledge", "Content Creation —", "Copywriting —", "Seo —", SOP 01 Content Planning, SOP 06 Seo Research, SOP 07 Blog Publishing (3,068 chars); growth: "Topical authority: build category hubs", "Keyword research for RFQ intent", "Programmatic SEO for RFQ categories", "Arabic and English SEO", "Local SEO for UAE B2B", "Technical SEO for a marketplace", "Link building and digital PR for UAE B2B authority", "Content and programmatic SEO: buying guides" | content pillar 19 hits; Arabic 14; 0 keyword lists |
| seo_categories | 24 pages with search_term, intro, FAQs | English only |
| blog_posts | 32, one format, 4 categories (1 case-dup), 1 duplicate title | no editorial calendar table found |
| kb_chunks marketing | textbooks; UAE-cited 0.2% | |
| fn_agent_context | 27,902 chars; Layer 2 = 40; Layer 4 = `specialist_manifest.yaml`, `rfq_quality_gate.yaml`, `retrieval_policy.yaml`, "Defect Escape Analysis" | none content-related |
| fn_agent_context_v3 | `Marketing Operations Specialist` pack; dept docs "Seo — how the department uses it", "Uae Advertising And Data-Use Rules — how the department uses it" (1,800 chars each); `Seo — controls and boundaries` dropped by cap | |

**Senior-staff standard (Content Strategist / SEO, UAE B2B)**

| # | Domain | Depth |
|---|---|---|
| 1 | UAE search demand: Arabic + English keyword sets per category × emirate, local intent modifiers (Dubai, Abu Dhabi, Sharjah, JAFZA, DIP…), procurement vocabulary (BoQ, MEP, fit-out, AMC, tender) | expert |
| 2 | Content pillars & editorial calendar: pillars tied to personas and funnel stage, cadence, UAE calendar, ownership | expert |
| 3 | Buyer personas (shared) | expert |
| 4 | Claims & evidence policy: which cost benchmarks may be published, sourcing, dating, disclaimers; FL 15/2020 & UAE Media Council truthfulness (**verify**); no supplier-identity implication | expert |
| 5 | On-page & technical SEO for a marketplace: hub/spoke, canonicalisation, thin-page control, hreflang ar-AE/en-AE, schema (FAQ, HowTo, Service), Core Web Vitals | expert |
| 6 | Programmatic SEO: category × intent × location matrix, quality gates against doorway pages | expert |
| 7 | E-E-A-T & authority: author bios, sources, link building/digital PR in the UAE | working |
| 8 | Bilingual copywriting: transcreation, register, Arabic SEO title/meta norms | working |
| 9 | Lifecycle email/WhatsApp copy rules (subject lines, consent footer, Arabic variant) | working |
| 10 | Brand guideline application (from brand_mgr row 1) | working |
| 11 | Measurement of content → RFQ → reveal (with analyst) | working |
| 12 | Copyright/licensing of images and quoted sources in the UAE | aware |
| 13 | Competitor content landscape | aware |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 UAE keyword corpus | expert | **missing** — 0 Arabic in any store; `seo_categories.search_term` 24 English terms; "Keyword research for RFQ intent" is method only | Keyword bank: per category (start with the 24 SEO categories + `category_keyword`/`subcategory_keyword` tables) EN + AR terms, intent, emirate modifiers, volume band, date → `ops_knowledge` growth `reference` `structured_data` + `kb_chunks` marketing (source_kind `guide`) | 24 × 1k | P1 |
| 2 Pillars & calendar | expert | **partial** — pillar prose exists (19 hits); no pillar list, no cadence, no calendar object (`content_drafts` 1 row) | The pillar document (5–6 pillars → personas → funnel stage → formats → cadence) → `ops_knowledge` growth `standard_operating_procedure` + `structured_data` | 1 × 3k | P1 |
| 3 Personas | expert | **missing** (CRO row 1) | shared persona pack | — | P1 |
| 4 Claims & evidence policy | expert | **partial** — profession row has the rule ("never publish a price benchmark the platform cannot evidence") but is undelivered; 32 published cost guides predate it; "Policy: advertising claims…" gated/dropped | Evidence standard for cost guides (source classes, sample size, dating, disclaimer text EN/AR, review cadence) + back-audit list of the 32 posts → `ops_knowledge` growth `policy` deterministic | 1 × 2k | P1 |
| 5 On-page/technical SEO | expert | **present** — "Technical SEO for a marketplace…", "Topical authority…"; hreflang/schema not measured | add hreflang ar-AE/en-AE, schema and CWV checklist → `reference` | 1 × 2k | P2 |
| 6 Programmatic SEO | expert | **present** — "Programmatic SEO for RFQ categories…" | quality gate thresholds → `structured_data` | 500 | P2 |
| 7 E-E-A-T / links | working | **present** — "Link building and digital PR for UAE B2B authority" | none | — | P3 |
| 8 Bilingual copy | working | **missing** — 0 Arabic | Arabic copy standard + 10 EN/AR title pairs → `agent_knowledge` profession validated | 1 × 2.5k | P2 |
| 9 Lifecycle copy | working | **present** — "Lifecycle email: the reveal-nudge and quote-ready trigger sequences"; consent policy dropped by cap | consent footer text EN/AR → `operational_template` | 500 | P2 |
| 10 Brand application | working | **partial** — see brand_mgr | — | — | P2 |
| 11 Measurement | working | **present** — "Measuring organic SEO's true contribution" | — | — | P3 |
| 12 Copyright | aware | **missing** | 1-page digest (**verify**) | 1 × 1.5k | P3 |
| 13 Competitor content | aware | **present** (advisory) | — | — | P3 |

**Reasoning check.** SOP 07 Blog Publishing exists (3k chars) but no acceptance thresholds (word count, source count,
readability, duplicate-title check — the live corpus has a duplicate). No worked example of a brief → draft → review. The
duplicate CCTV title and the `Cost guides`/`Cost Guides` split show no deterministic pre-publish check. P1 = 4.

---

## 6. `marketing_design` — Visual Design Specialist

**What it does today.** Role text: "Produces creatives from brand_assets, enforces logo, colour and typography rules."
`employee_authority`: `content_draft` autonomous ("Must cite the brand asset used"), `boost_recommend` autonomous, others
advisory. Runs 7 d: 2 ok. Exam latest: 3 correct, 2 partial (0.72); all-time 6/20 (its questions were growth economics and
pack manifests, not design). Retrievals 30 d: 0. Reviews authored 24 approve / 7 owned / 8 null. `agent_knowledge` 9 rows
(1 profession "Design for a two-sided B2B marketplace"; 1 with an example, 2 with numbers), 0 validated. `artifact_review`
0 rows — no creative it produced has a recorded review.

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| brand_assets | 30 files: logos 7, avatars 11 (10 platforms + Universal), covers 5, templates 4 (Instagram 2, TikTok 1, generic 1) | the only design-specific store |
| agent_knowledge | 9 rows | not delivered (G1) |
| ops_knowledge | "Corporate Identity — operating knowledge", "Brand Strategy —", SOP 02 Social Post Production, SOP 03 Brand Review | no spec numbers |
| kb_chunks marketing | textbooks; no design/typography source visible in the top-15 citations | |
| fn_agent_context | 28,110 chars; Layer 2 = 40 | |
| fn_agent_context_v3 | `Marketing Operations Specialist` pack | not a design role doc |

**Senior-staff standard (Visual Designer, UAE B2B marketplace)**

| # | Domain | Depth |
|---|---|---|
| 1 | Brand guideline as a spec: palette (hex/RGB/CMYK), typography incl. an Arabic typeface pairing, logo rules, grid, iconography, photo style | expert |
| 2 | Platform creative specs: Meta feed/story/reel, LinkedIn single/carousel/document, Instagram, TikTok, X, YouTube, WhatsApp status; safe zones; text-overlay limits; file specs | expert |
| 3 | Arabic/RTL design: mirrored layouts, Arabic type sizing, bilingual lockups, numerals | expert |
| 4 | B2B ad creative craft: proof elements, offer framing for the 3% fee, anonymity cues, CTA placement, carousel storytelling | working |
| 5 | Accessibility: WCAG 2.2 AA contrast, type size, alt text | working |
| 6 | UAE cultural & legal constraints on imagery (dress, religion, flags/emblems, alcohol, comparative visuals) — **verify** current rules | working |
| 7 | Image licensing & stock usage rights; AI-generated imagery disclosure norms | working |
| 8 | Design QA checklist & versioning; citing the `brand_assets.id` used | working |
| 9 | Document/report branding (Layer 1 "Document branding standard") | working |
| 10 | Personas → visual language (shared) | aware |
| 11 | Motion/video basics (`video.produce` tool exists) | aware |
| 12 | Print & signage basics (exhibitions) | aware |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Brand spec | expert | **partial** — files only; no palette/type values anywhere measured; "Corporate Identity" prose | same guideline as brand_mgr row 1, plus the machine-readable spec (`structured_data`: hex list, font names, min sizes) → `ops_knowledge` marketing `policy` | shared | P1 |
| 2 Platform specs | expert | **partial** — 4 templates; no spec table | dated spec sheet per platform → `ops_knowledge` marketing `reference` `structured_data` | 1 × 3k | P1 |
| 3 Arabic/RTL | expert | **missing** — 0 Arabic | RTL/bilingual design guide with 5 example lockups → `agent_knowledge` profession validated + asset templates in `brand_assets` | 1 × 2.5k + files | P1 |
| 4 B2B creative craft | working | **partial** — profession row (1 example) | 10 annotated before/after examples → `agent_knowledge` profession | 1 × 3k | P2 |
| 5 Accessibility | working | **present** — CS pack "Accessibility — controls…" (not marketing dept) | copy to marketing dept scope | — | P3 |
| 6 Cultural/legal imagery | working | **missing** — 0 hits | digest (**verify**) → `kb_chunks` regulatory + `policy` | 1 × 2k | P2 |
| 7 Licensing | working | **missing** | policy: allowed sources, attribution, AI disclosure → `policy` | 1 × 1k | P2 |
| 8 QA checklist | working | **missing as rule** — authority note says "cite the brand asset used"; `artifact_review` 0 | checklist → `decision_rule`; wire to `artifact_review.deterministic` | 1 × 1.5k | P2 |
| 9 Document branding | working | **present** — Layer 1 topic | — | — | P3 |
| 10 Personas | aware | **missing** (shared) | — | — | P2 |
| 11 Motion/video | aware | not measured | — | — | P3 |
| 12 Print | aware | **missing** | — | — | P3 |

**Reasoning check.** No design decision rule exists; the only rule is the authority note. P1 = 3.

---

## 7. `marketing_social` — Social Media & Community Manager

**What it does today.** Role: "Owns the channel calendar, drafts and schedules posts, monitors engagement, escalates
brand-risk content to the Director." `employee_authority`: `content_draft` autonomous ("May draft and schedule; may not
publish"), `content_publish` advisory ("Must submit to the Marketing Director" — that role is `retired`; the live
reviewer is `sales_director`), `boost_recommend` autonomous. Runs 7 d: 1 ok. Exam latest: 3 correct, 2 not covered
(0.59); all-time 6/20. Retrievals 30 d: 0. Reviews authored 21 approve / 6 owned / 1 reject (26 Jul) / 8 null; social
posts reviewed in `review_chain`: 12 approve, 1 reject, 5 null. `agent_knowledge` 9 rows (1 profession "Social and
community for a UAE B2B marketplace"; 2 with examples; 1 mentions "24-hour"; 1 "persona"), 0 validated. Output: 10
`social_posts`, last 6 Aug (postiz sync); no channel calendar table found.

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge | 9 rows incl. "WhatsApp as a UAE B2B growth channel" (exam-derived) | not delivered (G1) |
| ops_knowledge | "Social Media — operating knowledge", SOP 02 Social Post Production, growth "LinkedIn and trade-channel outreach…", "WhatsApp as a UAE B2B growth channel: fast, trusted, and rule-bound", "Ratings and reviews flywheel", "Policy: consent, anti-spam…" (dropped by cap) | |
| social_posts / postiz | 10 rows; `postiz_ids`, `permalinks`, `channels` columns | live |
| kb_chunks marketing | WhatsApp 82, LinkedIn ads 93, Facebook ads 233 (generic) | |
| fn_agent_context | 28,088 chars; Layer 2 = 40 | |
| fn_agent_context_v3 | role_knowledge only 2 records (`Marketing Operations Specialist`, `role_charter.md`) — the thinnest in the department | |

**Senior-staff standard (Social & Community Manager, UAE B2B)**

| # | Domain | Depth |
|---|---|---|
| 1 | Platform policies & mechanics: LinkedIn (Pages, Sponsored, community rules), Meta/Instagram (Business Messaging, Community Standards, ad policies), TikTok, X, YouTube; posting limits, formats, algorithm signals | expert |
| 2 | UAE online-content law: UAE Media Council advertiser permit & content standards, Cybercrime Law (FDL 34/2021) on defamation/false info/rumours, PDPL for community data — **verify** each | expert |
| 3 | Community response playbook: response SLA, tone ladder EN/AR, complaint-in-public handling, anonymity rule, escalation criteria (brand-risk, legal, security) | expert |
| 4 | Channel calendar rules: cadence per channel, UAE calendar (Ramadan hours, Eid, National Day, Fri prayer window, Mon–Fri B2B), pillar rotation | expert |
| 5 | WhatsApp Business as a channel: opt-in, 24-hour window, template categories & approval, quality rating tiers, Channels/Communities rules | expert |
| 6 | Engagement benchmarks for UAE B2B pages (follower growth, ER, CTR to RFQ) | working |
| 7 | Boost/paid amplification rules (ties to `ad_spend_policy`; `boost_recommend` authority) | working |
| 8 | Bilingual social copy (Arabic register, hashtags, RTL) | working |
| 9 | Brand guideline & claims policy (shared) | working |
| 10 | Social listening & `brand_signal` taxonomy | working |
| 11 | Influencer/partner rules (UAE Media Council influencer permit — **verify**) | aware |
| 12 | Crisis communication protocol | aware |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Platform policies | expert | **partial** — generic kb hits; no per-platform policy digest; "Linkedin Advertising — controls" title survives cap | Dated policy digest per platform (what gets a post removed/ad rejected; format limits) → `ops_knowledge` growth `reference` `structured_data` | 5 × 1.5k | P1 |
| 2 UAE content law | expert | **missing** — UAE Media Council 0, cybercrime 0 in ops | Digest with "do not post if" list EN/AR (**verify**) → `kb_chunks` regulatory + `policy` deterministic | 3 × 2k | P1 |
| 3 Community playbook | expert | **partial** — CX has "de-escalating the angry buyer", "handling negative reviews and reputation in the UAE market" (dept customer_experience, not growth); escalation criteria for brand-risk absent | Social response playbook: SLA, tone ladder, 15 canned EN/AR replies, escalation matrix (brand-risk → sales_director; legal → legal; security → cto) → `ops_knowledge` growth `decision_playbook` + `response_template` rows channel `social` | 1 × 3k + 15 templates | P1 |
| 4 Calendar rules | expert | **missing** — no calendar object; seasonality playbook dropped by cap | cadence table + UAE calendar 2026-27 → `standard_operating_procedure` `structured_data` | 1 × 1.5k | P1 |
| 5 WhatsApp channel | expert | **partial** — growth playbook exists; "24-hour" 2 ops hits; template approval 2 | WhatsApp Business Platform policy digest (window, template categories, approval, quality rating, opt-in) dated → `kb_chunks` `_global` + `policy` deterministic (shared with CX) | 1 × 3k | P2 |
| 6 Benchmarks | working | **missing** — "benchmark ranges are hypotheses" reference only | benchmark sheet dated → `kpi` | 1 × 1k | P2 |
| 7 Boost rules | working | **partial** — `ad_spend_policy` code | rule sheet (shared with analyst row 4) | — | P2 |
| 8 Bilingual copy | working | **missing** | shared Arabic copy standard | — | P2 |
| 9 Brand/claims | working | **partial** (shared) | — | — | P2 |
| 10 Listening/signals | working | **missing** — `brand_signal` 0 | taxonomy (shared) | — | P3 |
| 11 Influencer rules | aware | **missing** | 1 paragraph (**verify**) | 500 | P3 |
| 12 Crisis protocol | aware | **missing** | 1 page → `remediation` | 1 × 1.5k | P3 |

**Reasoning check.** The one recorded reject (26 Jul) is the only evidence of a judgment; the escalation criterion
"brand-risk content" has no definition in any store; `content_publish` authority points at a retired role. P1 = 4.

---

## 8. `optimisation_eng` — Product Optimisation Engineer

**What it does today.** `kind = 'agent'` (not `brain`), routing tier analyst_controller; responsibilities: "cost per
decision, cost per RFQ, model tier routing, response caching and automation coverage". `employee_authority`: `recommend`
autonomous, `code_selfheal` gated. Runs 7 d: 4 ok (lane routing of `campaign.launched` / `kpi.missed` tasks). Exam
latest: 3 correct, 2 partial (0.73); all-time 6/20 (questions were referral loops, supplier tiering, local SEO — not its
domain). Retrievals 30 d: 101 — the most in the department, all `context_assembly`. Reviews authored 24 approve / 8 owned
/ 8 null. `agent_knowledge` 9 rows (1 profession "Cost and latency optimisation of an AI-run company"; 1 mentions
Ramadan), 0 validated. Its context is the growth department's (`fn_ws_marketing` live state, marketing role pack "Strategy,
Performance & Evolution Analyst / Controller") — the department is the wrong home for its knowledge scope.

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge | 9 rows, avg 1,414 chars, 0 rules, 0 examples | not delivered (G1) |
| employee_knowledge | 13 rows, layer 1 `marketing` expert | its layer-1 domain is marketing, not AI operations |
| ops_knowledge growth/marketing | nothing on model tiers, caching, cost per decision (ops term "Meta" hits are Meta ads) | domain unmeasured in other depts (`ai_dept` 139, `engineering` 141 records exist — not audited here) |
| live tables | `model_policy`, `model_policy_by_identity`, `llm_policy`, `decision_policy` (`prompt_cache_enabled`, `confidence_min`, `cos_reflection_tasks_per_day` 500) | content not read in this audit |
| fn_agent_context | 28,124 chars; Layer 2 = 40 | |
| fn_agent_context_v3 | growth department rules (attribution, brand…) — none about cost | |

**Senior-staff standard (AI cost/latency optimisation engineer)**

| # | Domain | Depth |
|---|---|---|
| 1 | Current model price list & tier map (OpenRouter/Anthropic/Gemini tiers in use; input/output/cache pricing; the ~900-token gateway output cap) | expert |
| 2 | Cost per decision / cost per RFQ definitions, baselines, targets; the run-rate rule (30-day total ≠ run rate) | expert |
| 3 | Routing policy: which task classes go to which tier, confidence thresholds (`confidence_min` 0.6), cascade rules, held-provider gate | expert |
| 4 | Caching: prompt-cache mechanics (byte-stable prefix), response caching, hit-rate measurement | expert |
| 5 | Automation coverage: deterministic-vs-model share (target ~95/5), how to measure per workflow | expert |
| 6 | Latency budgets per surface (portal, WhatsApp, cron) | working |
| 7 | Cost anomaly detection & remediation playbook (budget.exceeded, paidProviderGate) | working |
| 8 | Growth-department economics enough to weigh cost vs revenue impact | aware |
| 9 | Priority hierarchy & constitution (present) | working |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Price list & tiers | expert | **missing in knowledge stores** — 0 growth/marketing records; live policy tables exist (unread here, **verify**) | Dated price/tier sheet + gateway limits → `ops_knowledge` dept `ai_dept` or a new `dept_key='growth'` record scoped `scope_type='agent'` `scope_key='optimisation_eng'`, `structured_data` | 1 × 2k | P1 |
| 2 Cost definitions & baselines | expert | **partial** — profession row (undelivered); no kpi record with a formula | metric dictionary (cost/decision, cost/RFQ, cache hit rate, tier mix) with formula, source table, baseline, target → `kpi` `structured_data` | 5 × 500 | P1 |
| 3 Routing policy | expert | **partial** — `decision_policy.confidence_min`, held-provider gate visible in runs; no written policy record | routing rule sheet mirrored from `model_policy*` tables with rationale → `decision_playbook` deterministic | 1 × 2k | P2 |
| 4 Caching | expert | **partial** — `prompt_cache_enabled` true; no how-to | cache mechanics & measurement note → `reference` | 1 × 1.5k | P2 |
| 5 Automation coverage | expert | **missing** | measurement method per workflow → `kpi` | 1 × 1.5k | P2 |
| 6 Latency budgets | working | **missing** | table → `structured_data` | 500 | P3 |
| 7 Anomaly playbook | working | **partial** — `budget.exceeded` event exists in code | remediation record → `remediation` | 1 × 1.5k | P2 |
| 8 Growth economics | aware | **present** (dept playbooks) | — | — | P3 |
| 9 Constitution | working | **present** | — | — | P3 |

**Reasoning check.** 0 rule arms in its 9 rows; its owned decisions (tier routing, caching) have thresholds only in
live policy tables it is not taught to read. Departmental placement means the v3 assembler feeds it marketing rules.
P1 = 2.

---

## 9. Department summary — Growth

| Agent | P1 | P2 | P3 |
|---|---|---|---|
| sales_director | 7 | 4 | 5 |
| brand_mgr | 4 | 4 | 4 |
| marketing_analyst | 4 | 4 | 4 |
| marketing_content | 4 | 5 | 4 |
| marketing_design | 3 | 5 | 4 |
| marketing_social | 4 | 5 | 3 |
| optimisation_eng | 2 | 4 | 3 |
| **Total** | **28** | **31** | **27** |

**Top 5 ingest items (each unblocks more than one agent)**

1. **Fix the assembler before ingesting anything** (G1, G2, G3): Layer 2 admits 0 profession rows for every employee
   (8,200-char test against a 13k-char prefix); the v3 rule list is alphabetical titles capped at 2,000 chars so
   `Authority: ad-spend caps…`, `Policy: consent, anti-spam…`, `Seo — controls…` never reach the agent; `dept_library`
   has 0 growth rows. Until this is fixed, every item below is stored, not known. (Engineering change, not ingest —
   recorded here because the audit measured it; the fix is a code/SQL change in `fn_agent_context` and the 3-arg
   emitter: rank rules by task relevance and emit bodies for the top N, raise the Layer 2 budget or move the genome/risk
   blocks after it.)
2. **UAE marketing-law digest** (brand_mgr, marketing_social, marketing_content, sales_director): PDPL FDL 45/2021
   marketing articles; Cybercrime FDL 34/2021 unsolicited e-marketing; TDRA anti-spam policy; Cabinet Res. 56/2024
   telemarketing; UAE Media Council advertising standards & advertiser permit; DET promotion permits; FL 15/2020
   advertising provisions — each as a dated `kb_chunks` regulatory source plus one deterministic `ops_knowledge` policy
   record with "reject if / may not" arms. ≈ 20k chars. All items **verify** against the current gazette text.
3. **UAE B2B buyer persona pack** (all 7): 5 personas with licence type, procurement cadence, RFQ value bands,
   decision-maker titles, channels, objections, EN/AR language preference — `ops_knowledge` growth `reference` +
   `structured_data`. ≈ 10k chars.
4. **Paid-media benchmark & autopilot rule sheet** (sales_director, marketing_analyst, marketing_social): UAE B2B
   CPM/CPC/CTR/CPL ranges per platform with sources and dates; the `ad_spend_policy` rules in plain language with the
   rationale for 150 AED target CPL; metric dictionary with formulas. ≈ 10k chars, `kpi` + `decision_playbook` with
   `structured_data`.
5. **Brand Guideline v1 (EN/AR) + creative acceptance checklist + platform spec sheet** (brand_mgr, marketing_design,
   marketing_social, marketing_content): palette/type/logo values as `structured_data`, Arabic typeface and RTL rules, 10
   do/don't pairs, objective reject criteria wired to `artifact_review.deterministic`. ≈ 15k chars + files.

Close behind: the UAE keyword bank EN/AR for the 24 SEO categories (marketing_content), and validating the 7 existing
`profession` rows so `validated_experience` stops returning 0.
