// Build the candidate fn_phase_d_rule_applies (step-position instead of whole-workflow for the
// PRODUCER branch) from the LIVE body, and run the applicability delta in one aborted transaction.
import { sql } from '../phase_b/lib/db.mjs';
import { writeFileSync } from 'node:fs';

const live = (await sql(`select pg_get_functiondef('public.fn_phase_d_rule_applies(text,text)'::regprocedure) def`))[0].def;

const ANCHOR = `      select min(x.step_id) into v_producer
        from public.phase_d_step_effect x
       where x.workflow_id = s.workflow_id and x.effect_object_id = v_governs;
      if (v_primary is not null and v_primary = v_governs) or v_producer is not null then
        applies := false;
        why := format('%s governs %s and %s is the workflow that produces it (%s); the rule guards its use downstream, not its creation',
                      r.rule_id, v_governs, s.workflow_id,
                      coalesce('first produced at ' || v_producer, 'primary_object ' || v_primary));
        return next; return;
      end if;`;
if (!live.includes(ANCHOR)) { console.error('ANCHOR NOT FOUND'); process.exit(1); }

const REPLACEMENT = `      select min(x.step_id) into v_producer
        from public.phase_d_step_effect x
       where x.workflow_id = s.workflow_id and x.effect_object_id = v_governs;
      select min(p.step_no) into v_prod_no
        from public.phase_d_step_effect x
        join public.phase_b_workflow_step p on p.step_id = x.step_id
       where x.workflow_id = s.workflow_id and x.effect_object_id = v_governs;
      if v_primary is not null and v_primary = v_governs then
        applies := false;
        why := format('%s governs %s and %s is the workflow whose primary object that is; the rule guards its use downstream, not its creation',
                      r.rule_id, v_governs, s.workflow_id);
        return next; return;
      end if;
      if v_prod_no is not null and s.step_no < v_prod_no then
        applies := false;
        why := format('%s governs %s, which %s does not produce until %s; %s runs before it, so the subject does not exist and cannot',
                      r.rule_id, v_governs, s.workflow_id, v_producer, p_step_id);
        return next; return;
      end if;`;

const cand = live
  .replace(ANCHOR, REPLACEMENT)
  .replace('  v_producer text;   -- K06', '  v_producer text;   -- K06\n  v_prod_no int;     -- L01')
  .replace('CREATE OR REPLACE FUNCTION public.fn_phase_d_rule_applies(', 'CREATE OR REPLACE FUNCTION public.zz_cand_rule_applies(');

writeFileSync('scripts/tmp_diag/l01_candidate.sql', cand);
console.log('candidate written, len=' + cand.length);
