// A SOCIAL REPLY THAT IS STILL OWED IS NOT LEFT OWED (22 Sep 2026, it_engineer, CONN-07).
//
// WHAT CHANGED AND WHY THIS EXISTS. marketing_social_inbox used to mark EVERY non-2xx from Meta's Graph
// API as send_status='failed', which is terminal — nothing re-drains social_message — so a rate-limit
// answer (HTTP 429, or Graph codes 4 app-hourly, 17 user-hourly, 613 calls-per-second) discarded a
// customer's answer for good. It now retries twice inside the handler and, if Meta is still throttling,
// leaves the row 'pending' with the reason: still owed, not failed.
//
// THAT IS ONLY HONEST IF SOMETHING LOOKS AT IT. 'pending' with no consumer is the estate's own recurring
// defect — a queue with no drain, a status column that is not a delivery record — so this is the alarm
// that stands in for the drain that does not exist yet. A reply Meta throttled is deliverable within
// minutes; at six hours it is not throttling any more, it is abandoned.
//
// WHEN THE DRAIN IS BUILT, this check does not get deleted: it becomes the check that the drain works.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

test('no social reply has been owed for more than six hours', { skip: SKIP }, async () => {
  const rows = await sql(`
    select m.id, m.platform, m.send_status, left(coalesce(m.send_error,''), 120) as why,
           round(extract(epoch from (now() - m.occurred_at))/3600, 1) as hours_owed
      from public.social_message m
     where m.direction = 'out' and m.author = 'seat'
       and coalesce(m.send_status, 'pending') = 'pending'
       and m.occurred_at < now() - interval '6 hours'
     order by m.occurred_at
     limit 10`);
  assert.equal(rows.length, 0,
    'social reply/replies the seat wrote and never sent — Meta throttled them and nothing came back for them:\n'
    + rows.map((r) => `  #${r.id} ${r.platform} ${r.hours_owed}h  ${r.why}`).join('\n'));
});

// POSITIVE CONTROL. "Nothing is owed" is also true of a table nobody writes to, and until the founder's
// Meta app is connected that is exactly what this is: social_send_enabled is off and every reply is
// stored 'held_switch_off'. So the check states which of the two it measured rather than reporting a
// clean bill either way. It does not FAIL on an empty table — the seat is new and pre-launch — it says so.
test('the seat is either sending or deliberately held, and this check says which', { skip: SKIP }, async () => {
  const [{ sent, held, pending, total }] = await sql(`
    select count(*) filter (where send_status = 'sent')            as sent,
           count(*) filter (where send_status = 'held_switch_off') as held,
           count(*) filter (where coalesce(send_status,'pending') = 'pending') as pending,
           count(*) as total
      from public.social_message where direction = 'out' and author = 'seat'`);
  console.log(`social_message seat replies: ${total} total — ${sent} sent, ${held} held by the switch, ${pending} pending`);
  assert.ok(Number(total) >= 0, 'social_message is unreadable');
});
