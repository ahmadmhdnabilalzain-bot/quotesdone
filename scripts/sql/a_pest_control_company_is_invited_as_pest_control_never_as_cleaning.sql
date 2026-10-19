-- A PEST-CONTROL COMPANY IS INVITED AS PEST CONTROL, NEVER AS CLEANING. Seat: marketing. 19 Oct 2026.
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 19 Oct 2026):
--   * 46 leads with sector 'pest_control' (source apify_2026-06, Maps category "Pest control service")
--     carry invite_trades = {cleaning}. A further 8 named "... PEST CONTROL ..." (uaecsd / uaecompanies)
--     carry {cleaning} or {} - so an invitation asked them to quote for cleaning, and a pest-control
--     inquiry never reached them.
--   * The cause is the mapping, still live: taxonomy_trade 'cleaning' holds the four Arabic pest-control
--     aliases (مكافحة حشرات, مكافحة آفات, مكافحة قوارض, رش مبيدات). an_intake_trade_word_names_its_own_trade_never_a_neighbour.sql
--     (24 Sep) moved the English 'pest control' alias off cleaning but not these, and invite_trades was
--     derived while 'pest control' still named cleaning, so those rows were never re-derived.
--   * fn_taxonomy_trades_for('pest control') and ('pest_control') already return {pest_control}: the
--     resolver is right, the alias table and the stored rows are not.
--
-- WHAT THIS CHANGES
--   1. The four Arabic pest aliases leave cleaning and join pest_control (one alias, one trade).
--   2. sector = 'pest_control' leads: invite_trades = {pest_control} (they are pest-control companies only).
--   3. Leads whose company name says "pest control" gain pest_control; a name that also says cleaning
--      keeps cleaning ("X Pest Control & Cleaning Services" does both).
-- NOT CHANGED: fn_norm_trades, fn_taxonomy_trades_for, any multi-trade web_scrape lead whose name does
-- not say pest control (its pest signal is one Maps category among many), any invited_at / outbox row.

update public.taxonomy_trade
   set aliases = array(select a from unnest(aliases) a
                        where a not in ('مكافحة حشرات','مكافحة آفات','مكافحة قوارض','رش مبيدات'))
 where code = 'cleaning';

update public.taxonomy_trade
   set aliases = array(select distinct a from unnest(aliases || array['مكافحة حشرات','مكافحة آفات','مكافحة قوارض','رش مبيدات']) a)
 where code = 'pest_control';

update public.leads
   set invite_trades = array['pest_control']
 where sector = 'pest_control'
   and invite_trades is distinct from array['pest_control'];

update public.leads
   set invite_trades = array(select distinct t from unnest(
         array_remove(coalesce(invite_trades, '{}'), case when company_name !~* 'clean' then 'cleaning' end)
         || array['pest_control']) t order by t)
 where company_name ~* 'pest[[:space:]-]*control'
   and not ('pest_control' = any(coalesce(invite_trades, '{}')));

do $v$
declare n_bad int; n_alias int;
begin
  select count(*) into n_bad from public.leads
   where (sector = 'pest_control' or company_name ~* 'pest[[:space:]-]*control')
     and not ('pest_control' = any(coalesce(invite_trades, '{}')));
  select count(*) into n_alias from public.taxonomy_trade
   where code = 'cleaning' and aliases && array['مكافحة حشرات','مكافحة آفات','مكافحة قوارض','رش مبيدات'];
  if n_bad > 0 or n_alias > 0 then
    raise exception 'pest_control routing not fixed: % leads still without pest_control, % cleaning pest aliases', n_bad, n_alias;
  end if;
end $v$;
