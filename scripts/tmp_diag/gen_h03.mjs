// H03 generator: fn_phase_d_step_context — reviewer_role_id for a step that is not itself a review
// is the reviewer of the review this run actually recorded.
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- H03 — a gate about the review that happened, asked at a step that did not do the reviewing
--
-- GATE-021 (marketing artifact approval, W03;W20) and GATE-026 (knowledge validation, W26) declare
-- reviewer_role_id among their evidence keys, and G03 narrowed both to apply from the workflow's
-- first review step to its last. Measured 23 Aug 2026: every step AFTER the review step --
-- W03-S07..S09, W20-S05..S08, W26-S06..S09 -- and the review steps themselves where the binding
-- names no reviewer -- W03-S06, W20-S04, W26-S05 -- refused with
--
--     gate GATE-021 (Marketing artifact approval) requires [reviewer_role_id] and the call names
--     none of it
--
-- because this resolver answered reviewer_role_id from exactly two places: the review recorded on
-- THIS step run, and the reviewer the binding declares for THIS step. A publish step reviews
-- nothing and declares nobody, so for it the key was unresolvable by construction -- while the
-- question the gate asks, "did an independent reviewer pass this artifact", is about the review the
-- run recorded one or more steps earlier.
--
-- The third source is therefore the most recent review fn_kernel_review_decide recorded on an
-- EARLIER step run of the SAME run, read from the same phase_c_task stamp F34 reads, and only for a
-- step that is not itself a review: handler class not REVIEW_HANDLER and no independent reviewer
-- declared in the frozen row. A review step still resolves from its own review or refuses; a gate at
-- a later step is handed the reviewer who actually reviewed, and fn_kernel_reviewer_independent
-- still judges that reviewer against the later step's own actor. Where the run recorded no review
-- the key stays unresolved and the gate refuses, which is the gate working.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_step_context (phase_d_g18 is the last file
-- that defines it). No DDL.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_step_context'`);
let def = r[0].def;
const once = (anchor, label) => { const n = def.split(anchor).length - 1; if (n !== 1) throw new Error(`${label}: anchor matched ${n} times`); };

const a1 = `      else
        v_val := to_jsonb(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''));
        v_src := 'phase_d_handler_binding.independent_reviewer_role_id, declared not chosen';
      end if;`;
once(a1, 'A1');
def = def.replace(a1, `      else
        v_val := to_jsonb(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''));
        v_src := 'phase_d_handler_binding.independent_reviewer_role_id, declared not chosen';
      end if;
      -- H03. A STEP THAT IS NOT A REVIEW IS ASKED ABOUT THE REVIEW THE RUN RECORDED. GATE-021 and
      -- GATE-026 apply from the first review step to the last step; at a publish step the reviewer
      -- is whoever reviewed earlier in this run. Read from the same task stamp, on an earlier step
      -- run of the same run, only where this step reviews nothing itself.
      if (v_val is null or v_val = 'null'::jsonb)
         and b.handler_class is distinct from 'REVIEW_HANDLER'
         and coalesce(btrim((select s3.independent_reviewer_role_id
                              from public.phase_b_workflow_step s3 where s3.step_id = sr.step_id)),'') = '' then
        select to_jsonb(nullif(btrim(coalesce(t2.reviewer_role_id,'')),'')) into v_val
          from public.phase_c_task t2
          join public.phase_c_workflow_step_run sr2
            on sr2.run_id = t2.run_id and sr2.step_id = t2.step_id
         where t2.run_id = sr.run_id
           and sr2.step_run_id < p_step_run_id
           and coalesce(btrim(t2.reviewer_role_id),'') <> ''
         order by sr2.step_run_id desc, t2.task_id desc
         limit 1;
        if v_val is not null then
          v_src := 'phase_c_task.reviewer_role_id of the most recent review fn_kernel_review_decide '
                || 'recorded on an earlier step run of this same run -- this step reviews nothing '
                || 'itself, and the gate asks about the review that happened';
        end if;
      end if;`);

writeFileSync('scripts/sql/phase_d_h03_the_gate_asked_a_publish_step_who_reviewed.sql', HEAD + '\n' + def + '\n');
console.log('H03 written');
