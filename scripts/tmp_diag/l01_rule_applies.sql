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
  v_producer text;   -- K06
  v_prod_no  int;          -- L02
  v_subjects text[];       -- L02
  v_needs_identity boolean; -- L02
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
    -- L02 (1). A CONTEXT KEY CAN NAME MORE THAN ONE OBJECT AND `limit 1` INVENTED AN ANSWER FOR IT.
    -- terms_version and terms_hash are facts about the customer acceptance AND about the supplier
    -- acceptance. Resolving the rule's subject to whichever row came first is the "a key written in
    -- two shapes" defect, so every register that maps a context key to an object is asked and the
    -- whole set is kept.
    select array_agg(distinct o) into v_subjects from (
      select st.object_id o from public.phase_d_fixture_stage st
       where st.contributes_ref = any(e.required_context)
      union
      select k.object_id o from public.phase_d_context_key_object k
       where k.context_key = any(e.required_context)) z;
    if v_subjects is not null and cardinality(v_subjects) > 0 then
      -- K06. A WORKFLOW PRODUCES MORE THAN ITS PRIMARY OBJECT. This compared the rule's subject
      -- with phase_b_workflow.primary_object alone, so BR-018 asked W14 to already hold the
      -- quotation revision W14 exists to produce, and BR-032 asked W16 to already hold the provider
      -- event W16-S03 receives. The producing step is read from the frozen effect registry; the
      -- primary object is still reported in the reason when it is the one that matched.
      select w.primary_object into v_primary
        from public.phase_b_workflow w where w.workflow_id = s.workflow_id;
      if v_primary is not null and v_primary = any(v_subjects) then
        applies := false;
        why := format('%s governs %s and %s is the workflow whose primary object that is; the rule guards its use downstream, not its creation',
                      r.rule_id, v_primary, s.workflow_id);
        return next; return;
      end if;

      -- L02 (2). NOT A WHOLE-WORKFLOW EXEMPTION. K06 removed the rule from EVERY step of the
      -- producing workflow. K07, written the same day for gates, had already recorded why that
      -- shape is wrong and had already written the right one:
      --
      --     before the producing step  -- every gate. The subject does not exist yet and cannot.
      --     AT the producing step      -- only where the test is the PRESENCE of the subject.
      --     a MEASURED predicate       -- untouched: it exists to judge the creating step.
      --
      -- BR-025 is the rule that made the difference visible. Its scope is W04;W09, W09-S06 is the
      -- only step in the estate that produces a supplier terms acceptance, and its own frozen
      -- completion condition is "Displayed version, recorded version and document hash match" --
      -- so a whole-workflow exemption of W09 leaves nothing anywhere asking whether a SUPPLIER
      -- acceptance names its exact terms. That is a repeal, not an exemption.
      --
      -- WHICH OF THE TWO A RULE IS, IS DERIVED, NOT LISTED. A rule that requires a key which
      -- IDENTIFIES its subject is asking the step to name a record; at the step that creates that
      -- record there is nothing to name (BR-018 needs quote_revision_ref, BR-032 needs
      -- provider_event_id). A rule whose keys only DESCRIBE the subject is judging the content of
      -- what is being written and must be asked exactly there (BR-025 needs terms_version and
      -- terms_hash). The distinction is public.phase_d_context_key_object.key_role, the same column
      -- the three identity doors in fn_phase_d_step_context read; a subject reached through
      -- phase_d_fixture_stage.contributes_ref counts as identifying, because a contributed
      -- reference is a reference.
      select min(x.step_id), min(p.step_no) into v_producer, v_prod_no
        from public.phase_d_step_effect x
        join public.phase_b_workflow_step p on p.step_id = x.step_id
       where x.workflow_id = s.workflow_id and x.effect_object_id = any(v_subjects);
      if v_prod_no is not null and s.step_no <= v_prod_no then
        select coalesce(bool_or(idf), false) into v_needs_identity from (
          select true as idf from public.phase_d_fixture_stage st
           where st.contributes_ref = any(e.required_context) and st.object_id = any(v_subjects)
          union all
          select (k.key_role = 'IDENTIFIES') from public.phase_d_context_key_object k
           where k.context_key = any(e.required_context) and k.object_id = any(v_subjects)) z2;
        if s.step_no < v_prod_no or v_needs_identity then
          select x.effect_object_id into v_governs from public.phase_d_step_effect x
           where x.step_id = v_producer limit 1;
          applies := false;
          why := format('%s governs %s, which %s produces at %s; %s',
                        r.rule_id, v_governs, s.workflow_id, v_producer,
                        case when s.step_no < v_prod_no
                             then format('%s runs before it, so the subject does not exist and cannot', p_step_id)
                             else format('%s is that step and the rule requires a key that IDENTIFIES the subject, '
                                      || 'so it would be asking the step to name what the step creates', p_step_id) end);
          return next; return;
        end if;
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
