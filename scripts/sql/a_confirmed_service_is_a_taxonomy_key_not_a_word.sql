-- A CONFIRMED SERVICE IS A TAXONOMY KEY, NOT A WORD (23 Sep 2026, agent: sales_engineer, SP-F-01).
--
-- WHY THIS EXISTS. The change beside it (an_inquiry_carries_the_services_it_names.sql) finally makes
-- fn_match_capability's p_services gate fire. The gate is right. The one confirmed row in production
-- was not, and the gate would have turned a stale demo row into a trade with ZERO reachable
-- suppliers the moment it deployed.
--
-- MEASURED 23 Sep 2026, on production, before this file:
--   supplier_capabilities            15,307 rows
--   confirmed_at is not null              1 row  — supplier 126512 "ZZ DEMO Interiors gypsum founderdemo"
--   its trades                            {gypsum, painting}
--   its services         {gypsum.partitions, gypsum.false_ceiling, gypsum.decorative,
--                         gypsum.acoustic_ceiling, gypsum.plastering, الدهانات}
--   fn_services_effective(...)        {gypsum.acoustic_ceiling, gypsum.decorative,
--                                      gypsum.false_ceiling, gypsum.partitions, gypsum.plastering}
--
-- The last entry is a raw Arabic WORD, not a '<trade>.<code>' key, so fn_services_effective drops it
-- — correctly: it joins taxonomy_trade_service and that string is not a service. supplier_capabilities
-- .services deliberately carries BOTH kinds (supplier_services.ts splitServices: a key is a stated
-- service, anything else is the supplier's own words, kept exactly as typed and never dropped). So the
-- shape is legal; THIS row is stale. Per-trade reachability for an inquiry that names a service was
-- therefore about to become: gypsum 1 -> 1, painting 1 -> 0. The backfilled inquiry
-- a179ea8d ("Internal painting for a retail unit handover in Al Nahda, Sharjah",
-- {flooring.epoxy, painting.decorative, painting.exterior, painting.interior}) would have matched
-- NOBODY where it matches one supplier today.
--
-- WHAT «الدهانات» ACTUALLY NAMES, asked of both readers rather than decided here:
--   the SQL alias reader (fn_ar_norm + the word-start pattern fn_norm_trades uses) -> painting.interior,
--     on the aliases 'دهان' and 'دهانات' of taxonomy_trade_service('painting','interior')
--   the TS reader servicesFromText (_shared/service_rewrite.ts), the one the runtime uses  -> ["painting.interior"]
-- Exactly one key, from both, on an exact alias. Nothing else is added: not painting.exterior, not
-- painting.decorative — the supplier did not say those, and "either exact match or no match" cuts
-- both ways. fn_services_effective then adds painting.repainting through the curated implication map,
-- which is the map's job and not this file's.
--
-- AFTER (computed on production with fn_services_effective before writing anything):
--   effective  {gypsum.acoustic_ceiling, gypsum.decorative, gypsum.false_ceiling, gypsum.partitions,
--               gypsum.plastering, painting.interior, painting.repainting}
--   inquiry a179ea8d hits  {painting.interior}   (was {})
--
-- THE WORD IS REPLACED, NOT KEPT BESIDE THE KEY. An own word is what the rewriter could NOT name; a
-- word an active alias names is not an own word, it is a service that was never rewritten. Keeping
-- both would leave the same stale entry in the sales engineer's "to map" queue forever.
update public.supplier_capabilities
   set services = array(select distinct s from unnest(
         array_remove(coalesce(services, '{}'::text[]), 'الدهانات') || array['painting.interior']) s),
       updated_at = now()
 where supplier_id = 126512
   and confirmed_at is not null
   and 'الدهانات' = any(coalesce(services, '{}'::text[]));
