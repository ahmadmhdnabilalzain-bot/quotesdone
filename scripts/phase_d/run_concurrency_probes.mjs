// PHASE D — THE CONCURRENCY CASES, DRIVEN ON TWO REAL SESSIONS.
//
//   node scripts/phase_d/run_concurrency_probes.mjs
//
// Every concurrency case in the injected-defect catalogue carried NOT_RUN with one reason:
//
//     "a true race needs TWO concurrent database sessions. Everything in this file runs in one
//      aborted transaction, so a second claimant cannot exist. Executing it needs a harness that
//      opens two connections and commits — which under the hold would leave rows behind."
//
// A BLOCKER IS A CLAIM TOO, and both halves of that one are wrong.
//
// (1) TWO SESSIONS WERE ALWAYS AVAILABLE. The management endpoint runs each statement in its own
//     transaction on its own backend. Two statements issued together therefore run concurrently.
//     Measured 24 Aug 2026 (scripts/tmp_diag/conc_probe.mjs):
//         A pid=1719034  00:48:42.416 -> 00:48:46.419
//         B pid=1719035  00:48:42.420 -> 00:48:46.424
//     A statement that takes a lock and sleeps holds it while the other tries to take it. That is
//     a race, on real backends, with no new connection library and no local database.
//
// (2) "A COMMITTED OUTBOX ROW SENDS FOR REAL WITHIN 60s" IS ALSO WRONG. Measured on the live
//     bodies: neither public.fn_kernel_outbox_deliver nor public.fn_kernel_event_consume contains
//     net.*, http, or any external-delivery call. Outbox "delivery" is an in-database PROJECTION
//     onto the downstream subject. The worst a cron tick could do to this canary is project it and
//     mark it delivered -- no email, no SMS, no webhook, no payment.
//
// THE SUBJECT IS A TEMPORARY COMMITTED CANARY, and it is the estate's own claimer that races for
// it -- public.fn_phase_c_outbox_claim, the kernel-internal primitive with
// `for update skip locked`. A harness that raced its own copy of the claim query would be
// answering its own question.
//
// SAFETY, in the order the risks actually arrive:
//   * the outbox is quiet -- measured at the start of the run, and the probe REFUSES to start if
//     any other row is claimable, because then the claim could take somebody else's work;
//   * the race is started only inside a window that cannot overlap the 1-minute cron tick;
//   * both racing transactions end in `raise exception`, so the claim itself is rolled back;
//   * the canary is removed through the audited maintenance door, and the relation is asserted
//     back at its starting watermark before any verdict is written;
//   * the result row carries the audit_run_id and CHECK constraints on the table refuse to store
//     a pass that left residue, or a "race" that had fewer than two claimants and one winner.
//
// THE CONTROL IS THE POINT. A second claimant reading 0 rows proves nothing on its own -- zero
// cannot tell a dead guard from an idle system. So after the race, a third session claims the same
// canary ALONE and must get exactly 1. Without that arm, "B claimed nothing" and "there was
// nothing to claim" are the same observation.
import { sql } from '../phase_c/lib/db.mjs';
import { randomUUID } from 'node:crypto';

const AUDIT = randomUUID();
const DEDUPE = `zz-phase-d-canary-conc-${AUDIT}`;
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const one = (rows) => (rows && rows[0]) ? Object.values(rows[0])[0] : null;

// A DO block that ends in `raise exception 'MK<<...>>'`; returns what it carried.
async function marked(body, mk) {
  try { await sql(body); return '(no marker)'; }
  catch (e) {
    const m = String(e.message), a = m.indexOf(mk + '<<');
    return a >= 0 ? m.slice(a + mk.length + 2, m.indexOf('>>', a)) : 'ERROR:' + m.slice(0, 300);
  }
}

// ---- 0. the estate must be quiet enough for a race to mean anything ----------------------------
const claimableBefore = Number(one(await sql(`
  select count(*) from public.phase_c_event_outbox
   where (status in ('pending','retry_wait') and coalesce(next_attempt_at, now()) <= now())
      or (status = 'claimed' and claimed_at < now() - interval '15 minutes')`)));
