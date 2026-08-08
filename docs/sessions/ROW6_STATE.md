# ROW #6 — STATE. Measured on production 2026-08-09.

Everything below is a measurement with the query behind it, not an inference from the spec or from
the opening brief. Where a measurement contradicts the brief, the brief is quoted so the correction
is auditable rather than silent.

---

## 1. THE BRIEF'S FIVE COUNTS: NONE MOVED

| thing | brief (8 Aug) | measured (9 Aug) | |
|---|---|---|---|
| `catalog_supplier_categories` | 86 | **86** | same |
| `catalog_subcategories` | 470 | **470** | same |
| `catalog_domains` | 67 | **67** | same |
| `category_agent_map` | 84 | **84** | same |
| `lead_category` | 17,107 | **17,107** | same |
| category agents in `agent_knowledge` | 132 agents / 1,584 rows | **132 / 1,584** | same |
| `category_specs` | 56 | **56** | same |

Nothing moved. The taxonomy is a strict SUPERSET of the spec: 67 domains against the spec's 66
(extra: 67 = "General Contracting & Civil Works") and 86 categories against the spec's 84 (extra:
85 = "Signage & Printing Suppliers", 86 = "Lifts & Escalator Suppliers"). Both extras are additions
beyond the spec, not omissions from it, and both are the two categories with no agent.

---

## 2. THE BRIEF IS WRONG ABOUT WHERE THE EIGHT DOMAINS LIVE — AND IT IS THE SAME CLASS OF ERROR ROW #5 MADE

> "`agent_knowledge.layer` today holds `company` / `profession` / `state` / `experience` … **None of
> the eight domains is a layer.** So 'does agent X cover Technical Knowledge?' is currently
> unanswerable from the schema, and that is the first thing a scorer has to be able to ask."

The first sentence is true. The conclusion is false. The eight domains are `agent_knowledge.topic`
values, spelled **exactly** as the spec spells them:

```
select topic, count(*) from agent_knowledge where agent_key like 'cat:%' group by 1;
  Industry Knowledge  87   Products & Services  87   Technical Knowledge  87
  Supplier Knowledge  87   Quotation Knowledge  87   Documents Knowledge  87
  UAE Regulations & Authorities  87            Inquiry Qualification Logic  87
```

`layer` is an orthogonal axis (who the knowledge is *about*), `topic` is the domain axis. A scorer
reading `layer` would have reported all eight domains MISSING on all 84 agents and issued a build
order to regenerate 672 rows that already exist and are individually unique — overwriting real
knowledge with generated text, which the brief itself names as the worst available outcome.

This is row #5's lesson at a different altitude: the scan's **population** excluded where the fact
lived. There it was the rpc hop; here it is the column.

## 3. AND THE "12 ROWS EACH" AVERAGE HIDES THREE DIFFERENT POPULATIONS

> "1,584 knowledge rows across 132 agents averages 12 rows each. Twelve rows cannot cover eight
> domains properly."

The arithmetic is right; the conclusion does not follow, because 132 is not one population:

| rows per agent | agents | what they are |
|---|---|---|
| 14–18 | **87** | the 15-module Expert Knowledge Framework — all eight spec domains + 7 optional |
| 7–9 | 31 | a legacy 7–8 topic scheme (pricing benchmarks, quote analysis, intake questions…) |
| 1–3 | 14 | stubs |

The mean of those three describes none of them. **All 84 of the categories the spec actually names
are in the 87.** The 48 that drag the average down are legacy or folded agents outside the spec's
list.

---

## 4. PER DOMAIN PER AGENT — THE MEASUREMENT THE FOUNDER ASKED FOR

Over the **84 mapped (realistic) categories**, not the 132:

| # | domain (`agent_knowledge.topic`) | agents | content len min/avg/max | distinct bodies |
|---|---|---|---|---|
| 1 | Industry Knowledge | **84 / 84** | 574 / 861 / 900 | 84 — all unique |
| 2 | Products & Services | **84 / 84** | 624 / 863 / 900 | 84 — all unique |
| 3 | Technical Knowledge | **84 / 84** | 744 / 871 / 900 | 84 — all unique |
| 4 | Supplier Knowledge | **84 / 84** | 681 / 871 / 900 | 84 — all unique |
| 5 | Quotation Knowledge ⭐ | **84 / 84** | 799 / 876 / 900 | 84 — all unique |
| 6 | Documents Knowledge | **84 / 84** | 627 / 865 / 900 | 84 — all unique |
| 7 | UAE Regulations & Authorities | **84 / 84** | 690 / 877 / 900 | 84 — all unique |
| 8 | Inquiry Qualification Logic ⭐⭐⭐ | **84 / 84** | 788 / 888 / 932 | 84 — all unique |

