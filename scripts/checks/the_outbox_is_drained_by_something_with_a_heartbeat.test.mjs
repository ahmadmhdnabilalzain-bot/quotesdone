// A ROW IN THE OUTBOX IS NOT A SENT EMAIL, AND NOTHING WAS DRAINING IT ON A HEALTHY DAY.
//
// 9 Sep 2026. resilience_ping is the only thing in this estate that runs on a heartbeat — an
// external scheduler hits it every ~15 minutes. Its ONLY call to send_outbox sat inside the
// scheduler-is-down branch, underneath `if (healthy) return`. So while everything was working, the
// heartbeat never looked at the mail queue, and a notification left the building only if whatever
// created it happened to push it itself.
//
// That is invisible from the data. A stuck row sits at status 'pending' with last_error NULL, which
// is exactly what a freshly queued row looks like. It was found by noticing that the IT engineer's
// two [RESOLVED] close notices, written at 08:00:40, were still pending at 08:35 while the ping had
// ticked at 07:30, 07:45, 08:00 and 08:15.
//
// TWO TESTS, DELIBERATELY DIFFERENT IN KIND.
//
//   1. THE SYMPTOM, against production: no notification has been waiting longer than 30 minutes.
//      This catches every future variant of "queued but nothing pushes it", whatever causes it.
//   2. THE MECHANISM, against the DEPLOYED bundle: send_outbox is reached from the healthy path.
//      The symptom test passes on a quiet estate with nothing queued, and a quiet estate is the
//      normal case — so on its own it is a zero that cannot tell a working drain from an empty
//      queue. The mechanism test is what fails the moment the drain is moved back inside the
//      outage branch.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

test('nothing has been sitting in the outbox longer than the heartbeat allows', { skip: SKIP }, async () => {
  const rows = await sql(`
    select id, status, subject,
           round(extract(epoch from (now() - greatest(created_at, coalesce(not_before, created_at))))/60)::int as waiting_minutes
      from public.notifications
     -- 'sending' IS IN THIS LIST OR THE CHECK CANNOT SEE ITS OWN FAILURE MODE (22 Sep 2026,
     -- it_engineer, CONN-03). fn_notifications_claim moves a row to 'sending' while a sender has it,
     -- and the ONLY thing that requeues an expired claim is that same function — i.e. a sender. So in
     -- exactly the case this check exists for, a sender that is down, the backlog accumulates in
     -- 'sending', nothing puts it back to 'queued', and a list of ('pending','queued') reads zero and
     -- passes. A row legitimately in 'sending' is there for seconds; at 30 minutes it is stuck.
     where status in ('pending','queued','sending')
       -- WAITING IS COUNTED FROM WHEN A ROW IS DUE (10 Nov 2026, it_engineer). The Microsoft 365 lane (founder ledger 1115,
       -- send_outbox/m365_lane.ts) HOLDS a capped invitation by moving not_before to the next window, and
       -- enqueue_supplier_invites spreads a batch the same way; measured 10 Nov: 10 supplier_invite rows created 05:00Z,
       -- not_before 11 Nov 06:00Z, last_error 'held: the Microsoft 365 lane reached invite_daily_cap'. A row scheduled for
       -- later waits on its clock, not on a heartbeat. One due 30 minutes ago and still unsent is stuck, as before.
       and greatest(created_at, coalesce(not_before, created_at)) < now() - interval '30 minutes'
     order by created_at
     limit 10`);
  assert.equal(rows.length, 0,
    'notification(s) stuck in the outbox — something queued mail that no heartbeat is draining:\n'
    + rows.map((r) => `  #${r.id} ${r.status} ${r.waiting_minutes}min  ${r.subject}`).join('\n'));
});

// POSITIVE CONTROL FOR THE TEST ABOVE. If the estate never sends anything, "nothing is stuck" is a
// statement about an empty table. This asserts the outbox is a thing that actually moves, so a pass
// on the staleness test means the drain works rather than that there is nothing to drain.
test('the outbox is a live queue, not an empty one', { skip: SKIP }, async () => {
  const [{ n }] = await sql(`select count(*) n from public.notifications
     where status = 'sent' and sent_at > now() - interval '7 days'`);
  assert.ok(Number(n) > 0,
    'no notification has been sent in seven days, so the staleness check above proves nothing');
});

// THE MECHANISM, read out of the file that is deployed. The healthy path returns early, so the
// drain has to be called BEFORE that return to run at all on a working day.
test('the heartbeat drains the outbox on the healthy path, not only during an outage', () => {
  const src = functionSource('resilience_ping');

  // MATCH THE CODE, NOT THE PROSE. The first draft searched for "if (healthy) return" and found it
  // inside outboxTick's own doc comment, which quotes the line it was written to fix — so the check
  // failed on a file that was already correct. A comment is not a code path; the anchor includes the
  // call to J( so it can only match the statement itself.
  const healthyReturn = src.indexOf('if (healthy) return J(');
  assert.ok(healthyReturn > 0, 'the healthy early-return is gone; this check needs rewriting against the new shape');

  const drainCall = src.indexOf('await outboxTick()');
  assert.ok(drainCall > 0, 'nothing calls outboxTick — the outbox has no heartbeat behind it');
  assert.ok(drainCall < healthyReturn,
    'outboxTick is called AFTER the healthy early-return, so on a working estate it never runs. '
    + 'That is the exact defect of 9 Sep 2026: mail could only escape during an outage.');

  // And the drain must actually reach the sender rather than merely counting the queue.
  const fn = src.slice(src.indexOf('async function outboxTick'), src.indexOf('\n}\n', src.indexOf('async function outboxTick')));  // outboxTick alone (it was the span up to backupTick while one file)
  assert.match(fn, /\/send_outbox/, 'outboxTick does not call send_outbox');

  // THE HEARTBEAT MUST BEAT WHEN THERE IS NOTHING TO DO. The first version of outboxTick returned
  // early on an empty queue, so send_outbox only ran when there was mail — which left it with no
  // cadence for run_silent to measure, and produced a self-feeding alarm: quiet queue, no run,
  // detector fires, the alert itself queues a notification, the next tick sends it, the finding
  // resolves, quiet again. Three emails to the founder in four hours with nothing wrong.
  const callAt = fn.indexOf('/send_outbox');
  assert.ok(!/\breturn\b/.test(fn.slice(0, callAt)),
    'outboxTick can return before it reaches send_outbox, so the sender only runs under load. '
    + 'A heartbeat that beats only when there is work has no cadence, and "send_outbox has not '
    + 'run" stops meaning anything.');
});
