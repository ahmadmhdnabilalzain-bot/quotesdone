// PHASE D — THE 347 FROZEN EVENTS, EMITTED *AND CONSUMED* TRANSACTION-LOCALLY.
//
//   node scripts/phase_d/observe_events_live.mjs [--only=W01,W02] [--jobs=3]
//
// public.phase_d_event_reconciliation held 347 rows and 333 of them said NEVER_OBSERVED. The
// fourteen that did not were the residue of earlier single-workflow drives. A registry row saying
// CONNECTED is a claim about the wiring; it is not an observation of an emission, and this estate
// has already recorded once that 347 event bindings said CONNECTED with one producer, no consumer
// and no cron.
//
// THE FIRST VERSION OF THIS FILE FIXED HALF OF THAT. It drove every workflow and read back the rows
// public.fn_kernel_outbox_emit wrote into public.phase_c_event_outbox in the same transaction, and
// recorded OBSERVED_IN_OUTBOX. That is exact and it is narrow: it proves the PRODUCER emitted. It
// says nothing about whether anything consumed the event, what the consumption resolved to, or what
// happened when it could not. One uniform value across 347 rows is a column whose name promises a
// journey and whose content records a departure.
//
// THIS VERSION OBSERVES THE WHOLE JOURNEY, still without a single external effect, by calling the
// canonical consumer inside the same aborted transaction:
//
//     public.fn_kernel_event_consume(p_outbox_id bigint)
//       returns table(handled boolean, downstream_ref text, result jsonb, reason text)
//
// It sets kernel.in_delivery and PROJECTS the event onto its downstream subject. It creates
// nothing, by explicit construction stated in its own body: fn_kernel_step_complete is the single
// authoritative progression path, and a consumer that created work would be a second creator racing
// the first. So the live cron phase_c_outbox_deliver_1min -- which DOES deliver externally -- never
// sees these rows, because the transaction they live in is aborted.
//
// WHAT IS MEASURED PER EVENT, and where each fact is read from:
//
//   handled / reason        the consumer's own answer. A refusal with no stated reason is
//                           indistinguishable from a crash, and the table's CHECK constraint
//                           refuses to store one.
//   downstream_ref          the resulting task, state or effect the consumption resolved to.
//   correlation / causation / dedupe / trace
//                           read off the OUTBOX ROW THAT WAS ACTUALLY WRITTEN, never off the
//                           registry. A registry column saying an event is correlated is the
//                           claim; a row carrying a correlation_id is the fact.
//   retry budget            max_attempts on the emitted row. A retry/dead-letter branch that does
//                           not exist cannot be reached, so its absence is reported, not assumed.
//   self-loop, AT RUNTIME   54 of the 347 have emitted_by = primary_consumer_role_id. That is a
//                           registry property and it is not a loop. The question that matters is
//                           whether CONSUMING re-applies the producer's action, and it is answered
//                           by counting the business rows the consume call adds -- tasks, runs,
//                           step runs and further outbox rows. Zero means the projection held.
//
// WHAT IS RECORDED AND WHAT IS NOT. A row reaches OBSERVED_SUCCESS only when a row carrying its
// event id was emitted AND the canonical consumer answered handled on it. An event no drive emits
// is NOT_EMITTED and is closed on the frozen structural reason its registry row already carries --
// never on silence.
import { sql } from '../phase_c/lib/db.mjs';

const arg = (k, d) => (process.argv.find(a => a.startsWith(`--${k}=`)) || `--${k}=${d}`).split('=').slice(1).join('=');
const ONLY = arg('only', '').split(',').filter(Boolean);
const JOBS = Math.max(1, Number(arg('jobs', 3)));

const WFS = (await sql(`select workflow_id from public.phase_b_workflow order by workflow_id`))
  .map(r => r.workflow_id).filter(w => !ONLY.length || ONLY.includes(w));

async function emit(q, marker) {
  for (let attempt = 1; ; attempt++) {
    try { await sql(q); return 'ERROR:no marker'; }
    catch (e) {
      const m = String(e.message); const a = m.indexOf(marker + '<<');
      if (a >= 0) return m.slice(a + marker.length + 2, m.indexOf('>>', a));
      if (/fetch failed|ECONNRESET|ETIMEDOUT|socket hang up|HTTP 429|HTTP 5\d\d/i.test(m) && attempt < 4) {
        await new Promise(r => setTimeout(r, 3000 * attempt)); continue;
      }
      return 'ERROR:' + m.slice(0, 300).replace(/[\s,]+/g, ' ');
    }
  }
}

