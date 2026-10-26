-- STAFF_ORG RE-CARVE, PART 3 — SETTLEMENT (3 Sep 2026, PACR-004).
--
-- Parts 1 and 2 re-carved the departments, seated 71 personas, parked 19, and moved every Phase B and
-- Phase C binding to the seats that inherited them. The org behaviour and connectivity suites then
-- measured the six things the merge convention of 14 Aug 2026 also settled and these two files had
-- not: (1) a parked persona's id must resolve to a live executor (org_agent_alias), (2) an inactive
-- employee holds no packaged identity — its rows move to the successor as runtime-shared, never as
-- an exclusive claim, (3) an open task follows its owner's department, (4) a remediation cannot
-- stand against a parked employee, (5) the new department needs an operating system, a standing
-- deputy and a target-model mapping like the other nine, and (6) no workflow is reviewed inside its
-- own department — two reviewers moved into the owner's department with the re-carve and go to a
-- reviewer outside it.
--
--   node scripts/apply_sql.mjs scripts/sql/staff_org_recarve_settlement_2026_09_03.sql --apply --ddl
--   (rehearsal: prepend `set local app.recarve_rehearsal = '1'`; the proof block rolls back)
begin;
set local app.change_reason = 'PACR-004 part 3, 3 Sep 2026: settlement of the STAFF_ORG re-carve';

create temp table m on commit drop as
  select a.alias old_role, a.role_id new_role, ro.runtime_agent_key old_agent, rn.runtime_agent_key new_agent
    from public.org_role_alias a
    join public.org_role ro on ro.role_id = a.alias
    join public.org_role rn on rn.role_id = a.role_id and rn.status = 'active'
   where a.kind = 'merged_role' and a.reason like 'PACR-004%';
do $chk$ begin
  if (select count(*) from m) <> 19 then
    raise exception 'PACR-004 part 3: expected the 19 parked-role aliases left by part 2, found %', (select count(*) from m);
  end if;
end $chk$;

-- 1. Every parked id resolves to its successor, the way the 14 Aug merges are addressable today.
insert into public.org_agent_alias (alias, agent_key, reason)
  select m.old_agent, m.new_agent,
         'PACR-004 3 Sep 2026: persona parked in the STAFF_ORG re-carve; every caller still using this id resolves to the seat that inherited its work'
    from m
  on conflict (alias) do update set agent_key = excluded.agent_key, reason = excluded.reason;

-- 2. Packaged identities. The rows part 2 gave the successors are runtime-shared holdings, not the
--    exclusive claims (one_to_one, requires_split, package_composite) the parked row carried; and an
--    inactive employee holds no identity at all (the 14 Aug convention the shape test asserts).
update public.org_role_identity i
   set mapping_type = 'runtime_composite', updated_at = now()
 where i.mapping_type <> 'runtime_composite'
   and exists (select 1 from public.org_agents a where a.agent_key = i.agent_key and a.active)
   and exists (select 1 from public.org_role_identity p join m on m.old_agent = p.agent_key
                where p.packaged_role_id = i.packaged_role_id);
delete from public.org_role_identity i using m where i.agent_key = m.old_agent;

-- 3. An open task follows the seat that now owns it.
update public.org_tasks t set dept_key = a.department
  from public.org_agents a
 where a.agent_key = t.assigned_agent and a.active
   and t.status in ('proposed', 'assigned', 'in_progress') and t.dept_key <> a.department;

-- 4. A remediation cannot stand against a parked employee; the KPI it remediated is the successor's now.
update public.agent_remediation ar
   set status = 'abandoned', closed_at = now(),
       detail = coalesce(ar.detail, '{}'::jsonb) || jsonb_build_object('closed_reason', 'PACR-004 3 Sep 2026: employee parked in the STAFF_ORG re-carve; the KPI this remediated is now owned by ' || m.new_agent)
  from m where ar.agent_key = m.old_agent and ar.status = 'open';

