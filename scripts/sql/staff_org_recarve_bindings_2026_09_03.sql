-- STAFF_ORG RE-CARVE, PART 2 — THE BINDINGS FOLLOW THE SEATS (3 Sep 2026, PACR-004).
--
-- Part 1 (staff_org_recarve_2026_09_03.sql) re-carved the departments, seated 56 personas, parked 34
-- and moved their live accountability in the org layer: components, org-level workflow steps,
-- subscriptions, ownership, managers, aliases. The kernel boards then measured what part 1 could not
-- see from the org layer alone — the Phase B structure and the Phase C bindings still named the
-- parked roles: 54 Phase B steps and their 54 bindings, 81 handoffs, 10 workflows, 18 exceptions, 47
-- events, 47 event bindings, 51 overlay bindings, 40 reporting-authority rows, 14 role bindings, 18
-- Phase C tasks, 131 open org tasks assigned to parked personas, and 21 packaged knowledge roles held
-- only by parked personas (26–27 runtime-eligible knowledge records each, unreachable through the
-- role layer). This file moves every one of them to the seat that inherited the function, using the
-- same map part 1 recorded in org_role_alias (kind merged_role, reason PACR-004), so the two files
-- cannot disagree about who inherited what.
--
-- FIFTEEN PARKS ARE REVERSED HERE, by a rule rather than a list. A Phase B handoff joins two parties
-- (phase_b_handoff_two_parties refuses a handoff from a role to itself), and 22 handoffs in W01, W02,
-- W07, W21–W28 and W30 join a step owned by a parked persona to a step owned by the seat that
-- inherited it. The founder's approved workflows treat those personas as distinct parties, so the
-- rule below walks the handoffs and keeps every such persona seated, in its successor's department,
-- reporting to its successor. What part 1 moved and can be identified comes back to them (their
-- event-subscription components, their subscriptions, their org-level step ownership, all restored
-- from the Phase B record, which part 1 never touched); the rest stays with the successor, where it is
-- owned by an active seat. Net after this file: 71 seated, 19 parked. Reaching the plan's ~48 means
-- merging those 22 handoffs — a redesign of the founder's workflows, not a roster decision.
--
-- Reviewer independence survives the move exactly as in part 1: where a successor would review its
-- own work the review goes one level up the reporting graph, or to the founder at the top.
-- Phase B department tokens (marketplace_supplier_network, growth_revenue, ...) are the package's
-- vocabulary and are left as written; the live department of every role is in org_role.
--
-- The Phase B baseline digests are recomputed in place (append-only trigger dropped and recreated in
-- the same transaction, the PACR-002/003 pattern) so fn_phase_b_baseline_drift() reports the state
-- the founder ordered on 2 Sep 2026 — no freeze, no ceremony — rather than the parked names.
--
--   node scripts/apply_sql.mjs scripts/sql/staff_org_recarve_bindings_2026_09_03.sql --apply --ddl
--   (rehearsal: prepend `set local app.recarve_rehearsal = '1'`; the proof block rolls back)
begin;
set local app.phase_b_change_reason = 'PACR-004 part 2, 3 Sep 2026: Phase B/C bindings follow the STAFF_ORG re-carve seats';
set local app.change_reason = 'PACR-004 part 2, 3 Sep 2026: bindings follow the STAFF_ORG re-carve seats';
-- phase_c_task is kernel-owned: a maintenance write needs a stated reason AND the table owner (K37).
set local kernel.maintenance_reason = 'PACR-004 part 2, 3 Sep 2026: 18 Phase C tasks still name parked roles as accountable/manager/reviewer; re-pointed to the seats that inherited them';

