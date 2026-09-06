CREATE OR REPLACE FUNCTION public.fn_kernel_reviewer_independent(p_creator text, p_reviewer text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a_pc text; b_pc text;   -- the Phase C canonical resolver
  a_or text; b_or text;   -- the org-layer alias resolver
begin
  -- An absent reviewer is not an independent reviewer. Absence is never a pass.
  if coalesce(btrim(p_reviewer), '') = '' or coalesce(btrim(p_creator), '') = '' then
    return false;
  end if;

  select role_id into a_pc from public.fn_phase_c_resolve_actor(p_creator);
  select role_id into b_pc from public.fn_phase_c_resolve_actor(p_reviewer);
  -- An identity that does not resolve is refused, not waved through. A null here used to mean
  -- "cannot tell", and "cannot tell" must not be spendable as "yes".
  if a_pc is null or b_pc is null then return false; end if;
  if a_pc = b_pc then return false; end if;

  a_or := coalesce(public.fn_org_agent_resolve(p_creator), a_pc);
  b_or := coalesce(public.fn_org_agent_resolve(p_reviewer), b_pc);
  if a_or = b_or then return false; end if;

  -- Cross-vocabulary collapse: the creator under one resolver and the reviewer under the other.
  if a_pc = b_or or a_or = b_pc then return false; end if;

  return true;
end $function$
