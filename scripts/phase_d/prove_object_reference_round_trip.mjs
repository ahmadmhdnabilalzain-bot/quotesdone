// PHASE D — §2 ROUND-TRIP REFERENCE PROOF, all 56 frozen business objects.
//
// The founder's ruling of 23 Aug 2026, section 2: for every object, inside an aborted transaction,
// create it through its canonical service, capture the returned canonical reference, resolve that
// reference through the canonical reader, prove the exact object and version comes back, replay the
// creation with the same idempotency key, prove no second object appears, roll back, and prove the
// persistent counts returned to baseline.
//
//   node scripts/phase_d/prove_object_reference_round_trip.mjs
//
// THE VERDICT PER OBJECT IS FOUR CHARACTERS, AND THAT IS DELIBERATE. The management endpoint
// truncates an exception message at 2000 characters, and the first version of this probe emitted a
// wide row per object and was cut off at object twelve — reporting 12 of 56 as though that were the
// population. The probe now carries a compact verdict out of the transaction and joins the
// descriptive columns from the registry afterwards, so a truncated result is impossible rather than
// merely unlikely.
//
// WHAT COUNTS AS A PASS, stated because a round trip that resolves the wrong row would otherwise
// look identical to one that resolves the right one:
//   O  the resolved object_id equals the one the reference names
//   I  the resolved canonical_identity equals the one the reference carries
//   V  the resolved version equals the one the reference carries
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql, PROJECT_REF } from '../lib/db.mjs';

const RS = String.fromCharCode(30);
const US = String.fromCharCode(31);

const PROBE = `
do $emit$
declare
  v_fx jsonb; v_out text := ''; r record; v_res jsonb;
  v_o boolean; v_i boolean; v_v boolean;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','refroundtrip'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','refroundtrip','execution_context','test'));

  for r in
    select s.object_id, sc.canonical_ref
      from public.phase_d_object_reference_strategy s
      left join public.phase_d_scenario_record sc
        on sc.object_id = s.object_id
       and sc.fixture_run_id = public.fn_phase_d_fixture_context()
     order by s.object_id
  loop
    -- TWO CHARACTERS PER OBJECT, IN REGISTRY ORDER, AND NO NAMES. The names cost the 56th object
    -- its place in a 2000-character message on the previous version of this probe, which reported
    -- 55 verdicts and would have been written as a complete result had the guard below not existed.
    if r.canonical_ref is null then
      v_out := v_out || 'N-';
      continue;
    end if;
    begin
      v_res := public.fn_phase_d_ref_resolve(r.canonical_ref);
      v_o := (v_res->>'object_id') is not distinct from (r.canonical_ref->>'object_id');
      v_i := (v_res->>'canonical_identity') is not distinct from (r.canonical_ref->>'canonical_identity');
      v_v := coalesce((v_res->>'version')::int,-1) = coalesce((r.canonical_ref->>'version')::int,-1);
      v_out := v_out || case when v_o and v_i and v_v then 'T' else 'M' end
            || case when not v_o then 'o' when not v_i then 'i' when not v_v then 'v' else '-' end;
    exception when others then
      v_out := v_out || 'R-';
    end;
  end loop;

  raise exception 'REFTRIP%', v_out;
end $emit$;
`;

const REPLAY = `
do $emit$
declare v_a jsonb; v_b jsonb; v_objs int; v_dupes int;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','refreplay'));
  v_a := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','refreplay','execution_context','test'));
  v_b := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','refreplay','execution_context','test'));
  select count(*) into v_objs from public.phase_d_object_record where superseded_by is null;
  select count(*) into v_dupes from (
    select object_id, business_key from public.phase_d_object_record
     where superseded_by is null group by object_id, business_key having count(*) > 1) d;
  raise exception 'REPLAY%', concat_ws(chr(31),
    coalesce(v_a->>'stages_created','?'), coalesce(v_b->>'stages_created','?'),
    v_objs::text, v_dupes::text);
end $emit$;
`;

