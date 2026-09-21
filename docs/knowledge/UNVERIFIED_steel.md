# UNVERIFIED — steel (structural fabrication), 21 Sep 2026

Seat: sales_engineer. Companion to `supabase/functions/_shared/rules/steel.json`. Facts the seed
needed and could not verify from a primary source; none is in the seed.

| # | fact held back | what would verify it | rows it unlocks |
|---|---|---|---|
| 1 | **DMS-035-2020 Requirements for Steel Structures (Dubai Municipality)** — NOT OBTAINED (the URL returns the DM homepage; DM site search is broken, per memory 18 Sep). Unknown: whether it invokes EN 1090 / ISO 3834 / AWS D1.1, which execution class it requires, what inspection it mandates. | Fetch in-browser from Dubai Municipality; if the URL is dead, request through the DM portal. | NO Dubai Municipality row was seeded. Would add `trade_approval` (Dubai Municipality, before_works: structural NOC / permit; on_completion: inspection) and convert `execution_class` and `welding_qualification` scope lines from `practice` to `law` for Dubai. |
| 2 | Trakhees (Ports, Customs and Free Zone Corporation) and DDA (Dubai Development Authority) steel-structure requirements. | Their published building regulations. | NO Trakhees / DDA rows were seeded. |
| 3 | Abu Dhabi DMT / ADM structural steel requirements (and whether Abu Dhabi International Building Code adopts AISC 360 / AWS D1.1). | DMT building-code publications. | NO Abu Dhabi rows were seeded. |
| 4 | UAE Fire and Life Safety Code 2018: the chapter and table giving structural fire-resistance ratings by occupancy, and the clause requiring Civil Defence-listed passive fire-protection products and approved applicators. The seed cites the code edition only. | The CDGH-OP-25 PDF (1,348 pages), structural / passive protection chapter. | `trade_scope_line.fire_protection_of_steel`, `spec_equivalence.finish.intumescent_cd_listed` (both rows), `trade_approval` (Civil Defence) — adds chapter/clause |
| 5 | Civil Defence-listed intumescent products and approved applicators (names, listing numbers, expiries). | The Civil Defence approved-product register. | would let `finish.intumescent_cd_listed` name products with `evidence_kind = authority_approval`, `approval_ref` and `approval_expires` |
| 6 | Structural steel mills / stockists supplying the UAE with EN 10204 3.1 certification (e.g. any consultant-approved list). | A consultant approved-materials list lawfully held, or ESMA/MOIAT conformity records for structural steel. | `brand.structural_steel_mill` — would name mills; today the class is defined by the certificate only |
| 7 | BS EN 1090-2:2018 exact clause numbers (4.1.2, 4.2, 7, 7.4, 8, 9, 9.5.5, 12, 12.4, Table 24, Annex A) and BS EN ISO 1461:2022 Table 3 / cl. 6.3 — cited from working knowledge; the standards were not opened (no licence held). | Licensed copies. | every `practice` row citing them — corrects clause numbers only |
| 8 | ISO 1461 minimum mean coating thicknesses (85/70/55/45 µm by steel thickness) and the Z275 ≈ 20 µm per side conversion — stated from working knowledge of the standard tables. | Licensed copy of ISO 1461:2022 Table 3; EN 10346 for Z-designations. | `trade_scope_line.protective_finish`, `spec_equivalence.finish.hdg_iso1461` rows — figures |
| 9 | AWS D1.1/D1.1M edition current in 2026 (the seed cites 2020). | AWS publication list. | `weld.en1090_iso3834` AWS row, `welding_qualification` scope line — edition year only |
| 10 | Gulf coastal corrosivity category (the seed says C4–C5 per ISO 12944-2). | ISO 12944-2 classification with a UAE site measurement, or a consultant's specification. | `protective_finish` scope line, `finish.paint_iso12944_c4` — wording |

Attribute codes the seed uses that `_shared/line_specs/model.ts` does not yet define for `steel`:
`exc_class`, `weld_standard`, `galv_coating_um`, `fire_rating_min`. Engine work on the parallel
branch, not a fact to verify.
