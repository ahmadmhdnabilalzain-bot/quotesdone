# The knowledge doctrine

Seat: sales_engineer. Written 21 Sep 2026 against founder instructions 520–523 (18 Sep 2026),
recorded verbatim in `public.founder_instruction`:

- **520** *"you gotta replace all the useless knowledge with useful one so that we close that chapter.
  anything that is not related need to be deleted permenantly"*
- **521** *"based on the requirement we need for the company as we are considered experts, then you
  accordingly you get to decide what we need. this is extremely important and sensitive"*
- **522** *"since the sales engineer makes comparison reports, i believe he should be literally
  having the brain of combined technical directors of all fields and sectors we cover."*
- **523** *"its not only about regulations. deep technical knowledge of materials and specs is super
  important. top brands supplied in UAE for every sector, engineering logic and reasoning. all those"*

Scope: the 40 trades in `docs/SECTORS_WE_COVER.md`. Nothing here is applied; §7 is a proposal and §8
is a read-only preview. OpenRouter is on hold, so every rule below is written to be **executed by
code** (`quote_compare`, `_shared/line_specs/*.ts`, `fn_price_confidence`), never interpreted by a
model.

## 1. The five admission tests

A record enters the sales engineer's knowledge only if it passes all five. A record that fails one is
not "low priority" — it is not knowledge, and it is not stored.

| # | test | how it is checked mechanically |
|---|---|---|
| 1 | **It serves a decision the platform makes.** The decisions are enumerated: hold a quotation (missing line spec), flag a non-equivalent substitution, flag an omitted scope line, flag a price outside the band, declare two quotations not comparable, tell the customer what an authority will require, route an inquiry to a trade, recognise a supplier's stated service. | Every row names its `decision` from that enum. A row with `decision = null` is refused by a CHECK. |
| 2 | **It is UAE/GCC, or a code adopted here.** "Adopted" means a UAE authority document names it as the requirement — e.g. DEWA Regulations 2017 cl. 4.5.1 naming BS EN 61439 / IEC 61439 for LV assemblies. A foreign code that a UAE document merely *refers to* is admitted only through the UAE document that refers to it, carrying that clause. | `jurisdiction in ('UAE','<emirate>','GCC')` or `adopted_by` names a UAE citation row. |
| 3 | **It carries a citation and an effective date.** The citation is the primary source (law number, code edition, manufacturer datasheet reference), never a blog or a summary. | `citation not null and effective_date not null`; `expires_on` when the source states one. |
| 4 | **It exists in English and full Arabic.** Every customer- or supplier-facing string is in both; a rule whose Arabic is missing is not live. | `rule_en` and `rule_ar` both not null and not equal to each other; CI check greps for Latin-only `*_ar` values. |
| 5 | **It is lawfully held.** Government publications, standards we hold a licence to quote, manufacturer datasheets published for that purpose, and QuotesDone's own writing. Copyrighted textbooks and bulk statute mirrors are not. | `licence` enum (`government`, `licensed_standard`, `manufacturer_public`, `quotesdone`); anything else refused. |

Each record is also **labelled** `law` / `practice` / `manufacturer_data`, because the comparison
report must say which of the three it is standing on when it flags a quotation.

## 2. The four bodies of knowledge, per trade

For each of the 40 trades, the technical-director brain is four bodies. All four are rules or
reference rows the engine reads; none is prose to be retrieved.

1. **Materials and specifications.** Per line type of the trade: the attributes that define the
   product (already modelled for 43 trade keys in `_shared/line_specs/model.ts`: material, thickness,
   grade, rating, finish, brand, standard), their legal values, units, and **what moves when one
   parameter moves** (18 mm vs 16 mm board; S355 vs S275; 4 MP vs 8 MP; porcelain vs ceramic).
2. **Brands actually supplied in the UAE, grouped into equivalence classes.** Neutral: a class is
   "these brands are accepted as equivalent for this attribute at this grade", evidence-based (a
   consultant-approved-materials list, a DEWA/ADDC/Civil Defence product approval, an ESMA/MOIAT
   conformity certificate, or a manufacturer datasheet), and **every approval carries an expiry**.
   A brand outside every class is not "worse"; it is *unclassified*, and the report says so.
3. **Engineering logic.** The if/then that a technical director applies: a chiller quote without a
   pump head is incomplete; a fire-rated door without a certified frame is not fire-rated; a
   waterproofing quote without a protection screed omits scope; a cheaper SPC floor at 4 mm is not
   equivalent to 5.5 mm. Stored as rules the engine fires (§3), with the reasoning in EN + AR.
