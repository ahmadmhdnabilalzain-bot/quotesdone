# Vendor evaluation — CAD / OCR / ERP references

Date: 6 Aug 2026. Branch `repair/finish-quotesdone`.

The founder asked for five third-party projects to be installed, believing they are needed for
spec-file row #3 and beyond. This is the evaluation. **Nothing here was adopted.** No project
dependency was added, `package.json` was not touched, and no pipeline was rewired.

## What is on disk, and what is not in the repo

All five are shallow-cloned (`--depth 1 --single-branch`) into `vendor/reference/<name>`.
`vendor/reference/` is in `.gitignore`, so **none of this source is committed** — verified with
`git status --porcelain -- vendor` returning zero entries.

| Project | Licence | Size | Files | Clone |
|---|---|---|---|---|
| `cad2data-Revit-IFC-DWG-DGN` | MIT (scripts) + **proprietary** (binary converters) | 3,014.6 MB | 1,233 | ok |
| `OpenConstructionERP` | **AGPL-3.0** | 596.5 MB | 8,025 | ok |
| `PaddleOCR` | Apache-2.0 | 238.4 MB | 2,521 | ok |
| `MinerU` | MinerU Open Source Licence (Apache-2.0 base + extra conditions) | 37.2 MB | 454 | ok |
| `cad-viewer` | MIT core; bundled DWG parser is **GPL-3.0** | 15.0 MB | 1,078 | ok |

**Total ≈ 3.9 GB.** All five clones succeeded; none failed, none 404'd. This is exactly why they
are ignored rather than committed.

## The capability that already exists

Worth stating plainly before evaluating replacements, because it decides four of the five verdicts.

QuotesDone does **not** do local OCR. It sends page images as multimodal content blocks through
`ai_gateway` to a vision model, and gets text *and* structure back in one call:

- `doc_extract` (229 LOC) → `{text, specifications, brands, models, dates, quantities, certifications}`, indexes non-sensitive kinds into `kb_chunks`. Gate green 7/7.
- `drawing_boq` (70 LOC) → a full draft BOQ (`section, description, qty, unit, basis, confidence`) plus category and matching keywords, from a UAE quantity-surveyor system prompt with privacy redaction built into the prompt itself.
- `drawing_redact` → verified redaction. `license_extract` → gate green 12/12. `extract_text` (62 LOC).
- `cad_convert` (73 LOC) → DWG/DXF via the CloudConvert API, with content sniffing (AC10xx header shape match, `SAFE_CAD` allowlist, 40 MB cap) rather than trusting the filename.

That is roughly **434 lines of Deno** delivering what the 3.9 GB above delivers. It also runs
inside Supabase edge functions, and inherits the gateway's routing, cache, budget ceiling and
per-call cost logging. Any replacement loses that instrumentation on day one.

---

## PaddleOCR — https://github.com/PaddlePaddle/PaddleOCR

- OCR and document-AI toolkit: text detection/recognition, layout analysis, table and formula recognition. Python 3.8–3.12, Apache-2.0 (the cleanest licence of the five).
- Would **add** a local OCR stage that produces text from pixels. It would not add structure extraction — `doc_extract` already returns structured JSON, which raw OCR does not.
- Cost to adopt: a Python runtime (**not installed on this machine**), several hundred MB of model weights, and a long-lived inference service. Supabase edge functions are Deno and cannot host it, so this means a new container/VM, plus a GPU if page latency matters.
- Row: **none.** No row needs it; the capability is already covered by `doc_extract`.
- Verdict: **already covered — adopting this is a regression risk.** The only honest argument for it is air-gapped operation or per-page cost at a volume QuotesDone is nowhere near.

## MinerU — https://github.com/opendatalab/MinerU

- PDF/document extraction to markdown/JSON, with layout, reading-order, table and formula models.
- Would **replace** `doc_extract`, not extend it. Same overlap as PaddleOCR, one layer higher.
- Cost: identical shape — Python runtime, model weights, a hosted service. Licence is *not* plain Apache-2.0: it is a custom "MinerU Open Source License" based on Apache 2.0 **with additional conditions**, so it needs a legal read before any commercial use, unlike PaddleOCR.
- Row: **none.**
- Verdict: **already covered — adopting this is a regression risk**, and it would trade a green 7/7 gate for an unproven service.

## cad-viewer — https://github.com/mlightcad/cad-viewer

