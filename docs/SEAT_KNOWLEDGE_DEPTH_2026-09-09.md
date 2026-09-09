# What a twenty-year professional holds that our seats do not

**Date:** 9 September 2026 · **Project:** `htdblwldjkcgjvmqkbeh` · **Agent:** `ceo`
**Answers founder instruction #13** ("every seat needs to be equal to a real human with twenty years'
experience… the numbers are way too low for every seat") **and #14** ("the general reference library
has to be ingested properly, with keywords — it has to be like a brain, not just text").

This document does **not** propose adding rows of the same shape. It says, per seat, which of that
seat's **own recorded decisions** it can and cannot make today, and why. Every number below was
measured against production on 9 Sep 2026 and the query that produced it is stated.

**Read sections 0 to 4 as the state at the START of this session.** They are the diagnosis, and they
describe the corpora before anything was added — `sales_knowledge` at 1,136 rows, `kb_chunks` at
166,093 embeddings. Section 5 says what changed and section 6 lists what was deliberately left open.

---

## 0. The finding that changes the answer to "the numbers are too low"

The founder is right that the seats are thin, but **row count is not the axis on which they are
thin, and adding rows of the current shape would make retrieval worse, not better.**

`sales_knowledge` is the largest seat corpus at **1,136 rows**. **896 of them (78.9%) are
`qualification_field` records** — one interview question each, wrapped in four sentences that are
*identical across every row of the same trade*:

```
Sector: <trade>. Scope: <same for all 7 rows of this trade>.
Question: <the only varying line>
Field: <trade>.<field>. Ask only if material and unresolved after evidence extraction. …
Matching caution: <same for all 7 rows of this trade>
Supplier evidence: <same for all 7 rows of this trade>
```

A further **128 rows are `sector_guide`** records built from one authored template; all 128 carry the
sentence *"Resolve from accepted documents or the current conversation first"* and all 128 end with
*"Coverage status: Authored intake foundation; not an exhaustive engineering manual…"* — the corpus
says of itself that it is not the thing the founder is asking for.

### The template has collapsed the vector space

`fn_accountant_assist` — the estate's best retrieval discipline — admits a row only if it clears a
**cosine floor of 0.86** *and* corroborates lexically. Measured across the 128 `sector_guide` rows,
which are 128 **different trades**:

| corpus | distinct pairs | pairs at cosine ≥ 0.86 | mean cosine |
|---|---|---|---|
| `sales_knowledge` sector guides | 8,128 | **8,033 (98.8%)** | **0.8925** |
| `accountant_knowledge` (all rows) | 6,328 | 911 (14.4%) | 0.8302 |
| `it_engineer_knowledge` (all rows) | 3,081 | 206 (6.7%) | 0.8248 |

*(query: pairwise `1 - (a.embedding_gte <=> b.embedding_gte)` over each corpus, self-join on
`a.record_id < b.record_id`)*

The nearest neighbours of **"Partitions and drylining"** are its own seven interview questions
(cosine 0.933–0.952) and then **"Masonry, blockwork and plaster" at 0.9262** — a different trade,
sitting 0.066 *above* the admission floor. In this corpus the cosine floor separates nothing.
Retrieval is being carried entirely by the lexical corroboration leg, which is precisely the leg the
floor exists to backstop.

**Therefore: 896 near-duplicate rows are not 896 units of expertise. They are one template with 896
subjects, and each new row of that shape raises the noise floor for every query.** The corpora that
were hand-authored with varied content (accountant, IT engineer) separate cleanly at a seventh of the
density. Depth comes from *distinct, decidable content*, not from row count.

### Two of the five seats have no semantic index at all

| seat corpus | rows | embedded | index |
|---|---|---|---|
| `accountant_knowledge` | 113 | 113 | vector + tsvector |
| `it_engineer_knowledge` | 79 | 79 | vector + tsvector |
| `sales_knowledge` | 1,136 | 1,136 | vector + tsvector |
| `ops_knowledge` | 9,139 | 9,139 | vector + tsvector |
| **`support_knowledge`** | **408** | **0 — no embedding column exists** | tsvector only |
| **`ceo_knowledge`** | **508** | **0 — no embedding column exists** | tsvector only |

