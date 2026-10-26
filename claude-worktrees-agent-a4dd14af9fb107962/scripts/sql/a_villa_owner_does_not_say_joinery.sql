-- A VILLA OWNER DOES NOT SAY "JOINERY"
--
-- Reported by the founder: ask the intake assistant for "marble worktops for a villa kitchen in
-- Dubai" and it asks you to choose between "Fit-Out Contractors / Interior Fit-Out Suppliers" and
-- "Joinery & Carpentry Suppliers" — our supplier taxonomy, not a buyer's words — while
-- fn_norm_trades('marble') returns {flooring}, which is neither of the two offered. Real friction
-- on the primary conversion flow.
--
-- MEASURED, and it is worse than the report. Three probes on production:
--     fn_norm_trades('marble')                                   -> {flooring}
--     fn_norm_trades('marble worktops for a villa kitchen ...')   -> {flooring}
--     fn_norm_trades('kitchen')                                  -> {}
--     fn_norm_trades('worktop')                                  -> {}
-- `kitchen`, `worktop` and `countertop` are in NO trade's alias list anywhere in a 40-trade
-- vocabulary. The words a villa owner would actually use for the job resolve to nothing, and the
-- only thing that does match is `marble`, which is an alias of `flooring` — a material treated as a
-- trade. So the one trade the phrase named was the one trade it does not mean.
--
-- THE SUPPLY SIDE HAS THE SAME HOLE. 122 leads mention kitchen, worktop or countertop and 104 of
-- them match none of joinery's existing aliases (joinery, carpentry, carpenter, woodwork, wooden,
-- millwork, cabinet, wardrobe). Those 104 suppliers are invisible to the exact query this defect
-- makes a customer type.
--
-- WHAT THIS DOES NOT DO: remove `marble` from flooring. It is tempting — a material is not a trade
-- — but measured, 157 leads mention marble and 25 of them mention no other flooring word at all, so
-- dropping it would orphan 25 real suppliers to fix a phrasing problem. Marble flooring is also a
-- real thing. The phrase now resolves to {flooring, joinery} instead of {flooring}: still ambiguous,
-- which is honest, but the correct trade is now among the options instead of absent from them.
-- Disambiguating an ambiguous phrase is the assistant's job; naming only the wrong trade was not.

update public.taxonomy_trade
   set aliases = (
     select array_agg(distinct a order by a)
     from unnest(aliases || array[
       -- the room, which is how a buyer names the job
       'kitchen', 'kitchens', 'fitted kitchen', 'kitchen fitting',
       -- the surface, which is what they are actually buying
       'worktop', 'worktops', 'work top', 'countertop', 'countertops', 'counter top',
       -- the adjacent joinery a kitchen or bathroom enquiry almost always carries
       'vanity', 'vanity unit', 'built in wardrobe', 'closet'
     ]) a)
 where code = 'joinery' and active;
