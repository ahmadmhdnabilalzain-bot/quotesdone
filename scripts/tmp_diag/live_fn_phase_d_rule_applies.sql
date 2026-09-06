CREATE OR REPLACE FUNCTION public.fn_phase_d_rule_applies(p_rule_id text, p_step_id text)
 RETURNS TABLE(applies boolean, why text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.phase_b_business_rule%rowtype;
  s public.phase_b_workflow_step%rowtype;
  e public.phase_d_rule_enforcement%rowtype;
  v_in_scope boolean;
  v_governs text;
  v_primary text;
begin
  select * into r from public.phase_b_business_rule where rule_id = p_rule_id;
  if not found then
    applies := false; why := format('unknown rule %L', p_rule_id); return next; return;
  end if;
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then
    applies := false; why := format('unknown step %L', p_step_id); return next; return;
  end if;
  select * into e from public.phase_d_rule_enforcement where rule_id = p_rule_id;

  -- 1. WORKFLOW SCOPE, from the frozen registry.
  v_in_scope := (lower(r.workflow_scope) = 'all'
                 or s.workflow_id = any (string_to_array(replace(r.workflow_scope,' ',''), ';')));
  if not v_in_scope then
    applies := false;
    why := format('%s is scoped to %s and %s is in %s', r.rule_id, r.workflow_scope, p_step_id, s.workflow_id);
    return next; return;
  end if;

  -- 2. STEP-LEVEL APPLICABILITY. Scope is not applicability, and conflating the two is what made
  --    the first executor refuse an intake step for a creator/reviewer collision.
  if p_rule_id in ('BR-002','BR-030','BR-031','BR-037','BR-038') then
    if coalesce(btrim(s.independent_reviewer_role_id),'') = '' then
      applies := false;
      why := format('%s governs the independence of a named reviewer and %s names none', r.rule_id, p_step_id);
      return next; return;
    end if;
  end if;

  if p_rule_id = 'BR-003' then
    if lower(coalesce(btrim(s.founder_gate),'none')) = 'none' then
      applies := false;
      why := format('BR-003 governs founder-reserved decisions and %s declares founder_gate none', p_step_id);
      return next; return;
    end if;
  end if;

  if p_rule_id = 'BR-009' and not coalesce(s.is_closure_step,false) then
    applies := false;
    why := format('BR-009 is a closure rule and %s is not the closure step', p_step_id);
    return next; return;
  end if;

  if p_rule_id = 'BR-042' and s.step_type <> 'analysis' then
    applies := false;
    why := format('BR-042 governs analysis output and %s is a %s step', p_step_id, s.step_type);
    return next; return;
  end if;

  if p_rule_id = 'BR-040' and s.step_type <> 'measurement' then
    applies := false;
    why := format('BR-040 governs metric definition and %s is a %s step', p_step_id, s.step_type);
    return next; return;
  end if;

  if p_rule_id = 'BR-044'
     and not exists (select 1 from public.phase_b_handoff h where h.from_step_id = p_step_id) then
    applies := false;
    why := format('BR-044 governs a step that opens a handoff and %s opens none', p_step_id);
    return next; return;
  end if;

  -- D50. BR-008 governs the CONTENTS OF A HANDOFF PACKET, so it can only apply to a step that opens
  -- one. Until D47 it fell through to ENFORCED_PASS and could not fail; giving it a real predicate
  -- without giving it this applicability rule turned it into the opposite defect — it refused 29 of
  -- the 30 workflows' first steps for not carrying a packet no handoff had asked for. The condition
  -- is the same one BR-044 already uses, and it is used here for the same reason.
  if p_rule_id = 'BR-008'
     and not exists (select 1 from public.phase_b_handoff h where h.from_step_id = p_step_id) then
    applies := false;
    why := format('BR-008 governs the packet a handoff carries and %s opens no handoff', p_step_id);
    return next; return;
  end if;

  -- 3. A RULE DOES NOT GOVERN THE WORKFLOW THAT PRODUCES ITS SUBJECT.
  if e.required_context is not null and cardinality(e.required_context) > 0 then
    select st.object_id into v_governs
      from public.phase_d_fixture_stage st
     where st.contributes_ref = any(e.required_context)
     limit 1;
    if v_governs is not null then
      select w.primary_object into v_primary
        from public.phase_b_workflow w where w.workflow_id = s.workflow_id;
      if v_primary is not null and v_primary = v_governs then
        applies := false;
        why := format('%s governs %s and %s is the workflow that produces it (primary_object %s); the rule guards its use downstream, not its creation',
                      r.rule_id, v_governs, s.workflow_id, v_primary);
        return next; return;
      end if;
    end if;
  end if;

  applies := true;
  why := format('%s (%s, %s) applies to %s: in scope %s%s', r.rule_id, r.rule_type,
                coalesce(e.enforcement_kind,'UNREGISTERED'), p_step_id, r.workflow_scope,
                case when e.status = 'OUTSTANDING'
                     then ' — enforcement OUTSTANDING, pending the D2 object map' else '' end);
  return next;
end $function$
