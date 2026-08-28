# Bulk corpus ingestion — the ~10,000-pages-per-agent path (28 Aug 2026)

The founder's bar for agent expertise is roughly **10,000 pages per agent**. That volume cannot be
hand-authored as `ops_knowledge` entries; it must live as a retrievable **corpus** and be pulled into
the prompt on demand, task-ranked. This is that path — built and verified end to end, zero cost.

## The two pieces

1. **Loader — `scripts/kb/ingest_extracted.mjs`.** Turns one extracted document (book-to-skill
   `full_text.txt`) into many `kb_chunks` rows: paragraph-aware chunking (~1,200 chars), page-marker /
   copyright / boilerplate stripped, mojibake sanitised to clean ASCII, tagged with a `category`,
   idempotent per `source_id`, batched insert. `fts` (tsvector) is generated on write and is
   immediately searchable; `embedding_gte` is backfilled later by the free in-region `kb_embed` path.

   ```bash
   node scripts/kb/ingest_extracted.mjs <full_text.txt> \
     --category <field> --source-id <id> --source-kind cert --citation "<cite>" --title-prefix "<p>"
   ```

2. **Retrieval wiring — `fn_agent_context_v3` now has a `field_corpus` section.** When a task is
   supplied it retrieves from `kb_chunks WHERE category = any(agent knowledge scope) AND fts @@
   task_tsquery`, ranked by `ts_rank`, top 12, budget-bounded. So the corpus reaches the agent, and it
   carries the passages that bear on the work — not a category dump. (SQL-side full-text today; the
   semantic/vector half is added when the query-embed edge path is wired — see
   `SEMANTIC_RETRIEVAL_STATE.md`.)

## Proven

- Ingested the full ISTQB CTFL v4.0.1 syllabus (~50 pages of body) → **174 `kb_chunks`** under
  `category='qa'` (which is in the QA agent's scope `[assurance, it, qa]`).
- `fn_agent_context_v3('ai_qa_specialist','test_design', <EP/BVA/decision task>)` now returns a
  `field_corpus` of **12 task-ranked ISTQB chunks** (Black-box Test Techniques, decision tables…),
  ranked by relevance to the task. No task → empty (correct). A finance agent asked about a VAT return
  pulls finance-scope chunks the same way.
- Phase A/B/C freeze drift 0; canonical routines 11/11; schema export identical.

## How categories map to agents

`kb_chunks.category` must equal one of the agent's knowledge-scope categories (org_role.knowledge_scopes
/ `fn_dept_scope(department)`). The existing corpus categories are supplier trades (construction-civil,
mep, testing-inspection, …) for the marketplace overlays; **functional-role cert knowledge is tagged
with the functional scope** (`qa`, `finance`, `legal`, …). Ingest each field's sources under its scope
category and they surface to that field's agents automatically.

## Ingested so far (live in kb_chunks)

| source | category | agent scope reached | chunks | ~pages | verified retrieval |
|---|---|---|---|---|---|
| ISTQB CTFL v4.0.1 syllabus | `qa` | QA roles (`[assurance,it,qa]`) | 174 | ~50 | `ai_qa_specialist` gets 12 task-ranked chunks on an EP/BVA task |
| UAE Commercial Companies Law 32/2021 | `legal` | legal roles (`[legal,trust_safety]`) | 199 | ~91 | `general_counsel` gets 12 chunks on a directors-duties task |

## The collection plan (per field → category, from the source registry)

Each field's authoritative sources are in `CERTIFICATION_SOURCE_REGISTRY.md`. Ingest each under the
category that equals one of the field's `fn_dept_scope` values, so it reaches that field's agents:

| field / track | kb category | flagship sources to ingest (see registry for URLs) | licensing |
|---|---|---|---|
| finance / acct-cpa, uae-vat, uae-ct | `finance`, `payments` | FTA VAT & Corporate Tax guides + Decree-Law 47/2022; IFRS overviews; CPA blueprint | FTA/gov: open; IFRS: check |
| legal / uae-ccl, uae-difc | `legal`, `trust_safety` | Companies Law 32/2021 (done); DIFC/ADGM regs; consumer/AML | gov: open |
| assurance-qa / qa-istqb | `qa`, `assurance` | ISTQB CTFL (done) + Advanced syllabi; ISO 9001 overviews | ISTQB: copyrighted, review |
| security / sec-cissp | `it`, `assurance` | ISC2 CISSP outline; ISO 27001:2022 structure; NIST (open) | NIST: open; ISO: paywalled |
| procurement / proc-cips | `procurement`, `marketplace` | CIPS syllabi; FIDIC/tender basics | CIPS: copyrighted, review |
| privacy / priv-pdpl | `pdpl`, `legal` | UAE PDPL (Decree-Law 45/2021); IAPP BoK | gov: open |
| people_ops / hr-shrm | `hr`, `people_ops` | SHRM BASK; UAE labour law | gov: open; SHRM: review |
| the 86 supplier trades | existing trade categories | trade standards (ACI/ASTM/NFPA/ASHRAE/…) already partly present | mostly copyrighted, review |

