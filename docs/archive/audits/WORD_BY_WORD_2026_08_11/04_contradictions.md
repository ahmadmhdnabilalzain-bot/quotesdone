> **Archived 16 Nov 2026** (simplification wave B, it_engineer): it describes the word-by-word audit of 11 Aug 2026, of the organisation before the 7-8 Sep 2026 deletions. 3 of the 13 routines it names are gone from production (SELECT pg_proc, 16 Nov 2026). History, not the build today.

# TASK 4 — CONTRADICTIONS: CODE THAT DOES THE OPPOSITE

A **CONTRADICTED** verdict is code that does the opposite of a stated workflow — not code that is
merely missing. Fourteen survived that bar. They are ordered by consequence, not by spec file.

---

## 1. The knowledge base is searched by keyword, not by meaning

**Contract:** spec #7 L827 — *"Search & Retrieval: Fast **semantic** search across company knowledge,
RFQs, suppliers, documents, and conversations."* Spec #8 §6 "Use Local Embeddings", §30 "Retrieval
Instead of Generation".

**Measured.** Of the six retrieval routines in `public`:

| routine | uses `embedding_gte` | uses full-text |
|---|---|---|
| `fn_kb_retrieve` | **no** | yes |
| `fn_dept_library_search` | **no** | yes |
| `fn_ops_knowledge_search` | **no** | yes |
| `fn_memory_search` | **no** | yes |
| `kb_query` | **no** | yes |
| `kb_match` | **yes** | no |

**Five of six are full-text. The one semantic routine is not the one agents call.**
`fn_agent_context` — the function that assembles every employee's prompt — reaches knowledge through
`fn_dept_library_search` and `fn_ops_knowledge_search`, both keyword-only.

> ### CORRECTED 11 Aug 2026, later the same day. Half of this verdict does not survive measurement.
>
> The table above counts **SQL routines in `public`**, and on that evidence it is right. It is not
> the whole reader. `agent_brain.retrieve()` — the path an employee's question actually takes —
> calls the **`kb_search` edge function**, and `kb_search` has been hybrid since it was written:
> it runs `gte-small` over the question, calls **`kb_match`** with the vector, runs the full-text
> query as well, and merges both with reciprocal-rank fusion.
>
> **Probed by execution on production**, `kb_search` with *"chilled water pipe insulation thickness
> Dubai Municipality"*: six results, **all six `via=semantic`**, similarity 0.891–0.922. Not one
> keyword hit reached the top six.
>
> So: `kb_match` **is** called by the employee path, and "make retrieval hybrid first" was work that
> was already done. What remains true, and is now the whole of the finding:
>
> * **`fn_agent_context`'s own layers are still keyword.** LAYER 2b (`fn_dept_library_search`) and
>   LAYER 2c (`fn_ops_knowledge_search`) are full-text, and they are a different corpus from
>   `kb_chunks`.
> * **The semantic half can only see the embedded 42.6%.** `kb_match` filters
>   `embedding_gte is not null`, so the hybrid path is real and looking at less than half the
>   corpus. The backfill is the lever, not the fusion.
>
> Recorded here rather than in a session log, because the un-corrected verdict would have bought a
> day of rebuilding something that already works.

And the embeddings that do exist are 39% complete:

| source_kind | rows | embedded | coverage |
|---|---|---|---|
| `qd_kb_pack` | 115,148 | 43,951 | **38.2%** |
| `document` | 2,752 | 2,528 | 91.9% |
| `trade` | 1,993 | **0** | **0%** |
| `generated` | 354 | 348 | 98.3% |
| `library` | 175 | 175 | 100% |
| `memory` | 60 | 40 | 66.7% |
| `regulation` | 45 | **0** | **0%** |
| `material` | 3 | **0** | **0%** |
| **total** | **120,530** | **47,042** | **39.0%** |

**73,488 chunks have no embedding.** The pack scorecard reports 100% *ingested* and 37 of 37 *in
use*, and both are true — **ingested is not retrievable, and neither word is "embedded".**

This is the deepest instance of the audit's theme: the expensive, sophisticated capability
(pgvector over 120,530 chunks) is built, 61% unpopulated, and bypassed by the code path that
matters. Nobody noticed the backlog because nothing that matters reads it.

