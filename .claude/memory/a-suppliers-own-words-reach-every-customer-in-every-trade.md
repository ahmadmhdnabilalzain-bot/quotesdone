---
name: a-suppliers-own-words-reach-every-customer-in-every-trade
description: 10 Nov 2026, ledger 1573/1579/1586. Matching is general across all 223 trades: profile services with evidence, licence check, reviewed alias queue, curated adjacency, similarity ranks only.
metadata:
  type: project
---
Founder ledger 1573 (profile keywords drive matching, "e.g. PVC decorative panels"), 1579 (every trade, not just that case),
1586 (every UAE trade except F&B: the 223 taxonomy codes in 12 groups, never the 32 intake slugs).

**What exists (branch sales_engineer-general-matching, stacked on inquiry-core; SQL pending until merge):**
- `scripts/sql/a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql`: `wallpaper.film_wrap`;
  `public.service_alias_proposal` (the review queue; `fn_service_alias_propose` / `fn_service_alias_decide`, approval appends
  to `taxonomy_trade_service.aliases` and refuses a phrase that names another service); 427 curated aliases on 44 services
  in all 12 groups; `public.taxonomy_trade_adjacent` (43 curated pairs); `supplier_capabilities.service_phrases`;
  `decision_policy.score_w_service_similarity` (ranking only).
- `fn_match_capability`: with a service named, the reach is the request's trades + each named service's trade + curated
  adjacent trades, ONE level; a supplier found only through the reach must hold a named service; no service named = the old
  exact trade gate.
- `_shared/profile_services.ts`: profile/catalogue -> services with the supplier's words (`DocEvidence.services`); licence
  activities kept (`DocEvidence.activities`); `source_docs.proposed_services` + `source_docs.licence_check`; not covered ->
  `agent_actions` `licence_scope_check` (never a rejection). The Services tab offers them UNTICKED (founder 862 stands).
- `service_rewrite.withoutFrame`: "supply/installation of X" is X (grammar). NO plural folding: an alias names each form.
- The request's chosen keys: `inquiry_state.specs.service_keys` (expert-advice branch) -> `inquiries.service_keys` at create
  (`customer_api/lib/state_service_keys.ts`) and the intake count.

**Proof:** `_shared/general_matching.test.ts` (44 rows, text -> codes; 46 failed before) and the probe (codes -> suppliers on
production, rolled back: 44/44 matched, 44/44 cross-group controls out, 12/12 confusables). Before the file, the same probe
matched 37/44 only at trade level (an exterior painter got interior painting) and missed every neighbour-trade request.

**How to apply:** grow coverage by approving queue rows (`sales_engineer` action `alias_decide`), never by a word rule at match
time; a new adjacency is a curated row with both reasons. Duplicate services across trades (packaging.labels vs
labels_sleeves, packaging.cartons vs corrugated_packaging, tents_shades vs fencing_shades) do not meet at the service gate.

**12 Nov 2026 (founder 1647; branch sales_engineer-the-catalogue-can-name-what-suppliers-do, SQL pending until merge):**
- The same work under two keys now meets through `service_implication.same = true` rows, ONE EACH WAY, plus a curated
  adjacency when the two trades are not neighbours: an implication alone is not enough, because `fn_match_capability`
  only reaches the request's trades, each named service's trade and their adjacent trades. Identity is ONE level deep:
  an implication that ends in a pair key needs its own row to the twin (fn_services_effective does not chain). 18 pairs
  done (36 rows) plus the twins; still open: packaging.labels/cartons vs labels_sleeves/corrugated_packaging. Not every
  near-duplicate is identity: waterproofing.thermal is roofs AND walls, so it IMPLIES roof and wall insulation. A reader
  that ASKS about implied services must skip `same` rows (confirming one key is confirming the other). The mirror
  `_shared/service_implications.json` carries every row (the_implication_map_has_one_seed reads both files).
- `fn_service_alias_propose` refuses a demo supplier (`fn_supplier_is_demo`). Before it, 26 of 28 open proposals were
  ZZ DEMO fixtures'. Their `supplier_ids` still name 1 to 7 leads each, but those leads are deleted, so the id list
  alone shows nothing; a row is traced through its `service_alias_review` agent_action (detail.pairs) and the quoted
  line in `scripts/e2e/registration_fixtures.mjs`. (An earlier version of this note said the lists were empty: wrong.)
- A new service's aliases must be checked against every NAME of every live service (key, code, both labels, aliases) before
  they are written; normalise the catalogue once (calling `fn_service_alias_owners` per alias did not finish in 120 s).
  Proof: `scripts/checks/the_catalogue_can_name_what_suppliers_do.test.mjs` and its probe.
