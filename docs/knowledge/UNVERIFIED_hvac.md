# UNVERIFIED — hvac (chillers), 21 Sep 2026

Seat: sales_engineer. Companion to `supabase/functions/_shared/rules/hvac.json`. Verified (memory
18 Sep): Cabinet Resolution 157/2025 exists, issued 04 Nov 2025, effective 15 Nov 2025, Gazette 811,
repeals Res. 3/2020, 365 days to regularise, **figures not read**; Al Sa'fat 2nd ed. Jan 2023 cl.
502.01, 503.04, 503.05, 701.05 as quoted in the seed, **no COP/IPLV/EER figure anywhere in it**.

| # | fact held back | what would verify it | rows it unlocks |
|---|---|---|---|
| 1 | **The efficiency schedule of Cabinet Resolution 157/2025** — the EER / efficiency figures, the capacity bands ("low" and "large"), and whether water chillers are inside its scope at all. The seed asserts only existence, dates and that registration evidence should be asked for. | Open the schedule link on https://uaelegislation.gov.ae/en/legislations/3862 in-browser. | `trade_approval` (MOIAT row) — would gain a scope statement and thresholds; could add `price_red_flag` / `spec_equivalence.efficiency` rows with figures |
| 2 | That MOIAT is the implementing authority named in Res. 157/2025 (the seed attributes it to MOIAT because ESMA was merged into MOIAT; the resolution text was not read for the attribution). | The resolution's articles. | `trade_approval` MOIAT row — `authority` column |
| 3 | **Dubai Building Code H.4.8.1 (buildings) and K.10.1.5.1 (villas) efficiency figures** that Al Sa'fat cl. 502.01 delegates to. | Dubai Building Code PDF (Dubai Municipality). | would add `spec_equivalence.efficiency` and `price_red_flag` rows with Dubai minimums; today the seed says only "at least 10 % above the Building Code figure for Golden/Platinum Sa'fa" |
| 4 | Whether Estidama (Abu Dhabi Pearl Rating) or the Abu Dhabi International Energy Code sets chiller efficiency or refrigerant limits. | Estidama PBRS manual; DMT publications. | NO Abu Dhabi rows were seeded. |
| 5 | GWP values used (IPCC AR4, 100-yr, as tabulated in ASHRAE 34): R-134a 1,430; R-410A 2,088; R-32 675; R-513A 631; R-1234ze(E) 6; R-290 3; R-717 0 — from working knowledge of ASHRAE 34 tables, not opened. Al Sa'fat does not say which GWP source (AR4/AR5/AR6) it applies. | ASHRAE 34 (licensed) and Al Sa'fat's definitions section. | every `refrigerant.al_safat_gwp_lt_100` row — figures; the pass/fail verdicts would not change under AR5/AR6 for any of these |
| 6 | AHRI 550/590 (I-P) and 551/591 (SI) current edition (the seed cites 2023), the standard rating conditions (35 °C air-cooled, 29.4 °C entering condenser water), and the IPLV weighting (1/42/45/12 %). | AHRI standards (freely published on ahrinet.org). | every row citing AHRI — confirms edition and figures |
| 7 | The AHRI certification directory entry for any quoted model (the class `brand.chiller_manufacturer_ahri_range` and `efficiency.ahri_certified_rating` depend on it). | https://www.ahridirectory.org per model. | brand rows — `evidence_kind` from `datasheet` to a citable listing; `source_ref` |
| 8 | UAE offices / distributors for Daikin, Carrier, Trane, York (Johnson Controls), Mitsubishi Electric, Petra, Zamil. | Manufacturer partner pages. | brand rows — `source_ref` |
| 9 | UAE design ambient of 46 °C for air-cooled selection and the "15–25 % derate" — practice figures; the ASHRAE climatic design data for Dubai/Abu Dhabi were not opened. | ASHRAE Handbook — Fundamentals climatic data; a consultant's design-basis report. | `capacity_at_design_conditions` scope line, `condenser.water_cooled` air-cooled row — wording |
| 10 | UAE Fire Code 2018 provisions for refrigerant machinery rooms (A2L/A3/B2L) and whether Civil Defence reviews them. | CDGH-OP-25, mechanical / refrigeration chapter. | `trade_approval` Civil Defence row — kept `practice` until then |
| 11 | CTI STD-201 for cooling-tower thermal certification — cited from working knowledge. | CTI publication. | `trade_comparability.cooling_tower` — citation only |

Attribute codes the seed uses that `_shared/line_specs/model.ts` does not yet define for `hvac`:
`cop_full_load`, `iplv`, `compressor_type`, `condenser_type`, `design_ambient_c`, `gwp`. The existing
`efficiency` reader already captures "COP 6.1" / "IPLV 9.5" as text. Engine work on the parallel
branch, not a fact to verify.
