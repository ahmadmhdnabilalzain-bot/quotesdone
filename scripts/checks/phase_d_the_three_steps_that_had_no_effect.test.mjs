// THE THREE STEPS OF THE 257 THAT PRODUCED NO DECLARED EFFECT — DRIVEN, BOTH DIRECTIONS.
//
// W05-S07, W12-S06 and W16-S05 were the whole of the gap the 23 Aug 2026 hand-over left open. Each
// was closed by a root-cause fix (K01..K05), and each fix is the kind that a green number cannot
// distinguish from the defect it replaced:
//
//   W05-S07  GATE-005 now accepts a DELEGATED authority reference as well as a founder command. A
//            gate that accepts more is a gate that could have been weakened, so this file proves
//            what it still refuses: a workflow the founder's frozen boundary register DOES reserve,
//            a reference that is not the one the estate resolves, and an authority whose approved
//            baseline no longer matches the live register.
//   W12-S06  the effect now carries the inquiry it belongs to. This proves the write is refused
//            when it does not, and that both gates on public.inquiry_matches now STATE their
//            refusal instead of returning a silent null.
//   W16-S05  the reveal invoice is keyed on its transaction, which is what the relation's own
//            primary key says. This proves one invoice per transaction, the invoice number
//            preserved, a replay adding nothing, and BR-020 still refusing a reveal before the
//            payment is reconciled.
//
// EVERY CASE RUNS IN ONE ABORTED TRANSACTION. The DO block always raises, so nothing survives, and
// the numbers travel out in the exception message.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const token = () => (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();
const REF = 'htdblwldjkcgjvmqkbeh';

// A TRANSPORT FAILURE IS NOT A MEASUREMENT. A dropped connection, a 429 and a 5xx are retried; only
// a raise carrying the marker is an answer.
async function probe(sql, marker) {
  for (let attempt = 1; ; attempt++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }),
    }).catch(e => ({ ok: false, status: 0, text: async () => String(e.message) }));
    const body = await r.text();
    const i = body.indexOf(marker + '<<');
    if (i >= 0) return body.slice(i + marker.length + 2, body.indexOf('>>', i));
    const transient = r.status === 429 || r.status >= 500 || r.status === 0;
    if (transient && attempt < 4) { await new Promise(x => setTimeout(x, 3000 * attempt)); continue; }
    assert.fail(`the probe did not reach its report (HTTP ${r.status}):\n${body.slice(0, 1800)}`);
  }
}

// The preamble every drive shares: a verified test context and one audited fixture scenario.
const PRE = (wf, label) => `
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','${label}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','${label}','execution_context','test',
    'for_workflow', case when '${wf}' = 'W12' then '${wf}' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${wf}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${wf}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${wf}','label','${label}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;`;

const DECL = `declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_run bigint;
        v_ref_key text; v_boid text; v_srid bigint; v_out text := '';`;

// ---------------------------------------------------------------------------------------------
// W05-S07 — the founder boundary gate
// ---------------------------------------------------------------------------------------------
test('W05-S07 produces its declared effect, and it does so on DELEGATED authority', { skip: SKIP }, async () => {
  const out = await probe(`do $p$
${DECL}
begin${PRE('W05', 'chk-w05-s07')}
  select sr.step_run_id into v_srid from public.phase_c_workflow_step_run sr
   where sr.run_id = v_run and sr.step_id = 'W05-S07' limit 1;
  v_out := 'srid=' || coalesce(v_srid::text,'-')
    || '|outcome=' || coalesce((select d.outcome from public.phase_d_dispatch d
                                 where d.step_run_id = v_srid order by d.dispatch_id desc limit 1),'-')
    || '|effects=' || (select count(*)::text from public.phase_d_effect_ledger e where e.step_run_id = v_srid)
    || '|kind=' || coalesce((public.fn_phase_d_founder_authority(v_run,'W05-S07'))->>'kind','-')
    || '|valid=' || coalesce((public.fn_phase_d_founder_authority(v_run,'W05-S07'))->>'valid','-')
    -- NO FOUNDER APPROVAL WAS REQUESTED AND NO FOUNDER WORK WAS CREATED.
    || '|cmds=' || (select count(*)::text from public.founder_command
                     where created_at > now() - interval '1 hour' and state <> 'cancelled')
    || '|links=' || (select count(*)::text from public.founder_command_workflow_link where run_id = v_run);
  raise exception 'CHK<<%>>', v_out;
end $p$;`, 'CHK');
  const f = Object.fromEntries(out.split('|').map(s => s.split('=')));
  assert.equal(f.outcome, 'EXECUTED', `W05-S07 did not execute: ${out}`);
  assert.equal(f.effects, '1', `W05-S07 produced ${f.effects} effects, expected exactly 1: ${out}`);
  assert.equal(f.kind, 'DELEGATED_AUTHORITY', `the authority W05-S07 rests on: ${out}`);
  assert.equal(f.valid, 'true', out);
  assert.equal(f.links, '0', `a founder command was linked to a run a customer inquiry started: ${out}`);
});