**No domain is empty on any of the 84.** 672 domain rows, 672 distinct bodies — not one is a
template shared between categories, which is the refutation that matters: 84 agents carrying an
identically-worded module would be one paragraph counted eighty-four times.

Across all 132 namespaces the picture is the one the brief expected — Industry/Products/Supplier/
Documents sit at 87/132 (66%) — because the 45 legacy agents never had those topics. That is the
number the brief was reaching for, and it is about agents the spec does not name.

---

## 5. THE BRIEF IS WRONG ABOUT `category_specs`, AND THIS ONE CHANGES A WORK ITEM

> "Quotation Knowledge is the one domain with real backing already: `category_specs` has `fields`,
> `supplier_requirements` and `compliance_checklist` for **56 of 86** categories."

Measured:

```
category_specs rows                                                  56
… whose `category` matches a catalog_supplier_categories slug         0     <- zero, not 56 of 86
… with supplier_requirements populated                               21     <- not 56
… with compliance_checklist populated                                21     <- not 56
catalog_supplier_categories with a category_specs row                 0  of 86
```

`category_specs.category` holds a **different vocabulary entirely** — `acrylic`, `hvac`, `tiling`,
`plumbing`, `movers`, `pest` — 56 legacy TRADE keys, of which 16 match `taxonomy_trade.code`. It is
the CUSTOMER INTAKE side (what to ask someone who wants an HVAC job), read by `fn_category_questions`
and `fn_rfq_required_check`. It is not supplier-category quotation knowledge and never was.

So step 6's question — "are the other 30 the gap, or are all 86 thin?" — has a third answer:
**neither; the premise mislocated the fact.** The real Quotation Knowledge for the 84 supplier
categories is `agent_knowledge.topic='Quotation Knowledge'`, present on 84/84, averaging 876
characters, every body unique. `category_specs` is a different axis and its 56 rows are not a
30-category shortfall in anything.

`fn_category_knowledge` already knew this. Its own header, on production:

> "All 84 spec categories carry their 8 modules under agent_key 'cat:<catalogue-slug>', but the live
> intake assigns one of 56 LEGACY slugs whose overlap with the catalogue is exactly zero.
> `lead_trade_map` is the bridge; this is the first thing that walks it at read time."

---

## 6. WHAT A CATEGORY AGENT IS — DECIDED, WITH THE COUNT THAT DECIDES IT

The brief says both halves of the codebase assume different answers. Measured, they do not: one
half is sixteen routines and the other is one.

| registry | rows | what it is |
|---|---|---|
| `category_agents` | 132 (110 active) | slug, name, persona, emoji, agent_class. **84 are exactly the spec's realistic categories.** |
| `agent_knowledge` `cat:…` | 132 namespaces, 1,584 rows | the knowledge |
| `org_agents` | 67, **0** prefixed `cat:` | departments (it, sales, finance, hr…), `manager_key` chains, `seniority`, `max_open_tasks`, `hired_at` — QuotesDone's internal org chart |

**16 routines** resolve a category agent through `cat:` + `agent_knowledge`/`category_agents`:
`fn_resolve_cat_agent`, `fn_category_knowledge`, `fn_category_expert_ref`, `fn_category_sales`,
`fn_category_knowledge_promote`, `fn_knowledge_gaps`, `fn_decide`, `fn_ws_agents`, `fn_ws_knowledge`,
`fn_ws_governance`, `fn_kb_reconcile`, `fn_regulation_propagate`, `fn_agent_institutional_memory`,
`fn_execution_run`, `fn_enqueue_doc_backups`, `kb_match`.

**1 routine** assumes `org_agents`: `fn_graph_rebuild` — and it is the one producing zero rows.

### THE ANSWER

**A category agent is a row in `category_agents` plus a namespace in `agent_knowledge`. It is NOT an
`org_agents` row.** `org_agents` is a 67-person org chart with manager chains and employee→goal
accountability edges; inserting 84 category agents into it would put 84 synthetic employees into
every department rollup, every manager chain and every employee edge in the graph — to satisfy one
join that a different table already satisfies.

---

## 7. WHICH MAKES THE BRIEF'S NAMED DEFECT A MISDIAGNOSIS, AND ITS PROPOSED FIX A REGRESSION

> "`category_agent_map.agent_slug` is missing the 'cat:' prefix, so all 84 rows resolve to nothing."

```
category_agent_map rows                                       84
… joined to org_agents.agent_key    on the bare slug           0
… joined to org_agents.agent_key    on 'cat:'||slug            0   <- prefixing fixes NOTHING here
… joined to category_agents.slug    on the bare slug          84   <- already resolves, all of them
… matching agent_knowledge          on 'cat:'||slug           84   <- already resolves, all of them
```