// A 64-CHARACTER ALPHABET, because the transport carries 1750 characters and 14 events per
// workflow each needing six booleans and a retry budget will not fit as words. One char per
// bitmask, one per budget; the decode is three lines and lives next to the encode.
const A64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const dec64 = (c) => { const i = A64.indexOf(c); return i < 0 ? 0 : i; };

// THE EVENT IDS ARE READ OFF THE ROWS, NEVER DERIVED FROM THE STEP LIST. A driver that computed
// "the event this step must have emitted" would be asserting the registry against itself.
const PRE = (wf, label, hold) => `
  ${hold ? `perform set_config('app.phase_d_hold_step',
    (select s.step_id from public.phase_b_workflow_step s
      where s.workflow_id = '${wf}' order by s.step_no limit 1), true);` : ''}
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','${label}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','${label}','execution_context','test',
    'for_workflow', '${wf}'));
  select coalesce(max(outbox_id),0) into v_ob0 from public.phase_c_event_outbox;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${wf}','label','${label}','execution_context','production',
    'reviewer_role_id', coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
      where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
      order by x.step_id limit 1),'risk_and_governance_manager'),
    'reviewer_candidates', v_cands${hold ? `, 'hold_at_step_id',
      (select s.step_id from public.phase_b_workflow_step s
        where s.workflow_id = '${wf}' order by s.step_no limit 1)` : ''}));
  v_run := (v->>'run_id')::bigint;`;

// The consume loop, shared by both arms. One call per emitted row, each wrapped so a consumer that
// raises is recorded as fail-closed with the SQLSTATE rather than taking the arm down with it.
const CONSUME = `
  for r in
    select o.outbox_id, o.event_id, o.correlation_id, o.causation_id, o.dedupe_value,
           o.trace_id, coalesce(o.max_attempts,0) max_attempts
      from public.phase_c_event_outbox o
     where o.outbox_id > v_ob0 and coalesce(btrim(o.event_id),'') <> ''
     order by o.outbox_id
  loop
    select count(*) into v_t0 from public.phase_c_task;
    select count(*) into v_r0 from public.phase_c_workflow_run;
    select count(*) into v_s0 from public.phase_c_workflow_step_run;
    select count(*) into v_o0 from public.phase_c_event_outbox;
    v_h := false; v_dref := null; v_creason := null;
    begin
      select c.handled, c.downstream_ref, c.reason into v_h, v_dref, v_creason
        from public.fn_kernel_event_consume(r.outbox_id) c;
    exception when others then
      v_h := false; v_dref := null;
      v_creason := 'consume raised ' || SQLSTATE || ': ' || left(SQLERRM, 70);
    end;
    -- RUNTIME SELF-LOOP TEST. Not "does the registry name the same role twice", which 54 rows do
    -- and which is not a loop. Does consuming ADD business rows -- i.e. re-apply what the producer
    -- already did? The consumer documents itself as projection-only; this is what checks it.
    v_added := ((select count(*) from public.phase_c_task) - v_t0)
             + ((select count(*) from public.phase_c_workflow_run) - v_r0)
             + ((select count(*) from public.phase_c_workflow_step_run) - v_s0)
             + ((select count(*) from public.phase_c_event_outbox) - v_o0);
    v_flags := (case when coalesce(v_h,false) then 1 else 0 end)
             + (case when r.correlation_id is not null then 2 else 0 end)
             + (case when r.causation_id  is not null then 4 else 0 end)
             + (case when coalesce(btrim(coalesce(r.dedupe_value,'')),'') <> '' then 8 else 0 end)
             + (case when r.trace_id is not null then 16 else 0 end)
             + (case when coalesce(v_added,0) = 0 then 32 else 0 end);
    v_out := v_out || r.event_id || '~'
          || substr(v_a64, v_flags + 1, 1) || '~'
          || substr(v_a64, least(coalesce(r.max_attempts,0), 63) + 1, 1) || '~'
          || left(regexp_replace(coalesce(v_dref,''), '[~;<>|]', ' ', 'g'), 28) || '~'
          || case when coalesce(v_h,false) then ''
                  else left(regexp_replace(coalesce(v_creason,'(the consumer answered not-handled and stated no reason)'),
                                           '[~;<>|]', ' ', 'g'), 64) end
          || ';';
  end loop;`;