-- =============================================================================================
-- 0. PARKS REVERSED BY THE HANDOFF RULE. Walk every Phase B handoff; while one joins two steps whose
--    owners would become the same role under the park map, keep the parked party (the sender first)
--    seated. The Phase B tables still carry the pre-re-carve owners, so the rule reads the record,
--    not a list typed here; the count is asserted so a change in the record is noticed.
-- =============================================================================================
create temp table u (old_role text primary key, new_role text, old_agent text, new_agent text) on commit drop;
do $u$
declare rec record; v_found boolean := true;
begin
  while v_found loop
    v_found := false;
    for rec in
      with m as (select a.alias old_role, a.role_id new_role from public.org_role_alias a
                  where a.kind = 'merged_role' and a.reason like 'PACR-004%' and a.alias not in (select old_role from u)),
           s as (select step_id, accountable_role_id r from public.phase_b_workflow_step)
      select sf.r from_role, st.r to_role, mf.new_role mf_new, mt.new_role mt_new
        from public.phase_b_handoff h
        join s sf on sf.step_id = h.from_step_id
        join s st on st.step_id = h.to_step_id
        left join m mf on mf.old_role = sf.r
        left join m mt on mt.old_role = st.r
       where coalesce(mf.new_role, sf.r) = coalesce(mt.new_role, st.r)
         and (mf.new_role is not null or mt.new_role is not null)
       order by h.handoff_id limit 1
    loop
      v_found := true;
      if rec.mf_new is not null then insert into u (old_role, new_role) values (rec.from_role, rec.mf_new) on conflict do nothing;
      else insert into u (old_role, new_role) values (rec.to_role, rec.mt_new) on conflict do nothing; end if;
    end loop;
  end loop;
  update u set old_agent = (select r.runtime_agent_key from public.org_role r where r.role_id = u.old_role),
               new_agent = (select r.runtime_agent_key from public.org_role r where r.role_id = u.new_role);
  if (select count(*) from u) <> 15 then
    raise exception 'PACR-004 part 2: the handoff rule keeps % personas seated, expected 15: %',
      (select count(*) from u), (select string_agg(old_role, ', ' order by old_role) from u);
  end if;
end $u$;

update public.org_agents a
   set active = true, available = true, unavailable_until = null, unavailable_reason = null,
       department = n.department, manager_key = u.new_agent
  from u join public.org_agents n on n.agent_key = u.new_agent
 where a.agent_key = u.old_agent;
update public.org_role r
   set status = 'active', runtime_enabled = true, updated_at = now(),
       primary_department_id = n.primary_department_id, manager_role_id = u.new_role,
       necessity_reason = nullif(regexp_replace(coalesce(r.necessity_reason, ''),
                            '( [|] )?PACR-004 3 Sep 2026: persona parked; accountability moved to [a-z_]+', ''), '')
  from u join public.org_role n on n.role_id = u.new_role
 where r.role_id = u.old_role;
delete from public.org_role_alias a using u where a.alias = u.old_role and a.kind = 'merged_role' and a.reason like 'PACR-004%';

-- What part 1 moved and can be identified comes back.
update public.phase_c_component c
   set accountable_role_id = u.old_role, department_id = n.primary_department_id
  from u join public.org_role n on n.role_id = u.new_role
 where c.component_id like 'evsub:' || u.old_agent || '@%';
update public.event_subscription e
   set agent_key = u.old_agent, reason = replace(e.reason, ' (moved from ' || u.old_agent || ', PACR-004)', '')
  from u
 where e.agent_key = u.new_agent and e.reason like '%(moved from ' || u.old_agent || ', PACR-004)%';
insert into public.event_subscription (agent_key, event_type, reason, active)
  select u.old_agent, split_part(c.component_id, '@', 2),
         'Restored 3 Sep 2026 (PACR-004 part 2): the persona keeps its seat because it hands work in a Phase B workflow', true
    from u join public.phase_c_component c on c.component_id like 'evsub:' || u.old_agent || '@%'
  on conflict (agent_key, event_type) do nothing;
update public.org_workflow_step o set accountable_role_id = s.accountable_role_id
  from public.phase_b_workflow_step s join u on u.old_role = s.accountable_role_id
 where s.workflow_id = o.workflow_id and s.step_no = o.step_no and o.accountable_role_id <> s.accountable_role_id;
-- A kept persona's responsibility is its Phase B steps. Part 1 moved its org-level rows (step
-- ownership, subscriptions, workflow membership) to the successor without a marker, so what can be
-- restored is what the Phase B record states: the org-level step mirror gets a row for every Phase B
-- step the persona owns, and the persona rejoins the employee_workflow for those workflows.
insert into public.org_workflow_step (workflow_id, step_no, step, accountable_role_id)
  select s.workflow_id, s.step_no, s.step_name, s.accountable_role_id
    from public.phase_b_workflow_step s join u on u.old_role = s.accountable_role_id
   where not exists (select 1 from public.org_workflow_step o where o.workflow_id = s.workflow_id and o.step_no = s.step_no)
  on conflict do nothing;
