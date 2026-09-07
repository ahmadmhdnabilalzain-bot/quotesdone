# Company brain — Legal, Trust & Safety, Compliance

Department `legal` (`qd-company:org-legal` calls it *the Trust, Safety & Compliance team*). Four active seats out of
seven rows in `public.org_agents`; three are parked with their titles kept for re-hire:

| agent_key | title | seniority | routing_tier | state |
|---|---|---|---|---|
| `legal` | General Counsel | director | director | active |
| `compliance_mgr` | Compliance & Privacy Officer | specialist | reviewer_auditor | active |
| `trust_safety_mgr` | Trust & Safety Manager | specialist | reviewer_auditor | active |
| `moderation_specialist` | Marketplace Content & Privacy Reviewer | specialist | reviewer_auditor | active |
| `contract_specialist` | Contract Manager | specialist | — | parked 4 Sep 2026, merged into `legal` |
| `fraud_analyst` | Fraud Reviewer | specialist | — | parked 3 Sep 2026, merged into `trust_safety_mgr` |
| `risk_governance_mgr` | Risk & Governance Manager | manager | — | parked 4 Sep 2026, governance machinery abolished |

**Hard architectural constraint for everything below: no language model at run time.** Every resolver in this file is
lexical matching, embedding similarity over `embedding_gte` (free, in-region, already computed), table lookup,
arithmetic, threshold comparison, or templated composition. Section 9 of each seat is the honest list of what that
leaves out.

---

## Measurement baseline

Everything asserted here was read from production `htdblwldjkcgjvmqkbeh` on **7 September 2026 between 08:02 and
08:40 UTC**. Where the estate lacks something the words used are *does not exist*.

**Registry and document state**

- `legal_documents`: **12 rows**. Two `agreement` rows — `customer-terms` v5 (effective 2026-09-06, sourced from
  `pages:legal_terms_body`, 15,838 bytes) and `supplier-agreement` v8 (effective 2026-09-06, from
  `pages:legal_supplier_body`, 18,707 bytes). Four `internal` (anti-bribery 1.1, data-retention 1.1,
  information-security 1.0, kyc-policy 1.0). Six `public` (acceptable-use 1.1, complaints 1.1, cookie 1.1,
  disclaimer 1.0, privacy 1.2, refund 1.3). Every row carries a `content_sha256`, maintained by
  `trg_legal_documents_hash`.
- `legal_checklist`: **16 rows, 13 present, 3 absent** — id 14 *Intellectual Property / content-ownership terms*,
  id 15 *NDA / confidentiality template*, id 16 *E-commerce / Consumer Protection compliance statement*.
  `critical_missing` = 0 (all three absentees are priority 2 or 3).
- `legal_kpis` view right now: `policies_published` 12, `policies_stale` 0, `coverage_pct` **81.3**,
  `customers` 1, `customer_terms_acceptance_pct` **0.0**, `suppliers_approved` 1,
  `supplier_terms_acceptance_pct` **100.0**, `open_legal_flags` 0, `high_risk_reviews` 2.
- `legal_kpi_snapshots`: 44 rows; the 2026-09-07 snapshot records `legal_health` **78.5**.
- `legal_reviews`: **3 rows**, all `reviewed_by = 'legal_ai'`, all `needs_licensed_review = true`; risk levels
  medium/high/high; 6, 9 and 3 risk flags. The table has **no version or hash column**, so nothing in the estate can
  distinguish a current review from one written against a superseded document body. Review id 1 was written
  2026-07-09 against a Refund Policy that then said "2% of the quoted amount"; the live document is v1.3 and says 3%.
- `policy_rules`: 7 active forbid-regex rules. Scanned against all 12 live document bodies: **0 hits**.
- `governance_policy`: 16 rows (ethics 3, privacy 3, audit 2, retention 2, approval 2, security 2, compliance 2).
- `retention_policy`: 11 storage buckets; four with no expiry at all (`brand`, `compliance-docs`, `signed-terms`,
  `site`), `finance-reports` / `receipt-files` / `supplier-docs` at 2,555 days, drawings and quotes at 1,095.
- `compliance_sources`: **17 rows, all active**, all last checked 2026-08-10. One is unreachable
  (Dubai Civil Defence, `note = 'reader unreachable (422)'`). Three carry a `last_changed_at`.
- `category_licence_activity`: **20 rows** mapping a catalogue slug to a licence-activity regex plus the extra
  approval note (SIRA, Civil Defence, RERA, MoE, FTA, MOCCAE, DET tourism, municipality food).

**Screening and integrity state**

- `screening_run`: **18 rows**. The most recent pair ran 2026-09-07 03:00 UTC — `un_consolidated` (UN Security
  Council consolidated XML, 4,157 entries, sha 683c29b7…) and `uae_local_terrorist_list` (EOCN Excel, 804 entries,
  sha 0811418a…, note records that the PDF half of the publication is not parsed). `screening_entry`: **4,961 rows**
  with `name_norm` and a `tokens` array. `supplier_screening_hit`: **0 rows**. `hlm_watchlist`: 0 rows.
- `fraud_flags`: **7 rows, every one `status = 'dismissed'`**, newest 2026-08-13. Kinds: `velocity_signups`,
  `duplicate_license`, `abnormal_price` ×4, `dup_customer_phone`.
- `chat_violations`: 0 rows. `contact_messages`: 0. `quote_review_messages`: 0. `os_incidents`: 61.
- Cron: **`legal_ai_daily` (jobid 76, `15 5 * * *`) active** and **`sanctions_screen_weekly` (jobid 345,
  `0 3 * * 1`) active**. Inactive: `agent_compliance_weekly` (9), `fraud_scan_daily` (48),
  `collections_legal_daily` (89), `licence_block_reconcile_daily` (100), `supplier_risk_complaints` (209),
  `supplier_risk_response_delays` (210), `supplier_risk_performance_drops` (211).

**Marketplace state (what these seats actually have to work on)**

- `leads`: **22,265**. Of those, **1** has a `trade_license_no`, **1** has a `license_expiry`, **0** expired,
  **1** has `accepted_terms_at` (version `v5`), **3** are `matching_blocked`, **0** are `banned`,
  **0** carry a `licence_gate_reason`, **0** carry a `license_activity`.
- `customers` 1, `inquiries` 0, `quotes` 0, `transactions` 0.

**People state**

- `employee_authority` holds 10 rows across the four seats (listed inside each section).
- `employee_kpi`: `legal` carries **three** rows — its own *Legal Counsel — primary objective* plus the inherited
  *Contract Specialist* and *Risk & Governance Manager* objectives of the parked seats — and `compliance_mgr`
  carries a fourth copy as *Compliance Manager — primary objective*. All four measure the same thing,
  `select round(100.0*count(*) filter (where present)/nullif(count(*),0),2) from legal_checklist`, currently
  **81.25**, target 100. `trust_safety_mgr` (2 KPIs) and `moderation_specialist` (1 KPI) have `actual_value` NULL and
  `no_measure_reason` = *"NEEDS DEMAND THAT DOES NOT EXIST…"*.
- `company_goals` owned by `legal`: `compliance_violations`, `contract_sla`, `data_breaches`,
  `regulatory_deadlines` — **all four carry `no_measure_reason` = "NO INSTRUMENT EXISTS"**.
- `role_certification`: 8 rows for these four seats (ICA GRC Diploma, CIPP/E ×3, CIPM ×2, CAMS, CFE).
  `certification_exam_result`: **0 rows for any legal seat**. The 22 exam rows in the estate belong to `bookkeeper`,
  `cs_support`, `marketing_analyst`, `procurement` and `security`. **No legal seat has sat an exam, so there are no
  failed syllabus areas to cross-reference — that data does not exist.**
- `agent_knowledge`: `legal` 32 rows (22 `profession`, 10 `experience`), `compliance_mgr` 9 (3 `profession`),
  `moderation_specialist` 10 (1 `profession`), `trust_safety_mgr` 7 (1 `profession`). **Twenty-one of the 22
  `legal` profession rows are `validation_status = 'unvalidated'`** and the twenty-second is `unsourced`; all 22
  carry `source_ref = 'legacy:pre-2026-07-26'` and confidence 0.70.
- `ops_knowledge`: **509 rows** with `dept_key` in (`legal` 375, `trust_safety` 134); **all 509 are
  `embedding_status = 'embedded'`**, which is what makes model-free semantic retrieval possible at zero cost.
- `org_tasks` with `dept_key = 'legal'`: 111 done, 32 cancelled, 9 assigned.

**Company and commercial constants these seats reason against**

- `company_registration`: DET **Trader Licence 1633275**, trade name *quotesdone technologies*, issued 2026-06-25,
  **expires 2027-06-24**, owner 100%, activities **722901** (Computer Systems & Communication Equipment Software
  Design) and **724003** (Portal), DE@AE Tier 1 home-registered digital business. `vat_registered` **false**,
  `trn` **null**, `vat_threshold_aed` 375,000, corporate tax not registered and not required (founder ruling
  2026-09-06), **no auditor and none required**.
- `pricing_config`: reveal fee **3%** promo and standard, caps 99,999,999 (i.e. none), supplier registration free for
  the first **1,000** registrants then **AED 1,000/year**, `supplier_charging_starts` **NULL** (no date; it starts at
  registration 1,001), refund window **5 working days**, chase at **3**, bank settlement **7–14 working days**,
  `category_open_min_suppliers` **10**, `auto_approve_suppliers` **true**.
- `decision_policy`: `founder_review_gates` = `["refund_decision","refund_outside_policy"]` and nothing else;
  `auto_action_max_aed` 0; `financial_review_aed` 10,000; `fraud_score_max` 0.7; `refund_admin_fee_aed` 250;
  `refund_late_fee_annual_pct` 9; `refund_reveal_fee_pct` 3; `legal_triggers` = 10 phrases
  (contract change, liability, indemnity, termination, dispute, refund dispute, regulatory complaint, data subject
  request, subpoena, chargeback); `sensitive_categories` = fire, security, electrical, structural, gas, lifts,
  medical.
- `agent_action_kind_policy`: `legal_flag` → `notify`, authority role **general_counsel**; `compliance_update` →
  `officer`, authority role **general_counsel**. Neither routes to the founder.
- `company_goals.revenue_annual`: **AED 1,000,000**, metric *Recognised revenue in trailing 12 months*, deadline
  **2027-08-31**, owner `finance`.

**Structural gaps that recur in every section below (each one measured, not assumed)**

1. **No incident register.** `company_goals.data_breaches` and `.compliance_violations` both say so in their own
   `no_measure_reason`. `os_incidents` is an operations table, not a regulator-facing one.
2. **No consent record.** There is no `consent`, `cookie_consent` or `dsar` table in `public`. Cookie consent, PDPL
   consent and terms acceptance are captured only as `leads.accepted_terms_at` / `accepted_terms_version` /
   `accepted_terms_ip` and the customer-side equivalent; there is no per-purpose consent ledger.
3. **PDPL machinery with no entry point.** `fn_pdpl_export`, `fn_pdpl_erase_plan`, `fn_pdpl_redact` exist; edge
   functions `pdpl_request` and `pdpl_erase` are deployed; `pdpl_requests` and `pdpl_erase_files` hold **0 rows**;
   and a grep of `src/` finds **no reference to either endpoint**. The capability is finished and unreachable.
4. **The legal evidence chain is fixtures.** `phase_d_legal_source` holds **5 rows, all `ZZ DEMO`**;
   `phase_d_legal_assertion` holds **0**. The machinery for "a legal position must cite a current authoritative
   source" exists and has never carried a real source.
5. **No DNFBP determination record.** `DNFBP` appears in 2 `ops_knowledge` rows and in **0** legal documents. There
   is no table, row or document recording whether QuotesDone is a Designated Non-Financial Business or Profession.

---

## legal — General Counsel

Reports to `ceo`. `routing_tier` director. Responsibilities on record: *maintain full regulatory compliance, reduce
contractual risk, keep policies and templates up to date.* It is also the authority role for `legal_flag` and
`compliance_update` in `agent_action_kind_policy`, and since 4 Sep 2026 it absorbed the contract and
risk-and-governance seats.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | cost of a wrong answer |
|---|---|---|---|---|---|
| L1 | Is the customer T&C version a given customer accepted the version in force when they paid the reveal fee? | gate | every reveal | payments, `cs_retention` | the 3% fee has no contractual basis; refund plus a consumer complaint |
| L2 | Which clause of `customer-terms` authorises this specific charge, and what is its exact wording? | craft | weekly | `cs_support`, finance | a customer-facing answer that misquotes our own contract |
| L3 | Does a proposed pricing change require a new agreement version, or is it inside the existing terms? | gate | per pricing change | `cfo`, `ceo` | charging under terms that do not cover the charge |
| L4 | What version and effective date must a published legal page carry after an edit? | craft | per edit | `moderation_specialist`, product | an unversioned change; no provable "terms in force on date X" |
| L5 | Has any live document drifted from a founder ruling (fee %, subscription term, category count)? | diagnosis | daily | itself, `ceo` | published contradiction of the founder's own pricing |
| L6 | Is a `legal_checklist` requirement genuinely satisfied, or only slug-matched? | gate | daily | itself | 81.3% coverage that overstates real cover |
| L7 | Which of the 3 absent checklist requirements should be closed first, and what does closing it cost? | sequencing | quarterly | `ceo` | effort spent on the least protective gap |
| L8 | Does the platform need an IP / content-ownership clause before suppliers upload catalogues? | gate | once, then on change | supply, product | uploaded catalogues with undefined licence to display |
| L9 | Do we need a mutual NDA template before a supplier sees a redacted drawing? | gate | once | supply, `moderation_specialist` | confidential customer drawings with no confidentiality instrument |
| L10 | Is the DET Trader Licence's activity list (722901, 724003) wide enough for what the platform actually does? | diagnosis | quarterly + before any new revenue line | `ceo`, `cfo` | trading outside licensed activity |
| L11 | How many days until the trade licence expires, and when must renewal start? | forecast | monthly | `ceo`, `cfo` | licence lapse; every supplier contract questionable |
| L12 | Does a new revenue line (subscription, escrow, listing fee) change the licence, VAT or regulatory posture? | gate | per new line | `cfo`, `ceo` | an unlicensed activity or an unregistered tax obligation |
| L13 | Is QuotesDone a DNFBP under the UAE AML/CFT regime? | gate | once, then on activity change | `compliance_mgr`, `cfo` | either an unmet registration/reporting duty or a compliance programme built for nothing |
| L14 | Which supplier categories on our catalogue are themselves DNFBPs, and what does that impose on us? | diagnosis | quarterly | `compliance_mgr`, supply | onboarding a regulated profession with no extra check |
| L15 | Is a "refund" under our policy a contractual remedy or a statutory one, and does the answer change the ladder? | diagnosis | per disputed refund | `cfo`, `cs_retention` | a refund refused on a ground the law does not allow |
| L16 | Does the AED 250 admin fee charged to the supplier survive as an enforceable liquidated sum? | gate | once, then per challenge | `cfo` | an unenforceable charge in the supplier agreement |
| L17 | Is 9% per annum the correct basis for late-payment interest in the supplier agreement? | gate | on challenge | `cfo` | interest charged on a basis the document does not support |
| L18 | Which of the 10 `legal_triggers` phrases has appeared in an inbound message, and what must stop? | escalation | per message | `cs_support`, the router | an automated answer to a dispute, subpoena or DSR |
| L19 | Has an authority source we monitor changed in a way that touches a published document? | diagnosis | daily (`legal_ai_daily`) | itself | terms out of step with a changed regulation |
| L20 | Which document does a given `compliance_sources` change actually touch? | diagnosis | per change | itself | a blanket "review everything" flag nobody acts on |
| L21 | Is a `legal_reviews` row still valid, or was it written against a superseded body? | gate | per read | itself, `ceo` | acting on a review of a document that no longer exists |
| L22 | Does a supplier-supplied contract, MoU or NDA contain a term we cannot accept? | craft | per document | supply, `ceo` | signing an indemnity or exclusivity we did not intend |
| L23 | What is the company's governing-law and jurisdiction position, and is it in both agreements? | gate | daily | itself | a dispute with no agreed forum |
| L24 | Does a marketing claim ("save 40%", "verified suppliers") need substantiation before publication? | gate | per campaign | `growth`, `brand_mgr` | a misleading-advertising exposure |
| L25 | Can we name a customer, supplier or brand in published content? | gate | per asset | `growth` | using a third party's mark or a customer's name without consent |
| L26 | Which retention bucket governs a given artefact, and when must it be destroyed? | allocation | per new artefact class | `it`, `cfo` | keeping personal data past its purpose, or destroying tax records early |
| L27 | Does a proposed data flow to a processor need a written processing agreement, and to where? | gate | per new vendor | `cto`, `compliance_mgr` | an uncovered transfer of personal data |
| L28 | Is an agent decision inside its `employee_authority` band, or is it acting beyond authority? | gate | per escalation | `chief_of_staff` | a decision nobody was empowered to make |
| L29 | Which decisions must reach the founder, and is this one of them? | escalation | per decision | every seat | breaking the founder's *refunds only* boundary in either direction |
| L30 | Does an irreversible action have the second reviewer `governance_policy` #12 requires? | gate | per irreversible action | `chief_of_staff` | a ban, publication or refund with one pair of eyes |
| L31 | Is a document due its annual review, and which clauses changed since the last one? | sequencing | monthly | itself | stale policy presented as current |
| L32 | What is the legal exposure of a supplier who quoted in a category their licence does not cover? | diagnosis | per mismatch | `compliance_mgr`, supply | facilitating unlicensed trade |
| L33 | If a customer alleges the platform is responsible for a supplier's work, what is our position? | craft | per allegation | `cs_support` | conceding principal liability we contracted out of |
| L34 | Does the disclaimer's limitation of liability survive against a consumer, if the buyer is a sole trader? | diagnosis | per claim | `cs_support`, `cfo` | relying on a cap that does not hold |
| L35 | What must a written company response to a regulator contain, and who signs it? | craft | rare, high stakes | `ceo` | an unconsidered admission in writing |
| L36 | Is there an obligation to notify a supervisory authority of an incident, and by when? | escalation | per incident | `compliance_mgr`, `cto` | a missed statutory notification window |
| L37 | Should a litigation hold be placed, and over which tables and buckets? | gate | per dispute | `ceo`, `cto` | evidence destroyed by ordinary retention |
| L38 | Which clause of the supplier agreement authorises suspension, and did we follow it? | gate | per suspension | `trust_safety_mgr` | a wrongful suspension claim |
| L39 | Is a proposed term change retrospective, and what notice must existing counterparties get? | gate | per version bump | `ceo` | a change nobody was told about, unenforceable against them |
| L40 | Given the four legal `company_goals` are all unmeasurable, which instrument do we build first? | sequencing | quarterly | `ceo` | another year of goals with no instrument |

