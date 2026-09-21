# UNVERIFIED — electrical (LV switchboards), 21 Sep 2026

Seat: sales_engineer. Companion to `supabase/functions/_shared/rules/electrical.json`. Everything here
is a fact the seed NEEDED and could not verify from a primary source in this session; none of it is
in the seed. Each item says what to fetch, in-browser (several authority sites 403 to curl), and
which row it would unlock. Verified facts live in `memory/uae-authority-source-facts-18-sep.md`.

| # | fact held back | what would verify it | rows it unlocks |
|---|---|---|---|
| 1 | Exact issue date of the DEWA Regulations for Electrical Installations, 2017 edition. The seed uses `effective_date = 2017-01-01` as the edition year, not a measured date. | The PDF's cover / foreword (linked from the DEWA homepage; the standards page 404s). | every `label = law` row citing DEWA 2017 — corrects `effective_date` only |
| 2 | The DEWA 2017 clause that requires a registered electrical contractor for LV works, and the registration classes. | DEWA 2017 PDF, contractor-registration chapter. | `trade_approval` — "Electrical contractor registered with DEWA" (cited to the edition, clause not named) |
| 3 | The DEWA 2017 clause on inspection and testing before connection. | DEWA 2017 PDF, inspection chapter. | `trade_scope_line.site_testing_and_dewa_inspection`, `trade_approval` row 1 (clause not named) |
| 4 | ADDC (Abu Dhabi) Electricity Wiring Regulations — edition, clause naming IEC 61439 for LV assemblies, contractor registration. | ADDC website, regulations PDF. | NO Abu Dhabi rows were seeded. Would add `trade_approval` (ADDC, before_works / on_completion / supplier_licence) and a Dubai→Abu Dhabi `label = law` mirror of the IEC 61439 scope line. |
| 5 | SEWA (Sharjah) electrical regulations — edition and LV assembly clause. | SEWA website. | NO Sharjah rows were seeded; same shape as #4. |
| 6 | Etihad Water & Electricity (formerly FEWA, Northern Emirates) — regulations edition, and confirmation that EtihadWE is the current name/authority. | EtihadWE website. | NO Northern-Emirates rows were seeded; same shape as #4. |
| 7 | Manufacturer UAE office or licensed panel-builder for each brand in `brand.lv_assembly_iec61439_range` (Schneider Electric, ABB, Siemens, Legrand, Hager, Eaton). | Each manufacturer's UAE contact / partner page. | `spec_equivalence` brand rows — would move `evidence_kind` from `datasheet` to a citable presence and let `source_ref` carry the URL. |
| 8 | Any consultant-approved-materials list for LV switchgear on a UAE project (the doctrine's `consultant_list` evidence kind). | A project specification or approved-vendor list lawfully held. | would let a `consultant_list` row exist; none does today |
| 9 | IEC 61439-1:2020 / -2:2020 exact clause numbers. The seed cites clauses (5.3.x, 8.2.2, 8.101, 10.x, 11) from working knowledge of the 2020 edition and did not open the standard (QuotesDone holds no licence to it). | A licensed copy of IEC 61439-1/-2:2020. | every `practice` row citing an IEC 61439 clause — corrects clause numbers only; the rule text stands |
| 10 | Typical fault levels downstream of 1600–2000 kVA transformers (the seed says "50 kA for 1 s is a common MDB requirement"). | DEWA transformer impedance data or a consultant's fault-level calculation. | `spec_equivalence.icw.50ka_1s` base row — wording only |

Attribute codes the seed uses that `_shared/line_specs/model.ts` does not yet define for `electrical`:
`form_of_separation`, `icw_ka`, `ip_rating`, `busbar_material`, `rated_current_a`. The engine cannot
read them from a quotation until readers are added there; the seed rows are correct and inert until
then. That is engine work on the parallel branch, not a fact to verify.
