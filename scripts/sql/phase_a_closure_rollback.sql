-- ROLLBACK for supabase/migrations/20260815060000_phase_a_closure_corrections.sql
--
-- Restores the organisation as it stood after the first Phase A deployment and before the five
-- closure corrections. Run whole; like the forward file it is one implicit transaction and the
-- assertion at the end takes everything with it if the pre-correction shape has not come back.
--
--   node scripts/apply_sql.mjs scripts/sql/phase_a_closure_rollback.sql --apply --ddl

set lock_timeout = '5s';
set statement_timeout = '60s';

-- ---- 4. the UAE tax decision -----------------------------------------------------------------
update public.org_role set
  owned_decisions = array_remove(array_remove(array_remove(array_remove(array_remove(owned_decisions,
    'UAE VAT and corporate-tax coordination'), 'invoice tax compliance'), 'tax filing calendar'),
    'tax supporting evidence'), 'operational tax reconciliation'),
  forbidden_decisions = array_remove(array_remove(forbidden_decisions,
    'current UAE tax law interpretation'), 'a disputed or material filing position'),
  escalation_targets = array_remove(escalation_targets, 'external UAE tax professional or firm'),
  rationale = replace(rationale, ' Phase A founder decision: owns routine UAE VAT and corporate-tax coordination; complex, material, disputed or current-interpretation questions escalate to authoritative current sources, Legal/Compliance and an external UAE tax professional. No 91st role.', '')
 where role_id = 'financial_controller';
delete from public.decision_record where decided_by='founder' and problem ilike '%UAE tax role%';

-- ---- 3. the product/technology head ----------------------------------------------------------
delete from public.org_role_alias where alias = 'chief_product_technology_officer';
update public.org_agents set title = 'Chief Technology Officer' where agent_key = 'cto';
update public.org_role set
  display_name = 'Chief Technology Officer',
  rationale = replace(rationale, ' Phase A retitle: the department is Product, Engineering & AI and its head is now titled for all three. Stable key cto unchanged.', '')
 where role_id = 'cto';

-- ---- 2. the phase-specific instruments -------------------------------------------------------
drop function if exists public.fn_phase_a_deferred_items();
drop function if exists public.fn_phase_a_organization_violations();

-- ---- 1. the UX designer and the organizational step register ---------------------------------
-- The step table goes before the column, because dropping runtime_enabled while a step row still
-- points at a role is harmless but the order reads as the inverse of the forward file and should.
drop table if exists public.org_workflow_step;
alter table public.org_role drop column if exists runtime_enabled;
update public.org_role set
  responsibilities = 'Own interaction flows, usability, accessibility and interface prototypes.',
  necessity_reason = 'Own interaction flows, usability, accessibility and interface prototypes.',
  owned_decisions = array['User journey','interaction design','prototype','usability recommendation.']::text[],
  forbidden_decisions = array['Final release approval or backend architecture.']::text[],
  output_contracts = array['UX design/prototype and rationale.']::text[],
  activation_conditions = 'Product requirement or usability issue.',
  rationale = 'Phase A CREATE. Structure only: no tools, no knowledge scope, no model policy, no route, no cron.',
  updated_at = now()
 where role_id = 'product_ux_designer';

-- ---- prove the pre-correction shape is back --------------------------------------------------
do $$
declare v int;
begin
  select count(*) into v from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  if v <> 90 then raise exception 'ROLLBACK: accountable roles = %, expected 90', v; end if;
  select count(*) into v from public.org_role where status='active' and runtime_mode='knowledge_overlay';
  if v <> 86 then raise exception 'ROLLBACK: category overlays = %, expected 86', v; end if;
  if not exists (select 1 from public.org_role where role_id='cto' and display_name='Chief Technology Officer')
    then raise exception 'ROLLBACK: the product/technology head kept its new title'; end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
              where n.nspname='public' and p.proname='fn_phase_a_organization_violations')
    then raise exception 'ROLLBACK: the Phase A violation function survived'; end if;
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='org_role' and column_name='runtime_enabled')
    then raise exception 'ROLLBACK: runtime_enabled survived'; end if;
  if (select cardinality(owned_decisions) from public.org_role where role_id='product_ux_designer') <> 4
    then raise exception 'ROLLBACK: the UX designer did not return to its pre-correction definition'; end if;
  raise notice 'PHASE A CLOSURE ROLLBACK COMPLETE: pre-correction organisation restored.';
end $$;
