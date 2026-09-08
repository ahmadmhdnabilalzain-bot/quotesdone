// L01 candidate, all parts, generated from the LIVE bodies.
import { sql } from '../lib/db.mjs';
import { writeFileSync } from 'node:fs';
const get = async sig => (await sql(`select pg_get_functiondef('${sig}'::regprocedure) def`))[0].def;

// ---- part 3: fn_phase_d_rule_applies -----------------------------------------------------------
let ra = await get('public.fn_phase_d_rule_applies(text,text)');
const A3 = `  if e.required_context is not null and cardinality(e.required_context) > 0 then
    select st.object_id into v_governs
      from public.phase_d_fixture_stage st
     where st.contributes_ref = any(e.required_context)
     limit 1;
    if v_governs is not null then`;
if (!ra.includes(A3)) { console.error('A3 MISS'); process.exit(1); }
const R3 = `  if e.required_context is not null and cardinality(e.required_context) > 0 then
    -- L01. A CONTEXT KEY CAN NAME MORE THAN ONE OBJECT, AND \`limit 1\` INVENTED AN ANSWER FOR IT.
    -- terms_version and terms_hash name the customer acceptance AND the supplier acceptance;
    -- acceptance_ref names either. Resolving to the first match is the "a key written in two
    -- shapes" defect, so every register that maps a context key to an object is asked and the
    -- whole set is kept.
    select array_agg(distinct o) into v_subjects from (
      select st.object_id o from public.phase_d_fixture_stage st
       where st.contributes_ref = any(e.required_context)
      union
      select k.object_id o from public.phase_d_context_key_object k
       where k.context_key = any(e.required_context)) z;
    if v_subjects is not null and cardinality(v_subjects) > 0 then`;
ra = ra.replace(A3, R3);

const A3b = `      select w.primary_object into v_primary
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
if (!ra.includes(A3b)) { console.error('A3b MISS'); process.exit(1); }
const R3b = `      select w.primary_object into v_primary
        from public.phase_b_workflow w where w.workflow_id = s.workflow_id;
      if v_primary is not null and v_primary = any(v_subjects) then
        applies := false;
        why := format('%s governs %s and %s is the workflow whose primary object that is; the rule guards its use downstream, not its creation',
                      r.rule_id, v_primary, s.workflow_id);
        return next; return;
      end if;
      -- L01. NOT A WHOLE-WORKFLOW EXEMPTION. K06 removed the rule from every step of the producing
      -- workflow, and K07 -- written the same day, for gates -- had already recorded why that shape
      -- is wrong: "before the producing step -- every gate. The subject does not exist yet and
      -- cannot" and "a rule that exists precisely to judge the creating step would be left
      -- governing nothing". BR-025 is that rule: its scope is W04;W09 and W09-S06 is the only step
      -- in the estate that produces a supplier terms acceptance, so a whole-workflow exemption
      -- would leave a hard rule governing 7 steps instead of 16 and never judging the acceptance it
      -- exists to judge. The rule is silent before the producing step and governs from it onward.
      select min(x.step_id), min(p.step_no) into v_producer, v_prod_no
        from public.phase_d_step_effect x
        join public.phase_b_workflow_step p on p.step_id = x.step_id
       where x.workflow_id = s.workflow_id and x.effect_object_id = any(v_subjects);
      if v_prod_no is not null and s.step_no < v_prod_no then
        select x.effect_object_id into v_governs from public.phase_d_step_effect x
         where x.step_id = v_producer limit 1;
        applies := false;
        why := format('%s governs %s, which %s does not produce until %s; %s runs before it, so the subject does not exist and cannot',
                      r.rule_id, v_governs, s.workflow_id, v_producer, p_step_id);
        return next; return;
      end if;
    end if;
  end if;`;
ra = ra.replace(A3b, R3b);
ra = ra.replace('  v_producer text;   -- K06', '  v_producer text;   -- K06\n  v_prod_no  int;      -- L01\n  v_subjects text[];   -- L01');
writeFileSync('scripts/tmp_diag/l01_rule_applies.sql', ra);

// ---- part 4: fn_phase_d_step_context ----------------------------------------------------------
let sc = await get('public.fn_phase_d_step_context(bigint)');
const A4 = `        v_val_txt := null;
      end if;

    elsif v_k = 'source_ref' then`;
if (!sc.includes(A4)) { console.error('A4 MISS'); process.exit(1); }
const R4 = `        v_val_txt := null;
      end if;
      -- L01. AND AT THE STEP THAT RECORDS THE ACCEPTANCE THERE IS NOTHING TO FIND YET.
      -- W09-S06 is the only step in the estate whose declared effect object is a terms acceptance.
      -- Asked to withhold the object the workflow under test produces -- which is what a harness
      -- that does not answer its own question must do -- no acceptance record exists at S06, both
      -- keys fell to the catalogue door, and BR-025 refused with "matches 0 row(s) in
      -- public.legal_documents" for fixture PDF-3104/PDF-3105: a version string and a digest over a
      -- fixture terms body that is not a published document and never can be one.
      -- An acceptance step accepts THE CURRENTLY DISPLAYED DOCUMENT. Which document that is, for
      -- which acceptance object, is registered once in public.phase_d_acceptance_document and read
      -- from public.legal_documents here -- the same source BR-025 judges against, so the rule can
      -- still fail: a run whose step produces no registered acceptance resolves nothing here.
      if coalesce(btrim(coalesce(v_val #>> '{}','')),'') = '' then
        select case when v_k = 'terms_version' then d.version
                    else encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex') end
          into v_val_txt
          from public.phase_d_step_effect x
          join public.phase_d_acceptance_document a on a.object_id = x.effect_object_id
          join public.legal_documents d on d.slug = a.document_slug
         where x.step_id = sr.step_id
         order by d.version desc limit 1;
        if coalesce(btrim(v_val_txt),'') <> '' then
          v_val := to_jsonb(v_val_txt);
          v_src := 'public.legal_documents — the currently published document this step''s own '
                || 'acceptance object accepts, per public.phase_d_acceptance_document';
        end if;
        v_val_txt := null;
      end if;

    elsif v_k = 'source_ref' then`;
sc = sc.replace(A4, R4);
writeFileSync('scripts/tmp_diag/l01_step_context.sql', sc);
console.log('rule_applies len=' + ra.length + '  step_context len=' + sc.length);
