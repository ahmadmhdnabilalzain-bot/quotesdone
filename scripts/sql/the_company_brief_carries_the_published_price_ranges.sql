-- customer_support, 12 Oct 2026 (founder rulings 1195/1196; coordinator decision on PR #1330).
--
-- WHY. Every conversation reply is now written by a model from the company brief (_shared/company_brief.ts), and a
-- money figure the brief does not state is sent back to the model for a rewrite. The published per-trade price ranges
-- (public.price_benchmark, 1,086 rows, 399 distinct trade/item/unit lines) were reachable only through the old
-- per-question price reasoning, which the redesign removed — so "what does a gypsum ceiling cost" lost its range.
--
-- WHAT. fn_price_brief() returns those ranges as one compact text block, one line per trade/item/unit, chosen exactly
-- as fn_price_guidance chooses them (the company's own published guide first, then the newest), plus the trades with a
-- deliberate gap row. company_brief.ts appends it to the brief, so the figure check accepts these figures and nothing
-- else. Read live on every brief build (cached 5 minutes per worker): a benchmark edit reaches the replies at once.
--
-- SECURITY. A new SECURITY DEFINER routine: search_path pinned and EXECUTE revoked from public, anon and authenticated
-- (CREATE grants EXECUTE to PUBLIC). The edge functions call it with the service role.
create or replace function public.fn_price_brief()
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with lines as (
    select distinct on (pb.category, pb.item, pb.unit)
           pb.category, pb.item,
           '- ' || pb.category || ': ' || pb.item || ': AED '
             || trim(to_char(pb.low, 'FM999999990.##'))
             || case when pb.high is not null and pb.high <> pb.low then ' to ' || trim(to_char(pb.high, 'FM999999990.##')) else '' end
             || coalesce(' per ' || nullif(nullif(pb.unit, ''), 'none'), '')
             || coalesce(' (as of ' || pb.as_of::text || ')', '') as line
      from public.price_benchmark pb
     where pb.source_kind <> 'gap' and pb.item is not null and pb.low is not null
     order by pb.category, pb.item, pb.unit, (case when pb.source_kind = 'blog_post' then 0 else 1 end), pb.as_of desc nulls last, pb.id
  )
  select '## PUBLISHED PRICE GUIDE (UAE ranges QuotesDone publishes; quote them as a range and say it is a guide, not a quotation — suppliers price the work)'
      || E'\n' || coalesce((select string_agg(line, E'\n' order by category, item) from lines), '')
      || coalesce(E'\nNo published range (say so, never estimate): '
                  || (select string_agg(distinct category, ', ') from public.price_benchmark where source_kind = 'gap'), '');
$fn$;

revoke execute on function public.fn_price_brief() from public, anon, authenticated;

-- PROBE (no DDL is undone: it reads only). The block must carry the published guide and the gap trades.
select case
  when public.fn_price_brief() !~ 'PUBLISHED PRICE GUIDE' then 'PROBE FAILED: no header'
  when (select count(*) from regexp_matches(public.fn_price_brief(), E'\n- ', 'g')) < 100 then 'PROBE FAILED: fewer than 100 price lines'
  else 'PROBE OK'
end as verdict;
