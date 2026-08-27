# Knowledge pipeline — end-to-end pilot (ISTQB CTFL v4.0)

**28 August 2026. Zero cost, under every hold. Verified by execution.**

This pilot proves the agent-expertise pipeline (`docs/expertise/README.md`) works end to end on a real
certification source — the founder's exemplar shape ("the agent passes its field's real exam"), run on
the assurance-QA anchor (`qa-istqb`). It de-risks the multi-session bulk ingestion.

## What was proven, and how

| step | action | result (measured) |
|---|---|---|
| 2 collect | `curl` the official ISTQB CTFL v4.0.1 syllabus PDF from istqb.org | 1.01 MB, 78-page valid PDF-1.4 downloaded (direct download of a standard from the certifying body — research, no held effect) |
| 3 extract | `book-to-skill <pdf> --mode text` (installed toolbox, `tools/venv`) | clean chaptered text: **27,458 words**, 4 chapters, ToC detected, 0 images dropped. `--mode technical` (docling, layout-aware) also runs; it downloads its public HF layout model once, then infers. |
| 4 load | insert a real extracted section (§4.2.1 Equivalence Partitioning) into `public.kb_chunks` (`source_kind='cert'`, `category='qa'`, citation to the syllabus §) | row inserted; `fts` (generated tsvector) populated automatically |
| 5 retrieve | `kb_query('equivalence partitioning test cases', 'qa', 8)` | **the loaded cert chunk was returned** (1 hit, correct title) |

Steps 4–5 were run in an **aborted transaction** (insert → retrieve → `raise` to roll back), so nothing
was permanently written: the pipeline path is proven with zero side effect on the 97,499-row live store.

### Exact commands

```bash
# 2. collect (official certifying-body URL, resolved from the CTFL v4.0 page)
curl -sL -A "Mozilla/5.0" -o ISTQB_CTFL_v4.0_Syllabus.pdf \
  "https://istqb.org/?sdm_process_download=1&download_id=3345"

# 3. extract (fast text chain; --mode technical uses docling for tables/formulas)
tools/venv/Scripts/python.exe -m book_to_skill ISTQB_CTFL_v4.0_Syllabus.pdf --mode text --install-missing no
```

## Proven across source types (collect + extract, steps 2–3)

The pipeline is not ISTQB-specific. Two anchor sources of different shape were each downloaded from the
issuing body and extracted cleanly, zero cost:

| source | track | download | extract (text mode) |
|---|---|---|---|
| ISTQB CTFL v4.0.1 syllabus (professional cert) | `qa-istqb` | istqb.org, 78-page PDF | 27,458 words, 4 ToC chapters; docling `--mode technical` also ran → 145 structural sections |
| UAE Commercial Companies Law, Federal Decree-Law 32/2021 (regulation) | `uae-ccl` | moet.gov.ae, 70-page PDF | 45,621 words, 7 numeric chapters; clean legal text (definitions, liability, capital) |

So both a cert syllabus and a dense UAE law extract to clean, chaptered text — the two dominant source
shapes in `CERTIFICATION_SOURCE_REGISTRY.md`. The remaining collection risk is the bot-blocked domains
the research flagged (ISO, DIFC, DEWA, CEN) — those need Scrapling / a stealth fetch, which the toolbox
carries for exactly that case.

## The store this lands in

`public.kb_chunks` (97,499 rows, 95,310 embedded) already carries BOTH a generated `fts` tsvector AND
an `embedding_gte` vector (pgvector 0.8.0). So the corpus supports keyword and semantic retrieval today.

## The remaining gap (step 5, and the real one)

Retrieval is split: **`kb_query` is full-text/keyword** (the widely-used path) while **`kb_match` is
vector** but takes a *pre-computed* query embedding. Switching the agent-facing retrieval from keyword
to semantic means (a) embedding the query with the free in-region gte-small model, then (b) calling
`kb_match`. That is a multi-routine change to live retrieval behaviour and belongs to its own session —
see memory `retrieval-is-keyword-not-vector`.

## Next (multi-session, still zero cost until the paid soak)

- Bulk-run steps 2–3 over the registry's anchor sources (CPA exemplar first, then the UAE anchors),
  chunk, and load into `kb_chunks` **with** gte embeddings (not fts-only) so `kb_match` can see them.
- Switch the 5 keyword retrieval routines to embed-the-query → `kb_match` (the semantic gap).
- Build the cert-grade exam loop on the existing `knowledge_exam_questions` / `knowledge_exam_results`
  tables (step 6); loop every failed gap back to steps 2–4.
- Schedule the refresh cron (step 7), paused-safe.