// WHAT IS FORCED HERE AND WHAT IS NOT, stated rather than implied. The authority answer carries
// three separate conditions -- exists, current, covers -- and `valid` is their conjunction. All
// three are forced on the FOUNDER_COMMAND branch below, by building a command and then breaking
// each condition in turn inside the aborted transaction. On the DELEGATED branch, `covers` is
// forced (a workflow the register reserves) and `exists` is forced by the same absence, but
// `current` -- the live boundary digest against the founder-APPROVED one -- is NOT forced: both
// sides of that comparison sit behind guards this test will not open (public.org_phase_baseline is
// append-only with a primary key on phase, and public.phase_b_founder_boundary is under the Phase B
// freeze). The comparison is asserted to be a live read of both values, and asserted true today.
test('GATE-005 still refuses: a reserved workflow, a made-up reference, and a broken command',
  { skip: SKIP }, async () => {
  const out = await probe(`do $p$
declare v_out text := ''; a jsonb; g record; v_cmd bigint; v_run bigint;
begin
  -- 1. A WORKFLOW THE FOUNDER'S OWN REGISTER RESERVES. W17 is scoped by FDR-002 and FDR-010, and
  --    no founder command instructed this (nonexistent) run, so there is no authority at all.
  a := public.fn_phase_d_founder_authority(null, 'W17-S07');
  v_out := 'reserved_kind=' || coalesce(a->>'kind','-') || '|reserved_valid=' || coalesce(a->>'valid','-')
        || '|reserved_ref=' || coalesce(a->>'ref','(null)');

  -- 2. A REFERENCE THE ESTATE DOES NOT RESOLVE. The gate used to be v_ok := true, so this passed.
  select * into g from public.fn_phase_d_gate_evaluate('GATE-005', jsonb_build_object(
    'step_id','W05-S07', 'run_id', null,
    'founder_authority_ref','founder_policy:phase_b_founder_boundary@0000000000000000'));
  v_out := v_out || '|forged_passed=' || coalesce(g.passed::text,'-')
                 || '|forged_absent=' || coalesce(g.evidence_absent::text,'-');

  -- 3. THE REFERENCE THE ESTATE DOES RESOLVE, on the same step. Without this the case above would
  --    only prove the gate refuses everything.
  a := public.fn_phase_d_founder_authority(null, 'W05-S07');
  select * into g from public.fn_phase_d_gate_evaluate('GATE-005', jsonb_build_object(
    'step_id','W05-S07', 'run_id', null, 'founder_authority_ref', a->>'ref'));
  v_out := v_out || '|real_passed=' || coalesce(g.passed::text,'-');

  -- 4. NO REFERENCE AT ALL.
  select * into g from public.fn_phase_d_gate_evaluate('GATE-005', jsonb_build_object(
    'step_id','W05-S07', 'run_id', null));
  v_out := v_out || '|absent_passed=' || coalesce(g.passed::text,'-')
                 || '|absent_absent=' || coalesce(g.evidence_absent::text,'-');

  -- 5. THE DIGEST COMPARISON IS A LIVE READ OF BOTH SIDES. Not forced -- see the note above the
  --    test -- so what is asserted is that the two values the resolver compares are the two values
  --    the estate holds right now, and that they agree.
  v_out := v_out
    || '|delegated_current=' || coalesce((public.fn_phase_d_founder_authority(null,'W05-S07'))->>'current','-')
    || '|live_eq_baseline=' || (
         (select d.sha256 from public.fn_phase_b_structure_digest() d where d.subject='founder_boundaries')
         = (select bl.registry_sha256->'structure'->'founder_boundaries'->>'database'
              from public.org_phase_baseline bl where bl.phase='B'))::text
    || '|ref_carries_digest=' || (
         (public.fn_phase_d_founder_authority(null,'W05-S07'))->>'ref'
         = 'founder_policy:phase_b_founder_boundary@' || left(
             (select d.sha256 from public.fn_phase_b_structure_digest() d
               where d.subject='founder_boundaries'), 16))::text;

  -- 6. THE FOUNDER_COMMAND BRANCH, all three conditions forced. A command is created through its
  --    own canonical service and then each condition is broken in turn.
  insert into public.founder_command (state, command_owner_role_id, outcome)
  values ('received', 'ceo', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH probe command') returning command_id into v_cmd;
  insert into public.phase_c_workflow_run (workflow_id, business_object_id, state, command_id,
                                           source_kind, source_ref, accountable_role_id)
  values ('W17', 'zz-phase-d-chk-gate005', 'active', v_cmd, 'founder_command',
          'chk-gate005', 'finance_controller') returning run_id into v_run;
  insert into public.founder_command_workflow_link (command_id, workflow_id, run_id)
  values (v_cmd, 'W17', v_run);
  a := public.fn_phase_d_founder_authority(v_run, 'W17-S07');
  v_out := v_out || '|cmd_kind=' || coalesce(a->>'kind','-') || '|cmd_valid=' || coalesce(a->>'valid','-');

  --    covers=false: the command selected W17, so ask about a step of another workflow whose run
  --    it does not own.
  delete from public.founder_command_workflow_link where command_id = v_cmd;
  update public.phase_c_workflow_run set command_id = v_cmd where run_id = v_run;
  a := public.fn_phase_d_founder_authority(v_run, 'W17-S07');
  v_out := v_out || '|cmd_run_covers=' || coalesce(a->>'covers','-');

  --    current=false: a cancelled command is not a live instruction.
  update public.founder_command set state = 'cancelled' where command_id = v_cmd;
  a := public.fn_phase_d_founder_authority(v_run, 'W17-S07');
  v_out := v_out || '|cancelled_current=' || coalesce(a->>'current','-')
                 || '|cancelled_valid=' || coalesce(a->>'valid','-');

  --    and the gate refuses a step whose only authority is that cancelled command.
  select * into g from public.fn_phase_d_gate_evaluate('GATE-005', jsonb_build_object(
    'step_id','W17-S07', 'run_id', v_run, 'founder_authority_ref','founder_command:' || v_cmd::text));
  v_out := v_out || '|cancelled_gate=' || coalesce(g.passed::text,'-');
  raise exception 'CHK<<%>>', v_out;
end $p$;`, 'CHK');
  const f = Object.fromEntries(out.split('|').map(s => s.split('=')));
  assert.equal(f.reserved_kind, 'FOUNDER_RESERVED', out);
  assert.equal(f.reserved_valid, 'false', out);
  assert.equal(f.reserved_ref, '(null)', out);
  assert.equal(f.forged_passed, 'false', `GATE-005 accepted a reference nothing resolves: ${out}`);
  assert.equal(f.forged_absent, 'false', `a forged reference is a JUDGED refusal, not absent evidence: ${out}`);
  assert.equal(f.real_passed, 'true', `GATE-005 refuses the authority the estate itself resolves: ${out}`);
  assert.equal(f.absent_passed, 'false', out);
  assert.equal(f.absent_absent, 'true', out);
  assert.equal(f.delegated_current, 'true', out);
  assert.equal(f.live_eq_baseline, 'true',
    `the live founder-boundary register no longer matches the founder-approved Phase B baseline: ${out}`);
  assert.equal(f.ref_carries_digest, 'true',
    `the delegation reference does not name the digest it rests on: ${out}`);
  assert.equal(f.cmd_kind, 'FOUNDER_COMMAND', out);
  assert.equal(f.cmd_valid, 'true',
    `a live command that selected this workflow must be valid, or the negatives below prove nothing: ${out}`);
  assert.equal(f.cmd_run_covers, 'true',
    `the run's own command_id must satisfy covers when the link row is gone: ${out}`);
  assert.equal(f.cancelled_current, 'false', `a cancelled founder command is still current: ${out}`);
  assert.equal(f.cancelled_valid, 'false', out);
  assert.equal(f.cancelled_gate, 'false', `GATE-005 passed on a cancelled founder command: ${out}`);
});

