-- GOVERNANCE "STALE" COUNTS EMPLOYEES, NOT PERSONAS (6 Sep 2026). Knowledge audit company_wide.md §5, action #10.
--
-- MEASURED: the Governance page's "88 stale" is fn_knowledge_gaps(14, 4), which iterates
-- category_agents - the 88 active supplier-category PERSONAS (cat:<slug>) - and marks each stale when
-- its agent_knowledge was last updated more than 14 days ago; all 88 were last written 2026-07-30.
-- It said nothing about the 54 employees, and no instrument did.
--
-- fn_employee_knowledge_freshness(p_stale_days) is the sibling over org_agents (active, kind brain /
-- agent): profession + state rows served (non-quarantined), last update, days stale, status
-- missing / stale / thin / ok - the same shape as fn_knowledge_gaps so the page renders it with the
-- same component. fn_knowledge_gaps now carries it under 'employees' (its own 'summary'/'agents'
-- keep meaning category personas, and are labelled so on the page). Default stale window 30 days:
-- a profession row is a job description, not a persona rewrite.
--
--   node scripts/apply_sql.mjs scripts/sql/governance_stale_counts_employees_not_personas.sql --apply --ddl

begin;

create or replace function public.fn_employee_knowledge_freshness(p_stale_days integer default 30, p_thin_min integer default 1)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with base as (
    select a.agent_key as slug, coalesce(a.title, a.role, a.agent_key) as name, a.department,
           (select count(*) from public.agent_knowledge k
             where k.agent_key = a.agent_key and coalesce(k.layer,'profession') in ('profession','state')
               and coalesce(k.validation_status,'') <> 'quarantined') as items,
           (select max(k.updated_at) from public.agent_knowledge k
             where k.agent_key = a.agent_key and coalesce(k.layer,'profession') in ('profession','state')
               and coalesce(k.validation_status,'') <> 'quarantined') as last_updated,
           (select count(*) from public.agent_knowledge k
             where k.agent_key = a.agent_key and k.layer = 'experience'
               and coalesce(k.validation_status,'') <> 'quarantined') as lessons
      from public.org_agents a
     where a.active and a.kind in ('brain','agent')
  ),
  scored as (
    select slug, name, department, items, lessons, last_updated,
           case when last_updated is null then null else floor(extract(epoch from (now() - last_updated))/86400)::int end as days_stale,
           case when items = 0 then 'missing'
                when last_updated < now() - (p_stale_days || ' days')::interval then 'stale'
                when items < p_thin_min then 'thin'
                else 'ok' end as status
      from base
  )
  select jsonb_build_object(
    'population', 'employees (org_agents active, kind brain/agent)',
    'thresholds', jsonb_build_object('stale_days', p_stale_days, 'thin_min', p_thin_min),
    'summary', jsonb_build_object(
      'total', (select count(*) from scored),
      'ok', (select count(*) from scored where status = 'ok'),
      'stale', (select count(*) from scored where status = 'stale'),
      'thin', (select count(*) from scored where status = 'thin'),
      'missing', (select count(*) from scored where status = 'missing'),
      'coverage_pct', round(100.0 * (select count(*) from scored where status = 'ok') / nullif((select count(*) from scored), 0), 1)),
    'agents', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', slug, 'name', name, 'emoji', null, 'department', department, 'items', items, 'lessons', lessons,
        'last_updated', last_updated, 'days_stale', days_stale, 'status', status)
        order by case status when 'missing' then 0 when 'stale' then 1 when 'thin' then 2 else 3 end, days_stale desc nulls last, slug)
      from scored), '[]'::jsonb));
$function$;

revoke execute on function public.fn_employee_knowledge_freshness(integer, integer) from public, anon, authenticated;
grant execute on function public.fn_employee_knowledge_freshness(integer, integer) to service_role;

CREATE OR REPLACE FUNCTION public.fn_knowledge_gaps(p_stale_days integer DEFAULT 14, p_thin_min integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with base as (
    select ca.slug, ca.name, ca.emoji,
      (select count(*) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as items,
      (select max(updated_at) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as last_updated,
      (select min(d.os_key) from os_knowledge_domain d
        where d.domain_key = 'cat:'||ca.slug and d.ownership = 'owns') as owner_os
    from category_agents ca where coalesce(ca.active,true)
  ),
  scored as (
    select slug, name, emoji, items, last_updated, owner_os,
      case when last_updated is null then null else floor(extract(epoch from (now()-last_updated))/86400)::int end as days_stale,
      case when items = 0 then 'missing'
           when last_updated < now() - (p_stale_days||' days')::interval then 'stale'
           when items < p_thin_min then 'thin'
           else 'ok' end as status
    from base
  )
  select jsonb_build_object(
    -- THE POPULATION IS NAMED. 'summary' and 'agents' are the supplier-category PERSONAS
    -- (category_agents, cat:<slug>); the 54 employees are under 'employees'.
    'population', 'category personas (category_agents active)',
    'thresholds', jsonb_build_object('stale_days', p_stale_days, 'thin_min', p_thin_min),
    'summary', jsonb_build_object(
      'total', (select count(*) from scored),
      'ok', (select count(*) from scored where status='ok'),
      'stale', (select count(*) from scored where status='stale'),
      'thin', (select count(*) from scored where status='thin'),
      'missing', (select count(*) from scored where status='missing'),
      'unowned', (select count(*) from scored where owner_os is null),
      'coverage_pct', round(100.0 * (select count(*) from scored where status='ok') / nullif((select count(*) from scored),0), 1)
    ),
    'agents', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', slug, 'name', name, 'emoji', emoji, 'items', items, 'owner_os', owner_os,
        'last_updated', last_updated, 'days_stale', days_stale, 'status', status
      ) order by case status when 'stale' then 0 when 'thin' then 1 when 'missing' then 2 else 3 end, days_stale desc nulls last, slug)
      from scored), '[]'::jsonb),
    'employees', public.fn_employee_knowledge_freshness(30, 1)
  );
$function$;

-- PROOF, in-file and read-only: the employee read covers every active employee and the page's
-- JSON carries it.
do $proof$
declare e jsonb; n_emp int;
begin
  e := public.fn_employee_knowledge_freshness(30, 1);
  select count(*) into n_emp from public.org_agents where active and kind in ('brain','agent');
  if (e->'summary'->>'total')::int <> n_emp then raise exception 'employee freshness covers % of % employees', e->'summary'->>'total', n_emp; end if;
  if (public.fn_knowledge_gaps()->'employees'->'summary'->>'total')::int <> n_emp then raise exception 'fn_knowledge_gaps does not carry the employee read'; end if;
  raise notice 'employees: %', e->'summary';
end $proof$;

commit;