### 2. Domain logic (the models this seat reasons with)

**M-L1 — Legal coverage score.** `coverage_pct = 100 × required_present / required_total`. Inputs:
`legal_checklist` (16 rows; `present` recomputed by `fn_legal_ai` — slug rows resolve against `legal_documents.slug`,
clause rows against `bool_and(body_html ~* match_clause)` over `category='agreement'`). Output today **81.3**.
*Unmeasured:* the checklist tests **existence, not adequacy**. A slug row is `present` because a row with that slug
exists — nothing scores whether the document is fit. There is no adequacy dimension in this estate.

**M-L2 — Legal health index.** `legal_health = 0.35·coverage_pct + 0.30·terms_acceptance_avg + 0.20·freshness +
0.15·max(0, 100 − 10·open_legal_flags)`, where `terms_acceptance_avg = (customer_pct + supplier_pct)/2` and
`freshness = 100·(published − stale)/published`. Inputs: `legal_kpis`. Output today **78.5**, written to
`legal_kpi_snapshots`. *Unmeasured:* the index is dominated by a denominator of one customer and one supplier;
`customer_terms_acceptance_pct` of 0.0 is one unaccepted row, not a trend.

**M-L3 — Version-in-force resolver.** For an event at timestamp *t* and document *d*:
`version_in_force(d,t) = the legal_documents row for d whose effective_date ≤ t::date, latest first`. Inputs:
`legal_documents(slug, version, effective_date, content_sha256)`. *Unmeasured and load-bearing:* `legal_documents`
holds **one row per slug**, not a version history. Once `customer-terms` moves to v6 the v5 body is gone, and
`leads.accepted_terms_version = 'v5'` will point at nothing. **A version-history table does not exist and must be
built before the next version bump** — this is the single most consequential structural gap in this seat.

**M-L4 — Clause presence test.** For a required clause *c* with regex *r*:
`present(c) = bool_and(body_html ~* r) over legal_documents where category='agreement'`. Already implemented for
`legal_checklist` id 13, `match_clause = 'governing law\s*(and|&amp;|&)\s*jurisdiction'`. Deterministic and
extensible: every remaining checklist row that is a clause rather than a document becomes a regex.

**M-L5 — Drift scan.** For each active `policy_rules` row, `hits(r) = {d : d.body_html ~* r.forbid_regex}`.
`drift_score = Σ severity_weight(r)` over hits, with weights critical 10, high 5, medium 2, low 1. Measured today:
**0 hits, drift_score 0**. Inputs: `policy_rules` (7), `legal_documents` (12).

**M-L6 — Licence runway.** `days_to_expiry = company_registration.expires_on − current_date` = 2027-06-24 minus
today = **290 days**. Renewal band: `amber` at ≤ 90, `red` at ≤ 45, `critical` at ≤ 14. *Unmeasured:* the DET renewal
lead time is not stored anywhere; the bands above are this seat's proposal, not a measured requirement.

**M-L7 — Activity-scope test.** `in_scope(activity_text) = activity_text ~* any(licensed_activity_regex)` where the
regexes derive from `company_registration.activities` (722901 software design, 724003 Portal). A new revenue line is
in scope only if its description matches. *Unmeasured:* there is no table of DET activity codes and their permitted
scope; the two codes are stored as free text.