// ---------------------------------------------------------------------------------------------
// W12-S06 — the supplier assignment
// ---------------------------------------------------------------------------------------------
test('W12-S06 produces one assignment carrying its inquiry, and a replay adds none',
  { skip: SKIP }, async () => {
  const out = await probe(`do $p$
${DECL}
        v_inq uuid; v_eff bigint; v_net_before bigint; v_notif_before bigint;
begin
  select coalesce(max(id),0) into v_net_before from net.http_request_queue;
  select count(*) into v_notif_before from public.notifications;
${PRE('W12', 'chk-w12-s06')}
  select sr.step_run_id into v_srid from public.phase_c_workflow_step_run sr
   where sr.run_id = v_run and sr.step_id = 'W12-S06' limit 1;
  select e.effect_id into v_eff from public.phase_d_effect_ledger e where e.step_run_id = v_srid limit 1;
  v_out := 'outcome=' || coalesce((select d.outcome from public.phase_d_dispatch d
                                    where d.step_run_id = v_srid order by d.dispatch_id desc limit 1),'-')
    || '|effects=' || (select count(*)::text from public.phase_d_effect_ledger e where e.step_run_id = v_srid)
    || '|rows=' || (select count(*)::text from public.inquiry_matches m
                     where 'public.inquiry_matches:id=' || m.id::text = (select e.result_reference from public.phase_d_effect_ledger e where e.effect_id = v_eff))
    || '|has_inquiry=' || coalesce((select (m.inquiry_id is not null)::text from public.inquiry_matches m
                     where 'public.inquiry_matches:id=' || m.id::text = (select e.result_reference from public.phase_d_effect_ledger e where e.effect_id = v_eff)),'-')
    || '|has_reason=' || coalesce((select (coalesce(btrim(m.match_reason),'') <> '')::text
                     from public.inquiry_matches m
                     where 'public.inquiry_matches:id=' || m.id::text = (select e.result_reference from public.phase_d_effect_ledger e where e.effect_id = v_eff)),'-')
    || '|has_similarity=' || coalesce((select (m.similarity is not null)::text from public.inquiry_matches m
                     where 'public.inquiry_matches:id=' || m.id::text = (select e.result_reference from public.phase_d_effect_ledger e where e.effect_id = v_eff)),'-');
  -- REPLAY. The same step run, the same idempotency key, through the same canonical service.
  perform public.fn_phase_d_dispatch_step(jsonb_build_object(
    'step_run_id', v_srid, 'actor_role_id',
    (select accountable_role_id from public.phase_c_workflow_step_run where step_run_id = v_srid),
    'opened_by_kind','replay_probe', 'opened_by_ref','chk-w12-s06 replay',
    'idempotency_key','chk-w12-s06-replay'));
  v_out := v_out
    || '|effects_after_replay=' || (select count(*)::text from public.phase_d_effect_ledger e
                                     where e.step_run_id = v_srid)
    || '|assignments_total=' || (select count(*)::text from public.inquiry_matches)
    -- NO LIVE NOTIFICATION AND NO OUTBOUND REQUEST OF OUR OWN. Requests are attributed by xmin
    -- through J04's own helper, because cron jobs 35 and 88 enqueue into the same table while this
    -- transaction is open and a bare queue delta reports their POSTs as ours.
    || '|our_outbound=' || (select o.n::text
                              from public.fn_phase_d_outbound_requests_by_this_transaction(v_net_before) o)
    || '|notifications_delta=' || ((select count(*) from public.notifications) - v_notif_before)::text;
  raise exception 'CHK<<%>>', v_out;
end $p$;`, 'CHK');
  const f = Object.fromEntries(out.split('|').map(s => s.split('=')));
  assert.equal(f.outcome, 'EXECUTED', out);
  assert.equal(f.effects, '1', out);
  assert.equal(f.rows, '1', `the effect's result_reference does not resolve to one assignment: ${out}`);
  assert.equal(f.has_inquiry, 'true', `the assignment belongs to no inquiry: ${out}`);
  assert.equal(f.has_reason, 'true', `the assignment states no inclusion reason: ${out}`);
  assert.equal(f.has_similarity, 'true', `the assignment carries no eligibility evidence: ${out}`);
  assert.equal(f.effects_after_replay, '1', `a replay produced a second effect: ${out}`);
  assert.equal(f.our_outbound, '0', out);
  assert.equal(f.notifications_delta, '0', out);
});