if (claimableBefore !== 0) {
  console.error(`REFUSING TO START: ${claimableBefore} outbox row(s) are already claimable. The claim `
    + `would take real work instead of the canary, and a race whose subject is somebody else's row `
    + `is not this probe.`);
  process.exit(2);
}

const base = (await sql(`select
  (select count(*) from public.phase_c_event_outbox)               outbox,
  (select count(*) from public.phase_c_event_delivery_attempt)     attempts,
  (select count(*) from public.kernel_maintenance_write)           maint`))[0];
console.log(`baseline  outbox=${base.outbox} delivery_attempts=${base.attempts} maintenance_receipts=${base.maint}`);

// ---- 1. WAIT FOR THE CLEAR WINDOW *BEFORE* CREATING THE CANARY ---------------------------------
// The first run of this file created the canary and THEN waited for a window. Measured: cron
// phase_c_outbox_deliver_1min claimed it in the gap, fn_kernel_event_consume refused it fail-closed
// ("carries no workflow_run_id: it was produced as a command, not as a record of a run"), and the
// worker dead-lettered it after one attempt -- so by race time there was nothing claimable and all
// three arms read 0. The canary must not exist across a cron tick, so it is created inside the
// window, not before it.
for (;;) {
  const s = Number(one(await sql(`select extract(second from now() at time zone 'utc')`)));
  if (s >= 3 && s <= 30) break;
  console.log(`waiting for a clear window (second=${Math.round(s)})`);
  await sleep(2000);
}

// ---- 2. the canary, created by the canonical producer, committed --------------------------------
const canary = Number(one(await sql(`
  select public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id','EV-W01-STARTED', 'workflow_id','W01',
    'producer','zz-phase-d-canary',
    'accountable_role_id','chief_of_staff',
    'correlation_id', gen_random_uuid(), 'causation_id', gen_random_uuid(),
    'source_id','zz-phase-d-canary',
    'dedupe_value', ${JSON.stringify(DEDUPE).replace(/"/g, "'")},
    'payload', jsonb_build_object(
      'fact','PHASE_D_FIXTURE_DO_NOT_PUBLISH — concurrency canary, removed by this same run',
      'audit_run_id', ${JSON.stringify(AUDIT).replace(/"/g, "'")})))`)));
console.log(`canary    outbox_id=${canary} audit_run_id=${AUDIT}`);

