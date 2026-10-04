-- THE NEGOTIATION POLICY LEAVES THE DATABASE (30 Sep 2026). Seat: sales_engineer.
--
-- Founder ruling 527: negotiation is removed. The portal panel, the edge function and fn_negotiation_guidance went on
-- 21 Sep 2026 (DROPPED.txt). MEASURED on production 30 Sep 2026 (ledger reconciliation): public.supplier_negotiation_policy
-- still held ONE row (scope 'default', approved_by 'spec3:2026-08-27', no supplier_id) whose bands included
-- {"suspiciously_high": {"action": "escalate_to_human"}} - a hand-off to a person that ruling 17 forbids - and ONE routine
-- read it: fn_customer_savings(uuid), for the single number min_sample = 4.
--
-- THE FIX. fn_customer_savings keeps 4 as its own rule (same behaviour, no negotiation dependency); nothing else reads
-- the table (pg_proc bodies, 30 Sep 2026: fn_customer_savings only; no view, no trigger, no cron command). The table is
-- DROPPED rather than archived: its one row is configuration, not a record of anything that happened, and its exact
-- content stays in git (scripts/sql/spec3_three_rows_a_capability_was_waiting_on.sql inserts it). Ruling 17 is kept
-- by removal: no "escalate to human" action remains. The daily export registry row goes with it.
-- The body below is production's, read with pg_get_functiondef on 30 Sep 2026, changed only where marked.
--
-- prevented by: scripts/checks/the_negotiation_policy_leaves_the_database.test.mjs

create or replace function public.fn_customer_savings(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_min_sample int;
  v_rows int;
  v_by_cat jsonb;
  v_spread numeric; v_bench numeric;
begin
  -- 30 Sep 2026 (sales_engineer): the minimum sample is this routine's own rule. It used to be read from
  -- the removed negotiation feature's policy table (ruling 527), whose one row held 4.
  v_min_sample := 4;

  select count(*) into v_rows
    from quotes q join inquiries i on i.id = q.inquiry_id
   where i.customer_id = p_customer and coalesce(q.status, '') <> 'draft'
     and q.quote_amount is not null and q.quote_amount > 0;

  if v_rows = 0 then
    return jsonb_build_object(
      'customer_id', p_customer, 'as_of', now(), 'min_sample', v_min_sample,
      'by_category', '[]'::jsonb,
      'total_spread_saving_aed', null, 'total_benchmark_saving_aed', null,
      'quotes_considered', 0,
      'empty_reason', 'No quotes on your requests yet. Potential savings are measured from the quotes you actually hold — the spread between them, and each one against the market median for its category — so there is nothing to compute until suppliers respond.');
  end if;

  with live as (
    select q.id, q.inquiry_id, q.quote_amount, coalesce(i.category, 'uncategorised') category
      from quotes q join inquiries i on i.id = q.inquiry_id
     where i.customer_id = p_customer and coalesce(q.status, '') <> 'draft'
       and q.quote_amount is not null and q.quote_amount > 0
       and coalesce(i.status, '') not in ('completed', 'cancelled', 'closed')
  ), per_rfq as (
    select inquiry_id, category, count(*) n_quotes,
           max(quote_amount) - min(quote_amount) spread, min(quote_amount) cheapest
      from live group by inquiry_id, category
  ), bench as (
    select l.category, l.inquiry_id, min(l.quote_amount) cheapest, s.median, s.n
      from live l left join category_price_stats s on s.category = l.category
     group by l.category, l.inquiry_id, s.median, s.n
  )
  select jsonb_agg(x order by x ->> 'category'), sum((x ->> 'spread_saving_aed')::numeric),
         sum(coalesce((x ->> 'benchmark_saving_aed')::numeric, 0))
    into v_by_cat, v_spread, v_bench
    from (
      select jsonb_build_object(
               'category', p.category,
               'rfqs', count(distinct p.inquiry_id),
               'quotes', sum(p.n_quotes),
               'spread_saving_aed', round(sum(case when p.n_quotes >= 2 then p.spread else 0 end), 0),
               'market_median', max(b.median),
               'market_sample_n', max(b.n),
               'benchmark_saving_aed', case when max(b.n) >= v_min_sample
                 then round(greatest(0, sum(b.cheapest) - sum(b.median)), 0) end,
               'benchmark_basis', case when coalesce(max(b.n), 0) >= v_min_sample
                 then format('cheapest quote(s) held against a market median over %s comparable quote(s)', max(b.n))
                 else format('no market benchmark: only %s comparable quote(s) recorded in this category, and %s are needed',
                             coalesce(max(b.n), 0), v_min_sample) end
             ) x
        from per_rfq p join bench b on b.inquiry_id = p.inquiry_id and b.category = p.category
       group by p.category
    ) z;

  return jsonb_build_object(
    'customer_id', p_customer, 'as_of', now(), 'min_sample', v_min_sample,
    'by_category', coalesce(v_by_cat, '[]'::jsonb),
    'total_spread_saving_aed', v_spread,
    'total_benchmark_saving_aed', case when v_bench > 0 then v_bench end,
    'quotes_considered', v_rows,
    'empty_reason', case when coalesce(v_bench, 0) = 0
      then format('No market benchmark saving is shown: no category on your open requests yet has the %s comparable quotes this house policy requires before it will quote a market median.', v_min_sample) end);
end $function$;

delete from public.table_export_registry where table_name = 'supplier_negotiation_policy';
drop table if exists public.supplier_negotiation_policy;

select case
  when to_regclass('public.supplier_negotiation_policy') is not null then 'PROBE FAILED: the table is still there'
  when exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ilike '%supplier_negotiation_policy%')
    then 'PROBE FAILED: a routine still names the table'
  when (public.fn_customer_savings('00000000-0000-0000-0000-000000000000'::uuid)->>'min_sample')::int is distinct from 4
    then 'PROBE FAILED: fn_customer_savings lost its minimum sample'
  else 'PROBE OK' end as verdict;
