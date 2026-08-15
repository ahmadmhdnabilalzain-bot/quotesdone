-- PHASE A ROLLBACK — the exact inverse of
-- supabase/migrations/20260815050000_phase_a_organization_closure.sql
--
-- Restores the organisation measured read-only at 2026-08-15 04:43 UTC, whose fingerprint is
-- recorded in docs/phase-a/phase_a_fingerprint_pre.json. Run it whole; like the forward file it
-- is one implicit transaction, and the assertion at the end takes everything with it if the
-- pre-change shape has not come back.
--
-- Nothing here resurrects a deleted row, because the forward migration deleted none: the three
-- superseded roles were RETIRED, so this is a status flip plus the removal of what was created.
--
--   node scripts/apply_sql.mjs scripts/sql/phase_a_rollback.sql --apply --ddl

-- ---- registries created by Phase A -------------------------------------------------------
drop table if exists public.org_workflow_ownership;
alter table public.org_role drop column if exists necessity_status;
alter table public.org_role drop column if exists necessity_reason;

-- ---- committee seats ---------------------------------------------------------------------
-- strategy_director held no seat before Phase A; the release director sat as an observer.
delete from public.org_role_committee where committee_key='exec_committee' and role_id='strategy_director';
update public.org_role_committee set seat='observer', note=null where committee_key='exec_committee' and role_id='quality_and_release_director';
update public.org_role_committee set seat='member' where committee_key='exec_committee' and role_id='corporate_performance_director';
update public.org_role_committee set note=null where committee_key='exec_committee';
-- The seat vocabulary goes back to four. This runs AFTER the two standing-adviser seats are
-- gone, or the constraint would be rejected against rows that still violate it.
alter table public.org_role_committee drop constraint if exists org_role_committee_seat_ck;
alter table public.org_role_committee add constraint org_role_committee_seat_ck
  check (seat = any (array['chair','member','observer','secretary']));

-- ---- change 5: tax_overlay_uae -----------------------------------------------------------
update public.org_role set status='active',
  rationale = replace(rationale, ' RETIRED by Phase A: not in the 86-entry category overlay registry and declaring none of the governance fields an overlay must have. UAE VAT/corporate-tax coordination sits with the Financial Controller per CURRENT_TO_FINAL_ROLE_CHANGES.csv.', '')
 where role_id='tax_overlay_uae';
delete from public.org_role_alias where alias='tax_overlay_uae';

-- ---- change 4: the created role ----------------------------------------------------------
delete from public.org_role where role_id='product_ux_designer';
delete from public.org_agents where agent_key='product_ux_designer';

-- ---- change 3: the independence move -----------------------------------------------------
update public.org_role set primary_department_id='product_eng', manager_role_id='ai_director',
  rationale = replace(rationale, ' Phase A MOVE to Independent Assurance: a model evaluator managed by the department that builds the models is not independent.', '')
 where role_id='model_evaluator';
update public.org_agents set department='product_eng', manager_key='ai_director' where agent_key='model_evaluator';

-- ---- change 2: the merge -----------------------------------------------------------------
update public.org_agents set active=true where agent_key='gov_relations_mgr';
-- the aliases that were repointed at the merged role go back to the two they described.
update public.org_role_alias set role_id='partnerships' where alias='partnerships_mgr';
update public.org_role_alias set role_id='government_relations' where alias in ('gov_relations_mgr','business-development-and-partnerships-operations-specialist');
delete from public.org_role_alias where alias in ('partnerships','government_relations');
update public.workflow_step set actor_role='government_relations' where workflow_key='lead_to_customer' and step_no=8;
update public.org_role set manager_role_id='business_development' where manager_role_id='strategic_partnerships_government_relations_manager';
update public.org_role_committee set role_id='partnerships' where role_id='strategic_partnerships_government_relations_manager';
delete from public.org_role where role_id='strategic_partnerships_government_relations_manager';
-- same reason: partnerships_mgr returns to the original role only once the merged one is gone.
update public.org_role set status='active',
  rationale = replace(rationale, ' RETIRED by Phase A: merged into strategic_partnerships_government_relations_manager.', '')
 where role_id in ('partnerships','government_relations');

-- ---- change 1: the rename ----------------------------------------------------------------
update public.org_role_alias set role_id='chief_performance_officer' where alias='cpo';
delete from public.org_role_alias where alias='chief_performance_officer';
update public.org_role_committee set role_id='chief_performance_officer' where role_id='corporate_performance_director';
update public.org_role set manager_role_id='chief_performance_officer' where manager_role_id='corporate_performance_director';
update public.workflow_step set actor_role='chief_performance_officer' where workflow_key='change_deployment' and step_no=9;
delete from public.org_role where role_id='corporate_performance_director';
-- only now: the partial unique index allows one ACTIVE role per runtime employee, so 'cpo'
-- cannot come back to the original row until the renamed one is gone.
update public.org_role set status='active',
  rationale = replace(rationale, ' RETIRED by Phase A: renamed to corporate_performance_director.', '')
 where role_id='chief_performance_officer';

-- ---- prove the pre-change shape is back ---------------------------------------------------
do $$
declare v int; v_txt text;
begin
  select count(*) into v from public.org_departments where active;
  if v <> 10 then raise exception 'ROLLBACK: active departments = %, expected 10', v; end if;
  select count(*) into v from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  if v <> 90 then raise exception 'ROLLBACK: accountable roles = %, expected 90', v; end if;
  select count(*) into v from public.org_role where status='active' and runtime_mode = 'knowledge_overlay';
  if v <> 87 then raise exception 'ROLLBACK: overlay roles = %, expected 87', v; end if;
  select count(*) into v from public.org_role where status='retired';
  if v <> 0 then raise exception 'ROLLBACK: % role(s) are still retired', v; end if;
  select string_agg(n::text, ',' order by n) into v_txt from (
    select count(*) n from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay'
     group by primary_department_id) s;
  if v_txt <> '4,5,7,7,7,9,11,11,12,17'
    then raise exception 'ROLLBACK: roles per department = %, expected the pre-change 4,5,7,7,7,9,11,11,12,17', v_txt; end if;
  if not exists (select 1 from public.org_role where role_id='model_evaluator' and primary_department_id='product_eng' and manager_role_id='ai_director')
    then raise exception 'ROLLBACK: the model evaluator did not return to product_eng'; end if;
  if exists (select 1 from public.org_role where role_id in ('corporate_performance_director','strategic_partnerships_government_relations_manager','product_ux_designer'))
    then raise exception 'ROLLBACK: a Phase A role survived the rollback'; end if;
  raise notice 'PHASE A ROLLBACK COMPLETE: pre-change organisation restored.';
end $$;

-- ---- follow-up migration 20260815051500 ---------------------------------------------------
-- Applied after the main Phase A file; its inverse belongs here so one rollback restores both.
update public.org_tasks set assigned_agent = 'gov_relations_mgr', updated_at = now()
 where assigned_agent = 'partnerships_mgr' and status in ('assigned','in_progress')
   and id in (select id from public.org_tasks where assigned_agent='partnerships_mgr'
              order by created_at limit 5);
update public.org_role set evaluation_suite = null where role_id = 'product_ux_designer';

delete from public.org_agent_alias where alias = 'gov_relations_mgr';

delete from public.employee_workflow where agent_key = 'product_ux_designer';
delete from public.org_role_identity where agent_key = 'product_ux_designer';