`fn_support_knowledge_search_vector` and `fn_ceo_knowledge_search_vector` are **tsvector triggers,
not embedders** — the word "vector" in their names means the full-text vector. Both corpora are
keyword-only. The two seats the founder actually kept (`ceo` and `customer_support`) are the two that
cannot retrieve by meaning. That is the sharpest form of instruction #14: for those seats the library
literally *is* just text with keywords, and never became a brain.

### The estate is a UAE company whose seats do not know they are in the UAE

| corpus | rows | rows mentioning UAE / Dubai / Emirates | rows containing "AED" |
|---|---|---|---|
| `ceo_knowledge` | 508 | **3** | 29 |
| `support_knowledge` | 408 | **1** | 2 |
| `accountant_knowledge` | 113 | 22 | **1** |
| `it_engineer_knowledge` | 79 | 2 | 0 |
| `sales_knowledge` | 1,136 | 1,136 (boilerplate line) | **0** |
| `ops_knowledge` | 9,139 | — | 646 |

`sales_knowledge`'s 1,136 UAE mentions are the same templated sentence, not 1,136 UAE facts: **zero
rows contain an AED figure**, and across all 9,139 `ops_knowledge` rows exactly **one** carries a
per-unit AED rate.

---

## 1. Accountant — `accountant_knowledge`, 113 rows

**Owned decisions** (`org_role.owned_decisions`):
1. how a receipt is classified against the chart of accounts
2. what the ledger says the company spent and earned
3. whether a figure is measurable or must be reported as unknown
4. when a refund is due under the published policy

**What it can do.** Decisions 1–3 are genuinely supported. 30 rows are `chart_of_accounts` records
across asset/expense/liability/revenue/equity; `epistemics · authority_protocol` (5 rows) is the
"measurable or unknown" discipline, and it is enforced in code, not just described — the seat's
`forbidden_decisions` include *"publishing a financial figure it cannot bind to a source row"*. This
is the one seat whose refusal behaviour is real.

**What a twenty-year UAE accountant holds and this seat does not.**

`accountant_knowledge` has 12 rows of `record_type = 'obligation_shape'` (8 VAT, 3 corporate tax,
1 each for audit/records/other registers/licensing/penalties). An **obligation shape is the sentence
that an obligation exists, with the number removed.** `fn_accountant_assist`'s own refusal text says
so out loud:

> "If it needs a rate, a threshold, a deadline or a penalty, that figure is deliberately not held in
> my knowledge: it is published by the Federal Tax Authority and must be read from its current
> publication for the period concerned."

That was a defensible choice for figures that move. It is **not** defensible for the stable, boolean,
procedural knowledge a working UAE accountant carries, which is simply absent. Measured by substring
search over `content` and `title`:

| what a UAE accountant is asked weekly | rows in corpus |
|---|---|
| the fourteen particulars the FTA requires on a **tax invoice** (Art. 59, Exec. Reg.) | 5 rows mention "tax invoice"; **none list the required particulars** |
| the AED 375,000 mandatory VAT registration threshold | **0** ("375,000" appears nowhere) |
| **EmaraTax** — the portal every filing actually goes through | **0** |
| what a **corporate tax return** is and when it is due | **0** |
| **designated zone** VAT treatment | **0** |
| **free zone** qualifying income / 0% regime | 2 rows mention "free zone", neither states the test |
| the **FTA audit file** / records-retention format | **0** |
| **WPS** (Wage Protection System) — payroll's hard constraint in the UAE | **0** |
| **IFRS** / IFRS for SMEs — the basis the accounts must be prepared on | **0** |
| **reverse charge** on imported services | 1 |

**Concretely: the accountant cannot answer "what must appear on a tax invoice we issue to a UAE
customer", cannot answer "must we register for VAT yet", and does not know the name of the portal it
would file through.** None of those are volatile figures; all of them are the standing procedural
knowledge that makes the difference between a bookkeeper and a twenty-year accountant. Decision 4
("when a refund is due under the published policy") is supported by only 4 `refunds` rows and no
worked example of a *contested* refund — the case a senior accountant is actually consulted about.

