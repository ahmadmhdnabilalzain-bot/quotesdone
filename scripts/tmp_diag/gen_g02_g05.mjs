// Generate G02–G05 by splicing the LIVE definitions. Each anchor must match exactly once.
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const live = async (name) => {
  const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='${name}'`);
  if (r.length !== 1) throw new Error(`${name}: ${r.length} definitions`);
  return r[0].def;
};
const HEAD_G02 = `-- G02 — two keys that name a record, answered from a constant, and the constant won
--
-- Two independent instances of one shape, both in fn_phase_d_step_context, both measured by
-- driving the workflows they refuse.
--
-- 1. terms_version and terms_hash. BR-025 refused W04-S01 and W09-S01 with
--       "acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f, which matches
--        0 row(s) in public.legal_documents whose displayed body hashes to exactly that digest"
--    Those are the committed catalogue fixtures PDF-3104 and PDF-3105 — a true pair over a real
--    fixture body, and the wrong answer. public.legal_documents holds customer-terms v3 (digest
--    20a7b47092a3…) and supplier-agreement v5 (digest 83045bcfa2cc…), the scenario factory reads
--    those and writes them onto the acceptance record it creates, and both keys then fell past
--    every branch of the resolver to the fixture door, which shadowed the record with the
--    constant. The keys now resolve from the acceptance record the run's own object owns.
--
--    NOTE FOR THE FOUNDER, because his section 4 asked for something else. The brief says to
--    "create the required legal-document/terms fixture through the canonical service" so that its
--    body hashes to the committed digest. Re-measured before building: the published documents
--    already exist and are real, and public.legal_documents is the table the live legal pages are
--    served from. Writing a fixture terms row into it would be publishing fixture terms — and the
--    same brief forbids inserting a hash-only fake evidence row. The defect was never a missing
--    document; it was a constant standing in front of the real one. No legal document is created.
--
-- 2. reviewer_role_id read only phase_d_handler_binding.independent_reviewer_role_id, which 229 of
--    257 steps leave blank, so every gate asking who reviewed something was told "nobody" even
--    after fn_kernel_review_decide had sealed a verdict and stamped the reviewer on the task.
--
-- Neither change can turn a refusal into a pass without a record behind it: both new branches
-- resolve from rows, and where the row is absent the key stays unresolved and the rule or gate
-- refuses exactly as before.
--
-- The rest of the routine is byte-identical; three anchors, each required to match exactly once.`;

const HEAD_G03 = `-- G03 — a reviewer's verdict demanded before the workflow has reviewed anything
--
-- GATE-021 "Marketing artifact approval" (pass_result: "Publish approved revision.") is scoped to
-- W03;W20 and, being scoped to the workflow rather than to a step, applied to W03-S01 "Set
-- acquisition objective" and W20-S01 "Define content objective and hypothesis". GATE-026
-- "Knowledge validation" (pass_result: "Publish runtime-eligible version.") applied to W26-S01
-- "Open knowledge gap or change", an INTAKE step. All three refused for want of a reviewer of
-- something the workflow had not yet produced, and all three were the first refusal of a workflow
-- that then produced no effect at all.
--
-- fn_phase_d_gate_applies already refines exactly this shape twice — GATE-020, which demanded an
-- approved case decision at the step that opens the case, and GATE-015, which refused a workflow
-- for having done its own job one step earlier. This is the third instance, stated as a derived
-- rule rather than a third named exception: a gate whose evidence_keys name reviewer_role_id does
-- not apply to a step that runs before the workflow's first review step.
--
-- The gate still governs W03-S06..S09, W20-S04..S09 and W26-S05..S09 — the artifact, the review
-- and the publication — and still refuses there without a recorded reviewer.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.`;

const HEAD_G04 = `-- G04 — the rule about money was asking the register that does not model money
--
-- BR-033, frozen: "Unknown, conflicting or unreconciled monetary states are blocked/quarantined and
-- cannot be treated as success." Its implementation read the allowed_states of the
-- TRANSACTION_RECORD object family: open, pending, settled, refunded, failed, reconciled. The
-- money ladder public.phase_d_payment_state — what public.transactions.fee_status holds and what
-- BR-020 reads — is checkout_created, payment_initiated, provider_success, payment_confirmed,
-- payment_reconciled, reveal_authorized.
--
-- MEASURED: the two sets do not share a single value. W16-S01 refused with "monetary state
-- reveal_authorized matches 0 allowed state(s) of the TRANSACTION_RECORD object family", and
-- payment_reconciled — the founder-approved bar in BR-020 — would have refused the same way, while
-- 'settled' would have passed for a payment that never reconciled. Two rules about one transaction,
-- structurally unable to agree about any transaction.
--
-- The rule now reads the ladder, and reads authorizes_reveal for the "unreconciled" half of its own
-- frozen sentence. Strictly tighter: five words that say nothing about reconciliation stop passing,
-- and the two that mean reconciled start passing. public.phase_d_object_state_contract is NOT
-- amended — the founder's section 5 forbids putting reveal_authorized into the TRANSACTION_RECORD
-- family to make this rule green, and nothing here does.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.`;

const HEAD_G05 = `-- G05 — every run arose by itself, so no run could rest on founder authority
--
-- fn_phase_d_drive_workflow started all 30 workflows with source_kind 'autonomous' and no
-- command_id. fn_phase_d_step_context resolves founder_authority_ref from
-- founder_command_workflow_link for the run, or from phase_c_workflow_run.command_id, and an
-- autonomous start leaves both empty by construction — so the key was unresolvable on every run of
-- every workflow and the five rules that require it refused every founder-gated step in the estate.
--
-- Measured: W03-S01 and W18-S05 refused with "BR-003 requires [founder_authority_ref] and the call
-- names none of it", while the scenario factory had created a founder command four statements
-- earlier and returned founder_authority_ref in its parent_refs, where nothing read it. That is the
-- "finished capability with no entry point" shape: the row existed, the resolver existed, and
-- nothing connected them.
--
-- The correction is an arrival, not an injection: fn_kernel_workflow_start already accepts
-- source_kind 'founder_command' with a command_id, which is how a founder-instructed run is really
-- started. It is used only where the frozen registry says the workflow has a founder-gated step or
-- a founder-authority rule in scope, both read from the registry and neither listed here.
--
-- The fixture command authorises nothing beyond its own sentence: founder_initiated_only false,
-- refund_semantics false, founder_identity resolving to nobody, and founder AUTHENTICATION remains
-- fn_phase_c_require_founder reading a verified auth subject. The refund trigger
-- z00_refund_founder_decision_only is untouched, and that it still refuses is measured after this
-- change rather than assumed.
--
-- Two anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const splice = (src, anchor, replacement, what) => {
  const n = src.split(anchor).length - 1;
  if (n !== 1) throw new Error(`${what}: anchor matched ${n} time(s)`);
  return src.replace(anchor, replacement);
};

// ============================================================================================
// G02 — fn_phase_d_step_context: two keys that name a record, answered from a constant
// ============================================================================================
{
  let def = await live('fn_phase_d_step_context');

  // (a) terms_version / terms_hash from the acceptance record, before the fixture door.
  const anchorSrcRef = `    elsif v_k = 'source_ref' then`;
  const termsBranch = `    elsif v_k in ('terms_version','terms_hash') then
      -- G02. A KEY THAT NAMES A RECORD WAS ANSWERED FROM A CONSTANT, AND THE CONSTANT WON.
      --
      -- BR-025 asks whether an acceptance references the exact displayed version AND hash, and it
      -- resolves the pair against public.legal_documents. Measured on W04 and W09: it refused with
      --
      --   "acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f, which matches
      --    0 row(s) in public.legal_documents whose displayed body hashes to exactly that digest"
      --
      -- Those two values are the COMMITTED CATALOGUE FIXTURES PDF-3104 and PDF-3105. Nothing was
      -- wrong with them; they are a real pair over a real fixture body. What was wrong is that they
      -- were the answer at all. The scenario factory reads the version and digest of the ACTUALLY
      -- PUBLISHED documents -- public.legal_documents customer-terms v3 and supplier-agreement v5 --
      -- and writes them onto the acceptance record it creates. Both keys then fell through every
      -- branch of this resolver to the fixture door, which answered from the catalogue, and the
      -- catalogue value shadowed the record the scenario had just written. That is D9g's "a
      -- generated fixture beat the real reference", one layer up, and F47's "a key that names an
      -- object is answered from that object's reference" stated for a third time.
      --
      -- THE ACCEPTANCE RECORD IS FOUND BY WHAT IT CARRIES, NOT BY WHAT IT IS CALLED. The record
      -- sought is the live object record owned by this run's own business object that carries both
      -- terms keys -- no object name, no naming convention, no workflow list. A run whose object
      -- row was not found, or that owns no acceptance, resolves nothing here and falls through to
      -- the catalogue exactly as before, where BR-025 still matches 0 rows and still refuses. The
      -- rule keeps its ability to fail, and it now also has a way to pass for a true reason.
      if v_found and v_row_id is not null then
        select o.payload ->> v_k into v_val_txt
          from public.phase_d_object_record o
         where o.superseded_by is null
           and o.payload ? 'terms_version' and o.payload ? 'terms_hash'
           and o.owner_ref = v_row_id
         order by o.record_id desc limit 1;
        if coalesce(btrim(v_val_txt),'') <> '' then
          v_val := to_jsonb(v_val_txt);
          v_src := 'the terms-acceptance record this run''s own business object owns, in '
                || 'public.phase_d_object_record -- the pair the acceptance actually names';
        end if;
        v_val_txt := null;
      end if;

${anchorSrcRef}`;
  def = splice(def, anchorSrcRef, termsBranch, 'G02 terms branch');

  // (b) reviewer_role_id: prefer the review that was actually recorded.
  const anchorRev = `      v_val := to_jsonb(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''));
      v_src := 'phase_d_handler_binding.independent_reviewer_role_id, declared not chosen';`;
  const revBranch = `      -- G02. THE REVIEWER WHO ACTUALLY REVIEWED, BEFORE THE ONE THE REGISTRY DECLARES.
      --
      -- This read only phase_d_handler_binding.independent_reviewer_role_id, which 229 of the 257
      -- steps leave blank, so every gate asking who reviewed something was answered "nobody" even
      -- after fn_kernel_review_decide had sealed a verdict and STAMPED THE REVIEWER on the task.
      -- fn_phase_d_recorded_review already reads that stamp and nothing consulted it here.
      --
      -- Order matters and this order is deliberate: the reviewer who actually reviewed outranks the
      -- reviewer a registry column names, because the gate's question is about the review that
      -- happened. Where no review has been recorded the declared reviewer still answers, and where
      -- neither exists the key stays unresolved and the gate refuses -- which is the gate working,
      -- and is what the previous comment here was protecting. Nothing chooses a reviewer: this
      -- resolver reports one or reports none, exactly as fn_pick_reviewer should have.
      v_val := to_jsonb(nullif(btrim(coalesce(
                 (public.fn_phase_d_recorded_review(p_step_run_id))->>'reviewer_role_id','')),''));
      if v_val is not null then
        v_src := 'phase_c_task.reviewer_role_id, stamped by fn_kernel_review_decide on the review '
              || 'actually recorded for this step run';
      else
        v_val := to_jsonb(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''));
        v_src := 'phase_d_handler_binding.independent_reviewer_role_id, declared not chosen';
      end if;`;
  def = splice(def, anchorRev, revBranch, 'G02 reviewer branch');

  // (c) the local the terms branch needs.
  const anchorDecl = `  sr public.phase_c_workflow_step_run%rowtype;`;
  def = splice(def, anchorDecl,
    anchorDecl + `\n  v_val_txt text;  -- G02: the acceptance value read back before it becomes jsonb`,
    'G02 declaration');

  writeFileSync('scripts/sql/phase_d_g02_two_keys_that_name_a_record_answered_from_a_constant.sql',
    HEAD_G02 + '\n' + def + '\n');
  console.log('G02 written');
}

// ============================================================================================
// G03 — fn_phase_d_gate_applies: a reviewer's verdict demanded before the workflow reviews
// ============================================================================================
{
  let def = await live('fn_phase_d_gate_applies');
  const anchor = `  applies := true;
  why := format('%s (%s, scope %s) applies to %s', g.gate_id, g.gate_type, g.workflow_scope, p_step_id);`;
  const add = `  -- G03. A GATE THAT DEMANDS A REVIEWER'S VERDICT AT A STEP THAT RUNS BEFORE ANY REVIEW.
  --
  -- Measured, on the three gates whose evidence_keys name reviewer_role_id:
  --
  --   GATE-021 "Marketing artifact approval", pass_result "Publish approved revision.", scope W03;W20
  --            refused W03-S01 "Set acquisition objective" and W20-S01 "Define content objective
  --            and hypothesis" for want of the reviewer of a final asset the workflow has not yet
  --            produced. W03 first reviews at S06; W20 at S04.
  --   GATE-026 "Knowledge validation", pass_result "Publish runtime-eligible version.", scope W26
  --            refused W26-S01 "Open knowledge gap or change", an INTAKE step. W26 first reviews
  --            at S05.
  --
  -- Both are the shape this function already refines twice. GATE-020 was narrowed because it
  -- demanded an approved case decision at the step that OPENS the case; GATE-015 because it
  -- refused a workflow for having done its own job one step earlier. This is the same sentence:
  -- a condition that the workflow itself is what satisfies, demanded before the workflow
  -- satisfies it.
  --
  -- NOTHING IS WEAKENED. The gate still applies from the workflow's first review step to its last
  -- step, which is where the artifact exists, where the review happens, and where publication is
  -- decided -- W03-S06..S09, W20-S04..S09, W26-S05..S09. A step at or after that point with no
  -- recorded reviewer still refuses.
  --
  -- NO GATE AND NO STEP IS NAMED. The condition is derived: the gate's own evidence_keys carry
  -- reviewer_role_id, and the frozen registry says which of this workflow's steps are reviews.
  -- A workflow with no review step at all is untouched -- there is no point before which to be
  -- early -- and GATE-004 keeps its own, narrower, earlier exemption.
  if exists (select 1 from public.phase_d_gate_contract gc
              where gc.gate_id = p_gate_id
                and 'reviewer_role_id' = any(gc.evidence_keys))
     and p_step_id < (select min(rs.step_id) from public.phase_b_workflow_step rs
                       where rs.workflow_id = s.workflow_id and rs.step_type = 'review')
  then
    applies := false;
    why := format('%s requires an independent reviewer''s verdict and %s runs before %s, the first review step of %s; the review this gate reads is produced by the workflow itself, later',
                  p_gate_id, p_step_id,
                  (select min(rs.step_id) from public.phase_b_workflow_step rs
                    where rs.workflow_id = s.workflow_id and rs.step_type = 'review'),
                  s.workflow_id);
    return next; return;
  end if;

` + anchor;
  def = splice(def, anchor, add, 'G03');
  writeFileSync('scripts/sql/phase_d_g03_a_reviewers_verdict_demanded_before_the_workflow_reviews.sql',
    HEAD_G03 + '\n' + def + '\n');
  console.log('G03 written');
}

// ============================================================================================
// G04 — BR-033 reads the register that models money
// ============================================================================================
{
  let def = await live('fn_phase_d_rule_check');
  const anchor = `    v_txt := lower(coalesce(btrim(p_context->>'monetary_state'),''));
    select count(*) into v_n
      from public.phase_d_object_state_contract c, unnest(c.allowed_states) s
     where c.policy_family = 'TRANSACTION_RECORD' and lower(s) = v_txt;
    v_ok := v_txt <> '' and v_txt not in ('unknown','conflicting','unreconciled') and v_n >= 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-033: monetary state %s matches %s allowed state(s) of the TRANSACTION_RECORD object family. Unknown, conflicting, unreconciled and unrecognised states are blocked and quarantined, never treated as success.',
                     coalesce(nullif(v_txt,''),'(unstated)'), v_n);
    return next; return;`;
  const repl = `    -- G04. THE RULE ABOUT MONEY WAS ASKING THE REGISTER THAT DOES NOT MODEL MONEY.
    --
    -- E30 corrected a deny-list of three words by reading the allowed_states of the
    -- TRANSACTION_RECORD family, which was right about the method and wrong about the register.
    -- Two vocabularies describe a transaction in this estate:
    --
    --   public.phase_d_object_state_contract  open, pending, settled, refunded, failed, reconciled
    --       the generic OBJECT-RECORD lifecycle, derived from policy_family and applied identically
    --       to dispatch_batch, payment_transaction, reveal_transaction and supplier_assignment.
    --   public.phase_d_payment_state          checkout_created, payment_initiated, provider_success,
    --       payment_confirmed, payment_reconciled, reveal_authorized -- a SIX-RUNG LADDER, each rung
    --       carrying authorizes_reveal and a stated reason, and it is what public.transactions
    --       .fee_status actually holds and what BR-020 reads.
    --
    -- MEASURED: the intersection of those two sets is EMPTY. Not "different in places" -- no value
    -- appears in both. So BR-033 refused every real monetary state this estate can produce,
    -- including payment_reconciled, the founder-approved bar in BR-020, and would have PASSED
    -- 'settled' or 'refunded' for a payment that never reconciled. Two rules about one transaction,
    -- unable to agree about any transaction, because one of them was reading the wrong register.
    --
    -- THE FROZEN TEXT DECIDES WHICH REGISTER IS RIGHT: "Unknown, conflicting or unreconciled
    -- monetary states are blocked/quarantined and cannot be treated as success." Recognised, and
    -- reconciled. The ladder is the register of recognised monetary states and authorizes_reveal is
    -- the ladder's own mark for the reconciled rungs, so both halves of the frozen sentence are
    -- read from the register that states them.
    --
    -- THIS IS STRICTLY TIGHTER THAN WHAT IT REPLACES, and that is the test of it. Before: five
    -- words passed that say nothing about reconciliation. After: an unrecognised state is refused
    -- as unrecognised, a recognised state below reconciliation is refused as unreconciled, and the
    -- three quarantine words are refused by name as they always were. Only payment_reconciled and
    -- reveal_authorized pass, which is the relationship the founder's section 5 asked BR-020 and
    -- BR-033 to evaluate between them.
    --
    -- public.phase_d_object_state_contract IS NOT AMENDED. The founder's section 5 forbids putting
    -- reveal_authorized into the TRANSACTION_RECORD family to make this rule green, and nothing
    -- here does: the family keeps the generic lifecycle it describes, and this rule stops asking
    -- it a question it was never the register for.
    v_txt := lower(coalesce(btrim(p_context->>'monetary_state'),''));
    select count(*) into v_n
      from public.phase_d_payment_state ps
     where lower(ps.state_key) = v_txt and ps.authorizes_reveal;
    v_ok := v_txt <> '' and v_txt not in ('unknown','conflicting','unreconciled') and v_n >= 1;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-033: monetary state %s matches %s reconciled rung(s) of the payment ladder public.phase_d_payment_state (%s of its %s rungs are reconciled: %s). Unknown, conflicting, unreconciled and unrecognised states are blocked and quarantined, never treated as success.',
                     coalesce(nullif(v_txt,''),'(unstated)'), v_n,
                     (select count(*) from public.phase_d_payment_state where authorizes_reveal),
                     (select count(*) from public.phase_d_payment_state),
                     (select string_agg(ps2.state_key, ', ' order by ps2.rung)
                        from public.phase_d_payment_state ps2 where ps2.authorizes_reveal));
    return next; return;`;
  def = splice(def, anchor, repl, 'G04');
  writeFileSync('scripts/sql/phase_d_g04_the_rule_about_money_asked_the_register_that_does_not_model_money.sql',
    HEAD_G04 + '\n' + def + '\n');
  console.log('G04 written');
}

// ============================================================================================
// G05 — the driver starts every run as autonomous, so no run can rest on founder authority
// ============================================================================================
{
  let def = await live('fn_phase_d_drive_workflow');
  const anchor = `  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id',        v_wf,
    'business_object_id', v_boid,
    'source_kind',        'autonomous',
    'source_ref',         format('zz-phase-d-%s-%s', v_label, v_wf),
    'requested_by',       w.accountable_role_id,
    'trigger_ctx',        jsonb_build_object('driver','fn_phase_d_drive_workflow',
                                             'path','kernel doors only')));`;
  const repl = `  -- G05. EVERY RUN AROSE BY ITSELF, SO NO RUN COULD REST ON FOUNDER AUTHORITY.
  --
  -- This started every one of the 30 workflows with source_kind 'autonomous' and no command_id.
  -- fn_phase_d_step_context resolves founder_authority_ref from founder_command_workflow_link for
  -- the run, or failing that from phase_c_workflow_run.command_id -- and an autonomous start
  -- leaves both empty by construction. So the key was unresolvable on every run of every workflow,
  -- and the six rules that read it refused every founder-gated step in the estate. Measured:
  -- W03-S01 and W18-S05 refused with "BR-003 requires [founder_authority_ref] and the call names
  -- none of it", and the scenario factory had created a founder command four statements earlier
  -- and handed back founder_authority_ref in its parent_refs, where nothing read it.
  --
  -- The correction is an ARRIVAL, not an injection. fn_kernel_workflow_start already accepts
  -- source_kind 'founder_command' with a command_id, and that is how a founder-instructed run is
  -- really started in production; F12's fixture command is a real row in public.founder_command
  -- created through its own canonical service inside this aborted transaction. Starting the run
  -- from it makes the run's origin TRUE rather than absent. Handing the rule a reference for a run
  -- that arose autonomously would have been the forgery; a run that has no origin at all is simply
  -- a run nothing instructed.
  --
  -- THE FOUNDER COMMAND IS ONLY USED WHERE THE FROZEN REGISTRY SAYS THE WORKFLOW IS FOUNDER-GATED,
  -- and which workflows those are is read from phase_b_business_rule.workflow_scope and
  -- phase_b_workflow_step.founder_gate, never listed here. A workflow with no founder-reserved
  -- step still starts autonomously, and BR-003 stays unresolvable there -- as it should, since
  -- BR-003 does not govern it.
  --
  -- IT AUTHORISES NOTHING BEYOND ITS OWN SENTENCE. The fixture command carries
  -- founder_initiated_only false and refund_semantics false, its founder_identity resolves to
  -- nobody, and founder AUTHENTICATION is fn_phase_c_require_founder, which reads a verified auth
  -- subject and never this table. z00_refund_founder_decision_only on public.refunds is untouched
  -- and still refuses a refund without a founder decision -- measured after this change, not
  -- assumed.
  if exists (select 1 from public.phase_b_workflow_step fs
              where fs.workflow_id = v_wf
                and lower(coalesce(btrim(fs.founder_gate),'none')) <> 'none')
     or exists (select 1 from public.phase_b_business_rule br
                 where br.rule_id in (select re.rule_id from public.phase_d_rule_enforcement re
                                       where 'founder_authority_ref' = any(re.required_context))
                   and (upper(br.workflow_scope) = 'ALL'
                        or v_wf = any(string_to_array(replace(br.workflow_scope,' ',''),';'))))
  then
    -- The command the factory recorded, read from the evidence manifest it wrote — the same row
    -- fn_phase_d_founder_authority_fixture returned, not a second lookup that might find another.
    select nullif(split_part(l.contributed_value, ':', 2),'')::bigint into v_founder_cmd
      from public.phase_d_scenario_record l
     where l.fixture_run_id = public.fn_phase_d_fixture_context()
       and l.contributes_ref = 'founder_authority_ref'
     order by l.scenario_record_id desc limit 1;
  end if;

  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id',        v_wf,
    'business_object_id', v_boid,
    'source_kind',        case when v_founder_cmd is null then 'autonomous' else 'founder_command' end,
    'source_ref',         format('zz-phase-d-%s-%s', v_label, v_wf),
    'requested_by',       w.accountable_role_id,
    'trigger_ctx',        jsonb_build_object('driver','fn_phase_d_drive_workflow',
                                             'path','kernel doors only'))
    || case when v_founder_cmd is null then '{}'::jsonb
            else jsonb_build_object('command_id', v_founder_cmd) end);
  if v_founder_cmd is not null then
    -- fn_kernel_event_consume refuses an event naming a workflow the command did not select, so the
    -- selection is recorded here rather than left implied by the run alone.
    insert into public.founder_command_workflow_link (command_id, workflow_id)
    values (v_founder_cmd, v_wf) on conflict do nothing;
  end if;`;
  def = splice(def, anchor, repl, 'G05 start');
  const anchorDecl = `  v_first_refusal jsonb := null;  -- where the deterministic HANDLER first declined, and why`;
  def = splice(def, anchorDecl,
    anchorDecl + `\n  v_founder_cmd   bigint := null; -- G05: the fixture founder command this run arises from, where one applies`,
    'G05 declaration');
  writeFileSync('scripts/sql/phase_d_g05_every_run_arose_by_itself_so_none_could_rest_on_founder_authority.sql',
    HEAD_G05 + '\n' + def + '\n');
  console.log('G05 written');
}