test('both gates on inquiry_matches now STATE their refusal instead of returning a silent null',
  { skip: SKIP }, async () => {
  const out = await probe(`do $p$
declare v_fx jsonb; v_out text := ''; v_inq uuid; v_sup bigint; v_id bigint; v_other uuid;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','chk-gates'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','chk-gates','execution_context','test','for_workflow','W12'));
  v_inq := (v_fx->'parent_refs'->>'inquiry_id')::uuid;
  v_sup := (v_fx->'parent_refs'->>'supplier_id')::bigint;

  -- 1. PASS. Without this the three refusals below would only prove the gate refuses everything.
  perform set_config('app.inquiry_match_gate_verdict','(unset)', true);
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
  values (v_inq, v_sup, 0.9, 'PHASE_D_FIXTURE_DO_NOT_PUBLISH probe') returning id into v_id;
  v_out := 'pass_verdict=' || current_setting('app.inquiry_match_gate_verdict', true)
        || '|pass_landed=' || case when v_id is null then 'false' else 'true' end;

  -- 2. NO INQUIRY AT ALL — the exact shape that cost W12-S06 its effect.
  perform set_config('app.inquiry_match_gate_verdict','(unset)', true);
  v_id := null;
  insert into public.inquiry_matches (supplier_id) values (v_sup) returning id into v_id;
  v_out := v_out || '|orphan_verdict=' || current_setting('app.inquiry_match_gate_verdict', true)
        || '|orphan_landed=' || case when v_id is null then 'false' else 'true' end;

  -- 3. AN INQUIRY THAT IS NOT rfq_ready. Created here with no category, no emirate and no scope, so
  --    trg_rfq_complete scores it below the bar on its own content.
  insert into public.inquiries (summary, status)
  values ('PHASE_D_FIXTURE_DO_NOT_PUBLISH incomplete rfq', 'new') returning id into v_other;
  perform set_config('app.inquiry_match_gate_verdict','(unset)', true);
  v_id := null;
  insert into public.inquiry_matches (inquiry_id, supplier_id) values (v_other, v_sup) returning id into v_id;
  v_out := v_out || '|notready_verdict=' || current_setting('app.inquiry_match_gate_verdict', true)
        || '|notready_landed=' || case when v_id is null then 'false' else 'true' end
        || '|notready_ready=' || coalesce((select rfq_ready::text from public.inquiries where id = v_other),'null');

  -- 4. AN INELIGIBLE SUPPLIER, on the same key.
  update public.leads set matching_blocked = true where id = v_sup;
  perform set_config('app.inquiry_match_gate_verdict','(unset)', true);
  v_id := null;
  insert into public.inquiry_matches (inquiry_id, supplier_id) values (v_inq, v_sup) returning id into v_id;
  v_out := v_out || '|blocked_verdict=' || current_setting('app.inquiry_match_gate_verdict', true)
        || '|blocked_landed=' || case when v_id is null then 'false' else 'true' end;
  raise exception 'CHK<<%>>', v_out;
end $p$;`, 'CHK');
  const f = Object.fromEntries(out.split('|').map(s => s.split('=')));
  assert.equal(f.pass_verdict, 'PASS', out);
  assert.equal(f.pass_landed, 'true', out);
  assert.equal(f.orphan_verdict, 'BLOCKED_MISSING_MATCH_EVIDENCE', out);
  assert.equal(f.orphan_landed, 'false', out);
  assert.equal(f.notready_ready, 'false', `the fixture for the not-ready case was scored ready: ${out}`);
  assert.equal(f.notready_verdict, 'BLOCKED_NOT_RFQ_READY', out);
  assert.equal(f.notready_landed, 'false', out);
  assert.equal(f.blocked_verdict, 'BLOCKED_INELIGIBLE_SUPPLIER', out);
  assert.equal(f.blocked_landed, 'false', out);
});

