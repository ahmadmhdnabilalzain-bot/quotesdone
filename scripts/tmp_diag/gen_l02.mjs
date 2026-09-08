// Candidate fn_phase_d_rule_applies, generated from the LIVE body.
import { sql } from '../lib/db.mjs';
import { writeFileSync } from 'node:fs';
let ra = (await sql(`select pg_get_functiondef('public.fn_phase_d_rule_applies(text,text)'::regprocedure) def`))[0].def;

const A = `  if e.required_context is not null and cardinality(e.required_context) > 0 then
    select st.object_id into v_governs
      from public.phase_d_fixture_stage st
     where st.contributes_ref = any(e.required_context)
     limit 1;
    if v_governs is not null then`;
const B = `      select w.primary_object into v_primary
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
  end if;`;
for (const [n, x] of [['A', A], ['B', B]]) if (!ra.includes(x)) { console.error('MISS ' + n); process.exit(1); }

ra = ra.replace(A, `  if e.required_context is not null and cardinality(e.required_context) > 0 then
    -- L02 (1). A CONTEXT KEY CAN NAME MORE THAN ONE OBJECT AND \`limit 1\` INVENTED AN ANSWER FOR IT.
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
    if v_subjects is not null and cardinality(v_subjects) > 0 then`);

ra = ra.replace(B, `      select w.primary_object into v_primary
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
  end if;`);

ra = ra.replace('  v_producer text;   -- K06',
  '  v_producer text;   -- K06\n  v_prod_no  int;          -- L02\n  v_subjects text[];       -- L02\n  v_needs_identity boolean; -- L02');
writeFileSync('scripts/tmp_diag/l01_rule_applies.sql', ra);
console.log('rule_applies len=' + ra.length);
