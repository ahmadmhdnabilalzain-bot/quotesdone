-- fn_owning_os — which Operating System owns the agent that took this action.
--
-- Layer 15 asks that every surfaced action explains which OS owned it. Nothing anywhere resolved
-- an agent to an operating system, so the answer was "0 of 35". The chain is exact matches only,
-- in falling order of certainty, and it returns NULL rather than guessing:
--
--   1. the agent IS an operating system's owner_agent          ceo -> leadership
--   2. the agent key IS a named responsibility                 compliance -> legal_gov
--   3. the agent's department is a named responsibility        legal -> legal_gov
--   4. the agent key with a role suffix stripped               finance_ai -> finance
--   5. the agent key IS an operating system key                operations_ai -> operations
--
-- NO FUZZY MATCHING. An agent that resolves to nothing returns null and the surface says
-- "unassigned", because a wrong owning OS on screen is worse than an absent one — it tells the
-- founder a system is accountable for work it never saw.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_owning_os.sql --promote
create or replace function public.fn_owning_os(p_agent text)
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $function$
  with a as (select coalesce(nullif(btrim(p_agent), ''), '~none~') k),
  stripped as (select regexp_replace(a.k, '_(ai|director|ops|monitor|watch|agent|bot)$', '') s from a)
  select coalesce(
    (select o.os_key from public.operating_system o, a where o.owner_agent = a.k and o.active limit 1),
    (select r.os_key from public.os_responsibility r, a where r.responsibility = a.k limit 1),
    (select r.os_key from public.os_responsibility r
       join public.org_agents g on g.department = r.responsibility, a
      where g.agent_key = a.k limit 1),
    (select r.os_key from public.os_responsibility r, stripped where r.responsibility = stripped.s limit 1),
    (select o.os_key from public.operating_system o, a where o.os_key = a.k and o.active limit 1),
    (select o.os_key from public.operating_system o, stripped where o.os_key = stripped.s and o.active limit 1)
  );
$function$;
