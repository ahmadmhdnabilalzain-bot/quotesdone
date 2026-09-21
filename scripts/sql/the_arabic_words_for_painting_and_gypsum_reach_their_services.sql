-- THE ARABIC WORDS FOR PAINTING AND GYPSUM REACH THEIR SERVICES (21 Sep 2026, it_engineer).
--
-- Supplier-portal audit of 21 Sep 2026, finding 8. A supplier wrote "نقوم بأعمال الجبس والأسقف
-- المستعارة والدهانات" on the Services tab. Only "False ceilings" came back; "الدهانات" fell to "kept in
-- your own words" although Painting & finishes › Interior painting exists.
--
-- MEASURED (production, 21 Sep 2026): taxonomy_trade_service.aliases for painting.interior held only
-- compound Arabic forms ('دهان داخلي', 'دهانات داخلية', 'صبغ داخلي'); gypsum.partitions held only
-- compounds ('قواطع جبس', 'جبس بورد', …). service_rewrite strips the article ال and the conjunction و,
-- so after stripping "الدهانات" is "دهانات" and "الجبس" is "جبس" — neither alias existed.
--
-- WHAT THIS CHANGES: appends 'دهان','دهانات' to painting.interior and 'جبس' to gypsum.partitions, only
-- when absent (a re-run changes nothing). The same two edits are in supabase/functions/_shared/
-- service_aliases.json (the edge function's copy) and in the original seed file
-- a_supplier_describes_its_services_in_its_own_words_and_the_sales_engineer_rewrites_them.sql, so the
-- one-seed check keeps the three in step.
--
-- NOT CHANGED: every other alias; the rewrite algorithm; labels; implications. A catalogue build is
-- changing aliases in parallel — this file touches two rows only, so the two merge cleanly.
--
-- PROOF: the verdict row at the end. Prevented from recurring by
-- supabase/functions/_shared/service_rewrite.test.ts (replays the audit sentence).
--
-- Seat: it_engineer.
--
--
--
--
--
--
--
--
--
--
--
--
--
--
update public.taxonomy_trade_service t
   set aliases = t.aliases || array(select a from unnest(x.add) a where not (a = any(t.aliases)))
  from (values ('painting', 'interior', array['دهان','دهانات']::text[]),
               ('gypsum', 'partitions', array['جبس']::text[])) as x(trade_code, code, add)
 where t.trade_code = x.trade_code and t.code = x.code
   and not (x.add <@ t.aliases);

select case
  when (select count(*) from public.taxonomy_trade_service
         where (trade_code = 'painting' and code = 'interior' and array['دهان','دهانات']::text[] <@ aliases)
            or (trade_code = 'gypsum' and code = 'partitions' and array['جبس']::text[] <@ aliases)) = 2
  then 'PROBE OK: painting.interior carries دهان/دهانات and gypsum.partitions carries جبس'
  else 'PROBE FAILED: an Arabic alias is missing after the update'
end as verdict;