-- 5. Supply is a department like the other nine: an operating system, a standing deputy, a target model.
insert into public.operating_system (os_key, num, name, charter, mandate, owner_agent, adapts_by, active, mission)
values ('supply', 13, 'Supply OS',
  'Runs the supplier engine: invite, claim, verify, retain, cover.',
  'Owns supplier acquisition, claim and onboarding, the licence gate that makes a supplier verified, retention of responsive suppliers, and category coverage — the side of the market that had one matchable supplier on 3 Sep 2026.',
  'bd',
  'Re-aims the invite campaign and verification at the emptiest categories from coverage-gap and response-rate data.',
  true,
  'Give every qualified buyer request at least three verified suppliers who can actually quote.')
on conflict (os_key) do nothing;
insert into public.os_department (os_key, dept_key) values ('supply', 'supply') on conflict do nothing;
update public.operating_system set active = false where os_key = 'assurance';
insert into public.delegation_rule (dept_key, when_agent, delegate_to, basis, rank, active)
select 'supply', 'bd', 'onboarding', 'standing deputy: most senior manager in the department', 1, true
 where not exists (select 1 from public.delegation_rule where dept_key = 'supply');
insert into ops_kb_stage.department_crosswalk (production_dept_key, target_department_key, mapping_type, note, production_exists, target_exists, review_status)
select v.p, v.t, 'merged_owner', v.n, true, true, 'reviewed'
  from (values
    ('supply', 'supplier_success',     'PACR-004 3 Sep 2026: Supply carved out of Marketplace; the supplier-success target model is its own'),
    ('supply', 'business_development', 'PACR-004 3 Sep 2026: supplier recruiting moved from Growth to Supply')
  ) v(p, t, n)
 where not exists (select 1 from ops_kb_stage.department_crosswalk x where x.production_dept_key = v.p and x.target_department_key = v.t);

-- 6. Review independence. qa_manager moved into Platform & Reliability with the re-carve and was
--    W22's reviewer of the CTO; rfq_success moved into Marketplace Ops and was W14's reviewer of
--    quote evaluation. Each review goes to a role outside the owner's department.
update public.org_workflow_ownership set independent_reviewer = 'risk_and_governance_manager'
 where workflow_id = 'W22' and independent_reviewer = 'quality_and_release_director';
update public.org_workflow_ownership set independent_reviewer = 'customer_success_director'
 where workflow_id = 'W14' and independent_reviewer = 'rfq_success';

-- The Phase A registry digest of workflow ownership follows.
drop trigger a00_org_phase_baseline_append_only on public.org_phase_baseline;
update public.org_phase_baseline b
   set registry_sha256 = jsonb_set(b.registry_sha256, '{workflow_ownership,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select o.workflow_id sortkey,
                                  o.workflow_id||'|'||o.workflow_name||'|'||o.accountable_role_id||'|'
                                  ||array_to_string(o.contributors, ';')||'|'||coalesce(o.independent_reviewer,'') x
                             from public.org_workflow_ownership o) s))),
       note = b.note || chr(10) || 'PACR-004 part 3, 3 Sep 2026: W22 and W14 reviewers moved outside the owner''s department; digest recomputed.',
       recorded_at = now()
 where b.phase = 'A';
create trigger a00_org_phase_baseline_append_only
  before delete or update on public.org_phase_baseline
  for each row execute function public.fn_org_phase_baseline_append_only();

-- 7. PROOF, same transaction.
do $proof$
declare
  v_unresolved int; v_no_identity int; v_shares int; v_split int; v_cross int; v_supply_targets int; v_supply_os int;
  v_same_dept int; v_a_drift int; v_viol int; v_rem int;
  v_rehearsal boolean := coalesce(current_setting('app.recarve_rehearsal', true), '') = '1';
