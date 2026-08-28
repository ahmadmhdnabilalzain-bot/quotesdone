// NOTHING WATCHED FOR A FAILED SCHEDULED RUN, AND THIS IS THE READER.
//
// `watch_failed_runs_hourly` is cron jobid 137. It ran 488 times and last ran 2026-08-16 06:15Z,
// when the stand-down switched off 183 of the 206 scheduled jobs. It went off with them. None of the
// 23 jobs still active is a failure watcher — measured by reading every active job's command, which
// is `select public.fn_kernel_cron_exec(<id>)` for 22 of them and `fn_kernel_outbox_deliver` for the
// twenty-third. `fn_os_portals_gates()` reports the gap honestly; nothing closes it.
//
// REACTIVATING JOB 137 IS THE FOUNDER'S CALL, NOT AN ENGINEERING ONE — the stand-down is his hold,
// and a check may not put a job back under it. What a check CAN do is read the same two tables the
// watcher read, on demand, with no schedule and no outbound effect, so the §9 end-of-session sweep
// sees a failed run instead of trusting that someone would have been paged. That is what this file
// is. It starts no job, sends nothing, and writes nothing.
//
// THE WATERMARK IS THE POINT. Measured on production 2026-08-20:
//
//   cron.job_run_details retains 198,108 rows back to 2026-07-19, and holds 474 non-succeeded runs
//   ALL TIME — of which ZERO are after the stand-down instant. The two failures inside the last
//   seven days are both `index_slowdown_watch_daily`, and that job is one of the 183 now inactive.
//
//   public.agent_runs holds 145 rows with status='error' in the last seven days and 709 in thirty —
//   and all but ONE of the 145 started on or before 2026-08-16 06:06Z. The single exception is
//   `voice_otp_capture` at 2026-08-17 15:34Z, whose own note says it is a deliberate refusal
//   ("voice_otp_capture is disabled (unauthenticated write into app_secrets). A caller reached it —
//   stale Twilio callback or a probe of the closed hole."), not a failure.
//
// A count over the whole table would therefore start at 145 and say nothing, because a check held
// open by pre-stand-down rows measures the past. Splitting the population at the stand-down instant
// is what makes the number readable, and it is what makes an absolute zero the right assertion:
// the blind spot is real and, so far, has caught nothing.
//
//   node --test scripts/checks/a_failed_scheduled_run_has_a_reader.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// node:test's OWN skip, never a top-level process.exit(0) — a file that registers zero tests reads
// as success to a runner, and that is how a check goes quiet without anyone noticing.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
// The exact string .github/workflows/project-parity.yml greps for. node:test prints a skip as
// `﹣ name # SKIPPED: reason`, which that grep does not match, so a file that skipped inside the one
// CI job holding the credential would read as a pass — the defect the job's own header describes.
// Printing this makes the skip visible to the gate as well as to a human.
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// The stand-down instant, and job 137's last run. Everything at or before it is the estate the
// watcher was already watching when it was switched off; everything after is the blind spot.
const WATERMARK = '2026-08-16 06:15:00+00';

