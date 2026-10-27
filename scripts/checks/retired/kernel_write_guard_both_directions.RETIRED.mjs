// RETIRED 7 SEPTEMBER 2026 — ITS SUBJECT WAS REMOVED, NOT BROKEN.
//
// This asserted that the kernel write guard refuses an unauthorised write and permits an authorised one.
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
// §4. The kernel-only write guard, proved in BOTH directions and as the roles that matter.
//
//   node scripts/checks/kernel_write_guard_both_directions.test.mjs
//
// A guard that only refuses is an outage; a guard that only permits is decoration. Every case here
// runs against the real production functions inside a transaction that is always aborted, so
// nothing it writes survives — including the audit row the maintenance door produces.
//
// The interesting cases are the ones that run AS anon, authenticated and service_role. The
// management connection is postgres, which owns the tables, so testing only as postgres would
// prove the guard against the one identity it is least meant to stop. `set local role` makes the
// session those roles for the duration of the aborted transaction, which is the closest thing to
// an Edge Function holding the service key that can be done from here.
import { SUPABASE_TOKEN_FILE } from '../../lib/supabase_token.mjs';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
if (!(process.env.SUPABASE_ACCESS_TOKEN
      || (existsSync(LOCAL_TOKEN) && readFileSync(LOCAL_TOKEN, 'utf8').trim()))) {
  console.log('SKIPPED: no management token, so production cannot be read. Not asserting anything.');
  process.exit(0);
}
const { sql } = await import('../../lib/db.mjs');

let pass = 0, fail = 0;
const line = (ok, name, detail) => {
  if (ok) pass++; else fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name.padEnd(62)}${detail ? '  ' + detail : ''}`);
};

// Every probe is one DO block that ends in a RAISE, so the transaction always aborts.
const probe = async (body) => {
  try {
    await sql(`do $p$\ndeclare v_note text := 'unreached'; v_out jsonb; v_rows bigint;\nbegin\n${body}\n  raise exception 'PROBE_DONE %', coalesce(v_note, '(none)');\nend $p$;`);
    return 'NO_RAISE';
  } catch (e) { return String(e.message); }
};

const INSERT = `insert into public.phase_c_workflow_run
      (workflow_id, business_object_id, object_version, start_event, accountable_role_id, state, dedupe_key)
    values ('W14','ZZ-GUARD-PROBE',1,'x','quote_evaluation','active','ZZ-GUARD-PROBE:1');`;

// ---- NEGATIVE: a direct write must be refused, for every identity ---------------------------
for (const role of ['anon', 'authenticated', 'service_role']) {
  const msg = await probe(`  begin
    set local role ${role};
    ${INSERT}
    v_note := 'ACCEPTED — THE GUARD DID NOT FIRE';
  exception when others then v_note := left(sqlerrm, 90);
  end;`);
  const refused = /is refused|permission denied|must be owner/i.test(msg) && !/ACCEPTED/.test(msg);
  line(refused, `${role} direct business write is refused`,
       (msg.match(/PROBE_DONE (.*?)(?:\\nCONTEXT|CONTEXT|$)/s) || [, ''])[1].trim().slice(0, 80));
}

// ---- NEGATIVE: an untrusted caller must not be able to manufacture kernel context ------------
{
  const msg = await probe(`  begin
    set local role service_role;
    -- The maintenance door needs a stated reason AND the table owner. service_role can state a
    -- reason; it cannot be the owner, and it cannot forge a call stack.
    set local kernel.maintenance_reason = 'probe: an untrusted caller trying to open the door';
    ${INSERT}
    v_note := 'ACCEPTED — SERVICE_ROLE MANUFACTURED KERNEL CONTEXT';
  exception when others then v_note := left(sqlerrm, 90);
  end;`);
  line(!/MANUFACTURED/.test(msg), 'service_role cannot manufacture kernel context with a GUC',
       (msg.match(/PROBE_DONE (.*?)(?:\\nCONTEXT|CONTEXT|$)/s) || [, ''])[1].trim().slice(0, 80));
}

// ---- POSITIVE: the canonical kernel write must NOT be refused --------------------------------
{
  const msg = await probe(`  begin
    v_out := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id','W14','business_object_id','ZZ-GUARD-PROBE-OK','source_kind','autonomous',
      'source_ref','probe:guard','requested_by','kernel:probe'));
    v_note := 'run=' || coalesce(v_out->>'run_id','none')
           || ' step_runs=' || coalesce(v_out->'created'->>'step_run','0')
           || ' tasks=' || coalesce(v_out->'created'->>'task','0');
  exception when others then v_note := 'REFUSED: ' || left(sqlerrm, 90);
  end;`);
  const got = (msg.match(/PROBE_DONE (.*?)(?:\\nCONTEXT|CONTEXT|$)/s) || [, ''])[1].trim();
  line(/^run=\d+/.test(got), 'the canonical kernel write is accepted', got.slice(0, 90));
}

// ---- POSITIVE: the audited maintenance door works, for the owner, and records itself ----------
{
  const msg = await probe(`  begin
    set local kernel.maintenance_reason = 'probe: the audited maintenance door, aborted';
    ${INSERT}
    select count(*) into v_rows from public.kernel_maintenance_write
     where reason = 'probe: the audited maintenance door, aborted';
    v_note := 'permitted, audit rows=' || v_rows::text;
  exception when others then v_note := 'REFUSED: ' || left(sqlerrm, 90);
  end;`);
  const got = (msg.match(/PROBE_DONE (.*?)(?:\\nCONTEXT|CONTEXT|$)/s) || [, ''])[1].trim();
  line(/permitted, audit rows=[1-9]/.test(got), 'the audited maintenance door works and records itself', got.slice(0, 90));
}

// ---- Nothing survived --------------------------------------------------------------------------
const [{ n }] = await sql(
  `select count(*) n from public.phase_c_workflow_run where business_object_id like 'ZZ-GUARD-PROBE%'`);
line(Number(n) === 0, 'no probe row survived the aborted transactions', `rows=${n}`);

console.log(`\n${fail === 0 ? 'WRITE GUARD PROVED BOTH DIRECTIONS' : `${fail} write-guard case(s) failed`}`
  + `  (${pass} passed)`);
process.exit(fail === 0 ? 0 : 1);
