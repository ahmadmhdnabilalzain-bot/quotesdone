-- THE COMPANY BRIEF READS NO DEPARTMENTS (24 Sep 2026; seat: ceo).
-- fn_company_self_knowledge_sync() calls fn_company_brief(), which looped over fn_company_state()->'departments'.
-- The departments were removed on 7 Sep 2026 (the founder's ruling), so that value is JSON null and every sync
-- raised 22023 "cannot extract elements from a scalar"; the terms file of 23 Sep calls the sync and could not apply.
-- This is the live body (it had no canonical file) with that one loop guarded. CREATE OR REPLACE keeps its ACL
-- (postgres, service_role).
--   node scripts/apply_sql.mjs scripts/sql/the_company_brief_reads_no_departments.sql --apply --ddl --seat ceo
CREATE OR REPLACE FUNCTION public.fn_company_brief(p_max_chars integer DEFAULT 1600)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s jsonb; out text; d jsonb;
begin
  s := fn_company_state();
  out := 'COMPANY SELF-KNOWLEDGE (authoritative org facts — you may answer any question about the company from this):'||E'\n'
       ||'Vision: '||(s->>'vision')||E'\n'
       ||'Totals: '||(s->'totals'->>'departments')||' departments, '||(s->'totals'->>'brain_agents')||' brain agents, '
       ||(s->'totals'->>'category_sales_agents')||' category sales agents, '||(s->'totals'->>'tools_wired')||' wired tools, '
       ||(s->'totals'->>'open_objectives')||' open objectives, '||(s->'totals'->>'open_tasks')||' open tasks.'||E'\n'
       ||'Departments (lead · brain agents · north star):'||E'\n';
  -- No departments since 7 Sep 2026: fn_company_state() returns null for them, which is not an array. Read it as
  -- an empty list rather than fail every self-knowledge sync (22023, measured 24 Sep 2026).
  for d in select * from jsonb_array_elements(case when jsonb_typeof(s->'departments') = 'array' then s->'departments' else '[]'::jsonb end) loop
    out := out || '- '||(d->>'name')||' ['||(d->>'dept')||']: lead '||coalesce(d->>'lead_agent','—')
                || ', '||(d->>'headcount')||' agent(s)';
    if jsonb_array_length(d->'brain_agents') > 0 then
      out := out || ' ('||replace(replace(replace((d->'brain_agents')::text,'"',''),'[',''),']','')||')';
    end if;
    out := out || ', north star: '||coalesce(d->>'north_star','—')||E'\n';
    exit when length(out) > p_max_chars;
  end loop;
  return left(out, greatest(p_max_chars, 400));
end $function$;