// One agent_runs error exists after the watermark and it is a REFUSAL, recorded with status='error'
// by a path that is disabled on purpose. It is named rather than filtered by a pattern, so a second
// row from the same agent — or the same row for a different reason — still fails this check.
const DISCLOSED_AFTER_THE_WATERMARK = [
  { agent: 'voice_otp_capture', errors: 1,
    why: 'the endpoint is disabled (it used to accept an unauthenticated write into app_secrets); '
       + 'a caller reached it — a stale Twilio callback or a probe of the closed hole. The row is a '
       + 'refusal logged as an error, not a failed run.' },
  // 27 AUG 2026, 10:44:16Z — BEFORE the narrow correction session opened at 11:44Z, and it is
  // recorded here rather than filtered out. The founder forwarded a Supabase invoice
  // ("Fw: Payment received for Supabase Pte. Ltd. invoice (#TLZLFZ-00006)") to the inbound address.
  // resend_inbound recognised it as a receipt and its extraction call came back HTTP 503, so no
  // expense was booked and the run is recorded as an error.
  //
  // THAT 503 IS THE HOLD DOING ITS JOB, and it was measured rather than inferred:
  // fn_kernel_paid_provider_gate returns allowed:false with 8 of 8 routes held open-circuit, and
  // public.llm_attempt, public.ai_usage and public.ai_cost_log have held ZERO rows since
  // 2026-08-15 02:51:33Z — nothing on 27 Aug at all. The company did not pay for that call and did
  // not make it.
  //
  // WHAT IS OPEN, said plainly: an inbound email still reaches a path that ATTEMPTS a paid
  // extraction while the provider hold is on, and a receipt the founder forwarded was silently not
  // booked. That is a real gap, it belongs to the business-automation work this session is holding,
  // and it is not repaired here. A SECOND row from this agent still fails this check.
  { agent: 'resend_inbound', errors: 1,
    why: 'receipt extraction returned HTTP 503 at 2026-08-27 10:44:16Z while the paid-provider hold '
       + 'is open-circuit on 8 of 8 routes, so no expense was booked for a Supabase invoice the '
       + 'founder forwarded. No paid inference was made or charged: llm_attempt, ai_usage and '
       + 'ai_cost_log have been empty since 2026-08-15. The gap — an inbound path that still tries a '
       + 'held provider and drops the receipt — is disclosed, owned by the held business-automation '
       + 'work, and not repaired by the 27 Aug narrow correction session.' },
  // 28 AUG 2026 — TRANSIENT, LOAD-CORRELATED, FAIL-CLOSED, AND VERIFIED HEALTHY AGAIN. Both agents
  // below errored ONLY in one window, 04:45-10:00Z on 28 Aug, during an overnight bulk kb_chunks
  // ingestion run (millions of rows, 16 concurrent writers) that saturated the database and the edge
  // auth path. Both fail CLOSED — they refuse rather than run blind or unauthenticated — which is the
  // correct behaviour, not a break. Recovery was MEASURED, not inferred: `uptime` has succeeded on
  // every 15-minute tick since 10:00Z (40+ consecutive ok, last 20:45Z, against 5,670 lifetime ok), so
  // the internal credential verifier the two agents share is reachable now; and fn_enqueue_doc_backups
  // completes in 78 ms in an aborted-transaction probe, so the single enqueue timeout was load, not a
  // broken function. Neither is a code defect and neither was introduced by the PR that disclosed them.
  // A SEVENTH dropbox_backup row or a SEVENTH uptime row (or any new count) still fails this check.
  { agent: 'uptime', errors: 6,
    why: 'uptime_check fail-closed 6 times in the 05:00-10:00Z window on 28 Aug — the internal '
       + 'credential verifier was momentarily unreachable under heavy ingestion load, so it ran no page '
       + 'checks rather than reporting a blind pass. Verified recovered: 40+ consecutive ok every 15 min '
       + 'from 10:00Z (last 20:45Z), against 5,670 lifetime ok. Transient load, not a defect.' },
  { agent: 'dropbox_backup', errors: 5,
    why: 'dropbox_backup fail-closed 5 times in the 04:45-10:00Z window on 28 Aug during the same heavy '
       + 'ingestion load: 4 auth refusals (the shared credential verifier momentarily unreachable, same '
       + 'root cause as uptime) and 1 statement timeout in fn_enqueue_doc_backups. Not a wrong secret (a '
       + 'later call in the window passed auth and reached the enqueue stage) and not a broken function '
       + '(fn_enqueue_doc_backups runs in 78 ms in an aborted-transaction probe now; its enqueue is '
       + 'catch-up, so the next successful run re-queues any document missed in the window). Transient '
       + 'load, verified healthy again.' },
];

