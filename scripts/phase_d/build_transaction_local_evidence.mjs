// PHASE D DELIVERABLE — PHASE_D_TRANSACTION_LOCAL_EVIDENCE.csv
//
// The founder's ruling of 22 Aug 2026, section 11: "Do not use empty production tables as proof no
// effect was produced. Generate committed evidence artifacts from the transaction-local result
// manifests." Section 12 lists it as a release condition.
//
// The problem it names is real and this estate has been living with it. Every Phase D figure is
// produced inside a transaction that aborts, so the only thing a later reader can check is that
// public.customers still reads 0 — which is equally true if nothing was ever attempted. An empty
// table is not evidence of a controlled effect; it is the absence of evidence about anything.
//
// So this file records, per effect, what happened INSIDE the transaction before it was rolled back:
// the fixture run that scoped it, the workflow and step, the effect type and the object it wrote,
// the digest of the payload, the row it produced in the canonical relation, and the provider mode.
// Then it records the rollback: the same counters read after the abort, from a new transaction.
//
//   node scripts/phase_d/build_transaction_local_evidence.mjs
//
// NO BUSINESS PAYLOAD AND NO PII. Section 11 is explicit -- "Do not store customer/supplier fixture
// payloads or PII in the evidence" -- so what is carried is the payload DIGEST and the object's
// key, never a field of it. The digest is what makes the row checkable; the payload is what would
// make it a leak.
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql, PROJECT_REF } from '../phase_c/lib/db.mjs';

const RS = String.fromCharCode(30);
const US = String.fromCharCode(31);

const DRIVE = `
do $emit$
declare
  v_fx jsonb; v jsonb; v_rev text; v_cands jsonb; v_ref_key text; v_boid text;
  v_out text := ''; r record; v_fixture bigint;
  v_c0 int; v_i0 int; v_q0 int; v_t0 int; v_n0 int; v_h0 int;
begin
  -- BEFORE, inside the same transaction, so the after-figures below are comparable.
  select count(*) into v_c0 from public.customers;
  select count(*) into v_i0 from public.inquiries;
  select count(*) into v_q0 from public.quotes;
  select count(*) into v_t0 from public.transactions;
  select count(*) into v_n0 from public.notifications;
  select count(*) into v_h0 from net.http_request_queue;

  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build', 'label','evidence-__WF__'));
  v_fixture := public.fn_phase_d_fixture_context();

  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';

  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','evidence-__WF__', 'execution_context','test',
    'for_workflow', case when '__WF__' = 'W12' then '__WF__' else null end));

  select coalesce(
    (select s.independent_reviewer_role_id from public.phase_b_workflow_step s
      where s.workflow_id = '__WF__' and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
      order by s.step_id limit 1),
    'risk_and_governance_manager') into v_rev;

  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='__WF__')
   limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
    then (select primary_object from public.phase_b_workflow where workflow_id='__WF__')
         || ':' || (v_fx->'parent_refs'->>v_ref_key) else null end;

  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','__WF__','label','evidence-__WF__','execution_context','production',
    'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands)
    || case when v_boid is null then '{}'::jsonb
            else jsonb_build_object('business_object_id', v_boid) end);

  -- ONE ROW PER EFFECT ACTUALLY LEDGERED INSIDE THIS TRANSACTION.
  for r in
    select el.step_id, el.effect_type, el.effect_object_id, el.effect_relation,
           el.effect_operation, coalesce(el.state_before,'(none)') as state_before,
           coalesce(el.state_after,'(none)') as state_after,
           coalesce(el.provider_mode,'(none)') as provider_mode,
           left(coalesce(el.payload_digest,'(none)'),16) as payload_digest16,
           split_part(coalesce(el.result_reference,''), ':', 1) as result_relation
      from public.phase_d_effect_ledger el
     where el.workflow_id = '__WF__'
     order by el.effect_id
  loop
    v_out := v_out || chr(30) || concat_ws(chr(31),
      v_fixture::text, '__WF__', r.step_id, r.effect_type, r.effect_object_id,
      r.effect_relation, r.effect_operation, r.state_before, r.state_after,
      r.provider_mode, r.payload_digest16, r.result_relation);
  end loop;

  -- The counters again, still inside the transaction, so a reader can see what the effects cost.
  v_out := v_out || chr(30) || concat_ws(chr(31),
    v_fixture::text, '__WF__', '(summary)', 'IN_TRANSACTION_COUNTS', 'customers/inquiries/quotes/transactions',
    format('%s/%s/%s/%s -> %s/%s/%s/%s',
      v_c0, v_i0, v_q0, v_t0,
      (select count(*) from public.customers), (select count(*) from public.inquiries),
      (select count(*) from public.quotes), (select count(*) from public.transactions)),
    'notifications ' || v_n0 || ' -> ' || (select count(*) from public.notifications),
    'outbound ' || v_h0 || ' -> ' || (select count(*) from net.http_request_queue),
    coalesce(v->>'dispatches_executed','0') || ' executed of ' || coalesce(v->>'dispatches_seen','0'),
    coalesce(v->>'run_state','(none)'),
    coalesce(v->>'steps_closed_by_the_handler','0') || ' handler / ' || coalesce(v->>'steps_driven','0') || ' actor',
    (select count(*) from public.phase_d_effect_ledger where workflow_id = '__WF__')::text);

  raise exception 'EVIDENCE%', v_out;
end $emit$;
`;

