-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727010021   name: rename_shared_situation_brief
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- fn_company_brief(int) already exists and carries org STRUCTURE self-knowledge.
-- The shared live SITUATION brief is a different thing; give it its own name so neither is ambiguous.
drop function if exists public.fn_company_brief();

create or replace function public.fn_company_situation() returns text
language plpgsql stable security definer set search_path = public as $fn$
declare v text;
begin
  select concat_ws(E'\n',
    'COMPANY SITUATION as at ' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ' UTC. Computed from live rows and shared by every department - do not re-derive it.',
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

revoke execute on function public.fn_company_situation() from anon, authenticated, public;
