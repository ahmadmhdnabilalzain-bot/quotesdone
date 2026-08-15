-- PURGE 02 — the score rows the deleted demo leads left behind.
--
-- supplier_capabilities is ON DELETE CASCADE on leads, so it cleaned itself: 0 orphans on both
-- projects. supplier_score is NOT — it keys on lead_id with no cascade — so deleting the demo
-- leads left its rows pointing at nothing:
--
--   production  supplier_score 20,471 against 20,465 leads   ->  6 orphans (the 6 ZZ DEMO rows)
--   staging     supplier_score     58 against      2 leads   -> 56 orphans
--
-- Left alone these are exactly the shape this codebase keeps meeting: a count that reads as
-- "20,471 suppliers scored" while 6 of them are companies that no longer exist. Only orphans are
-- touched; every score row belonging to a surviving lead stays, which is what he chose when he
-- kept the enrichment.

begin;

delete from supplier_score s
 where not exists (select 1 from leads l where l.id = s.lead_id);

do $$
begin
  raise notice 'supplier_score=% leads=% orphans=%',
    (select count(*) from supplier_score),
    (select count(*) from leads),
    (select count(*) from supplier_score s where not exists (select 1 from leads l where l.id = s.lead_id));
end $$;

commit;