**M-L8 — Refund arithmetic (legal's read of it).** `refund_to_customer = reveal_fee = 0.03 × accepted_quote_value`.
`supplier_clawback = refund_to_customer + 250 + refund_to_customer × 0.09 × days_outstanding/365`. Inputs:
`decision_policy.refund_admin_fee_aed` 250, `.refund_late_fee_annual_pct` 9, `.refund_reveal_fee_pct` 3,
`pricing_config.refund_window_working_days` 5, `.chase_after_working_days` 3,
`.bank_settlement_working_days_min/max` 7/14. Legal's contribution is not the sum but the **authority for each
term**: clause 33 of the supplier agreement for the 250, and the per-annum framing of the 9%.
*Unmeasured:* zero refunds have occurred (`transactions` = 0), so the ladder has never been exercised.

**M-L9 — Trigger match.** For inbound text *x*: `triggered(x) = {p ∈ decision_policy.legal_triggers : x ~* p}`,
plus embedding fallback — `cos(embed_gte(x), embed_gte(p)) ≥ 0.78` corroborated by at least one shared content
lexeme, because a nearest neighbour is always found. Non-empty ⇒ route to `legal`, never auto-answer.
*Unmeasured:* the 0.78 floor is unvalidated in this estate; it must be calibrated against a labelled set before it
gates anything, and until then the lexical half alone governs.

**M-L10 — Review staleness.** `stale(review) = review.reviewed_at < document.updated_at` OR
`review.doc_sha ≠ document.content_sha256`. **The second half cannot be computed: `legal_reviews` has no sha or
version column.** Adding `reviewed_sha256 text` to `legal_reviews` is the cheapest fix in this whole file and it
retires a whole class of silent error.

**M-L11 — Regulatory-change to document mapping.** For a `compliance_sources` row whose `last_changed_at` moved,
`affected(d) = d whose keywords intersect the source's topic tokens`. Inputs: `compliance_sources.topic` (17 rows),
document keyword sets. *Does not exist:* `legal_documents` has no keyword column, so today `fn_legal_ai` raises one
undifferentiated `reg_change_review` flag naming a count, not a document. Measured: 3 of 17 sources have ever
recorded a change.

**M-L12 — Authority-band test.** `permitted(agent, action_class, aed) = exists employee_authority row with
max_tier ≥ required_tier(action_class) and (threshold_aed is null or aed ≤ threshold_aed)`, then the absolute
ceilings: `auto_action_max_aed` 0 for money movement, `financial_review_aed` 10,000 for human review, and
`founder_review_gates` for the only two things that reach the founder. Inputs: `employee_authority` (320 rows
estate-wide, 10 for this department), `decision_policy`.

### 3. Reasoning procedures

**P-L1 — "Is this charge contractually supported?" (L1, L2, L3)**
1. Read the payment event: amount, timestamp *t*, customer id.
2. `version_in_force('customer-terms', t)` via M-L3. If the customer's `accepted_terms_version` ≠ that version,
   **stop**: output *not supported*, name the version they accepted and the version in force, and open a task on
   `cs_retention` to re-accept before any further charge.
3. If versions match, locate the authorising clause by regex over `body_html` for the fee vocabulary
   (`reveal fee`, `3%`, `no cap`). Quote the matched sentence verbatim with its character offset.
4. Recompute the charge: `0.03 × accepted_quote_value`. If it differs from the amount charged by more than
   AED 0.01, output *supported clause, wrong amount* and name both figures.
5. Compose from the template: verdict, version, clause quote, arithmetic, the one action.
**Stops and refuses when:** no accepted version is recorded at all (today that is 100% of customers — 1 of 1 with
`customer_terms_acceptance_pct` 0.0); or the version in force at *t* is not retrievable because M-L3's history table
does not exist.

**P-L2 — "Has a live document drifted from a founder ruling?" (L5, L19, L20)**
1. Run M-L5 over all 12 documents × 7 rules. Today: 0 hits.
2. Independently check the founder's numeric constants against document text: reveal 3% (`pricing_config`),
   AED 1,000/yr after 1,000 registrants, AED 250 admin fee, 9% p.a., 5/3/7–14 working days. Each is a regex over the
   agreement bodies; a constant present in `pricing_config` and absent from both agreements is a *gap*, a constant
   present with a different value is a *contradiction*.
3. Rank: contradiction × critical first, then gap × critical, then by severity weight.
4. For each, name the document, the version, the sentence, and the `pricing_config` or `decision_policy` row that is
   canonical.
**Stops and refuses when:** the canonical value is itself absent (e.g. `supplier_charging_starts` is NULL by
founder ruling — a NULL is the answer, not a gap, and the procedure must not report it as drift).

**P-L3 — "Is QuotesDone a DNFBP?" (L13, L14)**
1. Read `company_registration.activities` — the only two licensed activities are 722901 and 724003.
2. Compare against the enumerated DNFBP activity classes held in a new `dnfbp_activity_class` table (real-estate
   brokerage; dealing in precious metals and stones; independent accounting and audit; company service provision;
   independent legal services in specified transactions). **That table does not exist and is deliverable one of
   this seat's Q1.**
3. Match: activity codes 722901 and 724003 fall in none of them, and the platform takes no client money, holds no
   escrow (`auto_action_max_aed` = 0), and transfers no title.
4. Determination: **not a DNFBP on its own account**; record it as a `phase_d_legal_assertion` citing a
   `phase_d_legal_source` row for the AML/CFT primary law and its DNFBP implementing decision. *Today
   `phase_d_legal_assertion` is empty and every `phase_d_legal_source` row is a ZZ DEMO fixture, so the machinery is
   there and the evidence is not.*
5. Second pass, supplier-facing: intersect `category_licence_activity` (20 rows) with the DNFBP classes. Four
   catalogue slugs land inside — `real-estate-agencies`, `accounting-and-audit-firms`, `law-firms`,
   `tax-consultants` — and each already carries the extra-approval note (RERA broker card, MoE auditor registration,
   MOJ/Legal Affairs registration, FTA tax-agent registration). Output: the platform's duty on these four is
   **verification of the sector registration on top of the trade licence**, not a reporting duty of its own.
**Stops and refuses when:** a supplier's activity text matches a DNFBP class but their catalogue slug does not —
that is a mismatch for `compliance_mgr`, not a determination.

**P-L4 — "Is this review still valid?" (L21, L31)**
1. For each `legal_reviews` row, resolve the document from `source` (`legal_document:<slug>` or `pasted`).
2. `pasted` ⇒ unresolvable ⇒ mark *unanchored*; two of the three rows are `pasted`.
3. For the resolvable row, compare `reviewed_at` (2026-07-09) with `legal_documents.updated_at` (2026-09-06).
   Reviewed before updated ⇒ **stale**.
4. Output: 1 stale, 2 unanchored, 0 current. **Every row in `legal_reviews` today fails this test.**
**Stops and refuses when:** asked whether the review's *findings* still apply — that is a reading of the new body
against the old findings and needs a model or a lawyer (§9).

**P-L5 — "Route or answer?" (L18, L29, L30)**
1. Apply M-L9 to the inbound text.
2. Non-empty trigger set ⇒ never auto-answer; create an `org_tasks` row on `dept_key='legal'`, `action_class` set
   from the trigger, and reply with the acknowledgement template only.
3. Apply M-L12: if the requested action is `refund_decision` or `refund_outside_policy`, it is the founder's — the
   only two things that are. Everything else resolves to its accountable role via `agent_action_kind_policy`
   (`legal_flag` and `compliance_update` both → `general_counsel`).
4. If the action is irreversible (publish, first supplier contact, refund, ban, schema change — `governance_policy`
   #12), require a second reviewer before it executes.
**Stops and refuses when:** the trigger matched only on the embedding half with no shared lexeme — that is a
near-neighbour artefact, and the seat says so rather than escalating noise.

**P-L6 — "Which gap do we close first?" (L7, L40)**
1. For each of the 3 absent checklist rows and the 5 structural gaps in the baseline, compute
   `exposure = P(event in 12 months) × cost_if_it_happens`, both from a stored table of the seat's own
   standing estimates, never invented per question.
2. Compute `effort_days` from a stored estimate.
3. Rank by `exposure / effort_days`.
4. Publish the ranking with every input visible, so the founder disagrees with a number rather than a conclusion.
**Stops and refuses when:** the exposure table has no row for the gap — the honest output is *"I have no stored
estimate for this; here is the task to produce one."*

**P-L7 — "Is the licence wide enough for a new revenue line?" (L10, L12)**
1. Take the line's plain description.
2. M-L7 against 722901 and 724003.
3. Match ⇒ *in scope, on the stored reading of these two codes*, and say plainly that the reading is ours, not DET's.
4. No match ⇒ *out of scope on the stored reading*; open a task to obtain the DET activity list and, if still out of
   scope, an activity amendment — remembering the DE@AE Tier 1 condition on record: **no change of address or
   details without DET approval**.
**Stops and refuses when:** the line involves holding customer money — escrow, client accounts and payment
facilitation change the regulator, not just the activity code, and the seat must escalate rather than opine.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JL1 | A charge is made and no accepted terms version is on record for that party | **refuse the charge** | an unaccepted contract is not a contract; today this is 1 of 1 customers |
| JL2 | A document version bump is proposed and no version-history table exists | **block the bump** | v5 disappears the moment v6 is written and `leads.accepted_terms_version` becomes a dangling pointer |
| JL3 | `legal_checklist.present` is true but the document has never been read by a licensed human | **report coverage with the caveat in the same sentence** | 81.3% measures existence, not adequacy; a bare 81.3% is a misleading number |
| JL4 | An inbound message matches any of the 10 `legal_triggers` | **never auto-answer; route to `legal`** | founder-configured; a dispute or subpoena answered by a template is a worse fact than silence |
| JL5 | An action is `refund_decision` or `refund_outside_policy` | **founder, always, any amount** | founder ruling 17 Aug 2026, restated 5 and 6 Sep 2026 |
| JL6 | Any other matter looks important enough to "just check with the founder" | **do not** — resolve it to the accountable role | the same rulings; escalating outside the gate is as much a breach as skipping it |
| JL7 | A supplier's licence is absent or expired | **no RFQ may reach them** | `governance_policy` #15; measured: 1 of 22,265 leads has a licence number recorded |
| JL8 | A published claim cannot be substantiated from a table in this estate | **do not publish** | `governance_policy` #1, *no fabricated facts* |
| JL9 | A `legal_reviews` row is stale or unanchored | **do not cite it** | all 3 rows fail today; citing one is citing a review of a document that no longer exists |
| JL10 | A number would be reported that measures an empty marketplace | **report the emptiness, not the number** | 0 inquiries, 0 quotes, 0 transactions; a zero here is not performance |
| JL11 | A retention question has no bucket in `retention_policy` | **refuse and open a task to classify** | 11 buckets exist; inventing a twelfth in an answer creates policy by accident |
| JL12 | Tax records younger than 2,555 days would be deleted | **refuse** | `retention_policy` classes `tax`; UAE 7-year record-keeping |
| JL13 | A litigation hold is live | **suspend every retention deletion in scope, even overdue ones** | ordinary retention destroying evidence is the classic own-goal |
| JL14 | An irreversible action arrives with one reviewer | **hold** | `governance_policy` #12 |
| JL15 | A decision scores well but relies on a `phase_d_legal_source` row whose `authority_tier` is `NON_AUTHORITATIVE` or whose `review_by` has passed | **do not assert it** | a consultancy blog and an expired circular are the two fixtures already sitting in that table as the worked example |
| JL16 | The trade licence is inside 45 days of expiry | **red: nothing else in this seat outranks the renewal** | 290 days today; every supplier and customer contract depends on the licence |
| JL17 | A proposed clause improves our position but makes a headline metric fall (e.g. tightening the checklist drops coverage below 81.3%) | **make the change and say the number fell, with the reason** | the founder's standing rule; a metric protected from truth is worthless |
| JL18 | A supplier contract offers a benefit in exchange for exclusivity or a most-favoured-nation term | **refuse** even if it scores well | the marketplace's value is neutrality; an exclusivity is unwindable only by breach |
| JL19 | A regulator, court or authority is the counterparty | **nothing goes out without the CEO and a named signer** | a written admission cannot be withdrawn |
| JL20 | An answer would rest on a legal position with no stored primary source | **refuse and name the source needed** | `phase_d_legal_assertion` exists precisely to make this impossible to skip |
| JL21 | The question is US or non-UAE/GCC law | **out of scope** | standing rule on record |
| JL22 | A model would be needed to answer | **say so in the answer and open the task**, never approximate | the founder's constraint is that the seat works with OpenRouter off; a quiet approximation breaks it silently |

### 5. Technical knowledge

- **The registry.** `legal_documents(slug, title, category, version, effective_date, summary, body_html, updated_at,
  content_sha256, source)`. `trg_legal_documents_hash` maintains the hash; `trg_pages_legal_sync` keeps the two
  agreement rows in step with `pages.legal_terms_body` / `pages.legal_supplier_body`;
  `fn_legal_version_bump(p_version text)` and `fn_legal_body_without_labels(p_html text)` are the supporting
  routines. Categories in use: `agreement`, `internal`, `public`.
- **The daily routine.** `fn_legal_ai()` — SECURITY DEFINER, pure SQL and plpgsql, **no model call anywhere in its
  body**. It recomputes `legal_checklist.present`, reads `legal_kpis`, computes M-L2, upserts
  `legal_kpi_snapshots`, and raises five `leg_flag` escalations: `missing_core_docs`, `supplier_terms_acceptance`,
  `customer_terms_acceptance`, `stale_policies`, `reg_change_review`. Cron `legal_ai_daily` jobid 76, `15 5 * * *`,
  active. This is the proof that the seat's core loop already runs model-free.
- **The publication path.** Public pages live in `public.pages`; routes under `src/app/[locale]/` are
  `terms`, `privacy`, `cookie-policy`, `refund-policy`, `acceptable-use`, `disclaimer`, `complaints`,
  `supplier-agreement`, `contact`. A legal edit is a `pages` edit that syncs to `legal_documents`, not the reverse.
- **Escalation mechanics.** `agent_actions` with `kind='legal_flag'`; `agent_action_kind_policy` sets policy
  `notify` and authority role `general_counsel`. `founder_mail_policy` governs what may be emailed to the founder at
  all; a new kind without a policy row cannot be emailed. `fn_notify_founder` requires `p_kind`.
- **Authority tables.** `employee_authority` for this seat: `compliance_check` gated / AED 10,000,
  `legal_review` advisory / AED 10,000, `pdpl_action` gated / AED 10,000. `decision_policy` for the absolute
  ceilings. `governance_policy` for the 16 standing rules.
- **The evidence chain.** `phase_d_legal_source` (source_id, jurisdiction, subject, source_type, authority_tier,
  authority_name, source_reference, content_sha256, published_on, effective_from, retrieved_at, review_by,
  freshness_policy, superseded_by, evidence_owner, reviewer_role_id, trace_id) and `phase_d_legal_assertion`
  (subject, jurisdiction, position_summary, source_id, requires_authoritative, asserted_by_role_id, reviewer_role_id).
  Guards: `fn_phase_d_legal_source_current(source_id, require_authoritative, as_of)` and
  `fn_phase_d_legal_assertion_source_is_current()`.
- **Formats it must parse without a model.** HTML bodies (regex and clause offsets), the `pages`/`legal_documents`
  sync shape, ISO dates, `jsonb` risk flags, `content_sha256` hex.
- **What must be stored so the seat never has to ask.** The DET licence record (present), the founder's standing
  decisions (present, `company_policy_decision`, 15 rows), the pricing constants (present, `pricing_config`), the
  refund ladder (present, `decision_policy` + `qd-company:refunds`), the retention buckets (present).
  **Absent and needed:** a document version history; a clause index (clause id → document → offset → topic);
  a `dnfbp_activity_class` table; a `reviewed_sha256` column on `legal_reviews`; a keyword column on
  `legal_documents` to make M-L11 specific.

### 6. Academic knowledge

Disciplines this seat generalises from: contract law and the civil-law tradition of obligations; commercial and
company law; consumer-protection and e-commerce regulation; data-protection law; AML/CFT; competition and
advertising standards; private international law (choice of law and forum); dispute resolution and arbitration.

Lawful primary sources we may ingest (each is a public official publication; **no copyrighted study texts, and no US
material — out of scope by standing rule**):

| framework | lawful primary source to ingest |
|---|---|
| UAE federal legislation as enacted | the UAE Official Gazette and the federal legislation portal maintained by the Ministry of Justice |
| Consumer protection and e-commerce | the Ministry of Economy's published consumer-protection material and its implementing regulations |
| Data protection (PDPL 45/2021) | the UAE Data Office's own published law text and guidance |
| AML/CFT and the DNFBP classes | the Executive Office for Control & Non-Proliferation and the National Committee's published guidance; the UAE Local Terrorist List publication already ingested as `screening_run.source = 'uae_local_terrorist_list'` |
| Sanctions | the UN Security Council consolidated list XML, already ingested (`screening_run.source = 'un_consolidated'`, 4,157 entries) |
| Licensing scope and activity codes | Dubai DET's published activity list and the DE@AE Tier 1 conditions; `invest.dubai.ae` verification, named in `company_registration.license_class_note` |
| Sector regulators our catalogue touches | the 17 authority sources already in `compliance_sources` — DCD, DEWA, SIRA, DM, DMT, RTA, TDRA, SEWA, Trakhees, DHA, FEWA/EtihadWE, DDA, DoH, MoIAT, Sharjah Municipality |
| Governance, risk and compliance theory | ISO 31000 and ISO 37301 as published standards; COSO's public framework summaries |
| Contract drafting discipline | published model forms from standards bodies (e.g. FIDIC's public descriptions of its suites) — descriptions and structure only, never the copyrighted forms |

**Certifications on record** (`public.role_certification`, both created 2026-09-07 06:06 UTC):

- **ICA International Diploma in Governance, Risk and Compliance** (ICA), pass mark 50%, rank 1. Syllabus areas:
  Understanding Governance Risk and Compliance; The Regulatory Environment; Risk Management Frameworks; Compliance
  Frameworks and Culture; Financial Crime Prevention; Managing the Compliance Function.
- **CIPP/E** (IAPP), pass mark 70%, rank 2. Syllabus areas: Data Protection Laws; Personal Data; Controllers and
  Processors; Processing Personal Data; Information Provision Obligations; Rights of Data Subjects; International
  Data Transfers; Supervision and Enforcement.

**Syllabus areas failed: does not exist.** `certification_exam_result` holds **no row for `legal`** — this seat has
never sat either exam, so there is no weakest-area evidence to target. The first act of the learning plan is to sit
both, deterministically (`method` in the existing rows is `lexical` or `semantic`, both model-free), and let the
`weakest_areas` jsonb choose the study order rather than a guess.

### 7. Corporate knowledge

- **The founder's boundary.** Nothing routes to him except Stripe refunds (`decision_policy.founder_review_gates`,
  `company_policy_decision.every_refund_is_the_founders`, `.founder_standing_rules`). He is emailed exceptions only,
  under `founder_mail_policy`. He is never asked a technical question. Where it lives: `company_policy_decision`
  (15 rows), `decision_policy`, `qd-company:decisions`.
- **The commercial facts.** Reveal 3%, no discount, no cap, enforced by constraint
  `pricing_config_no_discount_no_cap_ck`. Supplier registration free to 1,000 then AED 1,000/yr, **no date** —
  charging starts at registration 1,001. Refund ladder 5/3, founder's call on day five, banks 7–14 working days,
  AED 250 admin fee to the supplier, 9% **per annum** interest. Where: `pricing_config`, `decision_policy`,
  `qd-company:commercials`, `qd-company:refunds`, Supplier Agreement clause 33.
- **The identity facts.** DET Trader Licence 1633275, expiring 2027-06-24; not VAT-registered, no TRN, threshold
  AED 375,000; corporate tax not registered and not required; **no auditor and none required**. Never re-ask any of
  these. Where: `company_registration`, `qd-company:registration`, `company_policy_decision.auditor` /
  `.corporate_tax`.
- **The product's central promise.** Anonymity until a paid reveal. `governance_policy` #4 makes any pre-reveal leak
  of a supplier name, phone, email, domain or licence number a **P0 defect**. This is a legal fact as much as a
  product one: it is what the reveal fee is consideration for.
- **Hand-offs.** To `compliance_mgr`: PDPL, sanctions, licence-activity, the regulatory calendar. To
  `trust_safety_mgr`: suspension, ban, fraud disposition. To `moderation_specialist`: published wording, redaction,
  pre-reveal payload. To `cfo`: refund arithmetic, VAT and corporate-tax thresholds. To `ceo`: anything touching a
  regulator or a court. From `cs_support`: every one of the 10 `legal_triggers`.
- **History it must not forget.** The pivot from a 2% capped reveal fee to 3% uncapped — `policy_rules` id 7 exists
  solely to stop the old wording reappearing, and `legal_reviews` id 1 is a surviving artefact of the old world.
  The 6 Sep 2026 correction of `legal_checklist` id 1, which pointed at a slug `terms-of-service` that never existed
  (recorded in its own `notes`). The 4 Sep 2026 merge of `contract_specialist` into this seat, which is why
  `employee_kpi` carries three ghost objectives here.
- **Does not exist:** a matter register, a counterparty register, a contract repository beyond the two agreements,
  a signature/e-signature record beyond `leads.signed_terms_path` / `.signed_terms_at`, and any record of legal
  advice ever taken from a licensed UAE lawyer.

### 8. One-year plan

**The company target.** `company_goals.revenue_annual` = AED 1,000,000 recognised revenue in the trailing 12 months
by **2027-08-31**, owned by `finance`. Two revenue lines exist in `pricing_config`:

- **Reveal fees.** 3% of accepted quote value, uncapped. AED 1,000,000 ÷ 0.03 = **AED 33,333,333 of accepted quote
  value** must pass through the platform in the year.
- **Supplier registrations.** AED 1,000/year, beginning at registration number 1,001. At the founder's stated target
  of **300 registrations a month**, registration 1,001 arrives in month four of outreach; the following eight months
  would produce ~2,400 chargeable registrations = **AED 2,400,000**. On the founder's own supply target the
  registration line alone clears the AED 1,000,000 — *if* the fee is billed and collected.
  Measured today: **1 registered supplier, 0 chargeable.**

**This seat's slice: AED 0 of direct revenue, and a veto over both lines.** Stating a revenue slice for the General
Counsel would be fiction. Its honest slice is *the share of that revenue that is collectible and defensible*, and
today that share is **not yet 100% on either line**:

- The reveal line rests on the customer having accepted the terms in force. `customer_terms_acceptance_pct` is
  **0.0**. Until acceptance is recorded and versioned, **100% of prospective reveal revenue rests on an unrecorded
  acceptance**, and M-L3 cannot even reconstruct which version was in force.
- The registration line rests on a supplier agreement that will be at v8 or later when the first invoice is raised,
  against suppliers who accepted an earlier version. With no version history, the company cannot prove what any
  supplier agreed to.

**Metrics this seat owns (three, all measurable today or by a named instrument):**

1. **Terms-acceptance integrity** = `100 × (parties whose accepted version = version in force at their last
   chargeable event) / (parties with a chargeable event)`. Instrument: the version-history table (Q1). Today:
   unmeasurable; the closest live proxy is `customer_terms_acceptance_pct` **0.0** and
   `supplier_terms_acceptance_pct` **100.0** (n=1).
2. **Legal coverage** = `legal_kpis.coverage_pct`. Today **81.3**. Target 100 by 2027-05-31, which means closing
   checklist rows 14, 15 and 16.
3. **Anchored-review rate** = `100 × current reviews / total reviews`, where *current* needs the `reviewed_sha256`
   column. Today **0%** (1 stale, 2 unanchored, 0 current).

**Quarterly milestones**

- **Q1, Sep–Nov 2026.** Ship the version-history table for `legal_documents` and backfill v5/v8 (retires JL2 and
  makes M-L3 computable). Add `reviewed_sha256` to `legal_reviews`. Write and store the **DNFBP determination**
  as a `phase_d_legal_assertion` with a real, non-fixture `phase_d_legal_source` — the first real row that table
  has ever held. Build `dnfbp_activity_class`. Sit both certification exams so §6 stops saying *does not exist*.
- **Q2, Dec 2026–Feb 2027.** Close checklist id 14 (IP / content-ownership) before supplier catalogue upload opens,
  and id 15 (NDA / confidentiality) before any redacted drawing reaches a supplier — both are prerequisites for
  supply, so they gate the registration line. Build the clause index so P-L1 can quote a clause by id, not by regex
  luck. Add keywords to `legal_documents` so M-L11 names a document instead of a count.
- **Q3, Mar–May 2027.** Close checklist id 16 (e-commerce / consumer-protection statement). Take coverage to 100.
  Build the incident register that `company_goals.data_breaches` and `.compliance_violations` say does not exist,
  so two of this seat's four goals become measurable for the first time. **Start the DET licence renewal at
  2027-03-26 (90 days out); red line 2027-05-10 (45 days).**
- **Q4, Jun–Aug 2027.** Licence renewed before 2027-06-24. Annual review of all 12 documents against the version
  history. Report the year with `terms-acceptance integrity` as the headline, and say plainly whether the revenue
  that arrived was collected under terms the parties had accepted.

**Capacity check — can this seat produce that number?** The seat produces no revenue, so the question is whether it
can *stop being the constraint*, and the arithmetic says yes with room. Its recurring load is a daily
`fn_legal_ai()` run (already automated, already model-free, ~seconds) plus per-event checks that are all table
lookups. At the founder's 300 registrations a month, the terms-version check is 300 lookups a month — nothing.
At AED 33.3m of quote flow with a median accepted quote of, say, AED 50,000, that is ~667 reveals in the year,
~56 a month, ~3 per working day: again nothing. **The seat's capacity is not the constraint; its
instrument-building backlog is.** Every gap named above is a build task measured in days, not a throughput problem.

**Dependencies.** `product_eng` for the version-history and clause-index migrations and for the PDPL entry point.
`compliance_mgr` for the DNFBP evidence and the regulatory calendar. `supply` for the licence data that makes
JL7 meaningful — 1 of 22,265 leads has a licence number today, and until that changes every downstream legal control
is inert. `finance` for the refund arithmetic and the registration invoicing that turns the second revenue line on.

**Is the slice achievable?** Yes, and it is not where the risk lives. The risk to AED 1,000,000 is supply and
demand, not law. But two legal facts can invalidate revenue after it arrives — an unrecorded terms acceptance and a
missing version history — and both are cheap to fix now and impossible to fix retrospectively. That is the argument
for doing Q1 first.

### 9. What this seat cannot do without a model

1. **Draft new contractual language.** Composing a fresh IP-assignment or confidentiality clause is generative.
   Model-free fallback: assemble from a stored, human-approved clause library, and refuse where no clause exists.
   The clause library does not exist yet.
2. **Read an unstructured third-party contract and find the unacceptable term** (L22). Regex finds vocabulary, not
   meaning; an indemnity can be written without the word *indemnity*. Model-free fallback: a red-flag term list plus
   an honest *"this needs a lawyer"*, which is what `legal_reviews.needs_licensed_review = true` already records on
   all three rows.
3. **Judge whether a stale review's findings still apply to a rewritten body** (P-L4 step 4).
4. **Decide whether a limitation-of-liability clause survives against a particular counterparty** (L34) — that is
   legal advice, and no amount of arithmetic substitutes for it.
5. **Compose a response to a regulator or a court** (L35). This should never be automated at all, model or not.
6. **Interpret an ambiguous statutory provision.** The seat can retrieve and cite a stored primary source; it cannot
   resolve an ambiguity in one. Where it matters, `phase_d_legal_assertion.requires_authoritative` is the switch
   that forces a refusal instead of an opinion.

---

## compliance_mgr — Compliance & Privacy Officer

Reports to `legal`. `routing_tier` reviewer_auditor, with **independent stop authority** granted 14 Aug 2026:
*"this role may block unsafe work in its domain and may never approve work it authored."* Responsibilities on
record: *owns UAE regulatory compliance including PDPL and marketplace policy.* Named in
`company_policy_decision.supplier_acquisition_and_screening` as the seat that *checks the sanctions list*.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | cost of a wrong answer |
|---|---|---|---|---|---|
| C1 | Does this supplier or its owner match a sanctions or terrorist-list entry? | gate | every registration | supply, `bd` | onboarding a listed party |
| C2 | Is a name match a true hit or a common-name collision? | diagnosis | per hit | itself | a false positive that kills a legitimate supplier, or a false negative |
| C3 | Is the screening list current enough to screen against? | gate | weekly | itself | screening against a stale list is worse than not screening, because it produces a clean answer |
| C4 | Has the UAE local list changed since the last run, and who must be re-screened? | diagnosis | weekly | itself | a party listed after their onboarding stays on the platform |
| C5 | Does the supplier's licensed activity cover the category they registered in? | gate | every registration | supply | facilitating unlicensed trade in a regulated category |
| C6 | Does this category need a sector approval on top of the trade licence? | gate | per category | supply | a SIRA, RERA, Civil Defence or FTA requirement missed |
| C7 | Is the trade licence unexpired, and how many days remain? | gate | daily | supply | RFQs sent to a supplier with a dead licence |
| C8 | Which suppliers' licences expire in the next 30/60/90 days? | forecast | weekly | supply, `bd` | a wave of blocked suppliers with no warning |
| C9 | Is this personal data being processed for a purpose we have a lawful basis for? | gate | per new data flow | product, `cto` | processing without a basis |
| C10 | What is the lawful basis for each field we collect, and where is it recorded? | craft | per field | itself, `legal` | a privacy notice that does not match what the database does |
| C11 | Does the privacy policy accurately describe what the database actually stores? | diagnosis | quarterly | itself | a notice that is a fiction; the worst kind of privacy failure |
| C12 | Has a data-subject request arrived, and what is the response clock? | escalation | per request | `cs_support` | a missed statutory response window |
| C13 | Which tables and buckets hold data for this data subject? | diagnosis | per request | itself | an incomplete export or erasure |
| C14 | Can this erasure be executed, or does a retention obligation override it? | gate | per erasure | itself, `cfo` | deleting a tax record, or refusing an erasure without a lawful ground |
| C15 | Is a cross-border transfer happening, and to where? | gate | per vendor | `cto` | an uncovered transfer |
| C16 | Does a new processor need a written processing agreement before it is switched on? | gate | per vendor | `cto` | live processing with no contract |
| C17 | Has an incident occurred that meets the notification threshold? | escalation | per incident | `cto`, `security` | a missed notification |
| C18 | Which retention bucket governs this artefact, and is anything overdue for destruction? | allocation | monthly | `it` | data kept past its purpose |
| C19 | Is consent recorded for each purpose we rely on consent for? | gate | per purpose | itself | consent asserted with no record |
| C20 | Is the cookie banner's behaviour consistent with the cookie policy? | diagnosis | quarterly | product | a policy that describes a banner we do not have |
| C21 | Does a marketing send have a lawful basis and an opt-out? | gate | per campaign | `growth` | an unlawful send at scale |
| C22 | Which of the 17 monitored authority sources changed, and what does it touch? | diagnosis | daily | itself, `legal` | a regulatory change nobody read |
| C23 | Is a monitored source still reachable, or has the monitor gone quiet? | diagnosis | weekly | itself | a dead monitor that reports "no change" forever |
| C24 | What is on the regulatory calendar in the next 30 days? | forecast | weekly | `legal`, `cfo` | a missed deadline; `company_goals.regulatory_deadlines` has no instrument today |
| C25 | Is the company approaching the VAT registration threshold? | forecast | monthly | `cfo` | a late VAT registration |
| C26 | Is QuotesDone required to register under the AML/CFT regime? | gate | once, then on change | `legal` | a registration duty missed, or a programme built for no duty |
| C27 | Does a supplier's own DNFBP status create any duty for us? | diagnosis | per DNFBP-category registration | `legal`, supply | onboarding a regulated profession without its sector registration |
| C28 | Is a customer-facing claim about "verified suppliers" true given what we actually verify? | gate | per campaign | `growth` | a misleading claim about verification |
| C29 | Does a payment flow make us a payment intermediary? | escalation | per payment change | `cfo`, `legal` | an unlicensed regulated activity |
| C30 | Has an agent acted outside its `employee_authority` band? | gate | weekly | `chief_of_staff` | an authority breach nobody caught |
| C31 | Is a SECURITY DEFINER routine executable by `anon` or `public`? | gate | per deploy | `cto` | the exact failure `risk_register` id 16 records |
| C32 | Are the 16 `governance_policy` rules each actually enforced by what their `enforced_by` claims? | diagnosis | quarterly | itself | a control that exists only as a sentence |
| C33 | Which controls are `enforcement='declared'` rather than `'database'` or `'code'`? | diagnosis | quarterly | `legal` | mistaking a declaration for a control |
| C34 | Has the compliance checklist coverage moved, and why? | diagnosis | daily | `legal` | a coverage change with no cause on record |
| C35 | Is a proposed data field necessary, or is it collected because it is available? | gate | per schema change | product | `governance_policy` #5, minimum data |
| C36 | Is buyer contact data about to enter a prompt where a reference id would do? | gate | per integration | `cto` | `governance_policy` #5 again — and the only remaining model-adjacent path |
| C37 | Do we hold a supplier's Emirates ID, DOB or bank details, and is that proportionate? | gate | quarterly | itself | holding identity documents with no basis |
| C38 | Is a screening hit's disposition documented well enough to survive an audit? | craft | per hit | itself | a decision with no reasoning on record |
| C39 | Which compliance obligation has no owner? | diagnosis | quarterly | `legal` | an obligation everybody assumes somebody else holds |
| C40 | Is the estate's evidence for a compliance claim a real source or a fixture? | gate | per claim | `legal` | citing `zz-demo-fta-corporate-tax-current` as if it were the FTA |

### 2. Domain logic

**M-C1 — Name screening.** For a supplier field value *v* and a screening entry *e*:
`norm(v) = lower(unaccent(trim(regexp_replace(v,'[^[:alnum:] ]',' ','g'))))`;
`tokens(v) = distinct words of norm(v) with length ≥ 3`;
`score(v,e) = |tokens(v) ∩ e.tokens| / |tokens(v) ∪ e.tokens|` (Jaccard), with `match_kind = 'exact'` when
`norm(v) = e.name_norm`, `'token'` when `score ≥ 0.60`, `'weak'` when `0.40 ≤ score < 0.60`.
Inputs: `leads.company_name`, `.contact_name`, `.signatory_name`, `.bank_account_name`; `screening_entry`
(**4,961 rows**, `name_norm` and `tokens` already materialised). Output: `supplier_screening_hit` rows.
Existing routine: `fn_supplier_sanctions_screen(p_run_ids bigint[], p_rehearsal_tag text)`.
*Measured:* `supplier_screening_hit` = **0 rows**, consistent with 1 registered supplier.
*Unmeasured:* no threshold in this model has been calibrated against a labelled set, because there has never been a
hit. The Jaccard cut-offs above are a proposal, and the seat must say so whenever it reports a rate.

**M-C2 — List currency.** `list_age_days = current_date − max(screening_run.fetched_at)::date` per source.
Green ≤ 7, amber 8–14, red > 14. Measured 2026-09-07: both sources fetched **the same day**, age 0.
`sha256` per run makes "did the list change?" a string comparison: the UAE list has held sha `0811418a…` across
runs 23, 25 and 27; the UN list `683c29b7…` across 24 and 26. **Nothing has changed since 6 Sep**, and that is a
measured fact rather than an absence of monitoring.

**M-C3 — Re-screen population.** When a run's `sha256` differs from the previous run of the same source,
`rescreen = every lead with approval_status='approved' or registration_status is not null`. Today that population is
**1**. Cost is linear in leads × new entries; with 4,961 entries and a token index it is a single set operation.

**M-C4 — Licence-activity match.** `activity_ok(lead) = lead.license_activity ~ (select activity_regex from
category_licence_activity where catalog_slug = lead.category)`. Existing routine:
`fn_check_licence_activity(p_subject_id, p_content)`. Inputs: `category_licence_activity` (**20 rows**),
`leads.license_activity`. *Measured:* **0 of 22,265 leads carry a `license_activity` value**, so this control has
never fired on real data. `leads.licence_gate_reason` is likewise 0.

**M-C5 — Licence expiry ladder.** `days_left = license_expiry − current_date`. Bands: notify at 90, chase at 60,
warn at 30, `matching_blocked = true` at 0. Routines that exist: `fn_check_licence_expiry`,
`fn_supplier_licence_gate(p_license_doc_path, p_trade_license_no, p_license_expiry)`,
`fn_reconcile_licence_blocks(p_grace_days)`, `fn_leads_licence_gate_rerun()`. *Measured:* 1 lead has an expiry,
0 expired, 3 `matching_blocked`, and the reconciler's cron (`licence_block_reconcile_daily`, jobid 100) is
**inactive**.

**M-C6 — Data-subject scope map.** For an email *e*, the set of (table, column, row-count) touched.
`fn_pdpl_export(p_email)` and `fn_pdpl_erase_plan(p_email)` already compute it; `fn_pdpl_redact(p_request_id)`
executes. *Measured:* `pdpl_requests` **0 rows**, `pdpl_erase_files` **0 rows**, and **nothing in `src/` calls the
`pdpl_request` or `pdpl_erase` edge functions.** The map exists; the door does not.

**M-C7 — Erasure-vs-retention conflict.** For each table in the scope map, `blocked = retention_policy.class in
('tax','legal','compliance') or retention_days is null`. Erasure proceeds on the rest and returns an itemised
refusal for the blocked part with the bucket and the reason. Inputs: `retention_policy` (11 rows).

**M-C8 — Source-change detector.** For each `compliance_sources` row, the monitor already stores `last_signature`
(file etag/size/mod, or `text:<sha1>`). `changed = new_signature ≠ last_signature`. *Measured:* all 17 last checked
**2026-08-10** — nearly a month ago — and `agent_compliance_weekly` (jobid 9) is **inactive**. One source
(Dubai Civil Defence) is unreachable with `note = 'reader unreachable (422)'`. **A monitor that has not run for
28 days reports "no change" indistinguishably from a monitor that ran and found none** — the detector needs a
liveness assertion, not just a change assertion.

**M-C9 — Regulatory calendar.** `due_in_days = obligation.due_date − current_date` over a table of obligations
(licence renewal, VAT threshold review, annual policy review, screening cadence). **The obligations table does not
exist**; `company_goals.regulatory_deadlines` says so in its own `no_measure_reason`. The only computable obligation
today is the licence: **2027-06-24, 290 days out**.

**M-C10 — VAT threshold watch.** `headroom = 375,000 − trailing_12m_taxable_supplies`. Inputs:
`company_registration.vat_threshold_aed` (375,000), revenue from finance. Bands: amber at 80% of threshold
(AED 300,000), red at 95% (AED 356,250). *Measured:* `transactions` = 0, so headroom is the full AED 375,000.
Note the interaction with the year-one plan: **AED 1,000,000 of revenue crosses this threshold by a factor of
2.7**, so the VAT registration is not a distant question — it is a mid-year certainty if the target is met.

**M-C11 — Control-reality test.** For each `governance_policy` row, `real = (enforcement in ('database','code'))
and (the artefact named in enforced_by exists)`. Measured composition of the 16 rows: **8 `database`, 3 `code`,
3 `declared`, 2 `process`**. The five `declared`/`process` rows are policies with no mechanism — including
*Minimum data* and *Documents retention*, both owned by `legal`.

**M-C12 — Authority-drift check.** Compare `employee_authority` against the actions actually taken in
`agent_actions` / `os_audit_log` (31,002 rows) / `security_audit_log` (2,956 rows). `drift = actions whose
action_class has no permitting row for that agent`. Deterministic set difference.

### 3. Reasoning procedures

**P-C1 — Screen a supplier registration (C1, C2, C38)**
1. Assert list currency by M-C2. If any source is red (> 14 days), **refuse to certify the registration** and say
   the list is stale — do not screen and return clean.
2. Extract the four name fields from the lead; normalise; tokenise.
3. Join against `screening_entry` on shared tokens; compute Jaccard; keep `score ≥ 0.40`.
4. Rank hits: exact > token > weak; within a band, by `entry_type` (entity before individual for a company name).
5. For each hit, write a `supplier_screening_hit` row carrying `entry_source`, `entry_reference`, `match_kind` and
   `score` — the reference is what makes the decision auditable against the published list.
6. Disposition: **exact ⇒ block and escalate to `legal`**; **token ⇒ block pending review**; **weak ⇒ pass with the
   hit recorded**, never silently dropped.
7. Compose: verdict, list versions with their sha256 and fetch timestamps, the hits with references, the action.
**Stops and refuses when:** any of the four name fields is null (a screen on a partial identity is not a screen);
or the name normalises to fewer than two tokens of length ≥ 3 (a one-word company name cannot be Jaccard-scored
safely).

**P-C2 — Admit a supplier to a category (C5, C6, C7, C27)**
1. Licence present and unexpired (M-C5). Absent or expired ⇒ **refuse**, cite `governance_policy` #15.
2. `activity_ok` by M-C4. Mismatch ⇒ refuse, quoting the lead's `license_activity` text and the
   `category_licence_activity.activity_regex` it failed.
3. Read the `note` on that catalogue row. Non-null ⇒ a sector approval is required on top of the licence
   (SIRA, Civil Defence, RERA, MoE, FTA, MOCCAE, DET tourism, municipality food). Require the document.
4. If the slug is one of the four DNFBP-adjacent ones (`real-estate-agencies`, `accounting-and-audit-firms`,
   `law-firms`, `tax-consultants`), additionally require the sector registration, and record the requirement against
   the `legal` seat's DNFBP determination.
5. Admit, and set the expiry ladder (M-C5) so the admission has an end date.
**Stops and refuses when:** `license_activity` is null — which is **every one of the 22,265 leads today**. The
honest output is *"the licence activity text has not been extracted; here is the task to extract it"*, not a pass.

**P-C3 — Handle a data-subject request (C12, C13, C14)**
1. Verify the requester controls the email — email is the identity; a phone may confirm but never select.
2. Run `fn_pdpl_export(p_email)` for the scope map (M-C6).
3. For access: return the map and the data.
4. For erasure: apply M-C7. Produce two lists — **erasable** and **retained, with the bucket and class that
   overrides**. Never a silent partial.
5. Execute via `fn_pdpl_redact(p_request_id)`; record files touched in `pdpl_erase_files`.
6. Log the response and the clock.
**Stops and refuses when:** the request arrives by a channel that has no `pdpl_requests` row — which is **every
channel today**, because nothing in the app writes to that table. The immediate deliverable is the entry point,
not the procedure.

**P-C4 — Weekly regulatory scan (C22, C23, C24)**
1. **Liveness first** (M-C8): if `max(last_checked_at)` is older than the cadence, the answer to *"what changed?"*
   is *"the monitor has not run since 2026-08-10 and `agent_compliance_weekly` is inactive"* — not *"nothing"*.
2. For live sources, compare signatures; collect changed rows.
3. Map each change to documents by topic-token intersection (M-L11) — today this returns a count, not a document.
4. Raise one `compliance_update` per changed source, routed to `general_counsel` per
   `agent_action_kind_policy`.
5. Report the unreachable source (Dubai Civil Defence, 422) every single week until it is fixed or retired. A
   permanently failing monitor that stops being reported becomes an absence of monitoring.

**P-C5 — Prove a control is real (C32, C33, C39)**
1. For each `governance_policy` row apply M-C11.
2. For `database` rows, verify the named artefact exists (trigger, constraint, table).
3. For `code` rows, verify the named check runs in CI or a cron that is **active** — this is where most failures
   will be, given seven of the nine legal-adjacent crons are inactive.
4. For `declared`/`process` rows, output them as *declared, not enforced*, with no softening.
5. Rank the unenforced by the exposure model and hand the list to `legal`.

**P-C6 — VAT threshold watch (C25)**
1. Read trailing-12-month taxable supplies from finance.
2. M-C10. Report headroom in AED and in months at the current run rate.
3. At amber (AED 300,000), open the registration task on the CFO. **Do not ask the founder** — his ruling of
   6 Sep 2026 says the CFO opens the task when revenue approaches the threshold.
**Stops and refuses when:** the run rate is computed from fewer than three months of data — a 30-day total is not
a run rate.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JC1 | Any screening list is more than 14 days old | **refuse to certify any registration** | a clean answer from a stale list is a false negative wearing a green badge |
| JC2 | Exact name match against any list | **block, escalate to `legal`, never auto-clear** | the one place a false negative is unrecoverable |
| JC3 | Token match 0.40–0.60 | **pass, but the hit is written and never deleted** | common Arabic and transliterated names collide; the record is the defence |
| JC4 | A screening decision has no `entry_reference` recorded | **it did not happen** | a disposition that cannot be traced to a published list entry is not auditable |
| JC5 | `license_activity` is null | **refuse to admit to a regulated category** | today that is all 22,265 leads; the honest answer is the extraction task |
| JC6 | Licence expired | **`matching_blocked = true`, no RFQ, no exception** | `governance_policy` #15 |
| JC7 | A category note names a sector approval and the document is absent | **do not admit** even if the trade licence is perfect | SIRA/RERA/Civil Defence/FTA requirements are not ours to waive |
| JC8 | An erasure would delete a record in a `tax`, `legal` or `compliance` retention class | **refuse that part, itemised** | `retention_policy`; UAE 7-year record-keeping |
| JC9 | An erasure is refused | **say exactly which bucket and class overrode it** | a bare refusal is indistinguishable from non-compliance |
| JC10 | Personal data would enter a model prompt where a reference id would do | **block** | `governance_policy` #5, and the only model-adjacent path left in the estate |
| JC11 | An identifier would go into a URL or query string | **block** | `governance_policy` #6 |
| JC12 | A monitor has not run within its cadence | **report the silence as the finding** | zero cannot tell a dead guard from an idle system |
| JC13 | A source has been unreachable for two consecutive checks | **raise it as a control failure**, not a note | the Dubai Civil Defence 422 has been a `note` since 2026-08-10 |
| JC14 | A compliance claim's only evidence is a `phase_d_legal_source` row whose `authority_tier` is not `AUTHORITATIVE_PRIMARY` | **do not make the claim** | the fixtures in that table model exactly this failure |
| JC15 | Evidence is a `ZZ DEMO` row | **it is a fixture; it proves the machinery, never the fact** | all 5 rows in `phase_d_legal_source` are fixtures today |
| JC16 | This seat authored the work | **it may not approve it** | the stop-authority grant of 14 Aug 2026 says so explicitly |
| JC17 | A control is `enforcement='declared'` | **it is not a control** | 5 of 16 `governance_policy` rows are in this state |
| JC18 | Taxable supplies reach AED 300,000 trailing 12 months | **open the CFO's VAT registration task** | threshold 375,000; AED 1,000,000 of revenue crosses it by 2.7× |
| JC19 | The founder would be asked about corporate tax, VAT, the auditor or the licence | **do not ask** | four standing rulings of 6 Sep 2026, `never_ask_again = true` |
| JC20 | A privacy notice statement cannot be traced to a column that actually exists | **the notice is wrong, not the database** | a notice that describes a fiction is the worst privacy failure available |
| JC21 | A control scores well but rests on a cron that is `active = false` | **fail it** | 7 of the 9 legal-adjacent crons are inactive today |

### 5. Technical knowledge

- **Screening stack.** `screening_run(id, source, source_url, fetched_at, sha256, entries, status, note, run_tag)`;
  `screening_entry(id, run_id, source, entry_type, reference, name, name_norm, tokens)`;
  `supplier_screening_hit(run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source,
  entry_reference, entry_type, match_kind, score, status, task_id, bd_task_id, decided_by, decided_at)`.
  Ingest: edge function `sanctions_screen`, posted by `fn_sanctions_screen_tick()` using
  `app_secrets.cred_cron_compliance`, cron `sanctions_screen_weekly` jobid 345 `0 3 * * 1`, **active**.
  Matcher: `fn_supplier_sanctions_screen(bigint[], text)`. Sources and their formats: UN consolidated **XML**
  (names + aliases + original-script names); UAE Local Terrorist List **legacy .xls** reached through a page anchor
  — and the run note records the limitation honestly: *the PDF half is not parsed, de-listing sheets excluded*.
- **Licence stack.** `fn_supplier_licence_gate`, `fn_check_licence_expiry`, `fn_check_licence_activity`,
  `fn_reconcile_licence_blocks(p_grace_days)`, `fn_leads_licence_gate_rerun()`; `category_licence_activity`
  (20 rows); `leads` columns `trade_license_no`, `license_authority`, `license_expiry`, `license_activity`,
  `license_doc_path`, `licence_gate_reason`, `matching_blocked`, `matching_block_reason`, `verification_status`.
- **PDPL stack.** `pdpl_requests(id uuid, kind, email, role, details, status, created_at, handled_at, handled_by)`;
  `pdpl_erase_files`; `fn_pdpl_export(text)`, `fn_pdpl_erase_plan(text)`, `fn_pdpl_redact(uuid)`;
  `trg_pdpl_request_to_kernel`; edge functions `pdpl_request`, `pdpl_erase`. **Both endpoints are unreferenced in
  `src/`.**
- **Monitoring stack.** `compliance_sources(authority, topic, url, last_signature, last_checked_at, last_changed_at,
  active, note, doc_path, doc_bytes, doc_content_type, fetch_mode)`; `fetch_mode` is `direct` or `reader`;
  documents land in the `compliance-docs` bucket, retention class `compliance`, `retention_days` null (keep current).
- **Retention and audit.** `retention_policy` (11 buckets); `os_audit_log` (31,002 rows);
  `security_audit_log` (2,956); `internal_credential_audit`; `autonomy_control_audit`; `control_mode_audit`.
- **Authority.** This seat's `employee_authority`: `compliance_check` **autonomous**/AED 1,000,
  `legal_review` **autonomous**/AED 1,000, `pdpl_action` **advisory**/AED 1,000 (*"may prepare, but execution
  requires the department head"*), `review_block` **autonomous**, no threshold.
- **What must be stored so the seat never has to ask.** The list sources and their sha256 lineage (present);
  the category→activity map (present); the retention buckets (present); the licence gate routines (present).
  **Absent and needed:** the regulatory-obligations calendar; the lawful-basis register (field → purpose → basis);
  the processor register with transfer destinations; a per-purpose consent ledger; the DNFBP class table.

### 6. Academic knowledge

Disciplines: data-protection law and privacy programme management; AML/CFT and sanctions compliance; consumer
protection; regulatory monitoring and horizon scanning; audit and control design; record-keeping law.

Lawful primary sources: the UAE Data Office's published PDPL text and guidance; the Executive Office for Control &
Non-Proliferation's published lists and guidance (already ingested as `uae_local_terrorist_list`); the UN Security
Council consolidated list XML (already ingested, 4,157 entries); FATF's published Recommendations and methodology
(public); the Ministry of Economy's published consumer-protection material; ISO/IEC 27701 and ISO 37301 as published
standards; the 17 sector-authority sources already held in `compliance_sources`; Dubai DET's published activity list.
No copyrighted study texts. No US material.

**Certifications on record:**

- **CIPP/E** (IAPP), pass mark 70%, rank 1 — *"the compliance manager answers for lawful processing, subject rights
  and transfers."* Syllabus areas: Data Protection Laws; Personal Data; Controllers and Processors; Processing
  Personal Data; Information Provision Obligations; Rights of Data Subjects; International Data Transfers;
  Supervision and Enforcement.
- **CAMS** (ACAMS), pass mark 75%, rank 2 — *"payments and supplier onboarding put financial crime compliance
  squarely in this seat."* Syllabus areas: Risks and Methods of Money Laundering; AML Compliance Programs;
  Sanctions and International Standards; Customer Due Diligence; Suspicious Activity Monitoring and Reporting;
  Conducting and Supporting Investigations.

**Syllabus areas failed: does not exist** — `certification_exam_result` holds no row for `compliance_mgr`. The CAMS
areas *Sanctions and International Standards* and *Customer Due Diligence* map directly onto P-C1 and P-C2, so the
exam is not decoration: its `weakest_areas` output is the study plan, and until it is sat there is no evidence about
what this seat does not know.

### 7. Corporate knowledge

- **The founder's screening instruction.** `company_policy_decision.supplier_acquisition_and_screening`
  (6 Sep 2026): the existing compliance employee checks the sanctions list; the invite campaign starts from the
  leads the company holds; target **at least 300 supplier registrations a month**; none of it runs until
  `app_secrets.supplier_outreach_golive`.
- **Auto-approval is on.** `pricing_config.auto_approve_suppliers = true`. That makes this seat's gates the *only*
  thing between a registration and an approved supplier. It is the single most important operational fact in this
  section.
- **The four never-ask rulings** that touch this seat: corporate tax, VAT, the auditor, the licence — all
  `never_ask_again = true` in `company_policy_decision`.
- **Anonymity.** `governance_policy` #4: a pre-reveal leak of supplier identity is a P0 defect. This seat's
  screening writes supplier names into `supplier_screening_hit`; that table must never surface on a customer path.
- **Minimum data.** `governance_policy` #5 is owned by `legal` and enforced only by *process* — this seat's control
  test (M-C11) will keep flagging it until it has a mechanism.
- **Hand-offs.** Exact sanction hits and DNFBP questions → `legal`. Licence chases → `bd` / supply
  (`supplier_screening_hit.bd_task_id` exists for exactly this). Security incidents → `cto` / `security`.
  VAT threshold → `cfo`. Suspensions → `trust_safety_mgr`.
- **History it must not forget.** The screening ingest already records its own limitations in
  `screening_run.note` — the PDF half of the UAE list is unparsed, de-listing sheets are excluded. That note is a
  model for how this seat reports: state the boundary of what was measured, every time.
- **Does not exist:** a regulatory-obligations calendar, a lawful-basis register, a processor/transfer register,
  a consent ledger, an incident register, a DNFBP determination, and any record of a real (non-fixture)
  authoritative legal source.

### 8. One-year plan

**Objective.** Make supplier admission and personal-data handling gates that a regulator could inspect, at the
throughput the revenue plan needs, with OpenRouter off.

**Direct revenue: AED 0.** This seat's arithmetic link to AED 1,000,000 runs through the registration line: the
founder's target is 300 registrations a month, registration 1,001 turns on AED 1,000/year, and **every one of those
300 must pass this seat's gates**. If the gates cannot run at 300/month the revenue line does not exist; if they
run but do not really check, the revenue exists and the licence risk sits behind it.

**Metrics this seat owns:**

1. **Screening completeness** = `100 × registrations screened against a list ≤ 7 days old / registrations`.
   Today: 1 registration, 0 hits, lists 0 days old. Target 100%, and the metric must fail closed when the list ages.
2. **Category-admission validity** = `100 × admitted suppliers whose license_activity matches their category regex /
   admitted suppliers`. Today **0%** — not because suppliers fail, but because `license_activity` is null on all
   22,265 leads. This is the seat's most honest number and it should be published as 0 until extraction ships.
3. **DSR responsiveness** = `100 × requests answered inside the statutory window / requests`. Today
   **undefined, 0 requests**, because there is no entry point.

**Quarterly milestones**

- **Q1, Sep–Nov 2026.** Ship the **licence-activity extraction** so metric 2 stops being 0 by construction —
  this is the gate on 300 registrations/month and nothing else this seat does matters more. Ship the **PDPL request
  entry point** wiring `pdpl_request` into `src/app/[locale]/privacy` so `pdpl_requests` can hold a row.
  Re-activate `agent_compliance_weekly` (jobid 9) or replace it, and add the liveness assertion from M-C8. Fix or
  retire the unreachable Dubai Civil Defence source. Sit CIPP/E and CAMS.
- **Q2, Dec 2026–Feb 2027.** Build the **regulatory-obligations calendar** so
  `company_goals.regulatory_deadlines` has an instrument. Build the **lawful-basis register** and reconcile the
  privacy policy against it column by column (C11 — expect findings). Calibrate M-C1's thresholds against a
  labelled set of at least 200 name pairs and publish the false-positive rate.
- **Q3, Mar–May 2027.** Build the **processor and transfer register** and the **consent ledger**. Run the first
  full control-reality audit (P-C5) across all 16 `governance_policy` rows and publish how many are declarations.
  VAT: at AED 300,000 trailing supplies, open the CFO's registration task.
- **Q4, Jun–Aug 2027.** Screening at steady state with a measured false-positive rate. Second control audit.
  Support the licence renewal (due 2027-06-24). Report the year with metric 2 as the headline.

**Capacity check.** At 300 registrations a month the work is: 300 × 4 name fields = 1,200 normalisations joined
against 4,961 entries — a single indexed set operation per registration, milliseconds. Licence-activity matching is
one regex per registration against a 20-row table. Expiry laddering is one daily pass over the registered set.
**The compute is nothing.** The real capacity question is the false-positive review: at an assumed 2% token-match
rate, 300 registrations produce ~6 hits a month needing disposition — well inside `max_open_tasks` = 50. **The slice
is achievable.** What is not achievable today is any of it at all, because `license_activity` is null everywhere
and the weekly monitor has not run since 10 August.

**Dependencies.** `supply`/`bd` for licence documents and for the extraction that populates `license_activity`.
`product_eng` for the PDPL entry point and for re-activating crons 9 and 100. `legal` for the DNFBP determination
and for every exact hit. `cfo` for the VAT trigger.

### 9. What this seat cannot do without a model

1. **Decide whether a token match is the same human being** when the transliteration differs and no date of birth
   or reference number is available (C2). Model-free fallback: block, escalate, ask for a document. This is the
   correct fallback anyway — a model should not be making sanctions dispositions.
2. **Read a scanned trade licence and extract the activity text** (the blocker on metric 2). OCR plus regex handles
   machine-generated PDFs; a photographed licence needs vision. Model-free fallback: require a text-layer PDF or a
   typed activity field at registration.
3. **Parse the PDF half of the UAE Local Terrorist List** — the run note already records this as an unparsed
   limitation. Fallback: use the Excel and state the limitation on every screening output, as the note already does.
4. **Judge whether a novel data flow has a lawful basis** where no register entry covers it (C9). Fallback: refuse
   the flow until the basis is registered — which is the better default regardless.
5. **Read a new regulation and say which clause of our terms it touches** (C22 step 3). Fallback: topic-token
   mapping, which names a source and not a clause, plus a task on `legal`.

---

## trust_safety_mgr — Trust & Safety Manager

Reports to `legal`. `routing_tier` reviewer_auditor. Responsibilities on record: *own platform integrity — fraud,
spam, fake suppliers, fake RFQs, moderation and verification. Set the risk thresholds and escalate anything that
would cost a real customer money.* Absorbed the parked `fraud_analyst` seat on 3 Sep 2026.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | cost of a wrong answer |
|---|---|---|---|---|---|
| T1 | Is this supplier registration genuine or fabricated? | gate | per registration | supply | a fake supplier receiving a real customer's RFQ |
| T2 | Are two registrations the same entity under different identities? | diagnosis | per registration | supply | one operator holding several slots in a top-3 |
| T3 | Is this trade licence number already used by another lead? | gate | per registration | supply | the `duplicate_license` pattern already in `fraud_flags` |
| T4 | Is a registration burst from one IP, domain or phone a campaign or a coincidence? | diagnosis | daily | itself | the `velocity_signups` pattern |
| T5 | Is a customer phone number attached to more than one customer identity? | diagnosis | daily | itself | the `dup_customer_phone` pattern already flagged once |
| T6 | Is this RFQ real, or a supplier probing the market through a fake buyer? | gate | per RFQ | marketplace | suppliers quoting into a fabricated job; wasted goodwill |
| T7 | Is a quote priced so far from the set that it signals manipulation? | diagnosis | per quote | marketplace | the `abnormal_price` pattern, flagged 4 times |
| T8 | Is a supplier bidding on their own customer's RFQ through a second account? | diagnosis | per quote | marketplace | rigged comparison |
| T9 | Is a supplier trying to identify or contact the customer before the reveal? | gate | per message and file | `moderation_specialist` | the P0 anonymity breach; the product's core promise |
| T10 | Is a customer trying to identify the supplier before paying? | gate | per interaction | product | the reveal fee circumvented |
| T11 | Has an off-platform circumvention attempt occurred after a reveal? | diagnosis | monthly | itself, `cfo` | revenue leakage the acceptable-use policy forbids |
| T12 | Is a supplier's non-response pattern negligence or abuse? | diagnosis | weekly | `cs_retention`, `cfo` | refunds triggered by a supplier who never intended to quote |
| T13 | Does a supplier's strike count warrant removal from matching? | gate | weekly | marketplace | `matching_strike_limit` = 3, founder decision 3 Aug 2026 |
| T14 | Should this account be suspended, and under which clause? | escalation | per case | itself, `legal` | a wrongful suspension, or a harmful account left live |
| T15 | Should a suspension be lifted? | gate | per appeal | itself | an unreviewable ban |
| T16 | Is a review or rating authentic? | diagnosis | per review | marketplace | fabricated reputation |
| T17 | Is an uploaded document forged or reused from another entity? | diagnosis | per upload | supply | a forged licence admitted |
| T18 | Do the licence, IBAN and signatory names belong to the same entity? | gate | per registration | supply, `cfo` | payment to a party unrelated to the supplier |
| T19 | Is a bank account shared across supposedly independent suppliers? | diagnosis | monthly | `cfo` | collusion or a single operator |
| T20 | Is an email domain disposable, or does it belong to a real business? | diagnosis | per registration | supply | throwaway identities |
| T21 | Is a website or Maps listing corroborated, or invented? | diagnosis | per registration | supply | a paper supplier |
| T22 | Does the fraud score cross `fraud_score_max` = 0.7? | gate | per scored item | itself | inconsistent thresholds applied case by case |
| T23 | Which fraud signals actually predicted a bad outcome? | diagnosis | quarterly | itself | keeping detectors that detect nothing |
| T24 | Is a `fraud_flags` row dismissed because it was wrong, or because nobody looked? | diagnosis | monthly | itself | **all 7 rows are `dismissed` today; the estate cannot tell these apart** |
| T25 | Is a detector silent because the estate is clean, or because it is switched off? | diagnosis | weekly | itself | `fraud_scan_daily` (jobid 48) is inactive; silence proves nothing |
| T26 | What is the acceptable false-positive rate for supplier blocking? | allocation | quarterly | itself, `ceo` | over-blocking starves supply; under-blocking costs a customer |
| T27 | Should a category be closed to new registrations after abuse? | escalation | rare | `ceo`, supply | a category poisoned, or a category needlessly frozen |
| T28 | Is a chargeback fraud, or a genuine service failure? | diagnosis | per chargeback | `cfo` | treating a wronged customer as an adversary |
| T29 | Is a refund claim genuine, or a pattern? | diagnosis | per refund | `cfo`, `legal` | refund abuse; and refunds are the founder's own gate |
| T30 | Does an incident need the customer told? | escalation | per incident | `legal`, `cs_support` | a harm concealed |
| T31 | Is a supplier's licence expiry being used to game the matching block? | diagnosis | monthly | `compliance_mgr` | a re-entry loophole |
| T32 | Is one operator holding several slots in a single top-3 comparison? | gate | per comparison | marketplace | the comparison report is the product; three faces of one supplier destroys it |
| T33 | Does a contact-form or inbound message contain abuse or a threat? | escalation | per message | `cs_support` | a safety issue treated as a ticket |
| T34 | Is an agent-to-agent chat leaking customer identity? | gate | continuous | `cto` | `chat_violations` exists for this and holds 0 rows |
| T35 | What integrity signals should a new category carry before it opens? | craft | per category | supply | opening a category with no detectors |
| T36 | Is the current risk threshold set costing more supply than it saves? | allocation | quarterly | `ceo` | invisible over-blocking |
| T37 | Has a banned operator returned under a new identity? | diagnosis | monthly | itself | a ban that lasts one signup |
| T38 | Which integrity control has never fired, and is that good news? | diagnosis | quarterly | itself | comfort from an untested control |

### 2. Domain logic

**M-T1 — Duplicate-identity graph.** Nodes are leads; edges join on shared normalised `trade_license_no`,
`bank_iban`, `phone_e164`, `email_domain` (excluding free providers), `domain`, `place_id`, `owner_email`.
`cluster_size = |connected component|`. Verdict: `cluster_size > 1` ⇒ investigate; shared `trade_license_no` or
`bank_iban` ⇒ **block pending proof**. Inputs: `leads` (22,265 rows; all seven columns exist).
*Measured:* the `duplicate_license` pattern is already in `fraud_flags` as a real historical detection.

**M-T2 — Velocity.** `rate(k, w) = count of registrations sharing key k in window w`. Bands: > 3 per hour or > 10
per day on one `email_domain`, `phone_e164` prefix or IP ⇒ flag. Inputs: `leads.created_at`, `.email_domain`,
`.phone_e164`. Existing detector kind: `velocity_signups`.

**M-T3 — Price outlier.** For quotes on one RFQ, `z = (p − median) / (1.4826 × MAD)`. Flag at `|z| ≥ 3.0`; severity
high at `|z| ≥ 4.5`. Median absolute deviation, not standard deviation, because n is small and the outlier is the
thing being measured. Inputs: `quotes` — **0 rows today**, so this model has no data and its thresholds are
uncalibrated. Existing detector kind: `abnormal_price`, 4 historical rows.

**M-T4 — Composite fraud score.** `score = 1 − Π(1 − wᵢ·sᵢ)` over fired signals, where `sᵢ ∈ {0,1}` and the weights
are stored, never per-case: duplicate licence 0.55, shared IBAN 0.50, velocity 0.30, disposable email domain 0.25,
no corroborating web/Maps presence 0.20, price outlier 0.30, licence-activity mismatch 0.35, name-screening weak hit
0.20. Gate at `decision_policy.fraud_score_max` = **0.7**. *Unmeasured:* the weights are this seat's proposal and
have never been fitted, because there has never been a confirmed fraud outcome to fit against. **The seat must say
"unfitted" every time it reports a score.**

**M-T5 — Non-response and strikes.** `strikes = consecutive RFQs with no response`; removal at
`decision_policy.matching_strike_limit` = **3** (founder decision 3 Aug 2026). `response_rate = rv_responded /
nullif(rv_reveals,0)` from the existing `leads.rv_reveals`, `.rv_responded`, `.rv_response_rate`,
`.rv_nonresponse_refunds` columns. **Abuse vs negligence separator:** negligence is a low response rate spread
evenly; abuse is a response rate that collapses specifically after a reveal is paid — i.e.
`rv_nonresponse_refunds / nullif(rv_reveals,0)` materially above the population rate. *Measured:* all four columns
exist; all are empty of signal because `transactions` = 0.

**M-T6 — Anonymity-breach detector.** `breach(text) = text ≠ mask_contacts(text)`. The estate already has
`mask_contact`, `mask_contacts`, `mask_contacts_jsonb`, `mask_name(t, nm)`, `scrub_inquiry_contacts()`,
`scrub_quote_contacts()` and trigger `trg_mask_quote_contact`. `mask_contacts` covers emails, URLs, social and
messenger short links (wa.me, t.me, bit.ly, instagram, facebook, fb, linkedin, twitter, x), international UAE
numbers, local 05x mobiles, UAE landlines on area codes 02/03/04/06/07/09, and bare domains on 20 TLDs.
**This is entirely deterministic and needs no model.**
*Unmeasured:* the residual class — an identity conveyed without a contact token ("we're the firm opposite the
Etihad Museum") — which no regex catches. §9.

**M-T7 — Top-3 independence.** For a comparison of suppliers {a,b,c}, `independent = no pair shares a component in
M-T1`. Verdict on failure: **rebuild the comparison**, never publish. Inputs: M-T1 plus the comparison set.
*This is the highest-value control in the seat*, because the top-3 report is the product the customer pays 3% for.

**M-T8 — Ban evasion.** Match a new registration against banned leads on M-T1's edge keys plus normalised
company-name Jaccard ≥ 0.7. *Measured:* `leads.banned` = **0 rows**, so there is nothing to evade yet — and the
control is therefore untested, not proven.

**M-T9 — Detector liveness.** `live(d) = the cron that runs d is active and has a run in the last cadence`.
*Measured:* `fraud_scan_daily` (48), `supplier_risk_complaints` (209), `supplier_risk_response_delays` (210),
`supplier_risk_performance_drops` (211) are **all inactive**. `fn_fraud_scan()`, `fn_ws_fraud()`,
`fn_supplier_risk_monitor(p_signal)` and `fn_fraud_resolve(p_subject_type, p_subject_id, p_action, p_by)` all
exist. **Four detectors, zero schedulers.** Every "no fraud detected" statement today is a statement about the
scheduler, not the estate.

**M-T10 — Disposition quality.** `documented(f) = the flag has a recorded action and actor`. *Measured:* all 7
`fraud_flags` rows are `status='dismissed'`; the table carries `status`, `detail jsonb` and `updated_at` but no
reason or actor column, so **the estate cannot distinguish a considered dismissal from a bulk clear**. Adding
`resolved_by text` and `resolution_reason text` is the fix; `fn_fraud_resolve` already takes `p_action` and `p_by`
and has nowhere durable to put them.

**M-T11 — Blocking cost.** `supply_cost = blocked_suppliers × expected_RFQs_per_supplier × conversion × median_fee`.
Set the threshold where marginal supply cost equals marginal customer-harm cost. *Unmeasured:* every input is
zero or absent today (0 inquiries, 0 quotes, 0 transactions), so **the threshold cannot be optimised and must
stay at the conservative default `fraud_score_max` = 0.7 until real flow exists.**

### 3. Reasoning procedures

**P-T1 — Admit or refuse a registration (T1, T2, T3, T17, T18, T20, T21)**
1. Build the M-T1 component for the new lead.
2. Shared `trade_license_no` or `bank_iban` with any other lead ⇒ **block immediately**, no scoring, escalate.
3. Otherwise fire the signal set: velocity (M-T2), disposable domain, web/Maps corroboration
   (`website_status`, `place_id`, `rating_maps`, `reviews_maps`), name-consistency across
   `company_name` / `signatory_name` / `bank_account_name` / `trade_license_no` holder.
4. Compute M-T4. `≥ 0.7` ⇒ hold for review. `< 0.7` with any signal fired ⇒ admit **with the signals recorded**.
5. Record every signal and its weight in `fraud_flags.detail`, so the disposition is reconstructable.
6. Compose: verdict, signals fired with weights, score, threshold, action, and the sentence *"the weights are
   unfitted — no confirmed fraud outcome exists in this estate to fit them against."*
**Stops and refuses when:** fewer than three of the eight signals are computable for this lead — a score from two
signals is a number pretending to be a judgement.

**P-T2 — Protect the top-3 comparison (T8, T32)**
1. Take the candidate set.
2. M-T7. Any shared component ⇒ drop the lower-ranked duplicate and pull the next candidate.
3. Re-run until three independent suppliers or the candidate pool is exhausted.
4. Pool exhausted ⇒ **publish fewer than three and say why**, never pad with a related party.
**Stops and refuses when:** fewer than two independent suppliers remain — a comparison of one is not a comparison,
and the honest output is the coverage gap, routed to supply.

**P-T3 — Anonymity breach (T9, T10, T34)**
1. Apply M-T6 to every supplier-facing string and jsonb payload.
2. Any difference ⇒ the payload is **held, not sent**; the masked version is what may pass.
3. Repeat offences by one supplier: strike ladder, then suspension under the named acceptable-use clause.
4. Log to `chat_violations` (0 rows today — the table exists and nothing writes to it, which is itself a finding).
**Stops and refuses when:** the payload is a binary (an image or CAD file) — regex does not see inside it. That is
`moderation_specialist`'s path and, for scanned images, §9.

**P-T4 — Suspend an account (T14, T15, T38)**
1. Name the clause of the supplier agreement or acceptable-use policy that authorises the suspension. **No clause,
   no suspension** — this is a `legal` dependency, not a discretion.
2. Assemble evidence: flags, scores, message references, dates.
3. Apply `governance_policy` #12 — suspension is irreversible-class, so a second reviewer is required.
4. Notify with the clause and the appeal route.
5. On appeal, re-run the evidence with the original signals frozen; a different answer requires new evidence, not a
   new mood.
**Stops and refuses when:** the only evidence is a score. A score is a prioritisation, never a proof.

**P-T5 — Weekly integrity report (T23, T24, T25, T38)**
1. **Liveness first** (M-T9): report which detectors ran and which are switched off. Today: four detectors, all
   with inactive crons.
2. For live detectors, report fires, dispositions and the false-positive rate.
3. For detectors that fired zero times, state explicitly whether that is a clean estate or a dead guard — with
   `fraud_scan_daily` inactive, today it is the latter.
4. Report the 7 historical `fraud_flags`, all dismissed, and state that **the table has no reason or actor column,
   so the quality of those dismissals cannot be assessed**.

**P-T6 — Separate abuse from negligence in non-response (T12, T13, T29)**
1. Compute `response_rate` and `rv_nonresponse_refunds / rv_reveals` per supplier.
2. Compare each against the population median, not against an absolute.
3. Low rate, evenly spread ⇒ negligence ⇒ strike ladder (limit 3).
4. Rate collapsing specifically after paid reveals ⇒ abuse ⇒ evidence pack to `legal` and `cfo`, because the AED 250
   admin fee and the 9% p.a. clawback are contractual remedies that need a documented basis.
5. Never issue the refund — that is the founder's, always.
**Stops and refuses when:** the supplier has fewer than five reveals. A rate on n<5 is noise, and today every
supplier has n=0.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JT1 | Two leads share a `trade_license_no` or `bank_iban` | **block both pending proof**, no score | one entity in two slots is the failure the top-3 cannot survive |
| JT2 | A top-3 would contain two suppliers from one M-T1 component | **rebuild it**, even if it delays the report | the comparison is what the 3% buys |
| JT3 | Fewer than three independent suppliers exist | **publish fewer and say why** | padding with a related party is worse than a short list |
| JT4 | Any supplier-facing payload differs from its `mask_contacts` output | **hold the payload** | `governance_policy` #4, P0 |
| JT5 | A suspension has no named clause | **do not suspend** | a ban with no contractual basis is a claim against us |
| JT6 | The only evidence is a composite score | **do not act on it** | the weights are unfitted and this seat must keep saying so |
| JT7 | A detector fired zero times and its cron is inactive | **report "switched off", never "clean"** | four detectors are in exactly this state today |
| JT8 | A `fraud_flags` row is dismissed with no reason recorded | **treat the dismissal as unverified** | all 7 rows; the table has no reason column |
| JT9 | A supplier has fewer than five reveals | **do not compute a response-rate verdict** | a rate on n<5 is noise |
| JT10 | A refund is the outcome | **the founder decides, always, any amount** | the only founder gate there is |
| JT11 | Blocking would empty a category | **escalate the trade-off to `ceo`; do not silently under-enforce** | `category_open_min_suppliers` = 10; over-blocking starves the marketplace invisibly |
| JT12 | A customer is affected by an integrity failure | **tell them**, even where no rule compels it | `governance_policy` #3, never blame the customer; concealment is the compounding error |
| JT13 | A registration burst is from one legitimate group company | **admit them all and record the relationship** | a group is not fraud, but an undeclared group in one top-3 is |
| JT14 | An appeal produces the same evidence | **the original decision stands** | re-deciding on the same facts is not review |
| JT15 | A signal has never predicted a confirmed outcome and costs supply | **retire it and say so** | detectors that detect nothing are a tax on supply |
| JT16 | A price outlier is the only signal | **flag, never block** | `abnormal_price` is a review trigger; a cheap quote is usually a cheap quote |
| JT17 | Fewer than three of the eight signals are computable | **refuse to score** | today that is the normal case, and a two-signal score would look like knowledge |
| JT18 | A ban is proposed on a first offence with no customer harm | **strike, do not ban** | strike limit 3 is the founder's ladder |

### 5. Technical knowledge

- **Detection routines that exist.** `fn_fraud_scan()`, `fn_ws_fraud()`, `fn_supplier_risk_monitor(p_signal text)`,
  `fn_fraud_resolve(p_subject_type, p_subject_id, p_action, p_by)`, `fn_check_licence_expiry`,
  `fn_check_licence_activity`.
- **Detection storage.** `fraud_flags(kind, subject_type, subject_id, severity, detail jsonb, status, created_at,
  updated_at)` — 7 rows, all dismissed, **no reason or actor column**. `chat_violations` — 0 rows.
  `risk_register` — 19 rows, of which id 4 (*payment fraud or duplicate payment*, `owner_agent = 'legal'`,
  mitigation *"money_move gated at AED 10,000"*) is this seat's inherited entry.
- **Scheduling.** Cron jobs 48, 209, 210, 211 exist and are **all `active = false`**. Re-enabling any of them goes
  through `fn_kernel_wrap_and_enable_cron(<jobid>, …)` plus `cron_registry` and
  `phase_d_committed_scenario_cron` rows, per the estate's conventions.
- **Masking primitives.** `mask_contact(s)`, `mask_contacts(t)`, `mask_contacts_jsonb(j)`, `mask_name(t, nm)`,
  `scrub_inquiry_contacts()`, `scrub_quote_contacts()`, `trg_mask_quote_contact`. Read the regexes before writing a
  new one — they already cover more than a fresh attempt would.
- **Identity columns on `leads` this seat reasons over.** `trade_license_no`, `license_authority`, `license_expiry`,
  `bank_iban`, `bank_account_name`, `signatory_name`, `emirates_id`, `owner_dob`, `owner_email_verified`,
  `owner_phone_verified`, `email_verified`, `email_domain`, `phone_e164`, `domain`, `place_id`, `website_status`,
  `permanently_closed`, `rating_maps`, `reviews_maps`, `chat_strikes`, `banned`, `banned_reason`,
  `matching_blocked`, `matching_block_reason`, `verification_status`, `rv_reveals`, `rv_responded`,
  `rv_response_rate`, `rv_nonresponse_refunds`.
- **Thresholds it must not invent.** `decision_policy.fraud_score_max` 0.7, `.matching_strike_limit` 3,
  `.financial_review_aed` 10,000, `.auto_action_max_aed` 0, `.match_max_fanout` 5, `.match_relevance_floor` 35,
  `.sensitive_categories` (fire, security, electrical, structural, gas, lifts, medical — where a bad supplier does
  physical harm, not just commercial harm).
- **Authority.** This seat's `employee_authority` is a **single row**: `analysis`, `max_tier = supervised`,
  no threshold, noted *"seeded 14 Aug 2026 from canonical authority_level execute_low; an active role with no
  authority record is undefined, not restricted."* **It has no `review_block` row**, unlike `compliance_mgr` and
  `moderation_specialist` — so the seat that owns suspension has, on the record, less stop authority than the two
  seats that report alongside it. That is an authority gap, and it is a Q1 fix.
- **Absent and needed:** `fraud_flags.resolved_by` and `.resolution_reason`; an outcome table linking a flag to what
  actually happened; a stored signal-weight table so M-T4 is data, not code; an appeals record.

### 6. Academic knowledge

Disciplines: fraud examination; identity resolution and record linkage; robust statistics for small samples;
network/graph analysis for collusion; platform trust-and-safety operations; investigative interviewing and evidence
handling; the law of suspension and unfair contract terms.

Lawful primary sources: ACFE's published Report to the Nations and its public fraud-tree taxonomy; FATF's published
typologies on trade-based money laundering and beneficial ownership; the UN and UAE lists already ingested; NIST's
public work on record linkage and entity resolution; published academic literature on Fellegi–Sunter probabilistic
record linkage; UAE consumer-protection material on unfair terms as it bears on suspension. No copyrighted study
texts. No US material.

**Certifications on record:**

- **CFE** (ACFE), pass mark 75%, rank 1 — *"trust and safety is fraud examination applied to the platform's own
  users."* Syllabus areas: Financial Transactions and Fraud Schemes; Law; Investigation; Fraud Prevention and
  Deterrence.
- **CIPM** (IAPP), pass mark 70%, rank 2 — *"investigations touch personal data, so the privacy programme lifecycle
  governs how they are run."* Syllabus areas: Developing a Privacy Programme; Privacy Programme Framework;
  Privacy Operational Lifecycle Assess / Protect / Sustain / Respond.

**Syllabus areas failed: does not exist** — no `certification_exam_result` row for `trust_safety_mgr`. The CFE
*Investigation* area maps onto P-T4, where this seat's biggest live weakness sits: the estate cannot currently
record why a flag was dismissed.

### 7. Corporate knowledge

- **The product this seat protects.** The top-3 comparison report (`qd-company:comparison-report`) and the paid
  reveal. A comparison containing two faces of one supplier is not a degraded product, it is a different product.
- **The founder's ladders.** `matching_strike_limit` = 3 (3 Aug 2026). `fraud_score_max` = 0.7. Refunds are his
  alone. Reveal 3%, uncapped, no discount — which sets what a manipulated comparison is worth to an attacker:
  3% of whatever quote they can get accepted.
- **Anonymity is contractual, not just technical.** The acceptable-use policy prohibits *off-platform
  identification of suppliers before reveal* and *circumvention* — that is the clause P-T4 needs before any
  suspension for it.
- **Auto-approval is on** (`pricing_config.auto_approve_suppliers = true`), so this seat and `compliance_mgr` are
  the only checks between registration and an approved, matchable supplier.
- **Hand-offs.** Sanctions and licence questions → `compliance_mgr`. Suspension clauses and appeals with legal
  exposure → `legal`. Payload and wording → `moderation_specialist`. Chargebacks and refund arithmetic → `cfo`.
  Detector scheduling → `it_operations_engineer`.
- **History it must not forget.** The 7 `fraud_flags` rows are the only real detections this platform has ever
  made: `velocity_signups`, `duplicate_license`, four `abnormal_price`, `dup_customer_phone` — one of them on a real
  UAE number. They are the seed set for calibration and must never be deleted.
- **Does not exist:** a suspension record, an appeals record, a confirmed-fraud outcome table, a shared-IBAN
  detector wired to a schedule, and any calibration of any threshold in this section.

### 8. One-year plan

**Objective.** Make the top-3 comparison provably independent and the supplier base provably real, at 300
registrations a month, with every threshold stated as unfitted until it is fitted.

**Direct revenue: AED 0, and the largest single lever on whether reveal revenue survives contact with customers.**
The arithmetic: AED 1,000,000 needs **AED 33,333,333 of accepted quote value**. At a median accepted quote of
AED 50,000 that is ~667 paid reveals. A customer who pays 3% and discovers two of their three quotes came from one
operator does not come back, and tells others. **One rigged comparison in the first hundred is a plausible
double-digit-percent hit to the reveal line**, and it is entirely preventable by M-T7, which is arithmetic.

**Metrics this seat owns:**

1. **Comparison independence** = `100 × published top-3 sets with no shared M-T1 component / published sets`.
   Target **100%, no exceptions**. Today undefined (0 comparisons published).
2. **Detector liveness** = `100 × detectors with an active schedule and a run inside cadence / detectors`.
   Today **0%** — four detectors, four inactive crons. This is the seat's most honest number.
3. **Disposition documentation** = `100 × flags with a recorded actor and reason / dispositioned flags`.
   Today **0%** by construction: the columns do not exist.

**Quarterly milestones**

- **Q1, Sep–Nov 2026.** Add `resolved_by` and `resolution_reason` to `fraud_flags` and wire `fn_fraud_resolve`'s
  existing `p_action` / `p_by` arguments into them — metric 3 becomes computable. Re-activate the four detector
  crons (48, 209, 210, 211) through the kernel wrapper — metric 2 goes from 0% to 100%. Implement M-T1 and M-T7 as
  routines and put M-T7 in front of every comparison **before the first one is ever published**. Add the missing
  `review_block` authority row. Sit CFE.
- **Q2, Dec 2026–Feb 2027.** Store the M-T4 weights in a table so they are data. Build the shared-IBAN and
  ban-evasion detectors. Build the outcome table so a flag can be linked to what happened, which is the only path
  to ever fitting a weight. Publish the first false-positive rate — even if the denominator is small, publish it.
- **Q3, Mar–May 2027.** With real flow, calibrate M-T3's z-threshold and M-T4's weights against confirmed outcomes.
  Run the first blocking-cost analysis (M-T11) and propose a threshold with the supply cost shown. Retire any signal
  that has never predicted an outcome (JT15).
- **Q4, Jun–Aug 2027.** Steady state: independence 100%, liveness 100%, documentation 100%, a published
  false-positive rate and a fitted score. Report which of the eight signals earned its place.

**Capacity check.** M-T1 over 22,265 leads is a connected-components pass on an indexed edge set — seconds, and it
needs to run once a day, not once a registration. M-T7 is a component lookup per comparison: at ~56 comparisons a
month, nothing. M-T6 is regex over strings, already implemented, already used by triggers. **Compute is not the
constraint.** The review load is: at 300 registrations a month and an assumed 5% hold rate, ~15 holds a month —
comfortably inside `max_open_tasks` = 50. **The slice is achievable**, and it is achievable today except that all
four detectors are switched off and the weights are unfitted.

**Dependencies.** `it_operations_engineer` for cron re-activation. `product_eng` for the `fraud_flags` columns and
the outcome table. `legal` for the suspension clauses P-T4 cannot proceed without. `marketplace` for the comparison
pipeline hook. `compliance_mgr` for licence and screening signals, which are two of the eight weights.

### 9. What this seat cannot do without a model

1. **Detect an identity conveyed without a contact token** — "the firm opposite the Etihad Museum", a logo in a
   photograph, a letterhead in a scan (T9). Regex sees tokens, not implications. Model-free fallback: strip
   metadata, require structured fields, and hold anything that fails a whitelist rather than trying to detect the
   leak.
2. **Judge whether an uploaded licence image is forged** (T17). Fallback: require a text-layer PDF, check the
   authority and number format deterministically, and treat images as unverified.
3. **Read a free-text complaint and classify abuse, threat or safety issue** (T33). Fallback: a keyword list plus
   escalation on any match, accepting a high false-positive rate on a low-volume path.
4. **Assess whether a written appeal raises a new fact** (T15). Fallback: require the appellant to submit evidence
   as structured fields; a narrative alone leaves the original decision standing.
5. **Judge whether an unusual but not duplicated registration pattern is a group structure or a fraud ring** (T13).
   Fallback: admit and record the relationship; block only on the hard keys in JT1.

---

## moderation_specialist — Marketplace Content & Privacy Reviewer

Reports to `legal`. `routing_tier` reviewer_auditor, with **independent stop authority** granted 14 Aug 2026.
Responsibilities on record: *inspects the actual supplier-facing payload, files and redacted drawings for customer
identifiers and unapproved revisions before any supplier sees them.*

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | cost of a wrong answer |
|---|---|---|---|---|---|
| M1 | Does this supplier-facing payload contain a customer identifier? | gate | every dispatch | marketplace | the customer identified before they chose; the anonymity promise broken from the other side |
| M2 | Does this customer-facing payload contain a supplier identifier before the reveal? | gate | every quote view | marketplace | `governance_policy` #4, **P0** — the 3% reveal fee is consideration for exactly this |
| M3 | Is a masked string still identifying after masking? | diagnosis | per payload | itself | false confidence in `mask_contacts` |
| M4 | Does an attached drawing or file carry a title block, logo or filename that identifies a party? | gate | per file | itself | the leak regex cannot see |
| M5 | Does a file's metadata (author, company, GPS, path) identify a party? | gate | per file | itself | an invisible leak in EXIF or PDF properties |
| M6 | Is this file revision the one the customer approved? | gate | per dispatch | marketplace | suppliers quoting a superseded drawing |
| M7 | Does the RFQ text name a brand in a way that forecloses competition unlawfully? | diagnosis | per RFQ | marketplace | a rigged specification |
| M8 | Is a published page's wording consistent with the live pricing constants? | gate | per publication | `growth`, `legal` | the exact drift `policy_rules` exists to prevent |
| M9 | Does published content violate any of the 7 `policy_rules`? | gate | per publication | `growth` | a contradiction of the founder's own terms in public |
| M10 | Does a marketing claim have evidence in a table? | gate | per asset | `growth` | `governance_policy` #1 |
| M11 | Is a customer testimonial or logo used with permission? | gate | per asset | `growth` | using a name without consent |
| M12 | Does an Arabic page say the same thing as its English counterpart? | diagnosis | per bilingual publication | `growth`, `legal` | two different contracts in two languages |
| M13 | Does a legal page carry the correct version and effective date? | gate | per edit | `legal` | an unversioned change to a contract |
| M14 | Has a `pages` edit desynchronised from `legal_documents`? | diagnosis | daily | `legal` | the published text and the registry disagreeing about what the contract says |
| M15 | Does a supplier's catalogue upload contain third-party IP we cannot display? | gate | per upload | supply, `legal` | publishing someone else's material |
| M16 | Does an uploaded image contain a person whose face needs handling? | gate | per upload | itself | biometric-adjacent personal data with no basis |
| M17 | Does user-generated text contain abuse, discrimination or a threat? | escalation | per submission | `trust_safety_mgr` | harm published under our name |
| M18 | Is a quote's commercial content complete enough to compare fairly? | gate | per quote | marketplace | an unfair comparison presented as a fair one |
| M19 | Does the comparison report present the three quotes symmetrically? | gate | per report | marketplace | a presentational thumb on the scale |
| M20 | Is a supplier's description consistent with their licensed activity? | diagnosis | per profile | `compliance_mgr` | a profile claiming work the licence does not cover |
| M21 | Does the redaction preserve enough for the supplier to quote accurately? | allocation | per drawing | marketplace | over-redaction makes quoting impossible; under-redaction leaks |
| M22 | Which fields are safe to expose in a supplier-facing RFQ? | allocation | per field, per schema change | product | an allowlist drifting into a denylist |
| M23 | Is an outbound template's variable set free of identifiers? | gate | per template | `growth`, messaging | a leak at template scale, not per message |
| M24 | Does a WhatsApp or email template match its Meta/provider-approved body? | gate | per send | messaging | a template rejection, or a send outside approval |
| M25 | Is a notification about to reach a real address during a rehearsal? | gate | per rehearsal | every seat | a fixture email reaching a real person |
| M26 | Does a page's cookie behaviour match the cookie policy? | diagnosis | quarterly | `compliance_mgr` | a policy describing a banner we do not have |
| M27 | Is a form collecting a field the privacy notice does not mention? | gate | per form change | `compliance_mgr` | collection outside the notice |
| M28 | Does an agent-authored deliverable contain a fabricated fact? | gate | per deliverable | every seat | `governance_policy` #1 |
| M29 | Does a deliverable blame the customer? | gate | per deliverable | `cs_support` | `governance_policy` #3, a review-chain rejection reason |
| M30 | Is a number in published content traceable to a query? | gate | per asset | `growth`, `data_intel` | an unsourced number in public |
| M31 | Does content state a supplier count or category count we cannot evidence? | gate | per asset | `growth` | `policy_rules` id 5 forbids a fixed category count |
| M32 | Does content state the subscription term in the founder's exact form? | gate | per asset | `growth` | `policy_rules` ids 3, 4 and 6 all exist for this one mistake |
| M33 | Does content state the reveal fee as 3% uncapped? | gate | per asset | `growth` | `policy_rules` id 7, severity critical |
| M34 | Should a published asset be withdrawn after a policy change? | sequencing | per change | `legal` | stale published claims |
| M35 | Which published assets are affected by a given constant change? | diagnosis | per change | `legal` | a change applied to some pages and not others |

### 2. Domain logic

**M-M1 — Payload leak test.** For a supplier-facing payload *p* (text or jsonb),
`leak(p) = p ≠ mask_contacts(p)` for text, `≠ mask_contacts_jsonb(p)` for jsonb, plus
`mask_name(p, customer_name) ≠ p` for the named-party test. Existing primitives cover emails, URLs, eight social and
messenger domains, UAE international and local mobiles, UAE landlines on six area codes, and bare domains on 20
TLDs. Verdict: any difference ⇒ **hold**. Deterministic, no model.
*Unmeasured:* the residual class — an identity implied without a token. §9.

**M-M2 — Field allowlist.** `safe(field) = field ∈ stored allowlist for the supplier-facing RFQ projection`.
An allowlist, never a denylist, so that a **new column defaults to hidden**. *Does not exist* as a table today; the
projection is defined in code. Making it a table is what lets this seat answer M22 without a deploy.

**M-M3 — File-surface test.** For each attachment: extension against a stored permitted set; filename against
M-M1; embedded metadata (PDF `/Author`, `/Producer`, `/Title`; image EXIF author, GPS, software; Office document
properties) against M-M1; extracted text layer against M-M1. Verdict: any hit ⇒ hold.
*Does not exist:* no metadata-stripping routine and no permitted-extension table exist in this estate. This is the
seat's single largest build item, and it is fully deterministic.

**M-M4 — Revision integrity.** `current(file) = file.sha256 = the sha256 the customer approved`. Inputs: the file
store plus an approval record. *Does not exist:* there is no approved-revision record. `legal_documents` already
demonstrates the pattern — `content_sha256` maintained by a trigger — and the same pattern applies here.

**M-M5 — Published-content rule scan.** `violations(asset) = {r ∈ policy_rules : asset ~* r.forbid_regex}`,
`severity_sum = Σ weight(r)`. Inputs: `policy_rules` (7 active), `pages`, `legal_documents`, campaign assets.
*Measured:* **0 hits across all 12 legal documents today.** The rules are working and the corpus is clean; the gap
is that campaign assets and blog content are not currently in the scanned set.

**M-M6 — Constants consistency.** For each published asset, extract every percentage, AED amount and day count by
regex and compare against the canonical row: reveal **3%** (`pricing_config.standard_reveal_rate`), registration
**AED 1,000/yr** after **1,000** free, admin fee **AED 250**, interest **9% p.a.**, window **5** working days,
chase **3**, bank **7–14**, category-open **10** suppliers. Any mismatch is a **contradiction**; any canonical
constant absent from a page that discusses that subject is a **gap**. All eight constants are single-row lookups.

**M-M7 — Bilingual equivalence.** For an English/Arabic pair, compare the extracted numeric and date sets. Equal
sets ⇒ *numerically equivalent*; unequal ⇒ **hold**. Semantic equivalence of the prose is **not** claimed —
this model checks numbers and dates only, and must say so. The estate already has a precedent: the Arabic pricing
parity check guards the count rule, not the date.

**M-M8 — Registry/page sync.** `synced(slug) = sha256(fn_legal_body_without_labels(pages.body)) =
legal_documents.content_sha256`. Existing machinery: `trg_pages_legal_sync`, `trg_legal_documents_hash`,
`fn_legal_body_without_labels(p_html)`. Measured: both agreement rows carry `source = 'pages:…'` and a live sha.

**M-M9 — Claim evidence test.** Each claim in published content must carry a `source_ref` naming a table and a
query. `evidenced = source_ref is not null and the query returns a row`. *Does not exist:* published assets have no
claim/source_ref structure. `agent_knowledge.supporting_evidence` and `.source_ref` show the pattern the estate
already uses elsewhere.

**M-M10 — Rehearsal safety.** `safe_to_send = decision_policy.demo_rehearsal_active = false or recipient ends
'.invalid'`. Measured: `demo_rehearsal_active` is **false** today. Fixtures are named `ZZ DEMO — …` with
`@example.invalid` addresses; `fn_notifications_release_held()` releases the real backlog afterwards.
This is a hard gate and it is already implemented — the seat's job is to never route around it.

**M-M11 — Symmetry of the comparison.** For the three quotes in a report, check that each has the same populated
field set. `asymmetric = a field populated for some suppliers and blank for others`. Verdict: normalise or annotate,
never present an asymmetric table as a like-for-like comparison. *Unmeasured:* 0 comparisons exist.

### 3. Reasoning procedures

**P-M1 — Clear a supplier-facing RFQ payload (M1, M4, M5, M6, M21, M22)**
1. Project the RFQ through the field allowlist (M-M2). A field not on the list is **absent**, not masked — masking
   a field that should not be there at all is the wrong control.
2. Apply M-M1 to every remaining string and jsonb value.
3. For each attachment, apply M-M3: extension, filename, metadata, text layer.
4. Apply M-M4: is this the approved revision?
5. Any hold ⇒ return the itemised reason to the originator; nothing partial goes out.
6. Clear ⇒ record what was checked and with which regex version, so a later leak can be traced to the gap that
   allowed it.
**Stops and refuses when:** an attachment is a raster image or a scan with no text layer — M-M3 sees the metadata
but not the drawing. That is §9, and the correct behaviour is to hold, not to pass with a caveat.

**P-M2 — Clear a customer-facing quote before the reveal (M2, M3, M18)**
1. Apply `mask_contacts` and `mask_name` to every supplier-originated string. `trg_mask_quote_contact` and
   `scrub_quote_contacts()` already do this at the database boundary — the seat's job is to verify, not to
   re-implement.
2. Verify the masked output does not still identify: check for a company name fragment of ≥ 2 tokens surviving,
   a licence number pattern, a distinctive letterhead string.
3. Verify completeness (M18): the quote has price, scope, validity and lead time.
4. Any residual ⇒ hold and route to `trust_safety_mgr`, because a supplier who keeps embedding identity is an
   integrity case, not a formatting case.
**Stops and refuses when:** the quote is a PDF attachment rather than structured fields — the same image limit.

**P-M3 — Clear published content (M8, M9, M10, M30, M31, M32, M33)**
1. M-M5: run all 7 `policy_rules`. Any critical hit ⇒ **block**.
2. M-M6: compare all eight constants against canonical rows. Contradiction ⇒ block; gap ⇒ warn.
3. M-M9: every claim needs a `source_ref`. Unsourced claim ⇒ block.
4. Check third-party names and marks (M11) against a permissions record.
5. Compose: verdict, rule hits with the matched text, constant comparison table, unsourced claims.
**Stops and refuses when:** the asset makes a qualitative claim with no numeric content ("the fastest way to
quote"). There is no rule that decides that, and this seat says so rather than passing it silently. §9.

**P-M4 — Clear a legal page edit (M13, M14, M34, M35)**
1. Confirm the edit went through `pages`, which is the source of truth for the two agreement bodies.
2. Verify `trg_pages_legal_sync` produced a `legal_documents` update and `trg_legal_documents_hash` a new
   `content_sha256`.
3. Verify the version and `effective_date` were bumped — a body change without a version bump is the failure JL2
   describes.
4. M-M6 across the new body.
5. M-M7 against the Arabic counterpart if one exists.
6. Fan out (M35): find every other published asset containing the changed constant and list them for withdrawal or
   update.
**Stops and refuses when:** no version-history table exists to record the outgoing version — which is today. The
seat's honest output is *"this edit destroys the previous body irrecoverably"*, which is exactly the warning
`legal`'s Q1 deliverable is meant to retire.

**P-M5 — Clear an outbound template (M23, M24, M25)**
1. Enumerate the template's variables; each must be on the allowlist for its audience.
2. Apply M-M1 to the static body — a hard-coded address or link in a template is a leak at scale.
3. Compare against the provider-approved body; any drift ⇒ hold, because an unapproved variant is a rejection.
4. Apply M-M10: rehearsal gate.
**Stops and refuses when:** the recipient list contains a real address during an active rehearsal window — that is
an absolute stop, not a judgement.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JM1 | Any supplier-facing string differs from its masked form | **hold the whole payload** | partial dispatch is a leak with extra steps |
| JM2 | Any customer-facing pre-reveal string identifies the supplier | **P0, hold and page it** | `governance_policy` #4; this is what the 3% is consideration for |
| JM3 | A field is not on the allowlist | **it is absent, not masked** | a denylist grows a hole every time a column is added |
| JM4 | An attachment has no text layer | **hold** | metadata is visible and the drawing is not; a caveat is not a control |
| JM5 | A file's sha does not match the approved revision | **do not dispatch** | suppliers quoting a superseded drawing is a dispute we created |
| JM6 | Redaction would remove information the supplier needs to quote | **escalate the trade-off**, do not silently over-redact | an unquotable RFQ is a failure that looks like caution |
| JM7 | Any `policy_rules` critical hit | **block publication** | ids 1 and 7 are severity critical for reasons already lived through |
| JM8 | A published constant contradicts `pricing_config` or `decision_policy` | **block** | the canonical row wins over any prose |
| JM9 | A claim has no `source_ref` | **do not publish** | `governance_policy` #1 |
| JM10 | An Arabic/English pair has different numbers or dates | **hold both** | two languages must not state two contracts |
| JM11 | A body changed and the version did not | **reject the edit** | an unversioned contract change is unprovable |
| JM12 | A rehearsal is active and a recipient is not `.invalid` | **absolute stop** | a fixture reaching a real person is unrecoverable |
| JM13 | Content names a customer, supplier or brand with no permission record | **do not publish** | consent is a record, not a memory |
| JM14 | A deliverable blames the customer | **return it** | `governance_policy` #3; it is already a review-chain rejection reason |
| JM15 | The seat authored the content | **it may not clear it** | the stop-authority grant says it may never approve work it authored |
| JM16 | An asymmetric comparison would be published as like-for-like | **normalise or annotate** | presentation is part of the product's fairness |
| JM17 | A claim is qualitative and unfalsifiable | **refuse to clear it and say no rule decides it** | passing it silently is the failure; refusing is honest |
| JM18 | Content states a fixed number of trade categories | **block** | `policy_rules` id 5; we are category-agnostic |
| JM19 | Content says "first year free" without the exact terms | **block** | `policy_rules` ids 3, 4 and 6 — three rules for one recurring error |

### 5. Technical knowledge

- **Masking primitives** (must be read before writing any new rule): `mask_contact(s)`, `mask_contacts(t)`,
  `mask_contacts_jsonb(j)`, `mask_name(t, nm)`, `scrub_inquiry_contacts()`, `scrub_quote_contacts()`,
  `trg_mask_quote_contact`. `mask_contacts` covers emails; `https?://` and `www.` URLs; the short-link domains
  wa.me, t.me, bit.ly, instagram.com, facebook.com, fb.com, linkedin.com, twitter.com, x.com; `+971` international
  numbers; local `05x xxx xxxx`; UAE landlines on area codes 02/03/04/06/07/09; and bare domains on
  ae, com, net, org, io, co, me, info, biz, shop, store, online, site, app, dev. `mask_contact` is the narrower
  IMMUTABLE SQL variant used where an index or a generated column needs immutability.
- **Publication path.** `public.pages` is the editable source; `trg_pages_legal_sync` pushes the two agreement
  bodies into `legal_documents`; `trg_legal_documents_hash` maintains `content_sha256`;
  `fn_legal_body_without_labels(p_html)` strips presentation labels before hashing so a cosmetic change does not
  read as a contract change. Routes: `src/app/[locale]/{terms,privacy,cookie-policy,refund-policy,acceptable-use,
  disclaimer,complaints,supplier-agreement,contact}`.
- **Rule engine.** `policy_rules(id, name, severity, forbid_regex, scope, note, active)` — 7 active rules,
  severities **critical ×2** (ids 1, 7), **high ×3** (ids 2, 3, 4), **medium ×2** (ids 5, 6). Scope is `all` on
  every row today.
- **Canonical constants.** `pricing_config` (one row) and `decision_policy` (39 rows). Never restate a constant
  from memory; always read the row.
- **Rehearsal machinery.** `decision_policy.demo_rehearsal_active` (false today);
  `fn_notifications_release_held()`; fixture convention `ZZ DEMO — …` + `@example.invalid`;
  `phase_d_external_message_contract` (4 rows).
- **Authority.** This seat's `employee_authority`: `analysis` **supervised**, and `review_block` **autonomous**
  with no threshold — *"may block unsafe work in its domain and may never approve work it authored."* It is a
  blocking seat by design.
- **Absent and needed:** the field allowlist table (M-M2); a metadata-stripping routine and a permitted-extension
  table (M-M3); an approved-revision record with a sha (M-M4); a claim/`source_ref` structure on published assets
  (M-M9); a third-party permissions record; and `policy_rules` coverage extended from the 12 legal documents to
  campaign and blog assets.

### 6. Academic knowledge

Disciplines: information privacy programme management; data minimisation and de-identification; content policy and
platform governance; technical writing and terminology control; document engineering (PDF and image metadata,
raster vs vector, text layers); bilingual terminology management.

Lawful primary sources: the UAE Data Office's published PDPL guidance on de-identification and minimisation;
ISO/IEC 27701 and ISO 25964 (thesauri and terminology) as published standards; NIST's public guidance on
de-identification of personal information; W3C's published accessibility and internationalisation guidance;
the PDF and EXIF specifications as published by their standards bodies; the Ministry of Economy's published
advertising and consumer material. No copyrighted study texts. No US material.

**Certifications on record:**

- **CIPP/E** (IAPP), pass mark 70%, rank 1 — *"moderation decisions are processing decisions about identifiable
  people."* Syllabus areas: Data Protection Laws; Personal Data; Controllers and Processors; Processing Personal
  Data; Information Provision Obligations; Rights of Data Subjects; International Data Transfers; Supervision and
  Enforcement.
- **CIPM** (IAPP), pass mark 70%, rank 2 — *"consistent moderation needs an operational privacy programme, not
  case-by-case judgement."* Syllabus areas: Developing a Privacy Programme; Privacy Programme Framework;
  Privacy Operational Lifecycle Assess / Protect / Sustain / Respond.

**Syllabus areas failed: does not exist** — no `certification_exam_result` row for `moderation_specialist`. The
CIPP/E *Personal Data* area is the direct theory behind M-M1's residual class, which is this seat's known blind
spot, so the exam has a specific job here.

### 7. Corporate knowledge

- **The single most important fact.** `governance_policy` #4: *"Supplier identity is not disclosed before a paid
  reveal. Any content path that could leak a supplier name, phone, email, domain or licence number pre-reveal is a
  P0 defect."* Enforced by `qa_suite` leak probes, owner `it`. This seat is the human-shaped half of that control.
- **The seven rules and why each exists.** id 1 and 2: we charge suppliers **no commission**, and legacy commission
  language keeps resurfacing. ids 3, 4 and 6: the subscription term has been mis-stated three distinct ways.
  id 5: we are category-agnostic and must not state a fixed category count. id 7 (**critical**): the reveal fee is
  **3% of accepted quote value, uncapped** — the old "2% capped at AED 250" wording is pre-pivot and wrong.
  Measured today: **0 hits across all 12 live documents.**
- **The founder's exact forms.** Registration is free for the first **1,000 registrations**, then **AED 1,000/year**
  — **no date**, because charging begins at registration 1,001 whenever it happens
  (`pricing_config.supplier_charging_starts` is NULL and stays NULL). Reveal is **3%**, no discounts, no caps,
  enforced by constraint. The refund ladder is 5 working days, chase at 3, banks 7–14, AED 250 admin fee, 9%
  per annum.
- **The brand kit** is the reference for every output and lives in `qd-company:brand`; it may be upgraded except
  the logo (founder ruling 6 Sep 2026).
- **Hand-offs.** Repeat leak attempts → `trust_safety_mgr`. Version and clause questions → `legal`. Cookie, consent
  and form-field questions → `compliance_mgr`. Campaign assets → `growth` / `brand_mgr`, whose Brand Manager review
  is already a required step in campaign publishing.
- **History it must not forget.** `legal_checklist` id 1 pointed at a slug `terms-of-service` that never existed
  until 6 Sep 2026 — a check that was green because it was pointed at nothing. That is this seat's cautionary tale
  about presence tests.
- **Does not exist:** a moderation queue table, a moderation decision log, an approved-revision record, a
  permissions record for third-party names and marks, and any coverage of campaign or blog assets by
  `policy_rules`.

### 8. One-year plan

**Objective.** Make every payload and every published word pass a deterministic gate before anyone outside the
company sees it, with the file path closed as well as the text path.

**Direct revenue: AED 0, and it is the guardian of the thing being sold.** The customer pays **3% of the accepted
quote value** for one specific thing: the identity of a supplier they could not otherwise reach. Every pre-reveal
leak converts a paying event into a free one. The arithmetic is stark — at AED 33,333,333 of accepted quote value
and a median accepted quote of AED 50,000, that is ~667 reveals worth ~AED 1,500 each; **a leak rate of 1% is
~AED 10,000 of revenue and a policy breach; a leak rate of 10% means the product does not exist.** M2 is not a
quality metric, it is the revenue model.

**Metrics this seat owns:**

1. **Pre-reveal leak rate** = `100 × dispatches where an identifier reached the other party / dispatches`.
   Target **0**. Today undefined (0 dispatches). The `moderation_specialist` KPI already on record —
   *"Contact-detail leakage in anonymous quotes, 0 incidents per month"* — is this metric, and its
   `no_measure_reason` correctly says there is no demand to measure yet.
2. **File-path coverage** = `100 × dispatched attachments that passed extension + filename + metadata + text-layer
   checks / dispatched attachments`. Today **0%** — M-M3 does not exist.
3. **Published-content compliance** = `100 × assets cleared by P-M3 / assets published`. Today the legal corpus is
   at 100% (0 rule hits across 12 documents); campaign and blog assets are **outside the scanned set**, so the true
   figure is unknown and should be reported as such.

**Quarterly milestones**

- **Q1, Sep–Nov 2026.** Build **M-M3**: permitted-extension table, metadata stripping for PDF/image/Office, text
  layer extraction, filename check. This is the seat's biggest gap and it must close before the first RFQ carries an
  attachment. Build the **field allowlist table** (M-M2) so a new column defaults to hidden. Extend `policy_rules`
  scanning to campaign and blog assets so metric 3 has a real denominator. Sit CIPP/E and CIPM.
- **Q2, Dec 2026–Feb 2027.** Build the **approved-revision record** (M-M4) with a sha, following the
  `legal_documents.content_sha256` pattern. Build the **claim/source_ref structure** so M-M9 is enforceable.
  Implement **M-M7** bilingual numeric parity as a check, stating plainly that it checks numbers and dates, not
  prose. Build the moderation decision log so a clearance is a record, not an absence of complaint.
- **Q3, Mar–May 2027.** Add the residual-identity heuristics that do not need a model: landmark and district
  gazetteer matching, letterhead-string detection, company-name fragment matching at ≥ 2 tokens. Measure and publish
  what they catch and what they miss. Third-party permissions record.
- **Q4, Jun–Aug 2027.** Steady state: leak rate 0, file coverage 100%, content compliance measured across the whole
  published corpus. Report the residual class honestly — what a deterministic gate cannot see.

**Capacity check.** Text masking is regex, already implemented, already running in triggers — microseconds per
payload. The allowlist projection is a set lookup. Metadata stripping is the only real cost: a few hundred
milliseconds per file, at an estimated 2–5 attachments per RFQ and ~56 RFQs a month once flow starts — under 300
files a month, entirely inside a single worker. Published content is ~10–30 assets a month against 7 regexes and 8
constants. **The slice is achievable with room to spare**, and the seat's ability to do it does not depend on
demand — every one of these builds can be finished before the first real RFQ arrives, which is the argument for
front-loading Q1.

**Dependencies.** `product_eng` for M-M2, M-M3, M-M4 and the decision log. `legal` for the version-history table
that P-M4 needs and for the clause index. `growth` for routing campaign assets through P-M3 instead of around it.
`trust_safety_mgr` for repeat offenders. `marketplace` for the dispatch hook.

### 9. What this seat cannot do without a model

1. **See identity inside a raster image or a scan** — a logo, a letterhead, a stamp, a signature, a photograph of a
   site with a visible sign (M4, M16). Model-free fallback: **hold every attachment with no text layer**, and
   require vector or text-layer files at upload. This is the correct control anyway; a caveat is not a control.
2. **Detect identity implied without a token** — "the firm on the corner opposite the Etihad Museum", a distinctive
   turn of phrase, a project reference only two parties know (M3). Model-free fallback: a landmark and district
   gazetteer plus a company-name fragment matcher, which raises the floor without ever reaching the ceiling.
   **The seat must state this residual explicitly on every clearance**, because a clearance that implies
   completeness is worse than one that names its boundary.
3. **Judge whether a qualitative claim is misleading** — "the fastest way to quote", "the best suppliers"
   (M10, JM17). Fallback: refuse to clear unfalsifiable claims and route them to `legal`.
4. **Assess whether an Arabic page means the same as its English counterpart** beyond numbers and dates (M12).
   Fallback: M-M7 checks numbers and dates and says so; prose equivalence needs a bilingual human.
5. **Decide whether an over-redaction has made an RFQ unquotable** (M21). Fallback: a required-field checklist per
   category — if every required field survives redaction, dispatch; otherwise escalate the trade-off rather than
   guessing.
6. **Classify free-text abuse or discrimination** (M17). Fallback: keyword lists plus escalation, accepting false
   positives on a low-volume path.

---

## What this department needs from the founder

Nothing. Every decision in this file is inside the department's own authority or already settled by his standing
rulings. The two things that would change the plan are outside legal's gift and are named where they bite:
**`app_secrets.supplier_outreach_golive`** (until it flips, every gate here has one supplier to gate) and the
**licence-activity extraction** that turns 22,265 leads into screenable, admissible suppliers.