// ---- THE INTENT ARM: an object Phase D never writes into a relation --------------------------
//
// `notification` was the 56th object and the one the fixture factory could not create. A stage for
// it was built, measured clean and REMOVED, because two kernel boards refuse it —
// fn_phase_d_effect_state.phase_d_write_maps_into_the_outbound_notification_table and
// fn_phase_d_fixture_state.fixture_stage_targeting_public_notifications. Neither asks whether the
// row would be deliverable, and that is deliberate: the outbound queue is a live delivery surface
// and a suppressed row in it is still a row in it.
//
// THE DECISION, 23 Aug 2026: the boards stay exactly as they are, and the object is proved the
// other way the founder's section 4 allows — somewhere other than the fixture factory.
//
// It is not a workaround, because it is what the frozen contract already says. Measured on
// public.phase_d_step_effect: all seven steps of W13, the governing workflow, declare
//   expected_effect_type  EXTERNAL_EFFECT_INTENT
//   effect_relation       public.phase_d_effect_ledger      <- not public.notifications
//   effect_service        public.fn_phase_d_effect_produce(jsonb)
//   completion_condition  "a phase_d_effect_ledger row exists with provider_mode = mock and no
//                          provider request id"
// and a third board, notification_effects_not_classified_as_intent, holds that shape in place.
// Phase D's canonical creation of a notification IS the intent record. The object binding's
// canonical_relation names where a DELIVERED notification lives, which is a different subject and
// is not Phase D's to write while the automation hold stands.
//
// So the arm drives W13 through the ordinary doors and asserts, on the run's own ledger rows:
//   O  the effect names this object
//   I  the result_reference is present and resolves back to exactly the effect that wrote it
//   V  provider_mode is mock/disabled/none and public.notifications gained NO row
// A row that fails any of those is a mismatch here exactly as it is in the stage arm. The verdict
// is reported under its own name, ROUND_TRIPPED_AS_EXTERNAL_EFFECT_INTENT, so nobody reads it as a
// relation round trip.
const INTENT_OBJECTS = await sql(`
  select b.object_id, b.governing_workflow_id
    from public.phase_d_business_object_binding b
   where not exists (select 1 from public.phase_d_fixture_stage s where s.object_id = b.object_id)
     and exists (select 1 from public.phase_d_step_effect e where e.effect_object_id = b.object_id)
     and not exists (select 1 from public.phase_d_step_effect e
                      where e.effect_object_id = b.object_id
                        and e.expected_effect_type <> 'EXTERNAL_EFFECT_INTENT')
   order by b.object_id`);

const INTENT_PROBE = (objectId, wf) => `
do $emit$
declare
  v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_ref_key text; v_boid text;
  v_n0 bigint; v_rows int; v_named int; v_resolved int; v_live int; v_noref int;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','refintent-${objectId}'));
  select count(*) into v_n0 from public.notifications;
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','refintent-${objectId}','execution_context','test'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${wf}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${wf}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${wf}','label','refintent-${objectId}','execution_context','production',
    'reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);

  select count(*) into v_rows from public.phase_d_effect_ledger
   where run_id = (v->>'run_id')::bigint and effect_type = 'EXTERNAL_EFFECT_INTENT';
  select count(*) into v_named from public.phase_d_effect_ledger
   where run_id = (v->>'run_id')::bigint and effect_type = 'EXTERNAL_EFFECT_INTENT'
     and effect_object_id = '${objectId}';
  select count(*) into v_noref from public.phase_d_effect_ledger
   where run_id = (v->>'run_id')::bigint and effect_type = 'EXTERNAL_EFFECT_INTENT'
     and coalesce(btrim(result_reference),'') = '';
  -- THE ROUND TRIP: the reference the effect returned, read back, must name that same effect and no
  -- other. A reference that resolves to two rows is not a reference.
  select count(*) into v_resolved from public.phase_d_effect_ledger el
   where el.run_id = (v->>'run_id')::bigint and el.effect_type = 'EXTERNAL_EFFECT_INTENT'
     and (select count(*) from public.phase_d_effect_ledger e2
           where e2.step_run_id = el.step_run_id and e2.result_reference = el.result_reference) = 1;
  select count(*) into v_live from public.phase_d_effect_ledger
   where run_id = (v->>'run_id')::bigint and effect_type = 'EXTERNAL_EFFECT_INTENT'
     and provider_mode not in ('mock','disabled','none');

  raise exception 'REFINTENT%', concat_ws(chr(31), '${objectId}', v_rows::text, v_named::text,
    v_resolved::text, v_noref::text, v_live::text,
    ((select count(*) from public.notifications) - v_n0)::text);
end $emit$;`;

function unwrap(msg, marker) {
  const at = msg.indexOf(marker);
  if (at < 0) return null;
  let got = msg.slice(at + marker.length)
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\"/g, '"').replace(/\\n/g, '\n');
  const c = got.indexOf('\nCONTEXT:'); if (c >= 0) got = got.slice(0, c);
  return got;
}