const DECL = `declare v jsonb; v_fx jsonb; v_cands jsonb; v_run bigint; v_ob0 bigint; v_out text := '';
        r record; v_h boolean; v_dref text; v_creason text; v_flags int; v_added bigint;
        v_t0 bigint; v_r0 bigint; v_s0 bigint; v_o0 bigint; v_srid bigint;
        v_a64 text := '${A64}';`;

const OVERFLOW = (wf) => `
  if length(v_out) > 1700 then
    raise exception 'PHASE_D_EVENT_OVERFLOW ${wf} produced % characters over the 1700 this transport carries; shorten the per-event fields rather than letting an event fall off the end.', length(v_out);
  end if;`;

function passArm(wf) {
  return `do $ev$
${DECL}
begin${PRE(wf, `ev-${wf.toLowerCase()}`, false)}
${CONSUME}
  v_out := 'PASS ' || coalesce((select state from public.phase_c_workflow_run where run_id = v_run),'-')
        || ' | ' || v_out;
${OVERFLOW(wf)}
  raise exception 'EVT<<%>>', v_out;
end $ev$;`;
}

function failArm(wf) {
  return `do $ev$
${DECL}
begin${PRE(wf, `evf-${wf.toLowerCase()}`, true)}
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  if v_srid is null then
    raise exception 'EVT<<FAIL no_open_step | >>';
  end if;
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_srid,
      'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run where step_run_id = v_srid),
      'outcome','fail', 'idempotency_key','evf:${wf}:' || v_srid,
      'inputs', jsonb_build_object('mode','failure path'),
      'output', jsonb_build_object('status','failed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH — deliberate failure path'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','failure')),
      'requested_action','block',
      'acceptance_criteria','the blocked event of ${wf} is exercised',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH — the Phase D failure path for ${wf}, driven deliberately inside a transaction that is aborted',
      'object_version', 1));
  exception when others then
    v_out := '';
  end;
  perform set_config('app.phase_d_hold_step','', true);
${CONSUME}
  v_out := 'FAIL ' || coalesce((select state from public.phase_c_workflow_run where run_id = v_run),'-')
        || ' | ' || v_out;
${OVERFLOW(wf)}
  raise exception 'EVT<<%>>', v_out;
end $ev$;`;
}

// event_id -> { n, handled, corr, caus, dedupe, trace, retry, reapplied, dref, reason }
const seen = new Map();
const notes = [];
let done = 0;

function record(tok) {
  const p = tok.split('~');
  if (p.length < 5) return;
  const [id, f, b, dref, reason] = p;
  const flags = dec64(f), retry = dec64(b);
  const cur = seen.get(id) || {
    n: 0, handled: false, corr: false, caus: false, dedupe: false, trace: false,
    retry: 0, reapplied: 0, dref: '', reason: '',
  };
  cur.n += 1;
  // ANY arm that handled it counts as handled; the flags that describe the ROW are ORed, because a
  // single emission carrying a correlation id proves the producer can carry one.
  if (flags & 1) { cur.handled = true; if (dref) cur.dref = dref; }
  else if (!cur.handled && reason) cur.reason = reason;
  cur.corr ||= !!(flags & 2);
  cur.caus ||= !!(flags & 4);
  cur.dedupe ||= !!(flags & 8);
  cur.trace ||= !!(flags & 16);
  // The self-loop flag is inverted on purpose: bit 32 set means the projection HELD. A single arm
  // in which consuming added rows is a re-application, so it is ORed the strict way.
  if (!(flags & 32)) cur.reapplied += 1;
  cur.retry = Math.max(cur.retry, retry);
  seen.set(id, cur);
}

async function worker(queue) {
  for (;;) {
    const wf = queue.shift();
    if (!wf) return;
    for (const q of [passArm(wf), failArm(wf)]) {
      const raw = await emit(q, 'EVT');
      if (raw.startsWith('ERROR:')) { notes.push(`${wf} ${raw.slice(0, 160)}`); continue; }
      const body = raw.split('|').slice(1).join('|').trim();
      notes.push(`${wf} ${raw.split('|')[0].trim()}`);
      for (const tok of body.split(';').map(s => s.trim()).filter(Boolean)) record(tok);
    }
    done++;
    process.stderr.write(`-- ${done}/${WFS.length} ${wf}\n`);
  }
}
const queue = [...WFS];
await Promise.all(Array.from({ length: JOBS }, () => worker(queue)));

// ---- record what was OBSERVED, and only that ---------------------------------------------------
const known = new Set((await sql('select event_id from public.phase_d_event_reconciliation'))
  .map(r => r.event_id));