-- The aliases part 1 re-pointed away from these roles (their package id, their agent key, their
-- title) point back at them, so their role binding and anything addressing the old names resolve to
-- the seated role rather than to the successor.
update public.org_role_alias a set role_id = u.old_role
  from u join public.org_agents ag on ag.agent_key = u.old_agent
 where a.role_id = u.new_role
   and (a.alias = u.old_agent or a.alias = ag.title
        or a.alias in (select b.canonical_role_id from public.phase_c_role_binding b where b.runtime_agent_key = u.old_agent));

create temp table m on commit drop as
  select a.alias old_role, a.role_id new_role, ro.runtime_agent_key old_agent, rn.runtime_agent_key new_agent
    from public.org_role_alias a
    join public.org_role ro on ro.role_id = a.alias
    join public.org_role rn on rn.role_id = a.role_id and rn.status = 'active'
   where a.kind = 'merged_role' and a.reason like 'PACR-004%';
do $chk$ begin
  if (select count(*) from m) <> 19 then
    raise exception 'PACR-004 part 2: expected 19 parked-role aliases (34 from part 1 minus the 15 the handoff rule keeps seated), found %', (select count(*) from m);
  end if;
end $chk$;

-- =============================================================================================
-- 1. PHASE B STRUCTURE. Owners, reviewers, contributors, handoff parties, exception owners,
--    event consumers, business-object owners.
-- =============================================================================================
update public.phase_b_workflow w set accountable_role_id = m.new_role from m where w.accountable_role_id = m.old_role;
update public.phase_b_workflow w
   set independent_reviewer_role_id = case when m.new_role <> w.accountable_role_id then m.new_role
        else coalesce((select r.manager_role_id from public.org_role r where r.role_id = w.accountable_role_id and r.manager_role_id <> w.accountable_role_id), 'founder') end
  from m where w.independent_reviewer_role_id = m.old_role;

update public.phase_b_workflow_step s set accountable_role_id = m.new_role
  from m where s.accountable_role_id = m.old_role and s.actor_kind = 'canonical_role';
update public.phase_b_workflow_step s
   set independent_reviewer_role_id = case when m.new_role <> s.accountable_role_id then m.new_role
        else coalesce((select r.manager_role_id from public.org_role r where r.role_id = s.accountable_role_id and r.manager_role_id <> s.accountable_role_id), 'founder') end
  from m where s.independent_reviewer_role_id = m.old_role;
update public.phase_b_workflow_step s
   set contributors = (select array_agg(coalesce(m2.new_role, u.c) order by u.ord)
                         from unnest(s.contributors) with ordinality u(c, ord) left join m m2 on m2.old_role = u.c)
 where exists (select 1 from unnest(s.contributors) c join m on m.old_role = c);

-- A handoff names the owners of the two steps it joins; the guard on the table checks exactly that.
update public.phase_b_handoff h
   set sending_role_id = s.accountable_role_id, receiving_role_id = t.accountable_role_id
  from public.phase_b_workflow_step s, public.phase_b_workflow_step t
 where s.step_id = h.from_step_id and t.step_id = h.to_step_id
   and (h.sending_role_id <> s.accountable_role_id or h.receiving_role_id <> t.accountable_role_id);
update public.phase_b_handoff h set return_owner_role_id = m.new_role from m where h.return_owner_role_id = m.old_role;

update public.phase_b_exception e set detection_owner_role_id = m.new_role from m where e.detection_owner_role_id = m.old_role;
update public.phase_b_exception e set escalation_owner_role_id = m.new_role from m where e.escalation_owner_role_id = m.old_role;
update public.phase_b_event e set primary_consumer_role_id = m.new_role from m where e.primary_consumer_role_id = m.old_role;
update public.phase_b_business_object o set accountable_role_id = m.new_role from m where o.accountable_role_id = m.old_role;

-- =============================================================================================
-- 2. PHASE C BINDINGS mirror the structure they bind.
-- =============================================================================================
update public.phase_c_step_binding b
   set accountable_role_id = s.accountable_role_id, independent_reviewer_role_id = coalesce(s.independent_reviewer_role_id, '')
  from public.phase_b_workflow_step s
 where s.step_id = b.step_id
   and (b.accountable_role_id is distinct from s.accountable_role_id
        or nullif(b.independent_reviewer_role_id, '') is distinct from s.independent_reviewer_role_id);
