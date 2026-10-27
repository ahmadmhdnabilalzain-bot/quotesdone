// RETIRED 7 SEPTEMBER 2026 — ITS SUBJECT WAS REMOVED, NOT BROKEN.
//
// This asserted that every active kernel signal type resolves to something that can execute it.
//
// On 7 September 2026 the founder removed, in his own words: the organisation chart ("remove the
// whole organization chart that you made cause its trash"), every pre-programmed workflow ("i dont
// want any pre programmed workflow as things will totally be different"), and finally the kernel
// gates themselves ("i said remove the kernel gates").
//
// What is gone: 30 workflows, 257 steps, 8 handoffs, 347 events, 56 business objects, 54 rules, 32
// gates, every Phase C binding, every Phase D handler schema and fixture, 41 event subscriptions,
// 94 action executors, and the 36 kernel write/trace/parent-delete gate triggers.
//
// So this file is not red because the estate regressed. It is red because every noun in it was
// deliberately deleted. It is RETIRED rather than edited down to something that passes: a check
// rewritten until it goes green against an empty schema asserts nothing while still looking like a
// guard, and that is worse than no check at all.
//
// WHAT REPLACES IT: nothing yet, and that is said plainly rather than hidden. When the new
// structure exists it deserves checks written fresh against THAT structure. Do not recover this
// file; write the new one from what the company then is.
//
// WHAT STILL GUARDS THE ESTATE TODAY, all green: kernel_invariants,
// cancellation_reaches_the_kernel, every_discharge_claim_reaches_its_table,
// anon_cannot_execute_security_definer (security, and it never depended on the org),
// phase_c_components_are_owned, canonical_routine_manifest, export_from_either_source_is_identical
// and receipts_never_wait_on_the_founder.
//
// Removed from .github/workflows/project-parity.yml in the same commit. Do not re-add this file.

/* eslint-disable */
// EVERY ACTIVE SIGNAL TYPE IS DRIVEN, NOT ASSERTED.
//
// Root cause 3 of the final Phase C acceptance. Ten of the twelve ACTIVE EXISTING_WORKFLOW_SIGNAL
// sources named a signal type registered 'inactive', and fn_kernel_signal_submit refused every one
// of them — while fn_kernel_cutover_measure reported all twelve CUT_OVER, because its test was
// "the adapter calls a function whose name contains kernel". The caller knocked; the door was shut.
//
// This check refuses to take activation_state as evidence of anything. For EVERY type currently
// active it opens a real run through the kernel and drives four cases inside a transaction that
// always aborts:
//
//   1. VALID STATE      a live run, a well-formed payload            -> accepted
//   2. DUPLICATE        the identical submission a second time       -> no second effect
//   3. INVALID STATE    the same signal against a CLOSED run         -> refused, with a reason
//   4. MISSING WORKFLOW no workflow_run_id at all                    -> refused, with a reason
//
// Deterministic and zero-cost: no model is called on any of these paths.
//
//   node scripts/checks/active_signal_types_are_executable.test.mjs
import { SUPABASE_TOKEN_FILE } from '../../lib/supabase_token.mjs';
import { readFileSync, existsSync } from 'node:fs';
const PROD = 'htdblwldjkcgjvmqkbeh';
const LOCAL = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(LOCAL) ? readFileSync(LOCAL, 'utf8') : '')).trim();
if (!token) { console.log('SKIPPED: no management token, so this asserted nothing.'); process.exit(0); }
// A SQL string literal, never a JS one. JSON.stringify gives double quotes, which Postgres reads as
// an identifier — the first run of this fixture asked for a column called W07.
const lit = s => `'${String(s).replace(/'/g, "''")}'`;
const q = async text => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: text }),
  });
  const b = await r.text();
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${b.slice(0, 700)}`);
  return JSON.parse(b);
};

const types = await q(`select signal_type, disposition, coalesce(workflow_id,'') wf
                         from public.kernel_signal_type where activation_state='active'
                        order by signal_type`);
console.log(`active signal types: ${types.length}\n`);

let fail = 0, accepted = 0, refusedInvalid = 0, refusedMissing = 0, dupEffects = 0;
for (const t of types) {
  // COMPLETE_STEP needs an output; ATTACH_ONLY does not. The payload is what the source would send.
  const payload = t.disposition === 'COMPLETE_STEP'
    ? `jsonb_build_object('output', jsonb_build_object('status','ok','output','the answer the customer sent'), 'reason','fixture')`
    : `jsonb_build_object('note','fixture')`;
  const wf = t.wf || 'W07';
  const probe = `do $f$
declare
  v jsonb; v_run bigint; a jsonb; b jsonb; c jsonb; d jsonb;
  n_before int; n_after int; v_closed bigint;
