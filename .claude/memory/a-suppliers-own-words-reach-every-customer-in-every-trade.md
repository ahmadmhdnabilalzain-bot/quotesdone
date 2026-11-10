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