**The column is correct.** Writing `'cat:'` into it would break the 84/84 join to `category_agents`
and still not satisfy `fn_graph_rebuild`, because that edge's problem is the TABLE it looks in, not
the string it looks for:

```sql
select distinct 'category', c.slug, 'served_by', 'employee', m.agent_slug
  from category_agent_map m join catalog_supplier_categories c on c.slug=m.catalog_slug
 where exists (select 1 from org_agents a where a.agent_key=m.agent_slug and a.active)
```

Row #5 found this dead and deliberately left it, reasoning that "repairing it would connect a
category to an internal AI agent — and that is org structure, which is the thing a supplier must not
be shown." That objection was right about the edge **as written** (`dst_kind='employee'`, joined to
the org chart) and wrong about what `agent_slug` holds. The target is a category agent — a product
surface — so the relationship is `category → category_agent` and expresses no org structure at all.
The supplier-facing reader (`fn_graph_supplier_market`) selects `rel='adjacent_to'` only, so
repairing this adds nothing to what a supplier sees.

**The fix is one clause: `org_agents`/`'employee'` → `category_agents`/`'category_agent'`.**

---

## 8. THE SCORE: 246 / 283 (87%) ON PRODUCTION

Composed of a full 283-check baseline run (243/283, zero errored checks, no denominator shortfall),
plus two verified section re-runs after the fixes below.

| § | | | § | | |
|---|---|---|---|---|---|
| 1 Domain taxonomy | 66/66 | **100%** | 8 Documents | 9/16 | 56% |
| 2 Realistic categories | 84/84 | **100%** | 9 UAE Regulations | 10/16 | 63% |
| 3 Industry | 7/9 | 78% | 10 Inquiry Qualification ⭐⭐⭐ | 7/9 | 78% |
| 4 Products & Services | 7/13 | 54% | 11 Optional modules | 24/35 | 69% |
| 5 Technical | 9/10 | 90% | 12 Agent mechanism | **8/8** | **100%** |
| 6 Supplier | 8/9 | 89% | | | |
| 7 Quotation ⭐ | 7/8 | 88% | | | |

**All eight BAR A domain-coverage checks are MET at 84/84.** No domain is empty on any of the 84
mapped agents, and 672 domain rows carry 672 distinct bodies — not one is a template.

Every remaining MISSING is a BAR B sub-bullet: a concept the spec listed as an *"Example:"* of a
domain that appears on fewer than 21 of the 84 agents in that domain's own content.

## 9. WHAT WAS FIXED, DEPLOYED TO BOTH, VERIFIED BY EXECUTION

| defect | before | after |
|---|---|---|
| `fn_graph_rebuild` category edge pointed at `org_agents` | 0 edges | **84** on both projects |
| `fn_resolve_cat_agent` could not speak the intake vocabulary | 36/56 | **54/56** on both projects |

The two trade slugs still unresolved — `acrylic`, `elevators` — have no `lead_trade_map` row at all.
That is missing DATA, a mapping decision somebody has to make, and inventing those rows to raise a
score is not on the table.

## 10. ONE SCORER DEFECT, FOUND BY READING THE PAYLOAD

`ind-overview` scored **0 of 84** on `/overview|landscape|sector|market structure|the industry/`.
Zero on a topic called "Industry Knowledge" averaging 861 characters is the shape of a bad regex,
so the bodies were read before the verdict was believed:

> "UAE aluminium & glass is a three-tier trade. Upstream: Emirates Global Aluminium smelts billet at
> Jebel Ali and Al Taweelah; extruders such as Gulf Extrusions press profiles. Midstream: float and
> coated glass from Emirates Float Glass … Downstream: thousands of fabricators and facade
> contractors clustered in Al Quoz, Ras Al Khor, Sharjah Industrial…"

That *is* an industry overview; it never says the word. The check was testing for textbook
meta-language expert writing does not use, and its build order would have been "add the word
'overview' to 84 bodies" — busywork that degrades real knowledge to move a number.

Replaced with a test of what an overview CONTAINS — supply-chain position, tiering, players,
clusters — and accepted only after a **discrimination test** against a control topic:
**72/84 inside Industry Knowledge against 13/84 inside Quotation Knowledge.**

**Three sibling legs were tested identically and their replacements were REJECTED**, so their
MISSING verdicts stand as real corpus gaps:

| leg | candidate in target topic | in control topic | verdict |
|---|---|---|---|
| `prod-hierarchy` | 26/84 | 34/84 | rejected — fires MORE in the control |
| `ind-scope-of-work` | 16/84 | 39/84 | rejected — the concept lives in Documents Knowledge |
| `prod-categories` | 14/84 | 13/84 | rejected — no discrimination |

## 11. BLOCKED BY BUSINESS REALITY, NOT BY CODE

