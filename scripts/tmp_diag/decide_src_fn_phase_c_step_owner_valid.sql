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
  if p_owner = 'relevant_category_overlay'
     and s.step_type = 'analysis'
     and s.workflow_id in ('W05','W06','W07','W10','W14') then
    return true;
  end if;
  select kind into v_kind from public.fn_phase_c_resolve_actor(p_owner);
  return v_kind = 'overlay' and s.step_type = 'analysis'
     and s.workflow_id in ('W05','W06','W07','W10','W14');
end $function$