update public.phase_c_handoff_binding b
   set sending_role_id = h.sending_role_id, receiving_role_id = h.receiving_role_id
  from public.phase_b_handoff h
 where h.handoff_id = b.handoff_id
   and (b.sending_role_id is distinct from h.sending_role_id or b.receiving_role_id is distinct from h.receiving_role_id);

update public.phase_c_task t set accountable_role_id = m.new_role from m where t.accountable_role_id = m.old_role;
update public.phase_c_task t set manager_role_id = m.new_role from m where t.manager_role_id = m.old_role;
update public.phase_c_task t set reviewer_role_id = m.new_role from m where t.reviewer_role_id = m.old_role;
update public.phase_c_task t set blocker_owner_role_id = m.new_role from m where t.blocker_owner_role_id = m.old_role;

-- Role bindings are keyed by the package's role ids (account_manager, boq_specification_analyst, ...),
-- one per persona, so the persona is the join: a parked persona's binding is retired.
update public.phase_c_role_binding b
   set connection_status = 'RETIRED',
       gap = 'PACR-004 3 Sep 2026: persona parked in the STAFF_ORG re-carve; accountability moved to ' || m.new_role
  from m where b.runtime_agent_key = m.old_agent;
update public.phase_c_role_binding b set department_id = r.primary_department_id
  from public.org_role r
 where r.role_id = b.canonical_role_id and r.status = 'active' and b.department_id is distinct from r.primary_department_id;

delete from public.phase_c_reporting_authority ra using m where ra.canonical_role_id = m.old_role;
update public.phase_c_reporting_authority ra set manager_role_id = m.new_role from m where ra.manager_role_id = m.old_role;
update public.phase_c_reporting_authority ra set department_head_role_id = m.new_role from m where ra.department_head_role_id = m.old_role;
update public.phase_c_reporting_authority ra set live_role_id = m.new_role from m where ra.live_role_id = m.old_role;
update public.phase_c_reporting_authority ra
   set department_id = r.primary_department_id,
       manager_role_id = coalesce(r.manager_role_id, 'founder'),
       department_head_role_id = (select h.role_id from public.org_departments d
                                    join public.org_role h on h.runtime_agent_key = d.lead_agent and h.status = 'active'
                                   where d.dept_key = r.primary_department_id order by h.role_id limit 1)
  from public.org_role r
 where r.role_id = ra.canonical_role_id and r.status = 'active'
   and ra.department_id in (select dept_key from public.org_departments)
   and (ra.department_id is distinct from r.primary_department_id or ra.manager_role_id is distinct from coalesce(r.manager_role_id, 'founder'));

update public.phase_c_system_actor x set accountable_role_id = m.new_role from m where x.accountable_role_id = m.old_role;
update public.phase_c_action_class x set accountable_role_id = m.new_role from m where x.accountable_role_id = m.old_role;
update public.phase_c_event_binding x set primary_consumer_role_id = m.new_role from m where x.primary_consumer_role_id = m.old_role;
update public.phase_c_overlay_binding x set broad_domain_escalation_role_id = m.new_role from m where x.broad_domain_escalation_role_id = m.old_role;
update public.phase_c_overlay_binding x set invocation_role_id = m.new_role from m where x.invocation_role_id = m.old_role;
update public.phase_c_overlay_binding x set live_role_id = m.new_role from m where x.live_role_id = m.old_role;
update public.phase_c_overlay_binding x set result_returns_to_role_id = m.new_role from m where x.result_returns_to_role_id = m.old_role;
update public.phase_c_command_intent x set command_owner_role_id = m.new_role from m where x.command_owner_role_id = m.old_role;
update public.phase_c_command_intent x set default_accountable_role_id = m.new_role from m where x.default_accountable_role_id = m.old_role;
update public.phase_c_command_rule x set primary_role_id = m.new_role from m where x.primary_role_id = m.old_role;
-- child_role_ids is a "; "-separated list; one rule can name several parked roles, so the list is
-- rebuilt token by token rather than updated once per match (UPDATE ... FROM applies one match per row).
update public.phase_c_command_rule x
   set child_role_ids = (select string_agg(coalesce(m2.new_role, btrim(t.tok)), '; ' order by t.ord)
                           from regexp_split_to_table(x.child_role_ids, ';') with ordinality t(tok, ord)
                           left join m m2 on m2.old_role = btrim(t.tok))
 where exists (select 1 from regexp_split_to_table(x.child_role_ids, ';') t(tok) join m on m.old_role = btrim(t.tok));