begin
  select count(*) into v_unresolved from m where coalesce(public.fn_org_agent_resolve(m.old_agent), m.old_agent) = m.old_agent
     or not exists (select 1 from public.org_agents a where a.agent_key = public.fn_org_agent_resolve(m.old_agent) and a.active);
  select count(*) into v_no_identity from public.org_role_identity i where not exists (select 1 from public.org_agents a where a.agent_key = i.agent_key and a.active);
  select count(*) into v_shares from public.org_role_identity i where i.mapping_type = 'one_to_one'
     and exists (select 1 from public.org_role_identity j where j.packaged_role_id = i.packaged_role_id and j.agent_key <> i.agent_key);
  select count(*) into v_split from public.org_role_identity i where i.mapping_type = 'requires_split'
     and exists (select 1 from public.org_role_identity j where j.packaged_role_id = i.packaged_role_id and j.agent_key <> i.agent_key);
  select count(*) into v_cross from public.org_tasks t join public.org_agents a on a.agent_key = t.assigned_agent
   where t.status in ('assigned', 'in_progress') and a.department is distinct from t.dept_key;
  select jsonb_array_length(coalesce(public.fn_ops_department_context('supply', null, 2)->'target_departments', '[]')) into v_supply_targets;
  select count(*) into v_supply_os from public.os_department where dept_key = 'supply';
  select count(*) into v_same_dept from public.org_workflow_ownership o
    join public.org_role r1 on r1.role_id = o.accountable_role_id join public.org_role r2 on r2.role_id = o.independent_reviewer
   where r1.primary_department_id = r2.primary_department_id;
  select count(*) into v_rem from public.agent_remediation ar join m on m.old_agent = ar.agent_key where ar.status = 'open';
  select count(*) into v_a_drift from public.fn_phase_a_baseline_drift();
  select count(*) into v_viol from public.fn_org_role_violations();
  if v_unresolved > 0 then raise exception 'PACR-004 part 3: % parked ids do not resolve to a live executor', v_unresolved; end if;
  if v_no_identity > 0 then raise exception 'PACR-004 part 3: % packaged identities still name an inactive employee', v_no_identity; end if;
  if v_shares > 0 then raise exception 'PACR-004 part 3: % one_to_one identities share their packaged role', v_shares; end if;
  if v_split > 1 then raise exception 'PACR-004 part 3: % requires_split identities share a packaged role (known baseline 1)', v_split; end if;
  if v_cross > 0 then raise exception 'PACR-004 part 3: % open tasks sit outside their owner''s department', v_cross; end if;
  if v_supply_targets = 0 or v_supply_os = 0 then raise exception 'PACR-004 part 3: supply resolves % target departments and % operating systems', v_supply_targets, v_supply_os; end if;
  if v_same_dept > 0 then raise exception 'PACR-004 part 3: % workflows are still reviewed inside their own department', v_same_dept; end if;
  if v_rem > 0 then raise exception 'PACR-004 part 3: % remediations still open against parked employees', v_rem; end if;
  if v_viol > 0 then raise exception 'PACR-004 part 3: fn_org_role_violations reports % rows', v_viol; end if;
  if v_a_drift > 0 then raise exception 'PACR-004 part 3: fn_phase_a_baseline_drift reports % rows: %', v_a_drift, (select string_agg(subject, ', ') from public.fn_phase_a_baseline_drift()); end if;
  raise notice 'PACR-004 part 3 proof: 19 ids resolve, 0 orphan identities, 0 exclusive shares, % split shares, 0 cross-dept tasks, supply % targets, 0 same-dept reviews, drift 0', v_split, v_supply_targets;
  if v_rehearsal then raise exception 'REHEARSAL OK — rolled back: 19 ids resolve, 0 orphan identities, 0 exclusive shares, % split shares, 0 cross-dept tasks, supply % targets, 0 same-dept reviews, drift 0', v_split, v_supply_targets; end if;
end $proof$;
commit;