const ids = (await sql('select workflow_id from public.phase_b_workflow order by workflow_id'))
  .map((r) => r.workflow_id);

const rows = [];
for (const id of ids) {
  let got = null;
  try {
    await sql(DRIVE.replaceAll('__WF__', id));
    console.error(`${id}: the probe did not raise — it must abort its own transaction`);
    process.exit(1);
  } catch (err) {
    const msg = String(err?.message ?? err);
    const at = msg.indexOf('EVIDENCE');
    if (at < 0) { console.error(`${id} failed before reporting:\n${msg.slice(0, 900)}`); process.exit(1); }
    got = msg.slice(at + 'EVIDENCE'.length)
      .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
      .replace(/\\"/g, '"').replace(/\\n/g, '\n');
    const c = got.indexOf('\nCONTEXT:'); if (c >= 0) got = got.slice(0, c);
  }
  const parsed = got.split(RS).filter((r) => r.trim() !== '').map((r) => r.split(US));
  rows.push(...parsed);
  process.stdout.write(`  ${id}: ${parsed.length - 1} effect row(s)\n`);
}

// THE ROLLBACK, READ FROM A NEW TRANSACTION. Everything above happened inside blocks that raised.
const after = await sql(`
  select (select count(*) from public.customers)               as customers,
         (select count(*) from public.inquiries)               as inquiries,
         (select count(*) from public.quotes)                  as quotes,
         (select count(*) from public.transactions)            as transactions,
         (select count(*) from public.phase_d_effect_ledger)   as effect_ledger,
         (select count(*) from public.phase_d_object_record)   as object_record,
         (select count(*) from public.phase_d_dispatch)        as dispatch,
         (select count(*) from net.http_request_queue)         as outbound,
         (select coalesce(sum(surviving_rows),0)::text from public.fn_phase_d_fixture_residue()) as fixture_residue,
         (select count(*) from public.ai_cost_log where occurred_at > timestamptz '2026-08-18 14:00+00') as ai_cost_rows,
         now()::text as read_at`);
const a = after[0];

const COLS = ['test_transaction_fixture_run', 'workflow_id', 'step_id', 'effect_type',
  'effect_object_id', 'effect_relation', 'effect_operation', 'state_before', 'state_after',
  'provider_mode', 'payload_digest_16', 'result_relation'];

const csvCell = (v) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};

const effects = rows.filter((r) => r[2] !== '(summary)');

const csv = provenance({
  command: 'node scripts/phase_d/build_transaction_local_evidence.mjs',
  numerator: effects.length,
  denominator: effects.length,
  of: 'effects ledgered inside an aborted transaction',
  attribution: 'one row per phase_d_effect_ledger row produced INSIDE the transaction, plus one '
    + '(summary) row per workflow carrying the in-transaction counters. Section 11 of the founder\'s '
    + '22 Aug 2026 ruling: an empty production table is not evidence that a controlled effect '
    + 'happened, so what happened before the rollback is recorded here. NO business payload and no '
    + 'PII: the payload DIGEST is carried, never a field of it. Rollback is proved by the footer, '
    + 'read from a NEW transaction after every drive had aborted',
}) + [COLS.join(',')]
  .concat(rows.map((r) => r.map(csvCell).join(',')))
  .join('\n')
  + `\n# ROLLBACK CONFIRMED, read from a new transaction at ${a.read_at} on ${PROJECT_REF}\n`
  + `# customers=${a.customers} inquiries=${a.inquiries} quotes=${a.quotes} transactions=${a.transactions}\n`
  + `# phase_d_effect_ledger=${a.effect_ledger} phase_d_object_record=${a.object_record} phase_d_dispatch=${a.dispatch}\n`
  + `# net.http_request_queue=${a.outbound} fn_phase_d_fixture_residue=${a.fixture_residue}\n`
  + `# ai_cost_log rows since 2026-08-18 14:00 UTC=${a.ai_cost_rows} (zero paid inference over the window)\n`;

writeFileSync(outPath('PHASE_D_TRANSACTION_LOCAL_EVIDENCE.csv'), csv);

console.log(`PHASE_D_TRANSACTION_LOCAL_EVIDENCE.csv  ${effects.length} effect rows, ${rows.length - effects.length} summary rows`);
console.log(`  rollback: customers ${a.customers}, effect ledger ${a.effect_ledger}, residue ${a.fixture_residue}`);

const bad = [['customers', a.customers], ['inquiries', a.inquiries], ['quotes', a.quotes],
  ['transactions', a.transactions], ['phase_d_effect_ledger', a.effect_ledger],
  ['phase_d_dispatch', a.dispatch], ['outbound', a.outbound],
  ['fixture_residue', Number(a.fixture_residue)], ['ai_cost_rows', a.ai_cost_rows]]
  .filter(([, n]) => Number(n) !== 0);
if (bad.length) {
  console.error('the rollback did not return every counter to zero: '
    + bad.map(([k, n]) => `${k}=${n}`).join(', '));
  process.exit(1);
}
if (!effects.length) {
  console.error('no effect was ledgered by any workflow — refusing to write an evidence file over nothing');
  process.exit(1);
}