update public.phase_c_handoff_run x set sending_role_id = m.new_role from m where x.sending_role_id = m.old_role and x.status not in ('accepted', 'closed', 'rejected');
update public.phase_c_handoff_run x set receiving_role_id = m.new_role from m where x.receiving_role_id = m.old_role and x.status not in ('accepted', 'closed', 'rejected');
update public.phase_c_handoff_run x set return_owner_role_id = m.new_role from m where x.return_owner_role_id = m.old_role and x.status not in ('accepted', 'closed', 'rejected');
update public.phase_c_handoff_run x set accountable_until_accept_role_id = m.new_role from m where x.accountable_until_accept_role_id = m.old_role and x.status not in ('accepted', 'closed', 'rejected');

-- =============================================================================================
-- 3. OPEN WORK and KNOWLEDGE. Open tasks on a parked persona go to its successor; the packaged
--    knowledge roles a parked persona held alone are now also held by the successor, so their
--    runtime-eligible knowledge is reachable through the role layer again.
-- =============================================================================================
update public.org_tasks t set assigned_agent = m.new_agent
  from m where t.assigned_agent = m.old_agent and t.status in ('proposed', 'assigned', 'in_progress');

-- Producer knowledge roles go to the successor. Reviewer-auditor roles do NOT: a seat that produces
-- in a domain must not also audit it (fn_role_identity_isolation_guard refuses exactly that), so the
-- reviewer-auditor roles a parked persona held alone go one level up, to the successor's manager.
insert into public.org_role_identity (agent_key, packaged_role_id, packaged_department, archetype, mapping_type, readiness, package_version)
  select distinct on (m.new_agent, i.packaged_role_id)
         m.new_agent, i.packaged_role_id, i.packaged_department, i.archetype, i.mapping_type, i.readiness, i.package_version
    from public.org_role_identity i join m on m.old_agent = i.agent_key
   where i.archetype <> 'reviewer-auditor'
     and not exists (select 1 from public.org_role_identity x join public.org_agents a on a.agent_key = x.agent_key and a.active
                      where x.packaged_role_id = i.packaged_role_id)
     -- never make the successor both producer and reviewer of one domain
     and not exists (select 1 from public.org_role_identity h where h.agent_key = m.new_agent
                      and h.packaged_department = i.packaged_department and h.archetype = 'reviewer-auditor')
   order by m.new_agent, i.packaged_role_id, i.updated_at desc
  on conflict (agent_key, packaged_role_id) do nothing;
insert into public.org_role_identity (agent_key, packaged_role_id, packaged_department, archetype, mapping_type, readiness, package_version)
  select distinct on (g.manager_key, i.packaged_role_id)
         g.manager_key, i.packaged_role_id, i.packaged_department, i.archetype, i.mapping_type, i.readiness, i.package_version
    from public.org_role_identity i
    join m on m.old_agent = i.agent_key
    join public.org_agents g on g.agent_key = m.new_agent and g.manager_key is not null
   where i.archetype = 'reviewer-auditor'
     and not exists (select 1 from public.org_role_identity x join public.org_agents a on a.agent_key = x.agent_key and a.active
                      where x.packaged_role_id = i.packaged_role_id)
     and not exists (select 1 from public.org_role_identity h where h.agent_key = g.manager_key
                      and h.packaged_department = i.packaged_department and h.archetype <> 'reviewer-auditor')
   order by g.manager_key, i.packaged_role_id, i.updated_at desc
  on conflict (agent_key, packaged_role_id) do nothing;

-- =============================================================================================
-- 4. THE PHASE B BASELINE RECORD, digests recomputed in place.
-- =============================================================================================
drop trigger a00_org_phase_baseline_append_only on public.org_phase_baseline;
update public.org_phase_baseline b
   set registry_sha256 = jsonb_set(b.registry_sha256, '{structure}',
         (select jsonb_object_agg(d.subject, coalesce(b.registry_sha256->'structure'->d.subject, '{}'::jsonb) || jsonb_build_object('database', d.sha256))
            from public.fn_phase_b_structure_digest() d)),
       note = b.note || chr(10) || chr(10) || 'PACR-004 part 2, 3 Sep 2026: the STAFF_ORG re-carve moved 34 parked roles'' ownership, review, '
              'contributor, handoff, exception and event-consumer entries to the seats that inherited them; '
              'no workflow, step, handoff, gate, rule, state or boundary was added or removed; digests recomputed to the values now held.',
       recorded_at = now()
 where b.phase = 'B';
