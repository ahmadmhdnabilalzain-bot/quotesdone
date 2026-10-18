-- aluminum IS the aluminium trade, by its US spelling. Seat: sales_engineer. 12 Oct 2026 (#1311 review).
--
-- A supplier who writes "Aluminum" is an aluminium supplier. public.fn_norm_trades resolves a live code or an intake
-- slug exactly; 'aluminium' resolved, 'aluminum' did not (measured: fn_norm_trades_many('{aluminum}') = {}). The US
-- spelling is stored here as an intake alias, so the database stays the one definition of an exact trade word
-- (trade_resolve.codeWordsOf reads it through fn_norm_trades_many). Data only: no routine, no grant.
insert into public.intake_trade_taxonomy (intake_slug, trade_codes, note)
values ('aluminum', array['aluminium'], 'aluminium = "Aluminium & cladding"; US spelling (12 Oct 2026, #1311)')
on conflict (intake_slug) do nothing;

-- verdict: the alias resolves to exactly the aluminium trade
select case when public.fn_norm_trades('aluminum') = array['aluminium'] then 'PROBE OK'
            else 'PROBE FAILED: fn_norm_trades(aluminum) = ' || coalesce(public.fn_norm_trades('aluminum')::text, 'NULL') end as verdict;