- Browser-side DXF/DWG viewer and editor. Parses, processes and renders entirely client-side, no backend, and can export a self-contained offline HTML of a drawing.
- The one genuinely **additive** item. Today `cad_convert` ships customer CAD files to CloudConvert — an external SaaS, an API key, a per-conversion cost, and the file leaving the tenant. In-browser rendering means a drawing preview with no round-trip and no third-party egress.
- Cost: real but bounded. It is a pnpm/nx monorepo carrying its own renderer dependencies; it is not a drop-in for a Next 16 / React 19 app and there is no `components.json`, so nothing can be pulled in by CLI. **Licence is the catch:** the core is MIT but the bundled DWG parser stack (`libredwg-web`) is GPL-3.0, and the repo openly sells a proprietary parser precisely for closed-source commercial SaaS that "cannot distribute GPL-3.0 code". A DXF-only preview path looks MIT-clean; DWG means GPL-3.0 exposure or a paid licence.
- Row: **#4 customer portal** (drawing preview on upload), with a spillover to **#3 executive UI**.
- Verdict: **worth one timeboxed spike, scoped to DXF preview only.** Do not touch the DWG path without a licence decision. Does not replace `cad_convert`.

## OpenConstructionERP — https://github.com/datadrivenconstruction/OpenConstructionERP

- A complete self-hosted construction ERP: BOQ, CAD/BIM takeoff, 4D scheduling, 5D cost model, tendering, module marketplace.
- This does not overlap a QuotesDone *component* — it overlaps the **entire product**. Adopting it is not integration, it is replacing QuotesDone with someone else's platform and its own stack, database and deploy.
- **AGPL-3.0 is a hard blocker for a commercial hosted SaaS**: the network clause obliges you to offer complete corresponding source to everyone who uses the service over a network. A `COMMERCIAL-LICENSE.md` exists, so a relicence is purchasable — that is a commercial decision, not an engineering one.
- Row: **#3 executive UI and #5 supplier portal**, but only as a **feature-list reference** — read how they model BOQ and tendering, copy nothing.
- Verdict: **do not adopt.** Useful as a design reference and competitive read; anything else is a rewrite with a licence problem attached.

## cad2data-Revit-IFC-DWG-DGN — https://github.com/datadrivenconstruction/cad2data-Revit-IFC-DWG-DGN

- ETL converters taking `.rvt` / `.dwg` / `.ifc` / `.dgn` to `.xlsx` / `.csv` / `.dae` / `.html` / `.pdf` / `.ifc`, shipped as bundled Windows and Linux binaries plus workflow scripts.
- Genuinely **additive** in one narrow way: `cad_convert` handles DWG/DXF only. This is the sole candidate here that reads **Revit and IFC**, i.e. real BIM input.
- Cost: heavy. **3.0 GB**, the majority of it committed binaries. The converters are under `LICENSE-PROPRIETARY` (MIT covers only the scripts and docs) with vendor pricing, there is an `EXPORT-COMPLIANCE.md` to read, and they are native executables — they cannot run inside a Deno edge function and need a worker VM or container.
- Row: **later than #5.** Nothing in rows #3–#5 ingests Revit or IFC.
- Verdict: **park it.** Revisit only when a real customer actually uploads a `.rvt` or `.ifc`. Buying a proprietary converter and standing up a worker VM ahead of that demand is speculative.

---

## Summary

| Project | Additive or already covered? | Row | Recommendation |
|---|---|---|---|
| PaddleOCR | Already covered by `doc_extract` | — | Do not adopt |
| MinerU | Already covered by `doc_extract` | — | Do not adopt |
| cad-viewer | **Additive** (client-side preview) | #4, #3 | Timeboxed spike, DXF only |
| OpenConstructionERP | Overlaps the whole product | #3, #5 | Reference only (AGPL-3.0) |
| cad2data | **Additive** (Revit/IFC only) | later | Park until real BIM demand |

Four of the five are not needed for row #3. The one that is worth engineering time is `cad-viewer`,
and only for a DXF preview in the customer portal.

## Configuration required by these clones

Vendoring anything into the repo tree breaks the typecheck, and this is worth recording because it
is not obvious: **TypeScript ignores `.gitignore` entirely.** `tsconfig.json` had `include: ["**/*.ts"]`
with `allowJs: true`, so the moment the clones landed, `tsc --noEmit` walked all 3.9 GB of them and
died:

```
FATAL ERROR: Ineffective mark-compacts near heap limit
Allocation failed - JavaScript heap out of memory
```

Two edits, both in the working tree and **not** part of this commit:

1. `.gitignore` — appended `vendor/reference/`, so none of the 3.9 GB can be staged.
2. `tsconfig.json` — `include` narrowed from a bare `**/*.ts` to an explicit allowlist
   (`next-env.d.ts`, `tailwind.config.ts`, `src/**`, `.next/types/**`), plus `"vendor"` added to
   `exclude`.

The allowlist is the load-bearing half and it is the better fix: listing the app's real sources is
narrower than blacklisting clone names one at a time, and it stays correct as more third-party
source is vendored. With it in place `tsc --noEmit` exits 0 against the full tree.

Anyone re-creating `vendor/reference/` in a fresh checkout must re-apply both, or accept a broken
typecheck and build.