-- Phase A again: one persona and one role changed state in section 0, so the counts and digests
-- recorded by part 1 are recomputed to the values now held (same formulas as fn_phase_a_baseline_drift).
update public.org_phase_baseline b
   set counts = b.counts || jsonb_build_object(
         'canonical_roles', (select count(*) from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay'),
         'retired_roles',   (select count(*) from public.org_role where status='retired'),
         'phase_a_violations', (select count(*) from public.fn_phase_a_organization_violations())),
       registry_sha256 = jsonb_set(b.registry_sha256, '{reporting_graph,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select r.role_id sortkey, r.role_id||'|'||coalesce(r.manager_role_id,'founder')||'|'||r.primary_department_id x
                             from public.org_role r where r.status='active' and r.runtime_mode <> 'knowledge_overlay') s))),
       organization_sha256 = (
         with
         d as (select string_agg(dept_key||'|'||name||'|'||active::text||'|'||coalesce(lead_agent,''), chr(10) order by dept_key) x from public.org_departments),
         r as (select string_agg(role_id||'|'||display_name||'|'||primary_department_id||'|'||coalesce(manager_role_id,'')
                 ||'|'||runtime_mode||'|'||coalesce(runtime_agent_key,'')||'|'||status||'|'||coalesce(evaluation_suite,'')
                 ||'|'||coalesce(array_length(owned_decisions,1),0)::text||'|'||coalesce(array_length(forbidden_decisions,1),0)::text,
                 chr(10) order by role_id) x from public.org_role),
         c as (select string_agg(category_key, chr(10) order by category_key) x from public.org_category_identity),
         w as (select string_agg(workflow_key||'|'||step_no::text||'|'||step||'|'||coalesce(actor_role,''), chr(10) order by workflow_key, step_no) x from public.workflow_step),
         f as (select string_agg(decision_key, chr(10) order by decision_key) x from public.founder_reserved_decision),
         a as (select string_agg(agent_key||'|'||department||'|'||active::text||'|'||coalesce(manager_key,''), chr(10) order by agent_key) x from public.org_agents)
         select encode(sha256(convert_to(
           'departments'||chr(10)||d.x||chr(10)||'--'||chr(10)||
           'roles'||chr(10)||r.x||chr(10)||'--'||chr(10)||
           'categories'||chr(10)||c.x||chr(10)||'--'||chr(10)||
           'workflow_steps'||chr(10)||w.x||chr(10)||'--'||chr(10)||
           'reserved'||chr(10)||f.x||chr(10)||'--'||chr(10)||
           'agents'||chr(10)||a.x, 'UTF8')), 'hex')
         from d, r, c, w, f, a),
       note = b.note || chr(10) || 'PACR-004 part 2, 3 Sep 2026: fifteen personas kept seated by the handoff rule (22 handoffs in W01, W02, W07, W21-W28, W30 join them to their successors); 71 seated, 19 parked; digests recomputed.',
       recorded_at = now()
 where b.phase = 'A';
create trigger a00_org_phase_baseline_append_only
  before delete or update on public.org_phase_baseline
  for each row execute function public.fn_org_phase_baseline_append_only();

-- =============================================================================================
-- 5. PROOF, same transaction.
-- =============================================================================================
do $proof$
declare
  v_b_drift int; v_a_drift int; v_a_viol int; v_pb_left int; v_pc_left int; v_pc_where text; v_tasks int; v_role_viol int; v_bad text;
  v_rehearsal boolean := coalesce(current_setting('app.recarve_rehearsal', true), '') = '1';