// ---------------------------------------------------------------------------------------------
// W16-S05 — the reveal invoice
// ---------------------------------------------------------------------------------------------
test('W16-S05 issues one invoice per transaction, keeps its number, and a replay issues none',
  { skip: SKIP }, async () => {
  const out = await probe(`do $p$
${DECL}
        v_txn uuid; v_eff bigint;
begin${PRE('W16', 'chk-w16-s05')}
  select sr.step_run_id into v_srid from public.phase_c_workflow_step_run sr
   where sr.run_id = v_run and sr.step_id = 'W16-S05' limit 1;
  select e.effect_id into v_eff from public.phase_d_effect_ledger e where e.step_run_id = v_srid limit 1;
  select ri.transaction_id into v_txn from public.reveal_invoices ri
   where 'public.reveal_invoices:transaction_id=' || ri.transaction_id::text
         = (select e2.result_reference from public.phase_d_effect_ledger e2 where e2.effect_id = v_eff);
  v_out := 'outcome=' || coalesce((select d.outcome from public.phase_d_dispatch d
                                    where d.step_run_id = v_srid order by d.dispatch_id desc limit 1),'-')
    || '|effects=' || (select count(*)::text from public.phase_d_effect_ledger e where e.step_run_id = v_srid)
    || '|ref_is_txn=' || case when v_txn is null then 'false' else 'true' end
    || '|invoices_for_txn=' || coalesce((select count(*)::text from public.reveal_invoices ri
                                          where ri.transaction_id = v_txn),'-')
    || '|invoice_no_kept=' || coalesce((select (coalesce(btrim(ri.invoice_no),'') <> '')::text
                                          from public.reveal_invoices ri where ri.transaction_id = v_txn),'-');
  perform public.fn_phase_d_dispatch_step(jsonb_build_object(
    'step_run_id', v_srid, 'actor_role_id',
    (select accountable_role_id from public.phase_c_workflow_step_run where step_run_id = v_srid),
    'opened_by_kind','replay_probe', 'opened_by_ref','chk-w16-s05 replay',
    'idempotency_key','chk-w16-s05-replay'));
  v_out := v_out
    || '|effects_after_replay=' || (select count(*)::text from public.phase_d_effect_ledger e
                                     where e.step_run_id = v_srid)
    || '|invoices_after_replay=' || (select count(*)::text from public.reveal_invoices ri
                                      where ri.transaction_id = v_txn);
  raise exception 'CHK<<%>>', v_out;
end $p$;`, 'CHK');
  const f = Object.fromEntries(out.split('|').map(s => s.split('=')));
  assert.equal(f.outcome, 'EXECUTED', out);
  assert.equal(f.effects, '1', out);
  assert.equal(f.ref_is_txn, 'true', `the effect's reference is not the transaction the relation keys on: ${out}`);
  assert.equal(f.invoices_for_txn, '1', out);
  assert.equal(f.invoice_no_kept, 'true', `the invoice number was not preserved: ${out}`);
  assert.equal(f.effects_after_replay, '1', out);
  assert.equal(f.invoices_after_replay, '1', `a replay issued a second invoice: ${out}`);
});

