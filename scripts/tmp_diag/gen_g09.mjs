import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- G09 — three keys that name an object and were not in the register of keys that name objects
--
-- public.phase_d_context_key_object exists so that a context key which names a business object is
-- answered from THAT object. G08 made fn_phase_d_step_context consult it for the seven object keys
-- it had been answering with the run's own row id. Three of the seven were not in it:
--
--     quote_id      -> quotation
--     document_id   -> inquiry_document
--     refund_id     -> refund_dispute_case
--
-- so for those three the new branch had nothing to consult and left them unresolved. A register
-- consulted by a resolver has to be complete or the resolver is worse than the guess it replaced;
-- this is the same shape as a deny-list that covered 22 of 46 kinds and left 24 never selected.
-- The three rows are derived from the objects the keys are named after and the derivation is stated
-- in the why column, exactly as the twelve existing rows state theirs.
--
-- AND ONE RESOLVER THAT COULD ONLY ANSWER FOR ONE WORKFLOW.
--
-- inquiry_owner is read by BR-049 alone: "Specialist and document handoffs do not transfer overall
-- inquiry accountability away from RFQ Qualification Manager unless an explicit approved workflow
-- says so." D41 correctly made the subject a ROLE rather than a customer, and resolved it from
-- phase_c_workflow_run.accountable_role_id -- this run's own role for a W05 run, and for W06 and
-- W07 the role of the W05 run that owns the same inquiry.
--
-- MEASURED: W06-S01 and W07-S01 both refused with "inquiry owner is (unstated)", because there is
-- no W05 run. The inquiry exists -- the scenario created it through the canonical service -- and no
-- workflow run has ever claimed it, so the branch resolved nothing and the rule refused a workflow
-- for an accountability that had not moved.
--
-- An inquiry no run has claimed is accountable to the role the FROZEN registry assigns to the
-- workflow whose primary object is the inquiry. That is read from public.phase_b_workflow, not
-- typed here, and it is the same value BR-049 is comparing against -- which is the point: an
-- unclaimed inquiry has not drifted.
--
-- THE RULE KEEPS ITS ABILITY TO FAIL, and that is the test of this change. The W05-run branch still
-- comes first, so an inquiry a run HAS claimed is answered by that run's actual accountable role,
-- and BR-049 still refuses when that role has drifted from the registry -- which is the drift it
-- exists to catch. Only the case of "no run has claimed it at all" changes, and there the honest
-- answer is the registry's, not silence.
--
-- Two anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const rows = `
insert into public.phase_d_context_key_object (context_key, object_id, why) values
  ('quote_id', 'quotation',
   'BR-015 and BR-018 judge the supplier quotation this key names; public.quotes is its canonical relation'),
  ('document_id', 'inquiry_document',
   'GATE-012 and the extraction steps judge the document revision this key names; public.documents is its canonical relation'),
  ('refund_id', 'refund_dispute_case',
   'GATE-020 and BR-032 judge the refund case this key names; public.refunds is its canonical relation')
on conflict (context_key) do nothing;
`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_step_context'`);
let def = r[0].def;
const splice = (anchor, repl, what) => {
  const n = def.split(anchor).length - 1;
  if (n !== 1) throw new Error(`${what}: anchor matched ${n} time(s)`);
  def = def.replace(anchor, repl);
};

splice(`      elsif v_found then
        select to_jsonb(r2.accountable_role_id) into v_val
          from public.phase_c_workflow_run r2
         where r2.workflow_id = 'W05'
           and r2.business_object_id = ('inquiry:' || v_row_id)
         order by r2.run_id desc limit 1;
        v_src := 'phase_c_workflow_run.accountable_role_id of the W05 run that owns this inquiry';
      end if;`,
`      elsif v_found then
        select to_jsonb(r2.accountable_role_id) into v_val
          from public.phase_c_workflow_run r2
         where r2.workflow_id = 'W05'
           and r2.business_object_id = ('inquiry:' || v_row_id)
         order by r2.run_id desc limit 1;
        v_src := 'phase_c_workflow_run.accountable_role_id of the W05 run that owns this inquiry';
        -- G09. AN INQUIRY NO RUN HAS CLAIMED HAS NOT DRIFTED FROM ANYTHING.
        -- Measured: W06-S01 and W07-S01 refused with "inquiry owner is (unstated)" because the
        -- inquiry exists and no W05 run does. The branch above still comes first, so an inquiry a
        -- run HAS claimed is answered by that run's actual role and BR-049 still refuses when it
        -- has drifted. Only the unclaimed case changes, and there the frozen registry's own
        -- accountable role for the workflow that owns the inquiry object is the answer -- read from
        -- public.phase_b_workflow, never named here.
        if v_val is null then
          select to_jsonb(w2.accountable_role_id) into v_val
            from public.phase_b_workflow w2
           where w2.primary_object = 'inquiry' order by w2.workflow_id limit 1;
          v_src := 'phase_b_workflow.accountable_role_id of the workflow whose primary object is '
                || 'the inquiry -- no workflow run has claimed this inquiry, so accountability is '
                || 'where the frozen registry puts it and has not moved';
        end if;
      end if;`,
  'G09 inquiry_owner');

writeFileSync('scripts/sql/phase_d_g09_three_keys_that_name_an_object_and_were_not_in_the_register.sql',
  HEAD + '\n' + rows + '\n' + def + '\n');
console.log('G09 written');