4. **Approvals per trade per emirate.** Which authority must accept what, before or after works:
   DEWA (electrical connection, Appendix-1 standards), Dubai Civil Defence (fire systems and
   materials), SIRA (security systems in Dubai), Dubai Municipality / Trakhees / DDA (permits,
   Al Sa'fat), ADDC/ADM/Estidama in Abu Dhabi, SEWA/FEWA elsewhere. Per trade per emirate, with the
   document the approval is evidenced by, and the expiry.

## 3. The rule families the comparison engine executes

Every family below maps to a check `quote_compare` already runs deterministically
(`rankable()`, `technicalComparison()`, `fn_price_confidence`) or a place where it runs nothing yet.
The doctrine makes each one a **data row**, not a code change per trade.

| family | what the rule says | executed where today | gap |
|---|---|---|---|
| **Mandatory scope lines** | For trade T and job type J, lines L1..Ln must be present in every quotation, else the quote is *incomplete* and held. EN + AR names of each line. | `line_specs/assess.ts` holds a quote for a missing line **attribute**; there is no per-trade list of required **lines** — `category_quote_specs` (141 regexes over 44 groups) is whole-quote, English only. | Table `trade_scope_line` (§7). |
| **Common omissions** | The lines a cheap quotation usually drops (protection screed, commissioning, DEWA inspection fee, scaffolding, disposal, testing certificate) and the words that prove they were included. | `quote_compare`'s prompt asks the model to catch omitted lines — the model is off. | Same table, `kind = 'commonly_omitted'`; the engine lists them as `missing_from_request` when absent. |
| **Non-equivalent substitutions** | Attribute A: value X is **not** equivalent to value Y (MDF ≠ solid oak; annealed ≠ laminated-toughened; Class 0 ≠ Class 1 insulation; 0.5 mm ≠ 0.7 mm duct gauge) — flagged `differs`, never `match`, with the reason. Equivalence classes for brands live here too. | `compare.ts sameValue()` treats two strings as the same by number tolerance or substring; it has **no** notion of "these two different values are, or are not, equivalent". | Table `spec_equivalence` (§7); `sameValue()` consults it before its fallback. |
| **Price red flags** | Per trade, per unit: the AED band and the *reason* a price lands outside it (thinner spec, missing scope, unlicensed labour). | `fn_price_confidence(category, amount, qty, unit)` reads `price_benchmark` (1,236 non-gap rows over 52 directory slugs; 4 slugs are recorded gaps) and returns `band` + `item_bands`; the caller is `negotiation_assistant`, **not** `quote_compare`. | Route `quote_compare` through it per itemised line; add `red_flag_reason_en/ar` to the band. `price_benchmark` is keyed by directory slug, not trade code — the 9 trades with no directory page have no bands. |
| **Comparability rules** | Two quotations are comparable on a line only if attributes A1..Ak are all stated by both and are equivalent; otherwise the report says *not comparable* and why. | `compare.ts` flags per cell but always ranks. | Rule `comparability_key` per trade line type; `rankable()` refuses to rank a pair that fails it. |
| **Approvals** | Trade T in emirate E needs approval P evidenced by document D; a quotation that excludes P's cost or the supplier that lacks the approval is flagged. | `taxonomy_trade.authority_required` holds 3 values on 3 trades (electrical_utility, civil_defence, sira); `catalog_supplier_categories.regulated` marks 20 catalogue rows; nothing is per emirate. | Table `trade_approval` (§7). |

## 4. Primary sources verified so far — and what each does NOT say

From `memory/uae-authority-source-facts-18-sep.md`, fetched in-browser 18 Sep 2026. These are the
only sources the rebuild may cite until more are verified the same way.

| source | what it establishes | what it does NOT say |
|---|---|---|
| **Cabinet Resolution No. (157) of 2025** — Technical Regulations for Energy Consumption Efficiency Requirements for Low and Large Capacity Air Conditioners. Issued 04 Nov 2025, effective 15 Nov 2025, Gazette 811 (14 Nov 2025), active; repeals Cabinet Resolution (3) of 2020; 365 days to regularise. https://uaelegislation.gov.ae/en/legislations/3862 | The AC efficiency regime that governs `hvac` quotations from 15 Nov 2025; the effective date and the repeal. | **The EER/efficiency figures.** The schedule sits behind a separate link that was not opened. No HVAC rule may quote a number from it until that schedule is read. |
| **Al Sa'fat, Dubai Green Building System, 2nd ed., Jan 2023** | 502.01 delegates efficiency to Dubai Building Code H.4.8.1 (buildings) / K.10.1.5.1 (villas); Golden Sa'fa needs a 4-star household AC rating, Platinum 5-star, commercial/central ≥ 10% above the Building Code figures; 701.05 refrigerants zero-ODP or GWP < 100 unless charge < 0.23 kg, no CFC/HCFC/halon in fire suppression, from 1 Jan 2030 no HCFC or any ODP material; 503.04 chilled-water metering; 503.05 CCMS for ≥ 1 MW cooling or ≥ 5,000 m² GFA. | **Any COP / IPLV / EER / kW-per-TR figure.** It contains none. An `hvac` rule that cites Al Sa'fat for an efficiency number is wrong. |
| **DEWA Regulations for Electrical Installations, 2017 edition** (supersedes 1997) | MDB/SMDB and final DBs are factory-built assemblies to BS EN 61439 / IEC 61439 (cl. 4.5.1, 4.5.2); busbar trunking to BS EN 61439 (cl. 7.3.2); cl. 1.6 accepts equipment meeting Appendix-1 standards / IEC / ISO; type-test certificates demanded for protection relays and instrument transformers; DEWA publishes approved-**contractor** lists for 11 kV substation work and cable laying. | **"Type-tested" is not required in those words for LV boards** (it appears only in the busbar-trunking definition). **There is no DEWA approved-manufacturer list for LV switchboards.** An `electrical` rule that holds a quote for "not a DEWA-approved panel brand" has no source. |
| **UAE Fire and Life Safety Code of Practice**, current published edition September 2018, ref CDGH-OP-25, 1,348 pages (page last updated 11 Jun 2026, no newer edition listed) | The governing fire code; cl. 2.2.4 and 2.2.7 direct the consultant to refer to NFPA 70/72/75/76/110/111 and manufacturer guidance. | **NFPA 72 is REFERENCED, not adopted.** There is no "this code adopts NFPA 72" clause. A `fire_fighting` rule may cite the UAE code's clause that refers to NFPA; it may not state that NFPA 72 is the law. |
| **DMS-035-2020 Requirements for Steel Structures** (Dubai Municipality) | Nothing yet. The published URL returns the DM homepage; DM site search is broken. | **NOT OBTAINED.** Whether it invokes EN 1090 / ISO 3834 / AWS D1.1 is unknown. No `steel` rule may assume it. |

Everything else a trade needs (per-trade brand approvals, ESMA/MOIAT conformity lists, SIRA's
approved-product list, Civil Defence material approvals, ADDC/SEWA/FEWA regulations, Dubai Building
Code figures) is **unverified** today and must be fetched in-browser and recorded in this table
before a rule cites it.

## 5. What exists and is reused (measured 21 Sep 2026)

- `taxonomy_trade` (40) / `taxonomy_trade_service` (201) / `service_implication` (113, one level,
  `fn_services_effective`) — the trade vocabulary and the curated implication map. Reused as the key
  space. `service_implication` is the pattern for every curated map below: `from`, `to`, `reason_en`,
  `reason_ar`, `active`, one seed file, one check that holds JSON and table equal.
- `_shared/line_specs/model.ts` — 43 trade keys with line attributes (code, EN, AR, unit,
  mandatory, deterministic EN+AR reader), including brand lexicons per trade. This **is** body 1 in
  code. It stays in code (the readers are regexes); the doctrine adds the *values* tables it consults.
- `category_quote_specs` (141 rows, 44 groups, `fn_quote_spec_group`) — whole-quote mandatory-spec
  regexes; superseded by `model.ts` for line specs; kept as the source of `must_state_specs` until
  `trade_scope_line` replaces it.
- `price_benchmark` (1,236 rows + 4 gap rows) and `fn_price_confidence` — body 3's price arm.
  Reused as-is; two columns added (§7).
- `agent_knowledge` `cat:*` rows (1,627 rows over 132 keys; 24 keys carry *Pricing benchmarks &
  red flags* and *Standards, materials & specifications*) read by `fn_category_expert_ref` into the
  model prompt only. Prose, English only, no citation column filled. **Not** a rule source; kept as
  authoring material to be converted row by row, then retired from the runtime path.
- `kb_chunks` — see §6 and §8. Read by `kb_query` (inquiry_intake), `fn_sales_assist`,
  `fn_os_search`, `fn_ws_knowledge`, `fn_agent_context_v3`, `kb_match`; **not** read by
  `quote_compare` or by anything in `line_specs`. The comparison engine has never used it.
- `kb_chunk_quarantine` (70,629 rows, 126 MB) — the reversible holding pen with a `reason` column.
  Reused as the audit record: the purge moves nothing here (2.4 M rows would be 3 GB of pen), but
  the *classification verdict per source_kind × category* is written to a ledger row before delete.

## 6. The classification rule for the kb_chunks purge

Applied row by row, in this order; the first clause that matches decides. The verdict, the clause
number and the counts are written to the audit ledger before any delete.

1. **KEEP — QuotesDone-authored.** `source_kind in ('qd_kb_pack','company_faq','memory',
   'generated','trade','material','document','library')` OR `citation ilike '%QD-KB%'` OR
   `citation ilike '%quotesdone%'` OR `category like 'cat:%'` OR `category like 'exec:%'`.
2. **KEEP — ever cited.** Any row whose `id` appears in a citation ledger. `kb_usage_log` holds
   **0 rows** and I did not find the ledger behind the "176 citations" in the 18 Sep audit; the
   coordinator must name that table so this clause joins it before the purge runs. Until then this
   clause is unproven, and that is a reason not to run the purge, not a reason to skip the clause.
3. **KEEP — cites a UAE/GCC authority.** `citation` matches the authority pattern (UAE, the seven
   emirates, DEWA, ADDC, AADC, SEWA, FEWA, EtihadWE, Civil Defence, SIRA, ESMA, MOIAT, GSO, GCC,
   Trakhees, Municipality, ADQCC, RTA, TDRA, Estidama, Al Sa'fat, Tadweer, OSHAD, DMT, JAFZA, DDA,
   TECOM). Kept for review under §1, not admitted as knowledge by this test alone.
4. **UNSURE — held for the founder.** (a) `source_kind in ('code','regulation','spec')` and not
   caught above — statute and code text is never deleted on a pattern; (b) the category is an
   in-scope trade family (the 26 `catalog_domains` slugs, the directory slugs and the `*-suppliers /
   *-contractors / *-companies` catalogue slugs that cover the 40 trades) **and** the citation names
   a foreign code that a UAE document may adopt (NFPA, NEC, BS EN, Eurocode, IEC, ISO, ASHRAE, ASTM,
   SMACNA, IAPMO/UPC/IPC, IBC/ICC, CIBSE, BS 7671, AWS D1, API, ASME, ANSI, UL, EN 54, EN 12845,
   LPCB, FM Global). §4 shows why: NFPA is referenced by the UAE fire code and BS EN 61439 by DEWA,
   so these rows may be admissible through test 2 — the founder decides whether to keep the foreign
   text or re-author the adopted clauses.
5. **DELETE — foreign bulk.** Everything else: `standard`, `reference`, `cert`, `textbook`, `book`,
   `handbook`, `guide`, `manual`, `report`, `paper`, `biography`, `letters`, `syllabus`,
   `framework`, `methodology`, `study` rows with no UAE authority in the citation, whether the
   category is an in-scope family (OpenStax Marketing filed under interior decoration is still
   OpenStax Marketing) or out of scope (US CFR Title 14, IPSASB handbooks, Debrett's, Mrs Beeton).

Rules that bind the purge itself: batched (`delete … where id in (select id … limit 50000)`) and
resumable from the ledger; the restorable copy confirmed *before* the first batch (§8); the audit
row per (verdict, source_kind, category) written first; `VACUUM (VERBOSE)` and `REINDEX` of the
`fts`, `embedding_gte` and `category_norm` indexes scheduled after, with the reclaimed size reported
against the 9,313 MB measured today; `kb_category_stats` refreshed after.

## 7. Schema proposal — how codified rules are stored and read

Principle: **one table per rule family, each row a rule the engine fires; EN + AR; citation +
effective date + label on every row; one seed JSON per table in `supabase/functions/_shared/rules/`
held equal to the table by a check, exactly as `service_implication` ↔ `service_implications.json`
is today.** Reads are by trade code (`taxonomy_trade.code`), never by directory slug, so the nine
trades without a directory page are covered from day one.

```sql
-- shared columns on every rule table (the doctrine's five tests as constraints)
--   trade_code   text not null references taxonomy_trade(code)
--   decision     text not null check (decision in ('hold_quote','flag_substitution','flag_omission',
--                  'flag_price','not_comparable','approval_required','route_inquiry','recognise_service'))
--   label        text not null check (label in ('law','practice','manufacturer_data'))
--   jurisdiction text not null              -- 'UAE' | 'Dubai' | 'Abu Dhabi' | ... | 'GCC'
--   citation     text not null              -- primary source, clause
--   effective_date date not null,  expires_on date null
--   licence      text not null check (licence in ('government','licensed_standard','manufacturer_public','quotesdone'))
--   rule_en text not null, rule_ar text not null check (rule_ar <> rule_en)
--   active boolean not null default true,  source_ref text, created_at, updated_at

create table trade_scope_line (      -- family: mandatory scope lines + common omissions
  trade_code, job_type text null, line_key text, line_en, line_ar,
  kind text check (kind in ('mandatory','commonly_omitted')),
  proof_regex_en text, proof_regex_ar text,   -- what in a quotation proves the line is included
  + shared columns, primary key (trade_code, coalesce(job_type,''), line_key));

create table spec_equivalence (      -- family: non-equivalent substitutions + brand equivalence classes
  trade_code, attr_code text,                 -- attr_code = line_specs/model.ts attribute code
  class_key text,                             -- e.g. 'board.mr_18mm', 'brand.paint.premium_interior'
  value text,                                 -- canonical value or brand name
  equivalent boolean,                         -- true: member of class; false: explicitly NOT equivalent to class
  evidence_kind text check (evidence_kind in ('authority_approval','conformity_cert','consultant_list','datasheet')),
  approval_ref text, approval_expires date,   -- approvals expire; an expired row is inactive by view
  + shared columns, primary key (trade_code, attr_code, class_key, value));

alter table price_benchmark add column trade_code text references taxonomy_trade(code),
  add column red_flag_reason_en text, add column red_flag_reason_ar text;
  -- fn_price_confidence gains p_trade_code and returns red_flag_reason with the band.

create table trade_comparability (   -- family: comparability rules
  trade_code, line_type text, required_attrs text[],   -- attrs both quotes must state and match/equal
  + shared columns, primary key (trade_code, line_type));

create table trade_approval (        -- family: approvals per trade per emirate
  trade_code, emirate text, authority text, approval_en, approval_ar,
  stage text check (stage in ('before_works','on_completion','supplier_licence')),
  evidence_doc text, cost_bearer text check (cost_bearer in ('supplier','customer','either')),
  + shared columns, primary key (trade_code, emirate, authority, approval_en));

create view v_trade_rules_live as    -- what the engine reads: active, in date, both languages present
  select ... from each table where active and effective_date <= current_date
   and (expires_on is null or expires_on >= current_date) and (approval_expires is null or approval_expires >= current_date);
```

How the engine reads them: `quote_compare` already loads `inq.category`, resolves the trade with
`tradeOfCategory()` and builds `technicalComparison()`; it adds one RPC `fn_trade_rules(p_trade_code)`
returning the five families as JSON (cached per run), and:

- `rankable()` also holds a quote missing a `mandatory` `trade_scope_line` (hold reason names the
  line in the customer's language);
- `compare.ts` `flagOf()` consults `spec_equivalence` before `sameValue()`: an explicit
  `equivalent=false` pair is `differs` with `rule_en/ar` as the note; an unclassified brand is
  `stated`, never `match`;
- `commonly_omitted` lines absent from a quote go to `missing_from_request` with the rule text;
- each itemised line with a quantity calls `fn_price_confidence(trade_code, amount, qty, unit)` and
  carries `band` + `red_flag_reason`;
- a line whose `required_attrs` are not all stated by two quotes is rendered *not comparable*
  (new `Flag = 'not_comparable'`, marker `≁`) and excluded from that line's ranking;
- `trade_approval` rows for the inquiry's emirate become `watch_outs`, and a supplier lacking a
  `supplier_licence`-stage approval is flagged in the roster.

All of this is deterministic and bilingual; nothing calls a model. The seed JSON per table is the
authoring surface for the four bodies; the check `the_rule_seeds_match_their_tables.test.mjs` (the
pattern of `the_implication_map_has_one_seed.test.mjs`) keeps them equal.

## 8. Purge preview, measured 2026-09-21 09:18–09:50 UTC (read-only)

`public.kb_chunks`: **2,615,397 rows**, 9,313 MB total (4,206 MB heap), 355 distinct categories,
27 source kinds; 0.55% of a 50,000-row sample contains Arabic; `embedding_gte` present on 225,336
rows. Every row was created between 2026-07-09 and 2026-08-31; **no row postdates the restorable
copy**. The rule of §6 applied to every row (clauses 1, 3, 4, 5; clause 2 could not be joined — see
§6):

| verdict | rows | content bytes | by source kind |
|---|---|---|---|
| KEEP — QuotesDone-authored (cl. 1) | **104,370** | 56 MB | qd_kb_pack 90,488 · standard 6,983 (QD-KB-cited) · document 2,826 · trade 2,045 · generated 1,317 · company_faq 481 · library 174 · memory 53 · material 3 |
| KEEP — cites a UAE/GCC authority (cl. 3) | **27,883** | 26 MB | standard 13,040 · cert 9,774 · guide 3,017 · regulation 1,657 · code 395 |
| UNSURE — held for the founder (cl. 4) | **45,169** | 43 MB | code 19,724 (NFPA 1/13/30/54/70/101, UPC, IPC, Eurocodes) · standard 19,351 · regulation 2,585 · spec 1,918 · guide 902 · textbook 689 |
| DELETE — in-scope family, foreign bulk (cl. 5) | **968,925** | 1,033 MB | standard 847,009 · reference 81,379 · guide 14,458 · handbook 13,976 · textbook 8,406 · report 3,409 · manual 288 |
| DELETE — out-of-scope family, foreign bulk (cl. 5) | **1,469,050** | 1,556 MB | standard 1,139,815 · reference 184,524 · cert 75,466 · textbook 35,639 · guide 10,518 · book 10,271 · manual 4,484 · paper 2,117 · biography 1,646 · letters 1,422 · syllabus 1,274 · framework 898 · methodology 478 · report 426 · study 72 |
| **total** | **2,615,397** | | |

Delete set: **2,437,975 rows (93.2%)**, about 2.6 GB of content plus indexes. Keep set: 132,253.
Unsure set: 45,169. The delete set contains **no row with a QD-KB or QuotesDone citation, no
`qd_kb_pack`/`company_faq`/`document`/`trade`/`generated`/`memory` row, and no `code`/`regulation`/
`spec` row** — those three kinds are routed to UNSURE by clause 4a regardless of category (the
query grouped by source kind, so the reassignment is exact: 98 code + 1,918 spec from the in-scope
group and 2,585 regulation from the out-of-scope group moved to UNSURE). The largest delete
citations, for the record: US CFR Title 14 Aeronautics (11,839), IPSASB handbook (11,766), CFR
Title 48 FAR (9,999), IPCC AR6 (9,871), US Code Title 49 (8,097), CFR Title 33 (8,044 ×2),
ATSDR toxicological profiles (7,971), OpenStax Principles of Marketing (6,216), Debrett's Peerage
(5,617), Mrs Beeton (5,009), PostgreSQL 16 documentation (5,908 in the reference kind).

`kb_chunk_quarantine` already holds 70,629 rows (HR and procurement libraries, 70,622; four
customer-document extractions; three withdrawn FAQ answers) and is untouched by this preview.

**The restorable copy exists and is verified.** `table_export_change_tracked` registers
`kb_chunks` (9,765,453,824 bytes at registration). The last **full** export day is
**2026-09-18** (`table_export_run` stamp 2026-09-18, kind `full`, status `done`, finished
06:19:26 UTC): `doc_backups` holds **4,177 pages for `2026-09-18/…/kb_chunks`, 11,929,993,565
bytes, all 4,177 `status='done'` with `verified_at` set** (content hash and size checked on
upload), at `/QuotesDone Backup/Company/Database Exports/2026-09/2026-09-18/kb_chunks/page_0000.json`
onwards. The incrementals of 2026-09-19, -20 and -21 each wrote one 2-byte kb_chunks page (no
change), and the newest row in the table is from 2026-08-31, so the 18 Sep full copy contains every
row in today's delete set. A 2026-09-15 full copy (2,616 pages, 11.87 GB) also exists.

Boundaries: clause 2 unjoined (see §6); the UAE-authority and adopted-code patterns are regexes
over `citation` only — a row whose content is UAE law but whose citation string is bare would fall
to DELETE, and I did not sample content for that case; `bytes` are `octet_length(content)`, not
index or TOAST size; nothing was deleted, quarantined or applied.
