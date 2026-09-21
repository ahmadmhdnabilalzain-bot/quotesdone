# UNVERIFIED — fire_fighting (fire alarm and detection), 21 Sep 2026

Seat: sales_engineer. Companion to `supabase/functions/_shared/rules/fire_fighting.json`. The only
verified facts are: the current edition is September 2018, ref CDGH-OP-25, 1,348 pages; cl. 2.2.4
and 2.2.7 refer the consultant to NFPA 70/72/75/76/110/111 and manufacturer guidance; NFPA 72 is
referenced, not adopted (memory 18 Sep). Everything else below was held back.

| # | fact held back | what would verify it | rows it unlocks |
|---|---|---|---|
| 1 | UAE Fire Code 2018 chapter and clause numbers for: fire alarm system requirements by occupancy, Civil Defence design approval and completion inspection, contractor registration, product listing (material approval), direct-alarm monitoring, and maintenance by approved contractors. The seed cites the edition only on every such row. | The CDGH-OP-25 PDF, fire detection and alarm chapter and the approvals / listing chapters. | every `law` row in `trade_scope_line`, `spec_equivalence.approval.*`, `trade_approval` — adds chapter/clause |
| 2 | Whether the code names EN 54 and/or UL 864 as acceptable product certification, and in which words. The seed treats EN 54 / UL 864 as the entry ticket and the Civil Defence listing as the approval. | Same PDF, product-listing chapter. | `control_panel_en54` scope line, `approval.civil_defence_listed` rows |
| 3 | The Civil Defence approved-product register itself (per emirate): listing numbers and expiries for panels, detectors, sounders, call points and cables of the brands in `brand.fa_panel_en54_addressable_range` (Notifier, Siemens, Bosch, Apollo, Hochiki, Kidde). | The register (Dubai Civil Defence and the other emirates' Civil Defence portals). | brand rows — would move `evidence_kind` from `datasheet` to `authority_approval` with `approval_ref` / `approval_expires` |
| 4 | UAE distributors / offices for those brands. | Manufacturer partner pages. | brand rows — `source_ref` |
| 5 | Dubai Civil Defence 24/7 direct-alarm monitoring service: its current name (the seed mentions "Hassantuk" as an example only), the building classes it is mandatory for, the approved transmitters, and the subscription cost bearer. Same for the other emirates. | Dubai Civil Defence service page and the code clause. | `civil_defence_monitoring_connection` scope line (kept `practice`), `trade_approval` Dubai monitoring row (kept `practice`) — would become `law` with a clause |
| 6 | EN 54 part numbers cited (54-2, -3, -4, -5, -7, -11, -12, -13, -16, -17, -20, -23, -25, -29) and the EN 54-5 class table — from working knowledge; the standards were not opened (no licence held). | Licensed copies or the CEN catalogue entries. | every row citing an EN 54 part — confirms part/title only |
| 7 | BS EN 50200 PH classes and BS 6387 CWZ categories — from working knowledge. | Licensed copies. | `cabling_fire_resistant` scope line, `cable.fire_survival_120` rows |
| 8 | The "10 m" ceiling-height rule of thumb for beam detectors and the "20 % spare loop capacity" convention in the seed are UAE practice, not code text. | A consultant specification, or the code clause if one exists. | `detector_schedule`, `loop_capacity_and_spare` scope lines — wording |
| 9 | Whether ionisation smoke detectors face an import / FANR (Federal Authority for Nuclear Regulation) restriction in the UAE. | FANR regulations. | `detector.smoke_optical` ionisation row — would become `law` if a restriction exists |

Attribute codes the seed uses that `_shared/line_specs/model.ts` does not yet define for `fire`
(the model.ts key for this trade): `detector_type`, `panel_type`, `loop_count`, `wiring_class`,
`cable_fire_rating`. Engine work on the parallel branch, not a fact to verify. Note the key
mismatch: taxonomy `fire_fighting` ↔ model.ts `fire`; `tradeOfCategory()` already maps the category
to `fire`, so the seed is keyed by the taxonomy code as the doctrine requires.