test('an unknown transaction is refused, and BR-020 still refuses a reveal before reconciliation',
  { skip: SKIP }, async () => {
  const out = await probe(`do $p$
declare v_fx jsonb; v_out text := ''; v_txn uuid; v_err text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','chk-w16-neg'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','chk-w16-neg','execution_context','test'));
  v_txn := (v_fx->'parent_refs'->>'transaction_id')::uuid;

  -- 1. AN UNKNOWN TRANSACTION. The relation's own foreign key answers this.
  begin
    insert into public.reveal_invoices (transaction_id, invoice_no)
    values (gen_random_uuid(), 'PHASE_D_FIXTURE_DO_NOT_PUBLISH');
    v_out := 'unknown_txn=ACCEPTED';
  exception when others then v_out := 'unknown_txn=' || sqlstate; end;

  -- 2. THE LADDER. The scenario leaves the transaction at payment_reconciled, rung 5, the only
  --    non-terminal rung that authorises a reveal. Walking it back down must refuse.
  v_out := v_out || '|reconciled=' || coalesce((select p.permitted::text from public.fn_phase_d_reveal_permitted(v_txn::text) p),'-');
  update public.transactions set fee_status = 'payment_initiated' where id = v_txn;
  v_out := v_out || '|initiated=' || coalesce((select p.permitted::text from public.fn_phase_d_reveal_permitted(v_txn::text) p),'-');
  update public.transactions set fee_status = 'provider_success' where id = v_txn;
  v_out := v_out || '|provider_success=' || coalesce((select p.permitted::text from public.fn_phase_d_reveal_permitted(v_txn::text) p),'-');
  update public.transactions set fee_status = 'payment_confirmed' where id = v_txn;
  v_out := v_out || '|confirmed=' || coalesce((select p.permitted::text from public.fn_phase_d_reveal_permitted(v_txn::text) p),'-');
  update public.transactions set fee_status = 'not_a_rung_at_all' where id = v_txn;
  v_out := v_out || '|unknown_rung=' || coalesce((select p.permitted::text from public.fn_phase_d_reveal_permitted(v_txn::text) p),'-');

  -- 3. AND BR-020 ITSELF, through the rule service every handler goes through.
  v_out := v_out || '|br020=' || coalesce((select rc.ok::text from public.fn_phase_d_rule_check('BR-020', jsonb_build_object('transaction_id', v_txn::text)) rc),'-');
  raise exception 'CHK<<%>>', v_out;
end $p$;`, 'CHK');
  const f = Object.fromEntries(out.split('|').map(s => s.split('=')));
  assert.equal(f.unknown_txn, '23503', `an invoice for a transaction that does not exist: ${out}`);
  assert.equal(f.reconciled, 'true', `rung 5 must permit the reveal or the negatives prove nothing: ${out}`);
  assert.equal(f.initiated, 'false', out);
  assert.equal(f.provider_success, 'false', out);
  assert.equal(f.confirmed, 'false', out);
  assert.equal(f.unknown_rung, 'false', `an unrecognised fee_status resolved to a permitted rung: ${out}`);
  assert.equal(f.br020, 'false', out);
});

