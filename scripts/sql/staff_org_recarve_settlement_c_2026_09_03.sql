-- STAFF_ORG RE-CARVE, PART 3c — EVERY ALIAS OF A PARKED PERSONA RESOLVES TO ITS SUCCESSOR (3 Sep 2026, PACR-004).
--
-- The connectivity register found one directionless connection after part 3: workflow steps name
-- the actor "Fraud & Risk Analyst" (a previous job title, kept addressable through org_agent_alias),
-- the alias still pointed at fraud_analyst, and fraud_analyst is parked, so fn_org_agent_resolve()
-- returned null. Part 3 aliased the parked personas' own keys and part 3b their canonical role ids;
-- the aliases that ALREADY pointed at a parked persona (previous titles, packaged role ids from the
-- 14 Aug reorganisation) were left pointing at it. They now point at the successor, the same way
-- part 1 moved the role-level aliases.
--
--   node scripts/apply_sql.mjs scripts/sql/staff_org_recarve_settlement_c_2026_09_03.sql --apply --ddl
begin;
set local app.change_reason = 'PACR-004 part 3c, 3 Sep 2026: aliases of parked personas resolve to their successors';

create temp table m on commit drop as
  select a.alias old_role, a.role_id new_role, ro.runtime_agent_key old_agent, rn.runtime_agent_key new_agent
    from public.org_role_alias a
    join public.org_role ro on ro.role_id = a.alias
    join public.org_role rn on rn.role_id = a.role_id and rn.status = 'active'
   where a.kind = 'merged_role' and a.reason like 'PACR-004%';
do $chk$ begin
  if (select count(*) from m) <> 19 then
    raise exception 'PACR-004 part 3c: expected the 19 parked-role aliases, found %', (select count(*) from m);
  end if;
end $chk$;

update public.org_agent_alias a
   set agent_key = m.new_agent,
       reason = coalesce(a.reason || ' | ', '') || 'PACR-004 3 Sep 2026: ' || m.old_agent || ' parked; resolves to ' || m.new_agent
  from m
 where a.agent_key = m.old_agent and a.alias <> m.old_agent;

do $proof$
declare v_left int; v_gaps int;
begin
  select count(*) into v_left from public.org_agent_alias a join m on m.old_agent = a.agent_key;
  select count(*) into v_gaps from public.fn_company_connectivity_register();
  if v_left > 0 then raise exception 'PACR-004 part 3c: % aliases still point at a parked persona', v_left; end if;
  if v_gaps > 0 then raise exception 'PACR-004 part 3c: the connectivity register still reports % gap(s): %', v_gaps,
    (select string_agg(gap_class || ' ' || subject, '; ') from public.fn_company_connectivity_register()); end if;
  raise notice 'PACR-004 part 3c proof: 0 aliases on parked personas, connectivity register 0 gaps';
end $proof$;
commit;
