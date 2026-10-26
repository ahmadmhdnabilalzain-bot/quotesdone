-- STAFF_ORG RE-CARVE, PART 3b — THE LAST FOUR SEAMS (3 Sep 2026, PACR-004).
--
-- After part 3 the org behaviour suite still measured four seams the 14 Aug merge convention had
-- closed and this re-carve had not:
--   1. a parked persona's CANONICAL ROLE ID must also resolve to a live executor through
--      org_agent_alias (part 3 aliased the agent keys; the role ids resolve to a role but not to an
--      agent — "canonical id document_operations_specialist does not resolve to an agent");
--   2. Supply has no knowledge scope: 544 ops_knowledge records live under the legacy department
--      keys supplier_success and bizdev, which merged into marketplace and growth on 14 Aug. Those
--      domains are Supply's now, so the merge map re-parents them and fn_dept_scope('supply') finds
--      them — the same mechanism that gives every other department its merged knowledge;
--   3. five committee seats are held by parked roles — they pass to the successor, or lapse where
--      the successor already sits on that committee;
--   4. a parked persona's KPIs and the remediation opened against one of them belong to the
--      successor that owns the function now; a KPI the successor already carries is retired.
--
--   node scripts/apply_sql.mjs scripts/sql/staff_org_recarve_settlement_b_2026_09_03.sql --apply --ddl
begin;
set local app.change_reason = 'PACR-004 part 3b, 3 Sep 2026: last seams of the STAFF_ORG re-carve';

create temp table m on commit drop as
  select a.alias old_role, a.role_id new_role, ro.runtime_agent_key old_agent, rn.runtime_agent_key new_agent
    from public.org_role_alias a
    join public.org_role ro on ro.role_id = a.alias
    join public.org_role rn on rn.role_id = a.role_id and rn.status = 'active'
   where a.kind = 'merged_role' and a.reason like 'PACR-004%';
do $chk$ begin
  if (select count(*) from m) <> 19 then
    raise exception 'PACR-004 part 3b: expected the 19 parked-role aliases, found %', (select count(*) from m);
  end if;
end $chk$;

-- 1. Canonical role ids of parked personas resolve to the successor's executor.
insert into public.org_agent_alias (alias, agent_key, reason)
  select m.old_role, m.new_agent,
         'PACR-004 3 Sep 2026: canonical role id of a persona parked in the STAFF_ORG re-carve; resolves to the executor that inherited its work'
    from m
   where not exists (select 1 from public.org_agents a where a.agent_key = m.old_role)
  on conflict (alias) do update set agent_key = excluded.agent_key, reason = excluded.reason;

-- 2. Supply's knowledge scope: the supplier-side legacy departments re-parent to Supply.
update public.org_departments set merged_into = 'supply', merged_at = now()
 where dept_key in ('supplier_success', 'bizdev') and not active;

-- 3. Committee seats follow the seat that inherited the role.
update public.org_role_committee c set role_id = m.new_role, note = coalesce(c.note || ' | ', '') || 'PACR-004 3 Sep 2026: seat inherited from ' || m.old_role
  from m
 where c.role_id = m.old_role
   and not exists (select 1 from public.org_role_committee x where x.role_id = m.new_role and x.committee_key = c.committee_key);
delete from public.org_role_committee c using m where c.role_id = m.old_role;

-- 4. KPIs and remediation follow the function.
update public.employee_kpi k set agent_key = m.new_agent
  from m
 where k.agent_key = m.old_agent
   and not exists (select 1 from public.employee_kpi x where x.agent_key = m.new_agent and x.kpi = k.kpi);
update public.employee_kpi k set active = false
  from m where k.agent_key = m.old_agent and k.active;
update public.agent_remediation ar
   set agent_key = m.new_agent, status = 'open', closed_at = null,
       detail = (coalesce(ar.detail, '{}'::jsonb) - 'closed_reason') || jsonb_build_object('transferred', 'PACR-004 3 Sep 2026: opened against ' || m.old_agent || ', now parked; the KPI it remediates is owned by ' || m.new_agent)
  from m
 where ar.agent_key = m.old_agent and ar.failure_class = 'kpi_miss';

-- PROOF
do $proof$
declare v_unres int; v_scope text[]; v_seats int; v_kpi int; v_rem int;
        v_rehearsal boolean := coalesce(current_setting('app.recarve_rehearsal', true), '') = '1';
begin
  select count(*) into v_unres from m where public.fn_org_agent_resolve(m.old_role) is null
     or not exists (select 1 from public.org_agents a where a.agent_key = public.fn_org_agent_resolve(m.old_role) and a.active);
  select public.fn_dept_scope('supply') into v_scope;
  select count(*) into v_seats from public.org_role_committee c where not exists (select 1 from public.org_role r where r.role_id = c.role_id and r.status = 'active');
  select count(*) into v_kpi from public.employee_kpi k join m on m.old_agent = k.agent_key where k.active;
  select count(*) into v_rem from public.agent_remediation ar where ar.failure_class = 'kpi_miss'
     and not exists (select 1 from public.org_agents o where o.agent_key = ar.agent_key and o.active);
  if v_unres > 0 then raise exception 'PACR-004 part 3b: % parked role ids do not resolve to a live executor', v_unres; end if;
  if not (v_scope @> array['supplier_success', 'bizdev']) then raise exception 'PACR-004 part 3b: fn_dept_scope(supply) = %', v_scope; end if;
  if v_seats > 0 then raise exception 'PACR-004 part 3b: % committee seats still held by non-active roles', v_seats; end if;
  if v_kpi > 0 then raise exception 'PACR-004 part 3b: % active KPIs still on parked personas', v_kpi; end if;
  if v_rem > 0 then raise exception 'PACR-004 part 3b: % KPI remediations still name a non-active employee', v_rem; end if;
  raise notice 'PACR-004 part 3b proof: role ids resolve, supply scope %, 0 orphan seats, 0 parked KPIs, 0 orphan remediations', v_scope;
  if v_rehearsal then raise exception 'REHEARSAL OK — rolled back: role ids resolve, supply scope %, 0 orphan seats, 0 parked KPIs, 0 orphan remediations', v_scope; end if;
end $proof$;
commit;