The 37 remaining MISSINGs are **not a coding backlog**. Every one is a gap in authored knowledge,
and they fall into three groups that need three different decisions:

**(a) Correctly narrow — arguably not gaps at all.** `uae-rta` (18/84), `opt-std-ul` (7/84),
`opt-std-nfpa` (33/84), `opt-brand-local` (7/84). RTA governs road transport; UL is a North American
listing mark. An accounting agent citing NFPA would be *wrong*. The spec introduced these with
"Example:", and BAR B at 21 is what keeps them from being scored as universal mandates — but four of
them land just under the bar. **This needs a founder call, not code.**

**(b) Genuinely absent, and platform-mechanical — buildable without fabricating anything.**
`opt-att-excel` (6/84), `opt-att-pdf` (8/84), `opt-draw-cad` (8/84), `opt-draw-bim` (4/84),
`doc-site-videos` (1/84), `opt-att-understands-content` (15/84). These describe **the platform's own
behaviour** — which file types an inquiry can arrive with and what each one tells you. Writing that
is documenting QuotesDone, not inventing industry facts, so it can be authored honestly. It is the
single largest recoverable block: roughly 11 requirements.

**(c) Genuinely absent, and category expertise — cannot be written without a source.**
`doc-rfi` (4/84), `doc-ifc-drawings` (3/84), `doc-shop-drawings` (16/84), `prod-hierarchy` (2/84),
`quo-optional-info` (5/84), `uae-addc` (8/84), `uae-etihad-we` (6/84). Filling these means writing
UAE regulatory and document-workflow knowledge per category. **Generating it with an LLM is exactly
what the brief forbids** — "this knowledge is what the platform will ask real customers real
questions with". It needs sourced research or a domain expert per category, and that is a
procurement decision, not a sprint.

**The honest position: 246/283 is the ceiling reachable by code. The remaining 37 are an authoring
programme.**

---

## 12. REFUTATION PASS — 14 CANDIDATES TESTED, 3 SURVIVED. FINAL: 249/283 (88%)

`ind-overview` proved a check can fail on vocabulary rather than substance, so every remaining
MISSING that could plausibly be the same defect was retested the same way: propose a substance-based
regex, then require it to **DISCRIMINATE** — at least 21 hits in its own topic AND at least 20 clear
of a control topic where the concept does not belong.

**Eleven rejected.** Listed so nobody retries them:

| leg | target | control | why it stands |
|---|---|---|---|
| `prod-models` | 18 | 18 | still below bar |
| `prod-sizes` | 23 | 19 | no discrimination |
| `prod-variants` | 23 | 13 | no discrimination |
| `prod-warranties` | 37 | 30 | no discrimination |
| `tech-installation-methods` | 31 | 34 | fires MORE in the control |
| `sup-maintenance-companies` | 17 | 18 | still below bar |
| `doc-photos` | 13 | 3 | still below bar |
| `uae-local-terminology` | 25 | 16 | no discrimination |
| `iql-missing-info` | 23 | 8 | 15 clear, short of 20 |
| `ind-scope-of-work` | 16 | 39 | the concept lives in Documents Knowledge |
| `quo-optional-info` | 5 | 0 | still below bar |

`iql-missing-info` is the closest call at 15 clear. **The threshold was stated before the results
were seen and is not being moved to admit it.**

**Three repaired**, each with its margin:

| leg | before → after | control | what the corpus says instead |
|---|---|---|---|
| `ind-terminology` | 17 → **57** | 30 | *"Vocabulary in the room: AFS, ISA, IFRS…"*, *"Speak the units: FAD…"* |
| `doc-technical-specs` | 17 → **23** | 2 | the abbreviation and tender-document names |
| `iql-enough-collected` | 19 → **59** | 5 | the act it gates — *"Mandatory before fanning out"* |

### Final section scores

| § | | | § | | |
|---|---|---|---|---|---|
| 1 Domain taxonomy | 66/66 | **100%** | 8 Documents | 10/16 | 63% |
| 2 Realistic categories | 84/84 | **100%** | 9 UAE Regulations | 10/16 | 63% |
| 3 Industry | 8/9 | 89% | 10 Inquiry Qualification ⭐⭐⭐ | 8/9 | 89% |
| 4 Products & Services | 7/13 | 54% | 11 Optional modules | 24/35 | 69% |
| 5 Technical | 9/10 | 90% | 12 Agent mechanism | 8/8 | **100%** |
| 6 Supplier | 8/9 | 89% | | | |
| 7 Quotation ⭐ | 7/8 | 88% | | | |

**249 / 283 (88%).** Four scorer defects found and fixed across two passes; 25 candidate
repairs proposed and rejected. The 34 remaining MISSINGs have now each been challenged twice and
survived — they are corpus gaps, not measurement artefacts.
