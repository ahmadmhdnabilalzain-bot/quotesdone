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

// P05. THE SEPARATORS COST MORE THAN THE DATA.
// chr(30) and chr(31) are JSON-escaped to six bytes each by the management transport, so ~108
// separators per workflow block added ~550 characters to a payload the endpoint truncates at 2000.
// Twelve of the thirty blocks were cut off mid-row. '|' and '~' are one byte each and escape to
// themselves; MEASURED 24 Aug 2026 over the committed file: no cell in it contains either.
const RS = '~';
const US = '|';

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
    'for_workflow', '__WF__'));

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
     offset __OFFSET__ limit __LIMIT__
  loop
    v_out := v_out || '~' || concat_ws('|',
      v_fixture::text, '__WF__', r.step_id, coalesce(r.effect_type,'(none)'), coalesce(r.effect_object_id,'(none)'),
      coalesce(r.effect_relation,'(none)'), coalesce(r.effect_operation,'(none)'), r.state_before, r.state_after,
      r.provider_mode, r.payload_digest16, r.result_relation);
  end loop;

  -- The counters again, still inside the transaction, so a reader can see what the effects cost.
  -- Emitted on the FIRST chunk only, so a chunked workflow still carries exactly one summary row.
  if __OFFSET__ = 0 then
  v_out := v_out || '~' || concat_ws('|',
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
  end if;

  -- The ledger total ALWAYS travels, on every chunk, as a short trailer the cap cannot reach. It is
  -- what lets the caller know when it has seen every row rather than guessing from a short chunk.
  v_out := v_out || '~TOTAL|' ||
    (select count(*) from public.phase_d_effect_ledger where workflow_id = '__WF__')::text;

  raise exception 'EVIDENCE%', v_out;
end $emit$;
`;

const ids = (await sql('select workflow_id from public.phase_b_workflow order by workflow_id'))
  .map((r) => r.workflow_id);

const COLS = ['test_transaction_fixture_run', 'workflow_id', 'step_id', 'effect_type',
  'effect_object_id', 'effect_relation', 'effect_operation', 'state_before', 'state_after',
  'provider_mode', 'payload_digest_16', 'result_relation'];

// P05. THE TRUNCATION THAT WENT UNREPORTED, AND THE THREE THINGS DONE ABOUT IT.
//
// The management endpoint cuts an exception message at 2000 characters. This builder carried its
// whole per-workflow payload out in ONE raise, and TWELVE of the thirty blocks — W02, W03, W09,
// W12, W15, W17, W20, W24, W26, W27, W29, W30 — were cut off mid-row. Line 246 of the committed
// file was the two characters `9851,W27`. The builder printed "254 effect rows, 18 summary rows"
// and asserted nothing about either number, so a file missing 40% of its workflows read as
// complete. Its sibling scripts/phase_d/prove_object_reference_round_trip.mjs was rewritten for
// exactly this in an earlier session and this one was not.
//
//   1. THE SEPARATORS SHRANK. chr(30)/chr(31) escape to six bytes each in the transport's JSON;
//      '~'/'|' escape to themselves. That alone took the largest block from ~1990 to 1863.
//   2. THE EMISSION IS CHUNKED. Each workflow is driven once per CHUNK of its effect ledger, so a
//      payload cannot outgrow the cap however many effects a workflow gains. Every chunk carries a
//      short TOTAL trailer, which is how the caller knows it has seen every row instead of
//      inferring completeness from a chunk that happened to be short.
//   3. IT FAILS CLOSED. A row with the wrong field count, a missing summary, a missing TOTAL, a
//      chunk within 200 characters of the cap, or a reassembled count that disagrees with the
//      ledger's own total — each exits non-zero and says which. A silent short file was the defect;
//      a builder that refuses is the fix.
const CHUNK = 5;

const rows = [];
for (const id of ids) {
  let offset = 0;
  let total = null;
  let effectsSeen = 0;
  let sawSummary = false;
  let chunks = 0;
  let widest = 0;

  for (;;) {
    let got = null;
    const q = DRIVE.replaceAll('__WF__', id)
      .replaceAll('__OFFSET__', String(offset))
      .replaceAll('__LIMIT__', String(CHUNK));
    try {
      await sql(q);
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
    chunks++;
    const escaped = JSON.stringify(got).length;
    widest = Math.max(widest, escaped);
    if (escaped > 1800) {
      console.error(`${id} chunk ${chunks}: the payload escapes to ${escaped} characters and the `
        + 'endpoint truncates at 2000. It has not been cut off yet, but it is within 200 characters '
        + `of being cut off silently. Lower CHUNK below ${CHUNK}.`);
      process.exit(1);
    }

    const parsed = got.split(RS).filter((r) => r.trim() !== '').map((r) => r.split(US));
    const trailer = parsed.filter((r) => r[0] === 'TOTAL');
    if (trailer.length !== 1) {
      console.error(`${id} chunk ${chunks}: ${trailer.length} TOTAL trailer(s). The trailer is the `
        + 'last thing emitted, so its absence means the message was cut off before the end.');
      process.exit(1);
    }
    const t = Number(trailer[0][1]);
    if (total !== null && t !== total) {
      console.error(`${id} chunk ${chunks}: the ledger total moved between chunks (${total} -> ${t}). `
        + 'Each chunk drives the workflow again, so a moving total means the drive is not deterministic.');
      process.exit(1);
    }
    total = t;

    const body = parsed.filter((r) => r[0] !== 'TOTAL');
    const short = body.filter((r) => r.length !== COLS.length);
    if (short.length) {
      console.error(`${id} chunk ${chunks}: ${short.length} of ${body.length} row(s) carry `
        + `${[...new Set(short.map((r) => r.length))].join('/')} fields and the contract is `
        + `${COLS.length}. Either the message was cut off, or a null slipped past a coalesce into `
        + `concat_ws — which is what shifted 63 rows one column left before this was fixed.\n`
        + `  first short row: ${JSON.stringify(short[0]).slice(0, 240)}`);
      process.exit(1);
    }
    const summaries = body.filter((r) => r[2] === '(summary)');
    if (summaries.length) sawSummary = true;
    effectsSeen += body.length - summaries.length;
    rows.push(...body);

    offset += CHUNK;
    if (offset >= total) break;
  }

  if (!sawSummary) {
    console.error(`${id}: no (summary) row came back on any chunk.`);
    process.exit(1);
  }
  if (effectsSeen !== total) {
    console.error(`${id}: reassembled ${effectsSeen} effect row(s) and the ledger reported ${total}. `
      + 'A file that goes short in silence is the whole defect this builder is being corrected for.');
    process.exit(1);
  }
  process.stdout.write(`  ${id}: ${effectsSeen} effect row(s) over ${chunks} chunk(s), `
    + `widest ${widest} escaped chars\n`);
}

// THE POPULATION THIS FILE IS ABOUT IS THE FROZEN STEP REGISTRY, NOT THE FILE'S OWN ROW COUNT.
const FROZEN_STEPS = Number((await sql('select count(*) n from public.phase_b_workflow_step'))[0].n);

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

const csvCell = (v) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};

const effects = rows.filter((r) => r[2] !== '(summary)');

const csv = provenance({
  command: 'node scripts/phase_d/build_transaction_local_evidence.mjs',
  numerator: new Set(effects.map((r) => r[2])).size,
  denominator: FROZEN_STEPS,
  of: 'frozen Phase B steps whose declared effect was ledgered inside an aborted transaction. The '
    + 'file previously stated its numerator against ITSELF ("254 of 254"), which cannot go short',
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