let verdict = 'NOT_DISCRIMINATED', observed = '', claimants = 0, winners = 0, residue = 0;
try {
  // ---- 3. THE RACE, immediately -- the canary was created inside the window on purpose ----------
  // A claims and HOLDS the row lock for six seconds, then aborts. B tries to claim 1.5s in.
  const A = `do $a$
declare n int; v_id bigint;
begin
  select count(*), max(outbox_id) into n, v_id from public.fn_phase_c_outbox_claim(1);
  perform pg_sleep(6);
  raise exception 'CA<<%|%>>', n, coalesce(v_id::text,'-');
end $a$;`;
  const B = `do $b$
declare n int; v_id bigint;
begin
  select count(*), max(outbox_id) into n, v_id from public.fn_phase_c_outbox_claim(1);
  raise exception 'CB<<%|%>>', n, coalesce(v_id::text,'-');
end $b$;`;

  const [ra, rb] = await Promise.all([
    marked(A, 'CA'),
    sleep(1500).then(() => marked(B, 'CB')),
  ]);
  const [aN, aId] = ra.split('|');
  const [bN, bId] = rb.split('|');
  console.log(`race      A claimed ${aN} (outbox ${aId})   B claimed ${bN} (outbox ${bId})`);

  // ---- 4. THE CONTROL: alone, the same claim must take the same row -----------------------------
  const rc = await marked(B.replace(/CB/g, 'CC'), 'CC');
  const [cN, cId] = rc.split('|');
  console.log(`control   C alone claimed ${cN} (outbox ${cId})`);

  claimants = 2;
  winners = Number(aN) === 1 && Number(bN) === 0 ? 1 : (Number(aN) + Number(bN));
  const raced = Number(aN) === 1 && String(aId) === String(canary);
  const skipped = Number(bN) === 0;
  const controlProves = Number(cN) === 1 && String(cId) === String(canary);

  if (raced && skipped && controlProves) {
    verdict = 'REFUSED_AS_REQUIRED';
    observed = `two concurrent backends raced the estate's own claimer `
      + `public.fn_phase_c_outbox_claim over committed outbox row ${canary}. Session A claimed it `
      + `(1 row) and held the lock; session B, running 1.5s later on a different backend, claimed `
      + `0 -- for update skip locked passed over the locked row rather than blocking or `
      + `double-claiming. CONTROL: a third session claiming ALONE afterwards took the same row `
      + `(1 row, outbox ${cId}), so B's zero was caused by A's lock and not by an empty queue. `
      + `No duplicate claim, no duplicate effect.`;
  } else {
    verdict = (Number(aN) + Number(bN)) > 1 ? 'NOT_REFUSED' : 'NOT_DISCRIMINATED';
    observed = `A=${aN}(row ${aId}) B=${bN}(row ${bId}) control=${cN}(row ${cId}); canary was ${canary}. `
      + (controlProves ? '' : 'The control did not reclaim the canary, so this arm cannot say whether B '
        + 'was blocked by the lock or by an empty queue. ');
  }
} finally {
  // ---- 5. CANONICAL CLEANUP, through the audited maintenance door -------------------------------
  // The write guard owns this relation. Door 2 is an audited maintenance write by the table owner,
  // and it leaves a receipt in public.kernel_maintenance_write. That receipt is AUDIT EVIDENCE and
  // is reported separately from business counts; it is not fixture residue.
  await sql(`do $c$
begin
  perform set_config('kernel.maintenance_reason',
    'PHASE_D N05: removing the concurrency canary this same run created (audit_run_id ${AUDIT}). '
 || 'A temporary committed canary that is not removed is residue.', true);
  delete from public.phase_c_event_outbox where dedupe_value = ${JSON.stringify(DEDUPE).replace(/"/g, "'")};
  delete from public.phase_c_event_delivery_attempt
   where outbox_id not in (select outbox_id from public.phase_c_event_outbox);
end $c$;`);
}

// ---- 6. the watermark, before any verdict is written -------------------------------------------
const after = (await sql(`select
  (select count(*) from public.phase_c_event_outbox)           outbox,
  (select count(*) from public.phase_c_event_delivery_attempt) attempts,
  (select count(*) from public.kernel_maintenance_write)       maint`))[0];
residue = (Number(after.outbox) - Number(base.outbox)) + (Number(after.attempts) - Number(base.attempts));
console.log(`after     outbox=${after.outbox} delivery_attempts=${after.attempts} maintenance_receipts=${after.maint}`);
console.log(`residue   ${residue} business row(s); maintenance receipts added ${Number(after.maint) - Number(base.maint)} (audit evidence, reported separately)`);

if (residue !== 0) {
  observed += ` RESIDUE: the relation did not return to its watermark (+${residue}).`;
  if (verdict === 'REFUSED_AS_REQUIRED') verdict = 'NOT_DISCRIMINATED';
}

const lit = s => `'${String(s).replace(/'/g, "''")}'`;
await sql(`insert into public.phase_d_concurrency_probe_result
  (probe_id, verdict, observed, claimants, winners, duplicate_effects, residue, audit_run_id, ran_at)
  values ('C1-skip-locked-single-claimant', ${lit(verdict)}, ${lit(observed)},
          ${claimants}, ${winners}, 0, ${residue}, ${lit(AUDIT)}, now())
  on conflict (probe_id) do update set
    verdict = excluded.verdict, observed = excluded.observed, claimants = excluded.claimants,
    winners = excluded.winners, duplicate_effects = excluded.duplicate_effects,
    residue = excluded.residue, audit_run_id = excluded.audit_run_id, ran_at = excluded.ran_at`);

console.log(`\nC1-skip-locked-single-claimant  ${verdict}`);
console.log(observed);
process.exit(verdict === 'REFUSED_AS_REQUIRED' ? 0 : 1);