**Why it is CONTRADICTED, not ABSENT:** the contract says semantic; the system does keyword while
maintaining a vector column, a vector index and a vector routine. It is not missing the capability —
it built it and routes around it.

---

## 2. `model_policy_by_identity`: 96 rows of dead configuration

**Contract:** spec #8 §13 AI Profiles; spec #7 §5 "The OS should decide which agent should handle a
request".

| scope | rows | resolve to `org_agents` | to `org_departments` | to `org_agent_alias` |
|---|---|---|---|---|
| `current_agent` | 24 | 23 | 3 | 0 |
| `target_employee` | **96** | **0** | **0** | **0** |

96 rows carrying a primary model, a fallback model, an escalation model, a token cap, a reasoning
effort, a manager and an authority tier — **for identities no lookup can reach**. Present identically
on **both** production and staging.

**Re-measured rather than assumed.** The keys are `<department-slug>-<role>` over 24 departments × 4
roles. **48 of 96 already match a slugified `org_departments.name`.** The other 48 fail on two
mechanical drifts:

- **`&` vs `and`** — `hr-and-people-operations` vs slug `hr-people-operations`; likewise
  `administration-and-operations`, `legal-and-compliance`, `qa-and-testing`, `trust-and-safety`,
  `sales-and-crm`, `notification-and-communications` (also plural).
- **renames** — `ai-and-model-operations` ("AI Department"), `it-sre-and-cybersecurity`
  ("IT & Cybersecurity"), `marketplace-operations` ("Marketplace & Procurement"),
  `payments-and-revenue-operations` ("Payment"), `strategy-performance-and-evolution` ("Evolution").

This is **instance 5** of the recurring root cause: *a complete thing addressed to an identity the
system does not model*. The fix shape already exists here — `org_agent_alias` (21 rows) +
`fn_org_agent_resolve`, applied at the **write boundary** by a BEFORE INSERT trigger, never by
widening the reader's join.

---

## 3. Executive Home shows a healthy company with no revenue and no customers

**Contract:** spec #3 screen 1 — Company Health beside Revenue Today, Monthly Revenue, Customers
Active.

Production renders **Company Health as a percentage** beside **AED 0 revenue and 0 customers**. The
health figure derives from `company_goals`, of which **55 of 63 active goals carry no
`measure_sql`**. An unmeasured goal cannot be missed, so it cannot pull the score down.

This is `least(100.0, NULL) = 100.0` promoted to the founder's headline screen. It is the same defect
that put 97.7% attainment in his email on a zero-revenue day, and the same class as the 126/152.

Contrast: `os_objective` carries `measure_sql` on **50 of 50** and an actual value on 46. The OS
layer got this right. The company-goal layer did not.

---

## 4. `fn_scenario_run` verifies staffing and is read as scenario coverage

**Contract:** spec #7 §3 — 16 named exception scenarios, each needing "a predefined recovery
strategy"; spec #3 §34 Organizational Stress Testing.

`scenario_library` holds **19 scenarios, all 19 with a `last_run`**. That reads as full coverage.

- **17 of the 19 are scenarios spec #7 never named.** Of the contract's 16, **13 have no scenario at
  all** — no OCR failure, no corrupted PDF, no ZIP-instead-of-PDF, no vector DB failure, no email
  outage, no WhatsApp outage, no payment gateway outage, no supplier site offline, no locked record,
  no post-quote requirement change.
- **The runner does not inject the failure.** Its own recorded verdict says so:
  *"ORG READINESS READY … Checked against org_departments and org_agents … **This verifies the
  organisation can answer the scenario; it does not claim the failure itself was rehearsed.**"*

The honesty is in the data and is to the previous session's credit. The contradiction is that
**"19/19 ran" is a staffing check being read as disaster-recovery coverage**, and no report
distinguishes them.

---

## 5. The observability trace cannot be produced, and observability reports healthy

**Contract:** spec #7 L1467–L1498 gives an exact eight-step trace as the acceptance test for
observability, ending *"Every step should be logged with timestamps and reasons."*

All eight steps have a routine. **None has ever executed**: `inquiries` 0, `quotes` 0,
`inquiry_matches` 0, `workflow_run` for `rfq_handling` **0**. The health screens report the
observability stack as healthy — over an event stream that has never had an event.

