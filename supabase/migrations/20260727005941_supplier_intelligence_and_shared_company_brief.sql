-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727005941   name: supplier_intelligence_and_shared_company_brief
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ 6. SUPPLIER INTELLIGENCE ============
-- Deterministic scoring from observed behaviour. No model call anywhere in this path.
create or replace function public.fn_supplier_score_refresh() returns integer
language plpgsql security definer set search_path = public as $fn$
declare n integer;
begin
  insert into supplier_score (lead_id, response_rate, avg_response_hours, quotes_submitted, quotes_won,
                              rejection_count, price_index, quality_rating, reliability, last_active, computed_at)
  select l.id,
         coalesce(l.rv_response_rate, 0),
         null,
         coalesce(q.submitted, 0),
         coalesce(q.won, 0),
         coalesce(q.rejected, 0),
         q.price_index,
         l.rating,
         -- Reliability: response behaviour dominates, win rate confirms it, rejections and refunds subtract.
         round(least(100, greatest(0,
             coalesce(l.rv_response_rate,0) * 0.55
           + (case when coalesce(q.submitted,0) > 0 then 100.0*coalesce(q.won,0)/q.submitted else 0 end) * 0.25
           + (case when l.verified then 20 else 0 end)
           - coalesce(q.rejected,0) * 2
           - coalesce(l.rv_nonresponse_refunds,0) * 5
         )), 1),
         greatest(l.portal_updated_at, l.approved_at, l.scraped_at),
         now()
  from leads l
  left join (
    select q.supplier_id,
           count(*) as submitted,
           count(*) filter (where q.status = 'won')      as won,
           count(*) filter (where q.status = 'rejected') as rejected,
           round(avg(q.quote_amount) filter (where q.quote_amount > 0), 2) as price_index
    from quotes q group by q.supplier_id
  ) q on q.supplier_id = l.id
  where l.id is not null
  on conflict (lead_id) do update set
    response_rate = excluded.response_rate, quotes_submitted = excluded.quotes_submitted,
    quotes_won = excluded.quotes_won, rejection_count = excluded.rejection_count,
    price_index = excluded.price_index, quality_rating = excluded.quality_rating,
    reliability = excluded.reliability, last_active = excluded.last_active, computed_at = now();
  get diagnostics n = row_count;
  return n;
end; $fn$;

revoke execute on function public.fn_supplier_score_refresh() from anon, authenticated, public;

create or replace view public.v_supplier_intelligence as
select l.id as lead_id,
       l.company_name,
       l.emirate,
       l.verified,
       l.approval_status,
       s.reliability,
       s.response_rate,
       s.quotes_submitted,
       s.quotes_won,
       s.rejection_count,
       s.price_index,
       s.quality_rating,
       case
         when not l.verified                                        then 'UNVERIFIED - must not receive an RFQ'
         when coalesce(s.quotes_submitted,0) = 0                    then 'UNPROVEN - never quoted'
         when coalesce(s.response_rate,0) < 30                      then 'SLOW RESPONDER - reveals here are refund risk'
         when coalesce(s.rejection_count,0) >= 5                    then 'FREQUENTLY REJECTED - check scope fit before fanning out'
         when coalesce(s.reliability,0) >= 75                       then 'RELIABLE - safe to prioritise'
         else 'AVERAGE'
       end as verdict,
       s.last_active,
       s.computed_at
from leads l
left join supplier_score s on s.lead_id = l.id;

-- ============ 4. ONE SHARED VIEW OF THE COMPANY, NOT TEN PRIVATE ONES ============
-- Every department reads the same computed brief instead of each paying a model to work out
-- the same situation from scratch. Cost point 4: "do not let every department think independently".
create or replace function public.fn_company_brief() returns text
language plpgsql stable security definer set search_path = public as $fn$
declare v text;
begin
  select concat_ws(E'\n',
    'COMPANY SITUATION as at ' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ' UTC. This brief is computed from live rows and is shared by every department - do not re-derive it.',
    '',
    'MARKETPLACE STATE',
    (select string_agg('- ' || label || ': ' || coalesce(value::text,'unmeasured')
              || case when target is not null then ' (target ' || target || ', ' || state || ')' else '' end, E'\n' order by domain, label)
     from v_bi_scorecard),
    '',
    'CATEGORY COVERAGE',
    (select '- ' || count(*) filter (where coverage='COMPLIANT') || ' of ' || count(*)
            || ' catalogue categories have an employee at the full 14-module standard; '
            || count(*) filter (where coverage='NO_AGENT') || ' have no employee at all.'
     from v_category_coverage),
    '',
    'RESOURCE PRESSURE',
    (select coalesce(string_agg('- ' || resource || ': ' || state || ' (' || coalesce(used_pct::text,'0') || '% of ' || capacity || ' ' || unit || ')', E'\n' order by resource)
            filter (where state <> 'OK'), '- All pools within limits.')
     from v_resource_pressure),
    '',
    'OPEN RISKS AND SELF-DETECTED DEFECTS',
    (select '- ' || count(*) || ' proposals open from the self-evolution scan; '
            || (select count(*) from risk_register where coalesce(status,'open') = 'open') || ' open risks on the register.'
     from evolution_proposal where status = 'proposed'),
    '',
    'ECONOMIC REALITY',
    (select '- ' || state || '. Reveal rate ' || (reveal_rate*100) || '%, ' || leads_total || ' leads in pipeline, '
            || verified_suppliers || ' verified, ' || inquiries_total || ' inquiries ever, ' || reveals_total || ' reveals ever.'
     from v_unit_economics)
  ) into v;
  return v;
end; $fn$;

revoke execute on function public.fn_company_brief() from anon, authenticated, public;