let raw = null;
try { await sql(PROBE); console.error('the probe did not raise'); process.exit(1); }
catch (err) {
  raw = unwrap(String(err?.message ?? err), 'REFTRIP');
  if (raw === null) { console.error('probe failed before reporting:\n' + String(err?.message ?? err).slice(0, 1500)); process.exit(1); }
}
const codes = raw.replace(/[^TMNRoiv-]/g, '');

const strategy = await sql(`select object_id, storage_kind, canonical_identity_type,
    physical_schema || '.' || physical_relation as physical_relation, physical_pk_column
  from public.phase_d_object_reference_strategy order by object_id`);

// A PROBE THAT REPORTED ON FEWER OBJECTS THAN EXIST IS NOT A RESULT.
if (codes.length !== strategy.length * 2) {
  console.error(`the probe returned ${codes.length / 2} verdict(s) for ${strategy.length} objects`);
  console.error('a partial round trip must never be written as a complete one');
  process.exit(1);
}
const verdictAt = (i) => codes.slice(i * 2, i * 2 + 2);

let replay = null;
try { await sql(REPLAY); console.error('the replay probe did not raise'); process.exit(1); }
catch (err) {
  replay = unwrap(String(err?.message ?? err), 'REPLAY');
  if (replay === null) { console.error('replay failed:\n' + String(err?.message ?? err).slice(0, 1200)); process.exit(1); }
}
const [stagesA, stagesB, liveObjects, dupes] = replay.split(US);

const after = await sql(`
  select (select count(*) from public.customers)             as customers,
         (select count(*) from public.inquiries)             as inquiries,
         (select count(*) from public.quotes)                as quotes,
         (select count(*) from public.transactions)          as transactions,
         (select count(*) from public.phase_d_object_record) as object_record,
         (select coalesce(sum(surviving_rows),0)::text from public.fn_phase_d_fixture_residue()) as residue,
         now()::text as read_at`);
const a = after[0];

// ---- run the intent arm ----------------------------------------------------------------------
const intentVerdict = new Map();
for (const o of INTENT_OBJECTS) {
  let got = null;
  try { await sql(INTENT_PROBE(o.object_id, o.governing_workflow_id)); }
  catch (err) { got = unwrap(String(err?.message ?? err), 'REFINTENT'); }
  if (got === null) {
    console.error(`the intent probe for ${o.object_id} did not report`);
    process.exit(1);
  }
  const [id, rows_, named, resolved, noref, live, notifDelta] = got.split(US);
  const ok = Number(rows_) > 0 && Number(named) === Number(rows_)
    && Number(resolved) === Number(rows_) && Number(noref) === 0
    && Number(live) === 0 && Number(notifDelta) === 0;
  intentVerdict.set(id, {
    ok,
    detail: `${rows_} intent effect(s), ${named} naming the object, ${resolved} resolving to exactly `
      + `one effect, ${noref} with no reference, ${live} claiming a live provider, `
      + `${notifDelta} row(s) added to public.notifications`,
  });
  console.log(`  intent arm ${id}: ${ok ? 'ROUND_TRIPPED_AS_EXTERNAL_EFFECT_INTENT' : 'FAILED'} — ${intentVerdict.get(id).detail}`);
}

const decode = (v) => v[0] === 'N' ? 'NOT_CREATED_BY_ANY_STAGE'
  : v[0] === 'R' ? 'REFUSED' : v[0] === 'T' ? 'ROUND_TRIPPED' : 'MISMATCH';
// The second character names the FIRST dimension that failed, so a mismatch says which one.
const flag = (v, ch) => v[0] === 'T' ? 'true'
  : v[0] === 'M' ? (v[1] === ch.toLowerCase() ? 'false' : 'true') : '';

const COLS = ['object_id', 'storage_kind', 'canonical_identity_type', 'physical_relation',
  'physical_pk_column', 'round_trip', 'same_object', 'same_identity', 'same_version'];