---

## 6. Five named events have emitters that are bound and have never fired

**Contract:** spec #3 §21 Enterprise Event Nervous System, nine named events.

`company_event` carries 17 live types; 4 of the 9 map. The other five:

| spec event | emitter | status |
|---|---|---|
| Customer registered | `fn_emit_customer_registered` | trigger bound, **never fired** (0 customers) |
| Supplier approved | `fn_emit_supplier_approved` | trigger bound, **never fired** (0 approved of 20,470) |
| Marketing campaign launched | `fn_emit_campaign_launched` | **never fired** (campaigns paused at AED 0) |
| Competitor changed pricing | `fn_emit_competitor_pricing_changed` | **never fired** (`market_intel` 0 rows) |
| AI confidence dropped | — | **no emitter exists at all** |

Four of these are among the 30 trigger functions with no table reference — built, bound, silent. The
timeline claims "nothing hidden" while being structurally incapable of showing the company's core
business.

---

## 7. The cache is complete, configured, and empty

**Contract:** spec #8 §7 "Cache Everything", §32 "Semantic Cache".

`llm_cache` has `cache_key`, `prompt_hash`, `hits`, `expires_at`, `saved_usd` **and a semantic
`embedding_gte` column**. `fn_llm_cache_get`, `_put`, `_lookup`, `_store` all exist. **All 61 model
policies carry a `cache_ttl_min`.**

| | production | staging |
|---|---|---|
| `llm_cache` rows | **1** | **0** |
| hits | 2 | — |
| `saved_usd` | **$0.00** | — |

**2 of 1,642 calls in 7 days were cache hits (0.12%).** With the balance at $8.68 this is the
cheapest available saving and nothing needs designing.

---

## 8. Model cascading is configured on 47 of 61 policies and cannot run

**Contract:** spec #8 §4 — *"Never directly call expensive models"* → cheap → confidence <80% →
medium → premium.

**Confidence is reported on 5 of 1,642 calls (0.3%) and on 0 of 622 `claude-sonnet-5` calls.**
A confidence-gated cascade with no confidence escalates every time and pays for both models.

**Building the cascade now would increase cost, not reduce it.** The prerequisite is the output
contract carrying a confidence: `agent_brain` returns prose plus an `@@ACTIONS@@` JSON tail, and
`selfReportedConfidence()` only parses whole-JSON bodies.

---

## 9. The premium/cheap distribution is inverted

**Contract:** spec #8 §2 states the target as a table.

| level | target | actual (calls) | actual (cost) |
|---|---|---|---|
| No AI | 20% | **0.1%** | — |
| Cheap | 55% | **25.2%** | 1.1% |
| Medium | 20% | **36.6%** | 14.2% |
| **Premium** | **5%** | **38.1%** | **84.8%** |

Premium runs at **7.6× its stated budget**. And **Level 0 has no instrument**: a deterministic answer
writes no `ai_cost_log` row, so the level the contract wants biggest is the one nothing counts —
even though `model_policy.deterministic_alternative` is populated on 38 of 61 task classes.

---

## 10. The waste detector never looks at the model doing the spending

`ai_cost_log.could_be_cheaper` flagged **179 calls in 7 days**:

- **175** on `gemini-3.1-flash-lite` — the cheapest model, **1.1% of spend**
- **4** on `claude-opus-4.8`
- **0** on `claude-sonnet-5` — 622 calls, **84% of all spend**

An instrument reporting on the wrong subject. Same class as the 152-check score.

---

## 11. Provider-side prompt caching is losing money, not "roughly break-even"

Re-measured over the **full 7 days** rather than a 10-hour window:

| | tokens |
|---|---|
| cache write | **85,342** |
| cache read | **9,851** |
| ratio | **0.115** |
| break-even (5-min TTL) | **0.278** |

The previous session measured 0.216 over 10 hours and recorded "roughly break-even". Over the full
window it is **less than half of break-even**.

---

## 12. `dept_key = 'knowledge'` is named "Administration & Operations"

The `org_departments` row named **"Administration & Operations"** has `dept_key = 'knowledge'`, and
its staff are `docs`, `ops_director`, `process_improvement_mgr`, `project_coordinator`. A separate
`knowledge_eng` ("Knowledge Engineering") department also exists.