begin
  select count(*) into v_b_drift from public.fn_phase_b_baseline_drift();
  select count(*) into v_a_drift from public.fn_phase_a_baseline_drift();
  select count(*) into v_a_viol from public.fn_phase_a_organization_violations();
  select count(*) into v_pb_left from (
    select 1 from public.phase_b_workflow_step s join m on m.old_role in (s.accountable_role_id, s.independent_reviewer_role_id)
    union all select 1 from public.phase_b_workflow w join m on m.old_role in (w.accountable_role_id, w.independent_reviewer_role_id)
    union all select 1 from public.phase_b_handoff h join m on m.old_role in (h.sending_role_id, h.receiving_role_id, h.return_owner_role_id)
    union all select 1 from public.phase_b_exception e join m on m.old_role in (e.detection_owner_role_id, e.escalation_owner_role_id)
    union all select 1 from public.phase_b_event e join m on m.old_role = e.primary_consumer_role_id
    union all select 1 from public.phase_b_business_object o join m on m.old_role = o.accountable_role_id) z;
  select count(*), coalesce(string_agg(distinct z.t, ','), '') into v_pc_left, v_pc_where from (
    select 'step_binding' t from public.phase_c_step_binding b join m on m.old_role in (b.accountable_role_id, b.independent_reviewer_role_id)
    union all select 'handoff_binding' t from public.phase_c_handoff_binding b join m on m.old_role in (b.sending_role_id, b.receiving_role_id)
    union all select 'task' t from public.phase_c_task t join m on m.old_role in (t.accountable_role_id, t.manager_role_id, t.reviewer_role_id, t.blocker_owner_role_id)
    union all select 'role_binding' t from public.phase_c_role_binding b join m on m.old_agent = b.runtime_agent_key where b.connection_status = 'CONNECTED'
    union all select 'reporting_authority' t from public.phase_c_reporting_authority r join m on m.old_role in (r.canonical_role_id, r.manager_role_id, r.department_head_role_id, r.live_role_id)
    union all select 'event_binding' t from public.phase_c_event_binding x join m on m.old_role = x.primary_consumer_role_id
    union all select 'overlay_binding' t from public.phase_c_overlay_binding x join m on m.old_role in (x.broad_domain_escalation_role_id, x.invocation_role_id, x.live_role_id, x.result_returns_to_role_id)
    union all select 'command_intent' t from public.phase_c_command_intent x join m on m.old_role in (x.command_owner_role_id, x.default_accountable_role_id)
    union all select 'command_rule' t from public.phase_c_command_rule x join m on m.old_role = x.primary_role_id or x.child_role_ids ~ ('[[:<:]]' || m.old_role || '[[:>:]]')) z;
  select count(*) into v_tasks from public.org_tasks t join m on m.old_agent = t.assigned_agent where t.status in ('proposed', 'assigned', 'in_progress');
  select count(*) into v_role_viol from public.fn_org_role_violations();
  select string_agg(check_name || '=' || actual, ', ') into v_bad
    from public.fn_phase_c_invariants()
   where not ok and check_name in ('roles_bound', 'step_owners_resolve', 'steps_owned_by_overlay_outside_declared_scope', 'command_tasks_without_canonical_owner');
  if v_pb_left > 0 then raise exception 'PACR-004 part 2: % Phase B rows still name a parked role', v_pb_left; end if;
  if v_pc_left > 0 then raise exception 'PACR-004 part 2: % Phase C binding rows still name a parked role (%)', v_pc_left, v_pc_where; end if;
  if v_tasks > 0 then raise exception 'PACR-004 part 2: % open org tasks still assigned to a parked persona', v_tasks; end if;
  if v_role_viol > 0 then raise exception 'PACR-004 part 2: fn_org_role_violations still reports % rows: %', v_role_viol,
      (select string_agg(rule || ':' || role_id, ', ') from (select rule, role_id from public.fn_org_role_violations() limit 8) z); end if;
  if v_bad is not null then raise exception 'PACR-004 part 2: kernel invariants still red: %', v_bad; end if;
  if v_a_viol > 0 then raise exception 'PACR-004 part 2: % Phase A organization violations: %', v_a_viol, (select string_agg(rule||':'||subject, ', ') from (select rule, subject from public.fn_phase_a_organization_violations() limit 8) z); end if;
  if v_a_drift > 0 then raise exception 'PACR-004 part 2: fn_phase_a_baseline_drift reports % rows: %', v_a_drift, (select string_agg(subject, ', ') from public.fn_phase_a_baseline_drift()); end if;
  if v_b_drift > 0 then raise exception 'PACR-004 part 2: fn_phase_b_baseline_drift still reports % rows: %', v_b_drift,
      (select string_agg(subject, ', ') from public.fn_phase_b_baseline_drift()); end if;
  raise notice 'PACR-004 part 2 proof: 0 Phase B rows, 0 Phase C rows, 0 open tasks on parked personas, 0 role violations, Phase B drift 0';
  if v_rehearsal then raise exception 'REHEARSAL OK — rolled back: 0 Phase B rows, 0 Phase C rows, 0 open tasks on parked personas, 0 role violations, Phase B drift 0'; end if;
end $proof$;
commit;
