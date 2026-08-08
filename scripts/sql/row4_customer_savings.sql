-- ROW #4 (customer portal) — spec §11, "cost optimization shows potential savings broken down by
-- category" and "a total potential-savings figure is presented".
--
-- WHAT EXISTED. project_api's dashboard computes ONE global avg_savings_pct from the spread between
-- quotes on the same RFQ. That is a percentage, not an amount; it is not broken down by anything;
-- and no routine in the database named a savings figure alongside a category at all.
--
-- TWO FIGURES, KEPT APART ON PURPOSE. They answer different questions and have different evidence:
--   spread_saving_aed    — the cheapest quote on an RFQ against the dearest one you also hold. Real
--                          money, available today, and it needs no market data — only 2+ quotes.
--   benchmark_saving_aed — the quote you would otherwise accept against the category median across
--                          the platform. This one needs the market sample to clear min_sample, and
--                          it is NULL, not 0, when it does not.
-- Adding them together would double-count, so they are returned separately and the total names
-- which of the two it sums.
--
-- ZERO-DATA CONTRACT. Production holds zero quotes. This returns by_category = [] and a total of
-- null with a reason — never a 0 that reads as "you have nothing to save".

create or replace function public.fn_customer_savings(p_customer uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_min_sample int;
  v_rows int;
  v_by_cat jsonb;
  v_spread numeric; v_bench numeric;
begin
  select coalesce((p.policy ->> 'min_sample')::int, 4) into v_min_sample
    from supplier_negotiation_policy p where p.scope = 'default';
  v_min_sample := coalesce(v_min_sample, 4);

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

revoke execute on function public.fn_customer_savings(uuid) from public;
grant execute on function public.fn_customer_savings(uuid) to service_role, postgres;
