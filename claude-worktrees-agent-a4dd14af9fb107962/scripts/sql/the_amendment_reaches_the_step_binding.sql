-- THE AMENDMENT REACHES THE STEP BINDING (org audit E13).
--
-- MEASURED. PBCR-001 moved W14-S05 accountability from the relevant_category_overlay placeholder to the
-- canonical role quote_evaluation in phase_b_workflow_step, but the Phase C STEP binding still named
-- relevant_category_overlay — a value absent from org_role AND org_role_alias. It was never flagged
-- because fn_phase_c_step_owner_valid HARDCODES relevant_category_overlay as valid for W14 analysis
-- steps, and W14-S05 is the only W14 step that used the overlay.
--
-- THIS FILE:
--   1. sets phase_c_step_binding.W14-S05.accountable_role_id = quote_evaluation (following the frozen
--      phase_b_workflow_step owner the amendment already set).
--   2. removes W14 from fn_phase_c_step_owner_valid's overlay hardcode, so a category overlay on a W14
--      step is no longer silently accepted (W05/W06/W07/W10 keep it — those steps legitimately use it).
-- A CI parity assertion (org_connectivity_scenarios.test.mjs) fails on any step binding owner that is
-- neither a real role (org_role or org_role_alias) nor the frozen spec's own owner.
--
--   node scripts/apply_sql.mjs scripts/sql/the_amendment_reaches_the_step_binding.sql --apply --ddl

begin;

update public.phase_c_step_binding
   set accountable_role_id = 'quote_evaluation'
 where step_id = 'W14-S05' and accountable_role_id = 'relevant_category_overlay';

CREATE OR REPLACE FUNCTION public.fn_phase_c_step_owner_valid(p_step_id text, p_owner text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s public.phase_b_workflow_step%rowtype; v_kind text;
begin
  if public.fn_phase_c_actor_may_own(p_owner) then return true; end if;
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then return false; end if;
  -- W14 removed: W14-S05 is now the canonical role quote_evaluation (PBCR-001), so no W14 step uses a
  -- category overlay. W05/W06/W07/W10 analysis steps legitimately still do.
  if p_owner = 'relevant_category_overlay'
     and s.step_type = 'analysis'
     and s.workflow_id in ('W05','W06','W07','W10') then
    return true;
  end if;
  select kind into v_kind from public.fn_phase_c_resolve_actor(p_owner);
  return v_kind = 'overlay' and s.step_type = 'analysis'
     and s.workflow_id in ('W05','W06','W07','W10');
end $function$;

commit;