**Licensing is a business call** (the founder's): government laws/regulations, NIST, and open materials
are unambiguous to ingest; commercial copyrighted standards (ISTQB, ISO, CIPS, SHRM) need a licensing
decision before the company ingests their full text — free syllabi/outlines and synthesised notes are
the safe subset until then.

## CONTINUOUS INGESTION PLAYBOOK (handoff — 28 Aug 2026)

**Target: 5–10 MILLION chunks.** Current corpus ~179k (≈97k pre-existing + ~82k added this session).
The bar is WORLD-CLASS per field (a CEO agent at Elon-Musk breadth; the same elite standard for every
functional role AND every supplier-category specialist). Copyright is authorised by the founder — ingest
full standards/textbooks/syllabi. Zero paid inference (no OpenRouter); downloads + local extraction +
kb_chunks writes are all free and allowed.

**Loop, run continuously, do NOT stop until the founder says stop; no partial check-ins:**
1. Fan out parallel ingestion subagents (general-purpose), each owning ONE field or trade category.
   Each does: find authoritative sources (WebSearch/WebFetch) → `curl -sL -A "Mozilla/5.0" -o <f>.pdf <url>`
   → verify `file` says "PDF document" → `tools/venv/Scripts/python.exe -m book_to_skill "<abs>" --mode text --install-missing no`
   → `node scripts/kb/ingest_extracted.mjs "<full_text.txt>" --category <CAT> --source-id <id> --source-kind <k> --citation "<c>"`.
2. Only ingest REAL downloaded docs; never fabricate. archive.org "borrow" pages are not direct PDFs.
3. If an agent fails (transient network / dying battery / stall watchdog) RESUME it via SendMessage to
   its agentId — the loader is idempotent per source_id so partial loads self-heal on re-run.
4. Keep launching new waves until every field and all ~70 trade categories are deep, then loop again for
   more depth. Snapshot `select count(*) from kb_chunks` periodically; don't report each agent.

**Category = how the corpus reaches the agent** (must be exact). Functional roles use their department's
`fn_dept_scope` value; supplier specialists use the canonical trade category.

| functional field | category to tag |
|---|---|
| finance/accounting/tax | `finance` |
| legal/compliance/privacy | `legal` |
| QA/testing | `qa` ; security/IT | `it` |
| HR/people | `hr` |
| engineering/AI/product | `engineering` |
| marketing | `marketing` ; sales/BD | `sales` |
| data/analytics/BI | `analytics` |
| customer success/support | `customer_success` |
| exec/strategy/management | `exec` |
| procurement/marketplace | `procurement` |

**Canonical supplier-trade categories** (tag trade standards with these; each already has 200–3,400
pre-existing chunks — ADD the real technical standards ACI/ASHRAE/NFPA/IEC/API/ISO/etc. to reach elite depth):
construction-civil-and-building-materials · mep-mechanical-electrical-plumbing · aviation-maritime-and-offshore ·
elv-smart-systems-home-automation · retail-and-consumer-goods · agriculture-food-production-and-environment ·
testing-inspection-certification-and-technical-services · logistics-transport-and-supply-chain ·
firefighting-life-safety-and-security · business-consulting · interior-fit-out-finishes-and-joinery · utilities ·
lifts-and-escalators · it-technology-and-digital-services · marketing-media-events-and-creative-services ·
real-estate-services · textile-uniforms-and-soft-goods · legal-and-compliance · media-av-production-and-creative-equipment ·
temporary-event-infrastructure · jewelry-and-luxury-retail · vehicles-automotive-and-equipment ·
accounting-finance-and-corporate-services · oil-and-gas-energy-and-industrial · facilities-management-and-support-services ·
gas-systems · human-resources-and-recruitment · catering-f-and-b-and-hospitality-services · manufacturing-by-process ·
luxury-and-concierge-services · recycling-and-circular-economy · travel-and-tourism-services ·
printing-packaging-and-office-supplies · beauty-wellness-and-personal-care · religious-facilities ·
sports-recreation-and-leisure · interior-decoration-and-styling · furniture-ff-and-e-and-loose-items ·
cold-rooms-refrigeration-and-cold-chain · healthcare-medical-and-life-sciences · insurance · industrial-automation ·
data-centres · bearings-power-transmission-and-hydraulics · fasteners-and-fixings ·
abrasives-tools-and-industrial-consumables · telecommunications · swimming-pools-spas-and-water-features ·
laboratory-and-scientific-suppliers · marine-safety · domestic-services · pet-industry ·
government-tenders-and-procurement-support · banking-and-financial-products · education-and-training-support ·
cleanrooms-and-controlled-environments · exhibition-industry · bakery-and-food-processing · wastewater-drainage ·
chemicals · translation-interpretation-and-localization · business-centres-and-coworking · renewable-energy ·
luxury-fit-out · air-compressors-and-pneumatics · hospitality-supplies.

**Retrieval is already wired:** `fn_agent_context_v3(agent, task_class, task_text, category_key)` returns
a `field_corpus` of kb_chunks where category = any(fn_dept_scope(dept)) OR category = category_key, ranked
by ts_rank against the task. fts is generated on write (immediately usable); `embedding_gte` (semantic)
backfills separately via the free in-region `kb_embed` cron (currently stood down).

**Throughput unlock for millions:** the Supabase MANAGEMENT API rate-limits every insert (the loader has
7-retry backoff and batches 200/insert). To reach 5–10M fast, get the project's **direct Postgres
connection string** (Supabase dashboard → Project Settings → Database) and rebuild the loader around
`COPY` — 10–100× faster. Until then, more parallel agents + big batches is the lever.

## Scale (honest)

174 chunks ≈ 50 pages is one syllabus — ~0.5% of one agent's target. Reaching ~10,000 pages/agent is a
sustained collection effort: dozens of full standards / textbooks / syllabi per field, each run through
collect → extract → this loader. The machinery and the retrieval path now exist and are proven; the
remaining work is volume (and licensing judgement on which copyrighted sources the company may ingest —
a business call; government standards, laws and open materials are unambiguous). Embedding backfill
(free, in-region) upgrades this from full-text to semantic once the `kb_embed` cron runs.