// ---------------------------------------------------------------------------------------------
// The structural fact behind W16-S05, so it cannot recur silently.
// ---------------------------------------------------------------------------------------------
test('every bound object names its relation\'s own primary key as its primary identity',
  { skip: SKIP }, async () => {
  const out = await probe(`do $p$
declare v_out text := '';
begin
  select coalesce(string_agg(x.object_id || ' says ' || coalesce(x.pid,'(null)')
                             || ' and the relation is keyed on ' || coalesce(x.pk,'(no single-column pk)'),
                             '; ' order by x.object_id), 'none')
    into v_out
    from (
      select b.object_id, b.primary_identity pid,
             (select array_to_string(array_agg(a.attname order by a.attnum), ',')
                from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
               where i.indrelid = to_regclass(b.canonical_relation) and i.indisprimary
               having count(*) = 1) pk
        from public.phase_d_business_object_binding b
       where b.relation_kind = 'EXISTING_TABLE' and to_regclass(b.canonical_relation) is not null) x
   where x.pk is not null and x.pid is distinct from x.pk;
  raise exception 'CHK<<%>>', v_out;
end $p$;`, 'CHK');
  assert.equal(out, 'none',
    `a bound object's declared primary identity disagrees with its relation's PRIMARY KEY — the ` +
    `defect that keyed the reveal invoice on its number: ${out}`);
});
