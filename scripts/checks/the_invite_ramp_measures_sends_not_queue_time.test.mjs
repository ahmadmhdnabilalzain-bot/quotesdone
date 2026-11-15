// THE INVITE RAMP MEASURES AN INVITATION BY WHEN IT LEFT, NOT WHEN IT WAS QUEUED (it_engineer, 3 Nov 2026).
//
// fn_invite_ramp read "the last invitation issued" as max(leads.invited_at), which enqueue_supplier_invites stamps at
// QUEUE time (~05:00Z). Measured: Mon 2 Nov 05:00:01.92Z was 0.78 s past three days after Friday's batch was queued
// (05:00:01.14Z), so the run was a restart and cut the cap 30 -> 20, although Friday's last invitation left at 12:46Z
// (64 h earlier); Tuesday then paged invite_sender_stalled. Fix:
// scripts/sql/the_ramp_measures_an_invitation_by_when_it_left_not_when_it_was_queued.sql
//
// This reads the CANONICAL fn_invite_ramp (the last MANIFEST or pending file that defines it) and fails if any of its
// "issued" reads goes back to leads.invited_at, or if growth can run on an empty window or an unused send day.
//   node --test scripts/checks/the_invite_ramp_measures_sends_not_queue_time.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { definitions } from '../lib/canonical_sql.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');

function canonicalRamp() {
  let last = null;
  for (const f of manifestWithPending()) {
    if (!existsSync(join(ROOT, f))) continue;
    const d = definitions(R(f)).find((x) => x.key === 'fn_invite_ramp()');
    if (d) last = { file: f, body: d.stmt.replace(/--[^\n]*/g, '') };
  }
  assert.ok(last, 'no applied or pending file defines fn_invite_ramp()');
  return last;
}

test('the canonical fn_invite_ramp reads issued invitations from the outbox by sent_at, never leads.invited_at', () => {
  const { file, body } = canonicalRamp();
  assert.doesNotMatch(body, /invited_at\s+is\s+not\s+null/i,
    `${file}: fn_invite_ramp still measures "issued" by leads.invited_at, which is the time a row was QUEUED`);
  assert.doesNotMatch(body, /max\(\s*invited_at\s*\)|max\(\s*\(\s*invited_at\s+at\s+time\s+zone/i,
    `${file}: the last send / the last send day is read from invited_at (queue time)`);
  assert.match(body, /max\(\s*n\.sent_at\s*\)/i, `${file}: the last invitation issued must be max(notifications.sent_at)`);
  assert.match(body, /n\.status\s*=\s*'sent'/i, `${file}: only rows the outbox actually sent count as issued`);
});

// 15 Nov 2026 (sales_engineer; the_invitation_ramps_on_measured_health_and_tests_its_copy.sql): the 48 h minimum of
// backoff_min_sends (20) could never be met at a cap of 3 (two days carry 6), so the cap could only fall: measured, it sat at 3.
// The rule this guards is unchanged in kind and moved in window: no growth on an EMPTY window ("0 bounces of 0 is not health"),
// judged now on the 14-day bounce judgement, and growth still needs the last send day to have used the cap.
test('the canonical fn_invite_ramp never grows the cap on an empty window or an unused send day', () => {
  const { file, body } = canonicalRamp();
  const guard = body.search(/elsif\s+v_wsent\s*=\s*0\s+then/i);
  const grow = body.search(/a\.finished_at\s*>\s*v_last_sent/i);   // the growth branch's "already grew" read
  assert.ok(guard > 0, `${file}: no hold for an empty 14-day judgement window`);
  assert.ok(grow > guard, `${file}: the empty-window hold must come before the growth branch`);
  assert.match(body, /v_last_day_sent\s*<\s*ceil\(v_cur \* v_used_pct\)/i, `${file}: growth no longer needs the last send day to use the cap`);
  assert.match(body, /fn_invite_bounce_judgement\(now\(\)\)/i, `${file}: health is not read from the bounce judgement`);
});