**Gap recorded, not filled:** everything in the table above is UAE statutory/procedural knowledge
that is not in the estate and cannot be manufactured from it. Writing it from model memory would
violate the founder's standing rule against stating what has not been measured, and this corpus is
the one place in the estate where a fabricated figure becomes a filed number. It needs a sourced
ingest (FTA publications), not generation.

---

## 2. Sales engineer — `sales_knowledge`, 1,136 rows

**Owned decisions:**
1. what technical question must be asked to resolve a material uncertainty
2. whether an inquiry is quote-ready and on what quote basis
3. how a composite request resolves into prime, separate lots or a hybrid
4. whether a supplier capability claim is supported, and by which class of evidence
5. which suppliers pass the mandatory gates and how survivors rank
6. what a supplier may see: the supplier-safe derivative and its boundaries

**What it can do.** Decision 1 is over-served: 896 rows exist for exactly this and nothing else.
Decisions 4–6 are supported by the `judgment` (32), `measurement` (28) and `sales_engineering` (27)
records, which are hand-written and separate properly in the vector space.

**What a twenty-year Dubai fit-out sales engineer holds and this seat does not.**

**(a) Not one price.** The seat exists to judge whether a quote is fair. **Zero of 1,136 rows contain
"AED".** No trade has a unit-rate band, so decision 2 ("whether an inquiry is quote-ready **and on
what quote basis**") can name a basis but cannot sanity-check a number, and a returned quote of
AED 900/m² for a plain gypsum ceiling would pass through the seat unremarked. This is the gap the
founder named in instruction #15 and it is closed in §5 below.

**(b) No specification defaults.** The partitions guide asks *"Are partitions gypsum, glazed,
demountable or another specified system?"* — but holds no record of what a standard UAE gypsum
partition **is** (single vs double stud, 12.5 mm board, 92 mm track, insulation or not). A real
engineer answers the customer's "just do a normal partition" from that default. This seat must
escalate it as an unresolved field, which is how a marketplace loses an inquiry.

**(c) No UAE regulatory gates on the trades.** The corpus knows *that* mandatory credentials exist —
`taxonomy_trade.authority_required` is a column — but the seat's own knowledge does not name which
authority gates which trade. **A twenty-year engineer in Dubai knows before the customer finishes
speaking** that CCTV is SIRA, that fire systems are Civil Defence (DCD), that a façade needs Dubai
Municipality approval, that a fit-out in a mall or a DMCC/DIFC tower needs the landlord's and the
free-zone authority's approval and that this adds weeks. The one place in the estate holding that
knowledge is a *blog post* (`fire-fighting-systems-uae-civil-defence`), not the seat.

**(d) No lead times, no seasons, no logistics.** Nothing on import lead time for European glass or
demountable systems, on the Ramadan/summer working-hours restriction that moves every fit-out
programme in the UAE, or on the difference between a Dubai and an Abu Dhabi mobilisation. Decision 3
(composite → prime / lots / hybrid) is a *sequencing* judgement, and sequencing without durations is
not judgement.

**(e) No losses.** 32 `worked_case` rows exist across the whole corpus — for 128 trades. A senior
engineer's value is disproportionately in the deals that went wrong. There is no record of a supplier
who passed the gates and then failed, and no counterexample library beyond the single
`wrong-match counterexample` line per sector guide.

---

## 3. Customer support — `support_knowledge`, 408 rows

**Owned decisions:** outbox handling retries and dead letters · suppression and opt-out enforcement ·
sender reputation actions.

**This is the sharpest mismatch in the estate: the corpus is not about the decisions the seat owns.**
The seat's three owned decisions are *deliverability operations*. The corpus is about *conversation*:
75 rows `autonomy_and_judgment`, 40 `decision_playbook`, 32 `worked_case`, 30 `conversation`,
28 `message_template`. Probing the corpus for the vocabulary of its own owned decisions:

| term | rows in `support_knowledge` (408) |
|---|---|
| outbox | 2 |
| **dead letter** | **0** |
| suppression | 1 |
| opt-out | 12 |
| **sender reputation** | **0** |
| bounce | 3 |
| **SPF / DKIM / DMARC** | **0** |
| **complaint rate** | **0** |
| Resend (the actual provider) | 13 |
| **WhatsApp template** | **0** — though WhatsApp is the founder's command channel |
| **Arabic** | **0** |

*(counts are substring matches on `title`/`body`; a substring match overstates topicality — e.g.
"TRA" returns 132 because it matches "contract", "extract" and "administrative". The zeroes are the
reliable half of this table.)*

**What a twenty-year UAE support lead holds and this seat does not.** How to read a bounce class and
decide suppress-vs-retry; what complaint rate forces a sending pause; how a WhatsApp Business
template gets approved and what happens when it is rejected mid-campaign; that a meaningful share of
UAE B2B counterparties will answer in Arabic and that a support function here is bilingual; the
public-holiday and Friday-prayer rhythm that decides when a chase email is sensible. The seat has 28
message templates and no knowledge of the delivery system those templates go through.

**Also: this corpus has no embeddings** (§0), so it cannot answer a question phrased differently from
its own headings at all.

---

## 4. IT engineer — `it_engineer_knowledge`, 79 rows · CEO — `ceo_knowledge`, 508 rows

**IT engineer owned decisions:** what the estate is doing right now and whether a number is a
measurement or an unknown · whether an observation is an incident, and at what severity · what the
suspected cause is, and which rows evidence it · when the founder is emailed directly.

79 rows across **47 domains** — a mean of 1.7 rows per domain, which is a table of contents, not a
body of knowledge. The epistemic discipline is real and is the best thing in this corpus. What is
missing is the estate's own operating substance: `deadlock` 0 rows, `RTO`/`p95` 0 rows, `vacuum` 1,
`pg_cron` 1, `Postgres` 2, `Supabase` 3. **The seat is required to decide severity and cause on a
Supabase/Postgres/Deno estate and holds two rows that name Postgres.** A twenty-year SRE's depth is
in failure modes — connection-pool exhaustion, lock contention, a partial index that stopped being
used, a cron that silently stopped claiming (which is exactly what happened to the embedding backfill
on 7 Sep, see §5) — and there is no failure-mode library here at all.

**CEO owned decisions:** company objectives and priority · capital allocation between departments ·
accepting or refusing a department's corrective plan · declaring a company-level risk.

508 rows, **3 of which mention the UAE**, and no embeddings. Two of the four owned decisions
("capital allocation **between departments**", "accepting or refusing **a department's** corrective
plan") are **written against an organisation the founder deleted on 7 September 2026** — there are no
departments. The corpus is a general management library (96 rows `autonomy_and_judgment`, 66
`finance`, 49 `growth`) with almost nothing about running *this* company in *this* market: no UAE
market sizing, no competitor position, no CAC/LTV for a Dubai B2B marketplace, no unit economics of
the 3% reveal fee against the AED 15k / 3x boundaries the founder set.

**Gap recorded, not filled:** the CEO seat's owned decisions need rewriting against the two-agent
structure before more knowledge is loaded into it. Writing new decisions for that seat is an
organisational change and is the founder's, not this session's — the skill is explicit that no third
agent, department or workflow may be invented. **Recorded as a gap; not acted on.**

---

## 5. What this session changed, and what it deliberately did not

**Fixed — the ingestion (instruction #14).** The backfill did not fail; it was dismantled in four
places. pg_cron was emptied on 7 Sep at 17:51 UTC on the founder's own instruction, taking four
embedding jobs with it; `fn_kernel_cron_exec` and `phase_c_system_execution_wrapper`, which held the
actual request payload, were dropped in the same change; the worker
`supabase/functions/kb_embed` was deleted the next morning by commit `182308b` with the other 137;
and `agent_runs` was cleared, which is why nothing reported the stall for two days. The replacement
runs from inside Postgres and needs **no edge deployment and no pg_cron**: `fn_kb_embed_dispatch`
queues one `net.http_post` per chunk to `ai_gateway {action:'embed'}` — deployed, ACTIVE, carrying
the same free in-region `gte-small` — and `fn_kb_embed_harvest` writes the vectors back. Ordering is
by `kb_embed_priority`, so the fit-out trades embed first and the categories the company itself
excludes embed last. `scripts/sql/the_library_starts_embedding_itself_again_and_starts_where_the_demand_is.sql`.

It has run. Measured on production, 27 cycles of 500, tier 1 only:

> **13,796 rows embedded in 26.0 minutes = 531 rows/minute. 4 failures out of 13,800 (0.03%).
> kb_chunks embeddings 166,093 → 180,139.**

Against the old cron's measured **33.7 rows/minute** — the mean of its 26 full hours on 6–7 Sep, a
figure recoverable only because `embed_claimed_at` was never cleared and so doubles as a clock —
this path is **15.8x faster**, because pg_net's queue is not bounded by the deleted worker's
7-second edge budget. The per-cycle rate was flat across the whole run (533–551/min), so it is a
sustained rate and not a burst.

**At 531/min the remaining 2,505,887 rows drain in 78.6 hours — 3.3 days, against the 51.9 days the
old cadence implied.** Cost is one Supabase edge invocation per chunk: single-digit dollars for the
whole library, since the model is free and in-region and nothing on this path touches OpenRouter.

Two caveats stated rather than buried. First, this run was driven by
`scripts/kb/run_embed_backfill.mjs`, a pump that has to be started; the *unattended* schedule is the
`resilience_ping` tick, and **that file is edited but NOT deployed** — until it is, the backfill only
advances when the script is run. Second, at 400 rows per 15-minute tick the unattended cadence is
~38,400 rows/day and drains in ~65 days, so the batch should be raised once pg_net is observed
keeping up; the script exists to close the gap in the meantime.

**Fixed — the pricing gap (instruction #15).** `public.price_benchmark` holds **1,082 UAE rates**
across **52 of the 56 marketplace trades**: 206 lifted from the company's own 29 published cost
guides (`blog_posts`, 26 Jun – 20 Jul 2026) and 876 from `kb_chunks`. Every row stores the sentence
its numbers came from — checked, and the first pass was rejected because 357 rows quoted the wrong
sentence. `fn_price_confidence` reads them and now answers instead of returning `insufficient_data`.
`sales_knowledge` went from **0 rows containing "AED" to 56**, and `fn_sales_assist` — under its
unmodified cosine-0.86-plus-lexical-corroboration discipline — now answers *"what should a gypsum
false ceiling cost per square metre in Dubai"* by citing `QD-SE-PRICE-gypsum`. Before today that
question had no answer anywhere in the seat's corpus.

One measured detail worth keeping: the price records were at first **unreachable**, scoring
`ts_rank` exactly 0.0000 on that question, because they said "UAE" where the customer says "Dubai"
and "sqm" where the customer says "square metre". They answered *"gypsum ceiling price per sqm UAE"*
at rank 1.0000 in the same breath. Adding the emirates, the spelled-out units and
`taxonomy_trade.aliases` to each record fixed 5 of 6 probe questions and made the sixth — a trade
with no price evidence — reach its **gap** record, so the seat says it does not hold a benchmark
rather than saying nothing. That is instruction #14 in miniature: the content was already correct
and still unretrievable, and keywords were the difference.

**Deliberately NOT done — and why.**

1. **No bulk row generation into any seat corpus.** §0 shows it would lower retrieval quality. The
   1,136-row corpus retrieves worse per row than the 79-row one.
2. **No invented UAE tax figures.** §1's table is a shopping list for a sourced ingest, not a
   licence to write rates from memory into the corpus a filing would be built on.
3. **No new decisions, seats or departments.** §4's CEO finding is escalated as a gap.
4. **No embedding columns added to `support_knowledge` / `ceo_knowledge` in this pass** — that is a
   schema change plus a full re-embed of 916 rows and is the single highest-value next action for
   those two seats. Recorded here so it is not lost.

---

## 6. The named gaps, in one list

| # | seat | gap | why not filled here |
|---|---|---|---|
| G1 | accountant | FTA tax-invoice particulars, VAT threshold, EmaraTax, CT return, designated zone, free-zone test, audit file, WPS, IFRS basis | needs a sourced ingest of FTA publications; fabricating a figure into this corpus is the worst failure mode in the estate |
| G2 | sales engineer | per-trade specification defaults (what "a normal gypsum partition" is in the UAE) | no evidence in the estate; must come from supplier submittals or a sourced ingest |
| G3 | sales engineer | authority-gate map per trade (SIRA / DCD / Dubai Municipality / free-zone landlord) | partially present in `blog_posts` and `taxonomy_trade.authority_required`; needs consolidation into the seat, not generation |
| G4 | sales engineer | lead times, seasonality (Ramadan / summer hours), Dubai vs Abu Dhabi mobilisation | no evidence in the estate |
| G5 | sales engineer | loss library — suppliers that passed the gates and failed | requires operating history; the company is pre-launch |
| G6 | customer support | deliverability knowledge matching its own owned decisions (bounce classes, complaint-rate thresholds, SPF/DKIM/DMARC, WhatsApp template lifecycle) | provider-specific; must be read from Resend/Meta documentation, not written from memory |
| G7 | customer support | Arabic-language capability; UAE holiday/working-week rhythm | no evidence in the estate |
| G8 | IT engineer | Postgres/Supabase failure-mode library | should be built from this estate's own incident history as it accumulates |
| G9 | CEO | owned decisions still reference departments deleted on 7 Sep 2026 | organisational change — the founder's, not a session's |
| G10 | support + CEO | no embedding column; retrieval is keyword-only for 916 rows | schema change + re-embed; named as the next highest-value action |
| G11 | pricing | four trades — `combined-mep`, `elevators`, `engineering-and-architectural-consultancies`, `water-tank-cleaning` — have no AED figure anywhere in the estate | recorded as `price_benchmark` rows with `source_kind='gap'` and as `QD-SE-PRICE-*` records that say so out loud, rather than guessed |
| G12 | pricing | `fn_customer_savings` (n≥4), `fn_customer_decision_support` (n≥5) and the `customer_portal` price-move card (n≥3) read `category_price_stats` **directly**, not through `fn_price_confidence`, so they stay empty until real quotes exist | union-ing benchmarks into that view was rejected: `n` would then mean two different things and a published range would be counted as a sample of this company's own quotes |
| G13 | pricing | `supplier_negotiation_policy` has every `ask_discount_pct` at 0, so `fn_negotiation_guidance` proposes no target price even now that it has a median | the policy row's own note records this as the founder's commercial call, not an engineering one |
| G14 | sales engineer | 29 of 56 trades have no `taxonomy_trade` alias row, so a customer's own word for them may not reach their record | aliases are data the estate already keeps; extending them is a content task, not an invention |
| G15 | ingestion | `resilience_ping` carries the embedding tick in the repo but is **not deployed**, so the backfill is not yet unattended | the brief withheld edge deployment from this session; it is one deploy of one function |
| G16 | ingestion | at 400 rows per 15-minute tick the unattended rate is ~38,400/day (~65 days), far below the 531/min the same code achieves when pumped | raise `p_limit` once pg_net's drain rate is observed under the tick; the number is a tuning knob, not a design limit |
| G17 | tooling | `verify_deploy_parity.mjs` reported `resilience_ping production=LIVE` **with my undeployed change sitting in the file** | it compares the **25 longest** string literals per function; `'fn_kb_embed_tick'` is 16 characters and is nowhere near the longest 25 in a 480-line file of prose literals. For any change to a large function the gate is a green that means nothing — which is the exact failure its own header warns about. Not fixed here: changing a deploy gate mid-session, on a check other sessions are relying on, is its own change and belongs in its own one |