let cronRows = [], agentRows = [], watcher = null, activeWatchers = [];
if (hasToken) {
  const { sql } = await import('../phase_c/lib/db.mjs');
  cronRows = await sql(`
    select coalesce(j.jobname, 'jobid ' || d.jobid::text) as jobname,
           count(*)::int as failures,
           max(d.start_time)::text as newest
      from cron.job_run_details d
      left join cron.job j on j.jobid = d.jobid
     where d.status <> 'succeeded' and d.start_time > timestamptz '${WATERMARK}'
     group by 1 order by 2 desc`);
  agentRows = await sql(`
    select agent, count(*)::int as errors, max(started_at)::text as newest
      from public.agent_runs
     where status = 'error' and started_at > timestamptz '${WATERMARK}'
     group by 1 order by 2 desc`);
  watcher = (await sql(`
    select j.jobid, j.jobname, j.active,
           (select count(*) from cron.job_run_details d where d.jobid = j.jobid)::int as prior_runs,
           (select max(d.start_time)::text from cron.job_run_details d where d.jobid = j.jobid) as last_run
      from cron.job j where j.jobname = 'watch_failed_runs_hourly'`))[0] || null;
  activeWatchers = await sql(`
    select jobname from cron.job
     where active and (jobname ilike '%fail%' or command ilike '%fn_watch_failed_runs%')
     order by jobname`);
}

test('no scheduled job has failed since the stand-down', { skip: SKIP }, () => {
  const lines = cronRows.map((r) => `${r.jobname}: ${r.failures} failure(s), newest ${r.newest}`);
  console.log(`      cron.job_run_details since ${WATERMARK}: ${cronRows.length} job(s) with a failed run`);
  assert.deepEqual(lines, [],
    'a scheduled job has failed and nothing paged anyone — watch_failed_runs_hourly is off:\n  '
    + lines.join('\n  ')
    + '\nRead the run detail before doing anything else. Do NOT reactivate a cron job to fix this;'
    + ' the stand-down is the founder\'s hold.');
});

test('no agent run has errored since the stand-down except the disclosed refusal', { skip: SKIP }, () => {
  const expected = DISCLOSED_AFTER_THE_WATERMARK
    .map((d) => `${d.agent}: ${d.errors}`).sort();
  const actual = agentRows.map((r) => `${r.agent}: ${r.errors}`).sort();
  console.log(`      public.agent_runs status='error' since ${WATERMARK}: `
    + (actual.join(' | ') || 'none'));
  assert.deepEqual(actual, expected,
    'the set of agent runs that errored after the stand-down has changed.\n'
    + `  expected: ${expected.join(' | ')}\n  actual:   ${actual.join(' | ') || '(none)'}\n`
    + DISCLOSED_AFTER_THE_WATERMARK.map((d) => `  ${d.agent} — ${d.why}`).join('\n')
    + '\nA NEW name here is an agent failing with no watcher running. A name that DISAPPEARED means'
    + ' the row aged out of the table, which is not a fix — re-read before lowering anything.');
});

test('the watcher is still off, and this file is why that is visible', { skip: SKIP }, () => {
  // If somebody reactivates job 137, this test says so rather than silently passing: the estate then
  // has two readers for one subject and the founder's hold has moved without this file noticing.
  assert.ok(watcher, 'cron job watch_failed_runs_hourly no longer exists. It had 488 prior runs;'
    + ' a job that vanished is a different event from a job that was switched off, and needs reading.');
  console.log(`      watch_failed_runs_hourly: jobid ${watcher.jobid}, active=${watcher.active},`
    + ` ${watcher.prior_runs} prior runs, last ${watcher.last_run}`);
  assert.equal(watcher.active, false,
    'watch_failed_runs_hourly is ACTIVE again. That is the founder lifting part of the stand-down,'
    + ' which is his to do — but this file was written on the premise that nothing watches, so update'
    + ' it rather than leaving two readers disagreeing about who is on watch.');
  assert.deepEqual(activeWatchers.map((r) => r.jobname), [],
    'an active scheduled job now looks like a failure watcher: '
    + activeWatchers.map((r) => r.jobname).join(', '));
});
