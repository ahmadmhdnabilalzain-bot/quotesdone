// PHASE D — THE 347 FROZEN EVENTS, OBSERVED TRANSACTION-LOCALLY.
//
//   node scripts/phase_d/observe_events_live.mjs [--only=W01,W02] [--jobs=3]
//
// public.phase_d_event_reconciliation held 347 rows and 333 of them said NEVER_OBSERVED. The
// fourteen that did not were the residue of earlier single-workflow drives. A registry row saying
// CONNECTED is a claim about the wiring; it is not an observation of an emission, and this estate
// has already recorded once that 347 event bindings said CONNECTED with one producer, no consumer
// and no cron.
//
// This driver observes them. Two aborted transactions per workflow:
//
//   PASS   drive the workflow through the kernel's own doors to its terminal state and read every
//          row public.fn_kernel_outbox_emit wrote into public.phase_c_event_outbox in THIS
//          transaction. That covers the started event, one completed event per step the drive
//          reached, and the workflow-completed event.
//   FAIL   drive again with the first step held open and fail it through fn_kernel_step_complete,
//          which is what produces the workflow's blocked/failure event.
//
// Nothing survives: both transactions end in `raise exception`, and the outbox rows are counted
// inside the transaction that wrote them, so the count cannot pick up another session's work.
//
// WHAT IS RECORDED AND WHAT IS NOT. A row moves to OBSERVED_IN_OUTBOX only when a row carrying its
// event_id was actually read back. An event no drive emits keeps NEVER_OBSERVED and the deliverable
// says so: a registry-only event reported as observed is the defect this file exists to prevent.
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

function passArm(wf) {
  return `do $ev$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_run bigint; v_ob0 bigint; v_out text := ''; r record;
begin${PRE(wf, `ev-${wf.toLowerCase()}`, false)}
  for r in
    select o.event_id, count(*) n
      from public.phase_c_event_outbox o
     where o.outbox_id > v_ob0 and coalesce(btrim(o.event_id),'') <> ''
     group by o.event_id order by o.event_id
  loop
    v_out := v_out || r.event_id || ':' || r.n::text || ' ';
  end loop;
  v_out := 'PASS ' || coalesce((select state from public.phase_c_workflow_run where run_id = v_run),'-')
        || ' | ' || v_out;
  if length(v_out) > 1750 then
    raise exception 'PHASE_D_EVENT_OVERFLOW ${wf} produced % characters over the 1750 this transport carries; emit per step instead of per workflow.', length(v_out);
  end if;
  raise exception 'EVT<<%>>', v_out;
end $ev$;`;
}

function failArm(wf) {
  return `do $ev$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_run bigint; v_ob0 bigint; v_out text := '';
        v_srid bigint; r record;
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
    v_out := 'stepfail=' || left(regexp_replace(SQLERRM,'[|~<>]',' ','g'), 120) || ' ';
  end;
  perform set_config('app.phase_d_hold_step','', true);
  for r in
    select o.event_id, count(*) n
      from public.phase_c_event_outbox o
     where o.outbox_id > v_ob0 and coalesce(btrim(o.event_id),'') <> ''
     group by o.event_id order by o.event_id
  loop
    v_out := v_out || r.event_id || ':' || r.n::text || ' ';
  end loop;
  v_out := 'FAIL ' || coalesce((select state from public.phase_c_workflow_run where run_id = v_run),'-')
        || ' | ' || v_out;
  raise exception 'EVT<<%>>', v_out;
end $ev$;`;
}

const seen = new Map();   // event_id -> emissions observed
const notes = [];
let done = 0;
async function worker(queue) {
  for (;;) {
    const wf = queue.shift();
    if (!wf) return;
    for (const q of [passArm(wf), failArm(wf)]) {
      const raw = await emit(q, 'EVT');
      if (raw.startsWith('ERROR:')) { notes.push(`${wf} ${raw.slice(0, 160)}`); continue; }
      const body = raw.split('|').slice(1).join('|').trim();
      notes.push(`${wf} ${raw.split('|')[0].trim()}`);
      for (const tok of body.split(/\s+/).filter(Boolean)) {
        const i = tok.lastIndexOf(':');
        const id = tok.slice(0, i), n = Number(tok.slice(i + 1)) || 0;
        seen.set(id, (seen.get(id) || 0) + n);
      }
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
const lit = s => `'${String(s).replace(/'/g, "''")}'`;
const rows = [...seen].filter(([id]) => known.has(id));
for (let i = 0; i < rows.length; i += 300) {
  const chunk = rows.slice(i, i + 300);
  await sql(`update public.phase_d_event_reconciliation r
       set runtime_observation = 'OBSERVED_IN_OUTBOX',
           emissions_observed = v.n,
           first_observed_at = coalesce(r.first_observed_at, now()),
           last_observed_at = now(),
           reconciled_at = now()
      from (values ${chunk.map(([id, n]) => `(${lit(id)},${n})`).join(',')}) as v(event_id, n)
     where r.event_id = v.event_id`);
}

const total = (await sql('select count(*) n from public.phase_d_event_reconciliation'))[0].n;
const obs = (await sql(`select count(*) n from public.phase_d_event_reconciliation
                         where runtime_observation = 'OBSERVED_IN_OUTBOX'`))[0].n;
const unknown = [...seen.keys()].filter(id => !known.has(id));

console.log(`\nfrozen events in the register        ${total}`);
console.log(`observed in the outbox, this run     ${rows.length}`);
console.log(`observed in the outbox, cumulative   ${obs} of ${total}`);
console.log(`emitted ids not in the register      ${unknown.length}${unknown.length ? ' — ' + unknown.slice(0, 10).join(', ') : ''}`);
if (notes.length) { console.log('\nper arm:'); for (const n of notes) console.log('  ' + n); }