Any code routing on `dept_key='knowledge'` reaches Admin & Ops. Any human reading `dept_key` believes
it reached Knowledge. `scenario_library.regulatory_change` names departments
`legal, procurement, knowledge` — which resolves to Admin & Ops, not Knowledge Engineering.

---

## 13. Layer 4 delivers internal learnings where the contract specifies external authority

**Contract:** spec #7 L541 — *"Layer 4 – External Knowledge: UAE regulations, industry standards,
manufacturer catalogs, and other authoritative external sources."*

`fn_agent_context` emits `# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED` — internal, the opposite
direction. The external stores exist and are populated: `regulations` 17, `reg_catalog` 38,
`compliance_sources` 17, `mdm_standards` 22, `mdm_manufacturers` 22, `supplier_catalog` 2.
**`fn_agent_context` references none of them** (each table name matched against the function body).

**118 rows of external authority are held and reach no employee.**

Related, same function: Layers 2b/2c exist only in the 3-argument overload, and **9 of 11 callsites
pass no `p_query`** — so 82% of callers silently receive no department knowledge.

---

## 14. Spec #5 §7 states a transformation ratio the pipeline has never demonstrated

**Contract:** *"Catalog.pdf 500 pages → Products: 245, Categories: 18, Specifications: 12,500
attributes, Searchable: YES."*

Built: `SupplierCatalogUpload.tsx`, `fn_supplier_products`, `supplier_catalog`, `supplier_product`,
`supplier_product_variant`. Holding: **2 catalogues, 7 products, 4 variants.**

---

# The shape behind eleven of the fourteen

Nine of these fourteen are the same defect wearing different clothes:

> **An instrument reports on something other than the thing it appears to measure, and no surface
> distinguishes "measured zero" from "never measured".**

- 19/19 scenarios = a staffing check (#4)
- observability healthy = no events (#5)
- 126/152 rising = 24 unmeasured claims, some large (spec #3)
- Company Health high = 55 of 63 goals unmeasurable (#3)
- 100% ingested = 61% unembedded (#1)
- BOTH PROJECTS IN SYNC = 418 = 418 tables, while **staging has 255 empty tables against
  production's 96**, `board_advisor` 0 vs 7, `workflow_run` 7 vs 198
- `could_be_cheaper` = flags the cheap model (#10)
- `least(100, NULL) = 100` — the original instance

**The single highest-value change this audit can recommend is not a deletion and not a feature.** It
is that any surface reporting a number derived from an empty table, an unmeasured goal, or an
unexercised mechanism must say **"no data yet"** rather than `0`, `100%`, `READY` or `IN SYNC`.
Every item in that list would have been caught by it.

---

# The identity vocabulary problem, stated precisely

The brief expected a large orphan count. Measured, it is narrower and sharper:

| column | rows | unresolved | distinct | distinct unresolved | verdict |
|---|---|---|---|---|---|
| `kb_usage_log.agent` | 81 | 0 | 12 | 0 | clean |
| `ai_quality_snapshots.agent` | 1,115 | 171 | 35 | 7 | 7 stale keys |
| `agent_actions.agent` | 2,450 | 415 | 54 | 28 | PARTIAL |
| `agent_expectations.agent` | 121 | 108 | 121 | 108 | **not a defect** — job names |
| `agent_runs.agent` | 20,530 | 17,911 | 123 | 109 | **not a defect** — documented as job names |
| `agent_knowledge.agent_key` | 2,040 | 1,741 | 234 | 141 | **not employees** — `cat:*` and `_global` |
| `model_policy_by_identity` | 96 | **96** | 96 | **96** | **CONTRADICTED** |

A column named `agent` or `agent_key` carries **four vocabularies** in this database — employee keys,
cron job names, `cat:<category>` keys, and `_global` — with **no discriminator column and no foreign
key anywhere**. `model_policy_by_identity` is the only one matching *none* of the four, which is why
it is the only CONTRADICTED row here.

**`org_agents.manager_key` is the counter-example and the proof it is fixable:** 93 of 94 set, every
one resolving, hierarchy complete and acyclic — 100% referential integrity in the same database.

The brief's figures for two of these (`ai_quality_snapshots` 754/1,066; `agent_expectations` 29/36)
do not reproduce. Current measurements are above.
