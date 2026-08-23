-- K06 — a rule does not govern the workflow that produces its subject, whichever step produces it
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh.
--
-- public.fn_phase_d_fixture_scenario has always been able to leave out the stages that build the
-- object the workflow under test produces -- SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST -- and the
-- deliverable builders asked for it on W12 and on no other workflow, by name. A harness that seeds
-- the row the step is supposed to create is answering its own question, and a hand-listed exception
-- is how that goes unnoticed everywhere else. Asking for it on all 30 workflows moved the coverage
-- matrix from 257 of 257 steps producing their declared effect to 221 of 257, and the 36 that fell
-- are all of W08, all of W09, all of W14, all of W16 and W17-S07.
--
-- Two of the four causes are one defect and this file is that fix.
--
-- fn_phase_d_rule_applies already carries the right sentence: "A RULE DOES NOT GOVERN THE WORKFLOW
-- THAT PRODUCES ITS SUBJECT -- the rule guards its use downstream, not its creation." It applied it
-- only where the subject is the workflow's phase_b_workflow.primary_object, and a workflow produces
-- more than its primary object. Measured, with the subject derived exactly as this function already
-- derives it (public.phase_d_fixture_stage.contributes_ref against the rule's required_context):
--
--   already exempt, unchanged   BR-012/W08, BR-013/W05, BR-014/W06, BR-019/W15, BR-020/W16
--   NEWLY exempt                BR-018/W14  quotation_revision, produced by W14-S02..S09
--                               BR-032/W16  provider_event,     produced by W16-S03
--
-- Two pairs. Nothing else in the estate changes, and the population is read from
-- public.phase_d_step_effect rather than named here, so a step that starts or stops producing an
-- object moves this with it.
--
-- NOTHING IS WEAKENED. BR-018 still governs W15 and every other workflow in its scope, and BR-032
-- still governs W17 -- the workflows that USE a quotation revision and a provider event without
-- creating one. What is removed is a rule asking a workflow to already hold the thing that workflow
-- exists to produce, which is the same condition GATE-015, GATE-020, GATE-021 and GATE-026 were
-- each narrowed for in fn_phase_d_gate_applies.
--
-- ROLLBACK: scripts/sql/down/phase_d_k06_a_rule_does_not_govern_the_workflow_that_produces_its_subject_down.sql
-- re-applies the previous body of fn_phase_d_rule_applies.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_k06.mjs.
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
      -- K06. A WORKFLOW PRODUCES MORE THAN ITS PRIMARY OBJECT. This compared the rule's subject
      -- with phase_b_workflow.primary_object alone, so BR-018 asked W14 to already hold the
      -- quotation revision W14 exists to produce, and BR-032 asked W16 to already hold the provider
      -- event W16-S03 receives. The producing step is read from the frozen effect registry; the
      -- primary object is still reported in the reason when it is the one that matched.
      select w.primary_object into v_primary
        from public.phase_b_workflow w where w.workflow_id = s.workflow_id;
      select min(x.step_id) into v_producer
        from public.phase_d_step_effect x
       where x.workflow_id = s.workflow_id and x.effect_object_id = v_governs;
      if (v_primary is not null and v_primary = v_governs) or v_producer is not null then
        applies := false;
        why := format('%s governs %s and %s is the workflow that produces it (%s); the rule guards its use downstream, not its creation',
                      r.rule_id, v_governs, s.workflow_id,
                      coalesce('first produced at ' || v_producer, 'primary_object ' || v_primary));
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
;
