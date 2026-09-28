-- PROBE: marketing plans recruitment for every trade below ten suppliers (instr 1013 item 3; seat marketing).
-- Pure probe, no DDL. It RUNS the duty (writes plan rows), reads the queue's dry run, and always ends in
-- raise exception 'CHK<<...>>', so the transaction rolls back and nothing it wrote survives.
-- Read with: node scripts/qsql.mjs scripts/sql/probe_marketing_plans_recruitment_for_every_trade_below_ten_suppliers.sql
-- Before merge it is run appended to the migration in one aborted transaction (see the PR).
do $probe$
declare
  v_brakes_before jsonb := (select jsonb_object_agg(key, value) from public.app_secrets
                             where key in ('invite_enabled', 'supplier_outreach_golive', 'invite_daily_cap'));
  v_outbox_before bigint := (select count(*) from public.notifications where type = 'supplier_invite');
  v_report jsonb; v_gaps int; v_plans int; v_bad_rank int; v_bad_body int; v_order_breaks int; v_variant_miss int;
  v_arabic_variant int; v_n int; v_planned int; v_unchecked int; v_fail text[] := '{}';
begin
  v_report := public.fn_marketing_gap_recruitment_plans();

  select count(*) into v_gaps from public.supply_gap where closed_at is null and status <> 'closed' and matchable < target;
  select count(*) into v_plans from public.marketing_gap_recruitment_plan;
  if v_gaps <> v_plans then v_fail := v_fail || format('%s gaps below target but %s plans', v_gaps, v_plans); end if;

  -- ranks are 1..n, and a lower rank never has a smaller gap, or equal gap and less demand
  select count(*) into v_bad_rank from (
    select rank, gap, demand_90d, lag(gap) over (order by rank) pg, lag(demand_90d) over (order by rank) pd,
           row_number() over (order by rank) rn from public.marketing_gap_recruitment_plan) x
   where rank <> rn or gap > pg or (gap = pg and demand_90d > pd);
  if v_bad_rank > 0 then v_fail := v_fail || format('%s plans out of gap/demand order', v_bad_rank); end if;

  select count(*) into v_bad_body from public.marketing_gap_recruitment_plan p
    left join public.taxonomy_trade t on t.code = p.trade
   where p.invite_body not like '%{{link}}%' or p.invite_body ~ '[؀-ۿ]'
      or position(coalesce(t.label, p.trade) in p.invite_body) = 0 or position(coalesce(t.label, p.trade) in p.invite_subject) = 0;
  if v_bad_body > 0 then v_fail := v_fail || format('%s variants without the link, with Arabic, or not naming the trade', v_bad_body); end if;

  select count(*) into v_unchecked from public.marketing_recruitment_source where checked_at is null or http_status is null or url !~ '^https?://';
  if v_unchecked > 0 then v_fail := v_fail || format('%s sources without a recorded lookup', v_unchecked); end if;
  if (select count(*) from public.marketing_gap_recruitment_plan where jsonb_array_length(sources) = 0) > 0 then
    v_fail := v_fail || 'a plan with no source at all'::text; end if;

  -- the queue: tier (recruit 0, planned 1, other 2) then plan rank never goes backwards; English planned leads carry their variant
  with c as (select * from public.fn_supplier_invite_candidates(200) with ordinality as q(lead_id, to_email, company_name, lang, subject, body, pos)),
  t0 as (
    select c.pos, c.lang, c.subject, c.body,
      case when exists (select 1 from public.supply_gap g join public.leads l on l.id = c.lead_id
                         where g.status = 'recruit' and g.trade = any(coalesce(l.invite_trades, '{}')) and (g.emirate = 'UAE' or g.emirate = l.emirate)) then 0
           when pl.rank is not null then 1 else 2 end as tier,
      coalesce(pl.rank, 2147483647) as prank, pl.invite_subject
    from c join public.leads l on l.id = c.lead_id
    left join lateral (select p.rank, p.invite_subject from public.marketing_gap_recruitment_plan p
                        where p.trade = any(coalesce(l.invite_trades, '{}')) and (p.emirate = 'UAE' or p.emirate = l.emirate)
                        order by p.rank limit 1) pl on true),
  t as (select t0.*, lag(tier) over (order by pos) as ptier, lag(prank) over (order by pos) as pprank from t0)
  select count(*),
         count(*) filter (where tier <= 1),
         count(*) filter (where tier < ptier or (tier = 1 and ptier = 1 and prank < pprank)),
         count(*) filter (where tier = 1 and lang = 'en' and subject is distinct from invite_subject),
         count(*) filter (where lang = 'en' and (subject ~ '[؀-ۿ]'))
    into v_n, v_planned, v_order_breaks, v_variant_miss, v_arabic_variant
    from t;
  if v_order_breaks > 0 then v_fail := v_fail || format('%s queue positions out of tier/plan order', v_order_breaks); end if;
  if v_variant_miss > 0 then v_fail := v_fail || format('%s English planned invitations without the trade variant', v_variant_miss); end if;
  if v_arabic_variant > 0 then v_fail := v_fail || format('%s English invitations with Arabic subject', v_arabic_variant); end if;

  -- the brakes: nothing sent, no go switch or cap moved
  if (select jsonb_object_agg(key, value) from public.app_secrets where key in ('invite_enabled', 'supplier_outreach_golive', 'invite_daily_cap'))
     is distinct from v_brakes_before then v_fail := v_fail || 'an invitation brake changed'::text; end if;
  if (select count(*) from public.notifications where type = 'supplier_invite') <> v_outbox_before then
    v_fail := v_fail || 'an invitation was written to the outbox'::text; end if;
  if exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public'
              and p.proname in ('fn_marketing_gap_recruitment_plans', 'fn_marketing_gap_recruitment_report', 'fn_supplier_invite_candidates')
              and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                   or not coalesce(array_to_string(p.proconfig, ',') like '%search_path%', false))) then
    v_fail := v_fail || 'a routine is callable by anon/authenticated or has no pinned search_path'::text; end if;

  raise exception 'CHK<<%>>', case when cardinality(v_fail) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_fail, '; ') end
    || format(' | gaps=%s plans=%s queue=%s planned_or_recruit_in_queue=%s | report=%s', v_gaps, v_plans, v_n, v_planned,
              (v_report - 'top') || jsonb_build_object('top5', (select jsonb_agg(e) from jsonb_array_elements(v_report->'top') with ordinality a(e, i) where i <= 5)));
end $probe$;