begin
  v := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id', ${lit(wf)}, 'business_object_id','ZZ-SIGFIX-${t.signal_type}',
    'source_kind','autonomous','source_ref','fixture:${t.signal_type}',
    'requested_by','kernel:fixture','priority','P2'));
  v_run := (v->>'run_id')::bigint;

  -- 1. VALID STATE
  a := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','fixture','source_id','${t.signal_type}:1','workflow_run_id', v_run,
    'signal_type', ${lit(t.signal_type)},
    'idempotency_key','fixture:${t.signal_type}:1','requested_by','system.webhook_receiver',
    'payload', ${payload}));
  select count(*) into n_before from public.kernel_signal_inbox where source_id='${t.signal_type}:1';

  -- 2. DUPLICATE, identical
  b := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','fixture','source_id','${t.signal_type}:1','workflow_run_id', v_run,
    'signal_type', ${lit(t.signal_type)},
    'idempotency_key','fixture:${t.signal_type}:1','requested_by','system.webhook_receiver',
    'payload', ${payload}));
  select count(*) into n_after from public.kernel_signal_inbox where source_id='${t.signal_type}:1';

  -- 3. INVALID STATE — a run the kernel has already closed
  v := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id', ${lit(wf)}, 'business_object_id','ZZ-SIGFIX-CLOSED-${t.signal_type}',
    'source_kind','autonomous','source_ref','fixture:closed:${t.signal_type}',
    'requested_by','kernel:fixture','priority','P2'));
  v_closed := (v->>'run_id')::bigint;
  -- Closed THROUGH THE KERNEL. A direct update is refused by fn_kernel_write_guard, which is the
  -- correct answer and is why this fixture cancels the run instead of writing its state by hand.
  perform public.fn_kernel_cancel(jsonb_build_object(
    'subject_kind','workflow_run','subject_ref', v_closed::text, 'op','cancel',
    'actor','kernel:fixture','reason','fixture: a terminal run must refuse a signal'));
  c := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','fixture','source_id','${t.signal_type}:closed','workflow_run_id', v_closed,
    'signal_type', ${lit(t.signal_type)},
    'idempotency_key','fixture:${t.signal_type}:closed','requested_by','system.webhook_receiver',
    'payload', ${payload}));

  -- 4. MISSING WORKFLOW
  d := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','fixture','source_id','${t.signal_type}:norun',
    'signal_type', ${lit(t.signal_type)},
    'idempotency_key','fixture:${t.signal_type}:norun','requested_by','system.webhook_receiver',
    'payload', ${payload}));

  raise exception 'SIG|%|valid=%|dup_ok=%|dup_rows_added=%|invalid=%|missing=%',
    ${lit(t.signal_type)}, coalesce(a->>'ok','?'), coalesce(b->>'duplicate','?'),
    (n_after - n_before), coalesce(c->>'status', c->>'ok','?'), coalesce(d->>'status', d->>'ok','?');
end $f$;`;

  let line;
  try { await q(probe); line = 'NO EXCEPTION (the probe must raise)'; }
  catch (e) {
    const s = String(e.message); const i = s.indexOf('SIG|');
    line = i < 0 ? s.slice(0, 260).replace(/\s+/g, ' ') : s.slice(i + 4).split('CONTEXT')[0].replace(/\\n.*/, '').trim();
  }
  const ok = /valid=true/.test(line) && /dup_rows_added=0/.test(line)
    && /invalid=refused/.test(line) && /missing=refused/.test(line);
  if (/valid=true/.test(line)) accepted++;
  if (/invalid=refused/.test(line)) refusedInvalid++;
  if (/missing=refused/.test(line)) refusedMissing++;
  if (!/dup_rows_added=0/.test(line)) dupEffects++;
  if (!ok) fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${t.signal_type.padEnd(26)} ${t.disposition.padEnd(14)} ${line.replace(/^[^|]*\|/, '')}`);
}

// And the register-level rule the fixtures exist to protect.
const reg = await q(`
  select 'active existing-workflow signal sources' k, count(*)::text v, null::int e
    from public.phase_c_source_cutover where current_activation='ACTIVE' and source_class like 'B %'
  union all select 'active signal types', count(*)::text, null from public.kernel_signal_type where activation_state='active'
  union all select 'ACTIVE source targeting an INACTIVE signal type', count(*)::text, 0
    from public.phase_c_source_cutover c
   where c.current_activation='ACTIVE' and c.source_class like 'B %'
     and not exists (select 1 from public.kernel_signal_type t
                      where t.signal_type=c.target_step_or_signal and t.activation_state='active')
  union all select 'active signal type with no implemented handler', count(*)::text, 0
    from public.kernel_signal_type
   where activation_state='active'
     and disposition not in ('ATTACH_ONLY','COMPLETE_STEP','REVIEW_VERDICT','CANCEL')
  union all select 'signal type with no recorded activation reason', count(*)::text, 0
    from public.kernel_signal_type where coalesce(btrim(activation_reason),'')=''
  order by 1`);
console.log('');
for (const r of reg) {
  if (r.e === null) { console.log(`      ${r.k.padEnd(48)} ${r.v}`); continue; }
  const ok = String(r.v) === String(r.e);
  if (!ok) fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${r.k.padEnd(48)} ${r.v}  (expected ${r.e})`);
}
console.log(`\nvalid-state accepted ${accepted}/${types.length}   invalid-state refused ${refusedInvalid}/${types.length}`
  + `   missing-workflow refused ${refusedMissing}/${types.length}   duplicate signals creating work ${dupEffects}`);
console.log(`${fail === 0 ? 'PASS' : 'FAIL'} — ${fail} finding(s)`);
process.exit(fail ? 1 : 0);