const cell = (v) => { const s = v == null ? '' : String(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };

const rows = strategy.map((s, i) => {
  const v = verdictAt(i);
  // An object the stage arm could not create, and the intent arm did, carries the intent arm's
  // verdict under its own name. The stage arm's 'N' is left in place for anything the intent arm
  // did not settle, so an unproved object is never silently upgraded.
  const iv = intentVerdict.get(s.object_id);
  if (iv && v[0] === 'N') {
    return [s.object_id, s.storage_kind, s.canonical_identity_type, s.physical_relation,
      s.physical_pk_column,
      iv.ok ? 'ROUND_TRIPPED_AS_EXTERNAL_EFFECT_INTENT' : 'INTENT_ARM_FAILED',
      iv.ok ? 'true' : 'false', iv.ok ? 'true' : 'false', iv.ok ? 'true' : 'false'];
  }
  return [s.object_id, s.storage_kind, s.canonical_identity_type, s.physical_relation,
    s.physical_pk_column, decode(v), flag(v, 'O'), flag(v, 'I'), flag(v, 'V')];
});

const tripped = rows.filter((r) => r[5] === 'ROUND_TRIPPED').length;
const trippedIntent = rows.filter((r) => r[5] === 'ROUND_TRIPPED_AS_EXTERNAL_EFFECT_INTENT').length;
const intentFailed = rows.filter((r) => r[5] === 'INTENT_ARM_FAILED');
const mismatch = rows.filter((r) => r[5] === 'MISMATCH');
const refused = rows.filter((r) => r[5] === 'REFUSED');
const nostage = rows.filter((r) => r[5] === 'NOT_CREATED_BY_ANY_STAGE');

const csv = provenance({
  command: 'node scripts/phase_d/prove_object_reference_round_trip.mjs',
  numerator: tripped + trippedIntent,
  denominator: rows.length,
  of: `frozen business objects have a proved creation path: ${tripped} round-tripped through a canonical relation row and ${trippedIntent} through the declared external-effect intent that is the whole of Phase D’s creation contract for it`,
  attribution: 'one row per object in public.phase_d_object_reference_strategy. The scenario factory '
    + 'creates what it creates through the canonical write services inside a transaction that is '
    + 'aborted; each created object is resolved back through fn_phase_d_ref_resolve and the resolved '
    + 'object, canonical_identity and version are compared with the reference the writer returned. An '
    + 'object no stage creates is reported NOT_CREATED_BY_ANY_STAGE and is never counted as a pass',
}) + [COLS.join(',')].concat(rows.map((r) => r.map(cell).join(','))).join('\n')
  + `\n# REPLAY: the same scenario driven twice in one transaction produced ${stagesA} then ${stagesB} stages,`
  + ` ${liveObjects} live object records and ${dupes} duplicate (object_id, business_key) pairs\n`
  + `# ROLLBACK CONFIRMED from a new transaction at ${a.read_at} on ${PROJECT_REF}:`
  + ` customers=${a.customers} inquiries=${a.inquiries} quotes=${a.quotes} transactions=${a.transactions}`
  + ` phase_d_object_record=${a.object_record} residue=${a.residue}\n`;

writeFileSync(outPath('PHASE_D_OBJECT_REFERENCE_ROUND_TRIP.csv'), csv);

console.log(`PHASE_D_OBJECT_REFERENCE_ROUND_TRIP.csv  ${rows.length} objects`);
console.log(`  round-tripped            ${tripped}`);
console.log(`  round-tripped as intent  ${trippedIntent}   (an object whose Phase D creation IS an external-effect intent)`);
console.log(`  mismatched               ${mismatch.length}   (must be 0)`);
console.log(`  refused                  ${refused.length}   (must be 0)`);
console.log(`  not created by any stage ${nostage.length}`);
console.log(`  replay duplicates        ${dupes}   (must be 0)`);
console.log(`  rollback: customers ${a.customers}, object_record ${a.object_record}, residue ${a.residue}`);
if (mismatch.length) console.log('  MISMATCHED: ' + mismatch.map((r) => r[0]).join(', '));
if (refused.length) console.log('  REFUSED: ' + refused.map((r) => r[0]).join(', '));
if (nostage.length) console.log('  NO STAGE: ' + nostage.map((r) => r[0]).join(', '));

const fatal = [];
if (mismatch.length) fatal.push(`${mismatch.length} round trips resolved the wrong object, identity or version`);
if (refused.length) fatal.push(`${refused.length} references could not be resolved at all`);
if (intentFailed.length) fatal.push(`${intentFailed.length} object(s) whose only creation path is an external-effect intent did not produce or resolve one`);
if (Number(dupes) !== 0) fatal.push(`replay created ${dupes} duplicate object identities`);
for (const [k, v] of Object.entries({ customers: a.customers, inquiries: a.inquiries, quotes: a.quotes,
  transactions: a.transactions, object_record: a.object_record, residue: Number(a.residue) })) {
  if (Number(v) !== 0) fatal.push(`${k} did not return to 0 after rollback (${v})`);
}
if (fatal.length) { console.error('FAILED: ' + fatal.join('; ')); process.exit(1); }
