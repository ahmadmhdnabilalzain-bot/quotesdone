# Agent expertise workstream

**The bar (founder, 27 Aug 2026):** every agent must be certification-grade in its field —
*"our accountant could easily pass a CPA test"* — and an agent is not done until it passes its
field's real certification exam. He will not help; the road is derived and validated against the
certifying bodies' OWN published syllabi, never against his review. See memory
`drive-the-knowledge-road-alone`.

## The zero-cost knowledge pipeline

1. **Map every role → its real certification(s) + authoritative sources.** ← DONE (this doc set)
2. Collect the sources off the public web (WebFetch/WebSearch/browser + fenced toolbox: Scrapling,
   you-get, direct download, self-hosted firecrawl). `tools/TOOLBOX.md`.
3. Extract with docling / book-to-skill (tables & formulas intact).
4. Convert to per-role agent skills with book-to-skill.
5. Load into Postgres/pgvector with free in-region gte-small embeddings; switch retrieval from
   keyword to **semantic** (5 of 6 routines still use full-text — the real gap; memory
   `retrieval-is-keyword-not-vector`).
6. Examine each agent against cert-grade exams; every failed gap loops back to steps 2–4.
7. Schedule a refresh so knowledge does not go stale over the hands-off year.

Collecting knowledge from the public web is research — it touches no customer, supplier, money, or
automation, so it is fully allowed and free. It is NOT a held external effect. The paid holds
(OpenRouter, live business effects) are unaffected.

## What exists now (Step 1 complete, 28 Aug 2026)

- **`CERTIFICATION_SOURCE_REGISTRY.md`** — the authoritative, web-validated registry of every
  certification / standard / regulation that defines expertise for these roles, with the certifying
  body's own syllabus URL, top domains, and an honest `validation` flag (**fetched** vs **located**).
  Four blocks: A professional certs, B UAE regulatory anchors, C trade/technical standards,
  D fields with no single licensing exam (body named, marked *derived*).
- **`ROLE_CERTIFICATION_MAP.csv`** — one row for **all 180 canonical roles** (verified to match
  `public.org_role` exactly: 0 missing, 0 extra). Columns: `role_id, department, primary_track,
  primary_credential, certifying_body, secondary_tracks, uae_overlays, notes`. The `*_track` values
  key into the registry above, so ingestion (steps 2–4) and the exam loop (step 6) iterate over
  role × track deterministically.

The founder's exemplar is honoured directly: `cfo` and `financial_controller` map to **CPA (2024
CPA Evolution, AICPA)** with IFRS + UAE Corporate Tax/VAT overlays — the accountant is built to pass
the CPA.

## Honesty boundary (session rule §10)

The registry's `validation` column states what was actually measured. **fetched** = the certifying
body's own page was loaded and confirmed this session. **located** = the URL is the official one but
the document is paywalled (ISO), bot-blocked (DIFC, DEWA, iso.org, CEN/EN, BICSI), or CDN-gated (PMI)
and could not be re-fetched here. Section D tracks are **derived** — no single license governs the
field, so the recognized body-of-knowledge is named rather than a single exam validated. No URL was
invented; every link is on the issuing body's own domain.

## Next (not done — multi-session, still zero-cost until the paid soak)

- Steps 2–4 (collect → extract → skill) for the anchor tracks, starting with the founder's exemplar
  (CPA) and the UAE regulatory anchors (FTA VAT/CT, PDPL).
- Step 5: land pgvector + gte-small embeddings for the ingested corpus and switch the 5 full-text
  retrieval routines to semantic, once there is a corpus to retrieve.
- Step 6: build the cert-grade exam loop and measure each agent; loop failures back to 2–4.
- Step 7: schedule the refresh cron (paused-safe; no live effect).