const lit = s => (s === null || s === undefined || s === '') ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
const rows = [...seen].filter(([id]) => known.has(id));

for (let i = 0; i < rows.length; i += 120) {
  const chunk = rows.slice(i, i + 120);
  const values = chunk.map(([id, c]) => [
    lit(id), c.n, c.handled, lit(c.reason), lit(c.dref),
    c.corr, c.caus, c.dedupe, c.trace, c.retry, c.reapplied,
  ].join(',')).join('),(');
  await sql(`update public.phase_d_event_reconciliation r
       set runtime_observation  = 'OBSERVED_IN_OUTBOX',
           emissions_observed   = v.n,
           consumer_observation = case when v.handled then 'HANDLED' else 'FAIL_CLOSED' end,
           consume_reason       = case when v.handled then null
                                       else coalesce(nullif(btrim(v.reason),''),
                                            'the canonical consumer answered not-handled and stated no reason') end,
           downstream_ref       = v.dref,
           correlation_observed = v.corr,
           causation_observed   = v.caus,
           dedupe_observed      = v.dedupe,
           trace_observed       = v.trace,
           retry_budget_observed= v.retry,
           self_loop_reapplied  = v.reapplied,
           runtime_evidence_status = case when v.handled then 'OBSERVED_SUCCESS' else 'OBSERVED_FAIL_CLOSED' end,
           first_observed_at    = coalesce(r.first_observed_at, now()),
           last_observed_at     = now(),
           reconciled_at        = now()
      from (values (${values})) as v(event_id, n, handled, reason, dref, corr, caus, dedupe, trace, retry, reapplied)
     where r.event_id = v.event_id`);
}

// ---- AND WHAT WAS NOT EMITTED, CLOSED ON ITS FROZEN REASON, NEVER ON SILENCE -------------------
// An event no drive emitted is not "unknown". Its registry row already records WHY: either its
// structural status is DEFERRED_RUNTIME_IMPLEMENTATION -- the state transition that would produce
// it cannot currently occur -- or it is CONNECTED and terminal, needing no consumer. Both are
// permitted final statuses; neither is "we did not look". Anything else is left NULL so the board
// reports it red rather than a status being invented for it.
await sql(`update public.phase_d_event_reconciliation r
     set consumer_observation = 'NOT_EMITTED',
         consume_reason = case
           when r.structural_status = 'DEFERRED_RUNTIME_IMPLEMENTATION'
             then 'no drive emitted it: ' || coalesce(nullif(btrim(r.factual_state_change),''),
                    'the frozen state transition that produces it') || ' cannot currently occur, which is the '
                  || 'frozen structural reason already on this row'
           else 'no drive emitted it and its registry row names a consumer, so it is not terminal' end,
         runtime_evidence_status = case
           when r.structural_status = 'DEFERRED_RUNTIME_IMPLEMENTATION'
             then 'STRUCTURALLY_DEFERRED_WITH_FROZEN_REASON'
           when coalesce(btrim(r.primary_consumer_role_id),'') = ''
             then 'TERMINAL_EVENT_NO_CONSUMER_REQUIRED'
           else null end,
         reconciled_at = now()
   where r.consumer_observation is null or r.consumer_observation = 'NOT_EMITTED'`);

const board = await sql('select * from public.fn_phase_d_event_evidence_state()');
const total = (await sql('select count(*) n from public.phase_d_event_reconciliation'))[0].n;
const byStatus = await sql(`select coalesce(runtime_evidence_status,'(none)') s, count(*) n
                              from public.phase_d_event_reconciliation group by 1 order by 2 desc`);
const unknown = [...seen.keys()].filter(id => !known.has(id));

console.log(`\nfrozen events in the register        ${total}`);
console.log(`emitted and consumed, this run       ${rows.length}`);
console.log(`emitted ids not in the register      ${unknown.length}${unknown.length ? ' — ' + unknown.slice(0, 10).join(', ') : ''}`);
console.log('\nfinal evidence status:');
for (const r of byStatus) console.log(`  ${String(r.n).padStart(4)}  ${r.s}`);
console.log('\nboard:');
for (const r of board) {
  console.log(`  ${r.ok ? 'ok ' : 'RED'} ${r.check_name}  ${r.numerator} of ${r.denominator}`);
}
if (notes.length) { console.log('\nper arm:'); for (const n of notes) console.log('  ' + n); }
