# Market-pack recall below the floor: diagnosis and fix (27-28 Oct 2026)

Seat: it_engineer. Instrument: `node scripts/eval/knowledge_pack_eval.mjs --mode live`, path `ml` (production's
`fn_ml_read_space()`), trade-blind (the gate's default), `p_audience => 'visitor'`, recall@5, floor EN 0.35 (unchanged).

## The numbers

| run (market packs only, `--packs '\.market$'`, 219 packs x 2 seats) | EN | AR | pairs below EN floor | packs below |
|---|---:|---:|---:|---:|
| before, trade-blind (the gate) | 0.849 | 0.758 | 66 | 34 |
| after, trade-blind (the gate) | **0.909** | 0.767 | **40** | **21** |
| after, trade named (`--with-trade`, as think() calls once its planner names the trade) | 0.982 | 0.968 | 8 | 4 |

The brief said 33 packs. The live run on 27 Oct measured 34. `machinery_repair.market` read EN 0.000 / AR 0.000 for
both seats, as stated.

No row, vector or routine changed. Only the expected-answer sets of 13 market questions changed, so every
non-market pack scores exactly as before by construction.

## What was measured, per failing question (`mdiag`: the routine's own output plus the exact ml rank inside `sales_knowledge`)

There are three classes. Each pack can show more than one.

1. **The right trade, but a sibling entry wins. 25 of 34 packs had one of their own trade's rows in the top 5.** The question's nearest `sales_knowledge` row is its
   own trade's base-pack entry, usually `product-distinctions`, not the one market entry the eval expects.
   - Example: business_centres asks "shared spots, a mailing-only setup, or my own closed room". The row returned first
     is `business_centres:product-distinctions`, whose body is hot desk, dedicated desk, private office and virtual
     office.
   - In most of these cases the returned entry answers the question. The eval named only one of the two correct entries.
2. **The wrong trade wins. In 9 packs no row of the question's own trade reached the top 5.** The question was written blind, in paraphrase ("scratchy pads, spinning
   cutters"; "measuring, ashore or underwater"; "drinking machines"), and another trade's entry is nearer.
   - machinery_repair: `elevators:amc-comprehensive-vs-non` 0.879 and `power_generators:maintenance-amc` 0.870 beat the
     expected `machinery_repair:uae-market-sizes` at 0.854.
   - The 205 market packs share three template titles ("<label>: typical sizes, units and how it is quoted in the UAE"),
     so a market entry looks like its 204 twins apart from the label.
3. **Displaced by other sources: a few.** The expected row is in the top 5 of `sales_knowledge`, but `kb_chunks` rows
   with higher similarity fill the combined top 5 (agri_inputs: every one of the top 5 is a chunk at 0.843-0.863).
   These are honest near-ties, not a ranking defect. In 13 of the 15 cases where the expected row was in the exact
   top 5, it was present in the routine's output, so the HNSW candidate search is not dropping rows.

## Options tried and refused, with the measurement

| option | measured | ruling |
|---|---|---|
| Content: replace the template title with "<label> in the UAE: <the entry's own lead sentence>" | similarity moved by -0.016 to +0.019 per entry; cleared 23 of 72 entries by a loose proxy; lowered several | no. It changes little, and what it does change is chance |
| Content: a title written for the question (machinery: "how repair workshops charge: inspection fee, hourly labour, call-out, per job or AMC") | 0.858 -> 0.887, above elevators 0.879 | no. It echoes the question's words. Each market pack has ONE eval question, so nothing held out could show the change generalises. This is writing the entry to the test |
| Retrieval: infer the trade from the vector (the trade of the nearest trade-tagged rows) and use the trade-resolved branch | top-5/min-2 gate: 634 right, **58 wrong** (28 of them now passing); stricter top-5/min-3: 418 right, 14 wrong, 444 undecided | no. Even on questions that are all about one trade, it misroutes 2-8%. A misroute gives a customer the wrong trade's pack, labelled as theirs. Trade identification is the planner's job, and production already sends `p_trade` (#1590) |
| Rewrite the blind questions | - | no. They are written blind on purpose. Making them easier is weakening the eval |
| Lower the floor, or gate on `--with-trade` | - | no. Both weaken the gate |

## What was done

**1. The eval's answer key, corrected for 13 packs (class 1).**
- Each question now names its trade's base-pack entry beside the market entry. It uses `expected_mode: "any"` with a
  `why` written for that question, which is the mechanism `verified_packs.mjs` already validates and which 14 questions
  already used.
- Candidates were only the trade's own rows the routine returned. One was accepted only when its body answers the
  question as asked.
- Accepted: business_centres, calibration_services, exhibition_stands, fleet_maintenance, hotel_furniture,
  insurance_brokerage, investigation_screening, jewellery_supplies, marble_stone, pest_control, road_works,
  uniforms_corporate_apparel, waterproofing.
- Refused:
  - castings_forgings, auto_parts: the question asks whether it can be made or found locally, and a types entry does not
    say.
  - hvac: price drivers do not say how load is matched.
  - hospitality_supplies, mannequins: no pricing or rental units.
  - solar, swimming_pools: the candidate answers only part of the question.
  - luxury_rigid_boxes, laboratory_equipment, stationery, landscaping, plastics_pipes: no candidate answered.
- Each question carries `alternate_ruled` saying how it was chosen.

**2. The daily exam now scores those questions the same way.**
- `fn_it_engineer_knowledge_recall_exam` divided hits by the number of entries named.
  `seat_knowledge_eval_question` never carried the mode, so every `any` question (14 before this PR, 27 after) was
  scored "all required" in production while the eval scored it "any one".
- `scripts/sql/an_any_mode_eval_question_is_answered_by_any_of_its_entries.sql` adds `expected_any` and changes that one
  expression. The loader writes the flag.
- The file was diffed against the live `pg_get_functiondef` (md5 b470cf9f…, equal line for line to its canonical file).
  The only difference is the recall expression and a restated revoke for the one signature.
- Probe, replayed together with the file through `safe_replay` and always rolled back:
  - with the change: `PROBE OK: any-mode fixture 1 / all-required fixture 0.5`;
  - on the live routine: `REPRODUCED`;
  - alone: `NOT APPLIED`.
- Live md5 and the column were re-read after each run and were unchanged.
- Pending: apply at merge, then re-run `load_knowledge_eval_questions.mjs`.

**3. `--packs <regex>` on the eval**, because a full run took more than 30 minutes against the management API's
throttle. A filtered run ranks against every row; the full run is still the gate.

prevented by: `scripts/checks/an_any_mode_eval_question_is_answered_by_any_of_its_entries.test.mjs` (fails when the
exam's any-branch is removed; checked by mutation).

## What is still below the floor, and why it is left

There are 21 packs on the trade-blind path:
- abrasives_surface_finishing, agri_inputs, auto_parts, castings_forgings, hospitality_supplies, hvac
- laboratory_equipment, land_survey, landscaping, luxury_rigid_boxes, machinery_repair, mannequins_visual_merchandising
- plastics_pipes, racking_storage, solar, stationery_office_supplies, steel, swimming_pools
- textiles_fabrics, vending_machines, water_dispensers

With the trade named, 17 of the 21 clear. The 4 that do not (hvac, mannequins, plastics_pipes, stationery) lose to
their own trade's other entries, not to another trade.

So the remaining blind-path failures are trade identification on paraphrased questions. No measured option fixes that
without either writing entries to the one test question or misrouting 2-8% of trade questions. Production identifies
the trade through the planner.

The open measurement that decides whether this is a real risk is **how often the planner names the right trade for
these 21 questions**. That needs a model call per question, so it was not run here, under the ruling against paid
batch inference.
