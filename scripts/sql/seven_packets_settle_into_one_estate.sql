-- SEVEN PARALLEL PACKETS SETTLE INTO ONE ESTATE (4 Sep 2026, integration).
--
-- Seven agents worked the MASTER_PLAN and STAFF_ORG packets against the one production database at
-- the same time. Each proved its own packet; four seams only show where the packets meet:
--   1. the STAFF_ORG walk parked agent_workforce_capability_director (alias -> chief_operating_officer,
--      kind merged_role) and three kernel_trigger_source rows still name the parked role -- the
--      trigger board resolves packaged aliases, not merged ones: 3 of 484 red;
--   2. the same walk moved W23 to cto and W26 to knowledge_director; three phase_d_event_reconciliation
--      rows still record the old producer (ai_director, knowledge_engineer), so the event board reads a
--      handoff to a "different owner" that is the same seat: self_loop_after_handing_the_work_on 3;
--   3. the new red_view_alerter role (STAFF_ORG seat 40) sits in no Phase B artefact: roles_unrepresented
--      1. It contributes to W29 (security incident and reliability recovery), where its alert lands;
--   5. 4xx open org_tasks carry tier=autonomous from an approval made when the authority model granted
--      it; the STAFF_ORG walk lowered several grants and cos_execute now refuses each such row as
--      tier_claim_exceeds_grant. The tier follows the grant of the day (fn_dept_authority); rows a
--      lower grant re-scopes keep their status and are executed at the tier the model allows.
--   4. three crons re-enabled by the Phase E and dead-triggers packets reach watched relations and are
--      not registered at the committed-scenario door, which therefore refuses to open (positive control
--      red): 62 gl_sync_nightly (transactions, leads), 280 department_conflict_scan_weekly, 331
--      collections_reminders_daily (leads, quotes).
-- Every statement is idempotent; the proof block raises if any seam is still open.
--
--   node scripts/apply_sql.mjs scripts/sql/seven_packets_settle_into_one_estate.sql --apply --ddl
begin;

-- 1. trigger-source rows follow the merged role.
update public.kernel_trigger_source s
   set accountable_role_id = a.role_id,
       evidence = coalesce(s.evidence, '') || ' | 4 Sep 2026: accountable role ' || s.accountable_role_id || ' parked by the STAFF_ORG walk; follows its merged_role alias to ' || a.role_id
  from public.org_role_alias a
 where a.alias = s.accountable_role_id and a.kind = 'merged_role'
   and exists (select 1 from public.org_role r where r.role_id = a.role_id and r.status = 'active')
   and not exists (select 1 from public.org_role r where r.role_id = s.accountable_role_id and r.status = 'active');

-- 2. event reconciliations name the seat that owns the step today.
update public.phase_d_event_reconciliation r
   set producer = s.accountable_role_id
  from public.phase_b_workflow_step s
 where s.step_id = substring(r.event_id from 'EV-(W[0-9]+-S[0-9]+)')
   and r.producer is distinct from s.accountable_role_id
   and exists (select 1 from public.org_role_alias a where a.alias = r.producer and a.kind = 'merged_role' and a.role_id = s.accountable_role_id);

-- 3. the alerter contributes to the incident workflow it feeds.
update public.phase_b_workflow
   set contributors = array_append(contributors, 'red_view_alerter')
 where workflow_id = 'W29' and not ('red_view_alerter' = any(coalesce(contributors, '{}')));

-- 4. the three crons are registered at the committed-scenario door with their quarantine.
insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
  (62, 'gl_sync_nightly',
   'fn_gl_sync_business reads public.transactions and public.leads to post the business ledger (gl_* tables); it writes no watched relation.',
   'Re-enabled 4 Sep 2026 (Phase E, wired into Finance & Collections). Runs nightly in its own transaction; it cannot see a committed scenario''s uncommitted ZZ DEMO fixtures, and a ZZ DEMO transaction it does see is a real committed row the scenario close removes by run id.'),
  (280, 'department_conflict_scan_weekly',
   'fn_emit_department_conflict reads department objectives and emits department.conflict through fn_emit; it writes company_event and, through the bridge, workflow rows -- no watched business relation.',
   'Re-enabled 4 Sep 2026 (dead-triggers packet). Weekly, deterministic, no model; any fixture objective it reads carries the ZZ DEMO label and the scenario close removes what the run created by run id.'),
  (331, 'collections_reminders_daily',
   'fn_collections reads public.leads and public.quotes for overdue dues and writes portal-channel reminders (no email, no dues); it writes no watched relation.',
   'Enabled 4 Sep 2026 (Phase E, wired into Finance & Collections). Daily, deterministic; ZZ DEMO leads and quotes are labelled and the scenario close removes the run''s rows by run id.')
on conflict (jobid) do update set reaches = excluded.reaches, quarantine = excluded.quarantine;

-- 5. an open task claims no more than its department is granted today.
update public.org_tasks t
   set tier = g.tier,
       detail = t.detail || ' | 4 Sep 2026: tier re-scoped from autonomous to ' || g.tier || ' -- the authority model grants ' || g.tier || ' for ' || t.dept_key || '/' || t.action_class
  from (select x.id, coalesce(nullif(public.fn_dept_authority(x.dept_key, x.action_class)->>'tier', ''), 'gated') as tier
          from public.org_tasks x
         where x.tier = 'autonomous' and x.status not in ('done','cancelled','failed')) g
 where g.id = t.id and g.tier <> 'autonomous';

do $proof$
declare v1 int; v2 int; v3 int; v4 int; v5 int; v6 int;
begin
  select count(*) into v1 from public.kernel_trigger_source s
   where not exists (select 1 from public.org_role r where r.role_id = s.accountable_role_id and r.status = 'active')
     and not exists (select 1 from public.org_role_alias a where a.alias = s.accountable_role_id);
  select actual::int into v2 from public.fn_phase_d_event_state() where check_name = 'self_loop_after_handing_the_work_on';
  select actual::int into v3 from public.fn_phase_b_invariants() where check_name = 'coverage.roles_unrepresented';
  select count(*) into v4 from public.fn_phase_d_committed_scenario_guards() where not ok;
  select (regexp_match(actual, '^\s*(\d+)'))[1]::int into v5 from public.fn_kernel_trigger_state() where check_name = 'inventory_row_whose_accountable_role_does_not_resolve' limit 1;
  select count(*) into v6 from public.org_tasks t where t.tier = 'autonomous' and t.status not in ('done','cancelled','failed') and coalesce(nullif(public.fn_dept_authority(t.dept_key, t.action_class)->>'tier', ''), 'gated') <> 'autonomous';
  if v6 > 0 then raise exception '% open tasks still claim autonomous above their grant', v6; end if;
  if v1 > 0 or v2 > 0 or v3 > 0 or v4 > 0 or v5 > 0 then
    raise exception 'seams still open: unresolvable trigger sources %, self loops %, roles unrepresented %, door guards red %, inventory rows not resolving %', v1, v2, v3, v4, v5;
  end if;
  raise notice 'proof: trigger sources resolve, 0 self-loop handoffs, 0 roles unrepresented, scenario door guards all green';
end $proof$;
commit;
