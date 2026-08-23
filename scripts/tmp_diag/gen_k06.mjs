// K06 — a rule does not govern the workflow that produces its subject, whichever step produces it.
import { writeFileSync } from 'node:fs';
import { liveBody, splice } from './splice.mjs';

const HEADER = `-- K06 — a rule does not govern the workflow that produces its subject, whichever step produces it
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
`;

const body = splice(await liveBody('fn_phase_d_rule_applies'), [
  [`    if v_governs is not null then
      select w.primary_object into v_primary
        from public.phase_b_workflow w where w.workflow_id = s.workflow_id;
      if v_primary is not null and v_primary = v_governs then
        applies := false;
        why := format('%s governs %s and %s is the workflow that produces it (primary_object %s); the rule guards its use downstream, not its creation',
                      r.rule_id, v_governs, s.workflow_id, v_primary);
        return next; return;
      end if;
    end if;`,
   `    if v_governs is not null then
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
    end if;`],
  [`  v_governs text;
  v_primary text;`,
   `  v_governs text;
  v_primary text;
  v_producer text;   -- K06`],
]);

writeFileSync('scripts/sql/phase_d_k06_a_rule_does_not_govern_the_workflow_that_produces_its_subject.sql',
  HEADER + body + ';\n');
console.log('written');
