// A RESUMED INVITATION DAY SENDS THE SAME DAY (2 Nov 2026, sales_engineer, ledger 1486).
// On 2 Nov the bounce brake fired inside the 09:00 batch, the founder resumed at 11:07, and the tick answered "already ran
// this Dubai day" until midnight: the resume queued nothing. This fails if the canonical tick (the last file in MANIFEST
// that defines it) stops letting a resume later than the day's batch run reopen that batch.
// The behaviour is proved on production by a_resumed_invitation_day_sends_the_same_day_probe.sql (rolled back).
//   node --test scripts/checks/a_resumed_invitation_day_sends_the_same_day.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const SQL = 'scripts/sql/';
const DEF = /create or replace function public\.fn_sales_engineer_supplier_outreach_tick\(/i;
const files = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#')).map((l) => l.replace(/^scripts\/sql\//, ''))
  .filter((f) => existsSync(SQL + f) && DEF.test(readFileSync(SQL + f, 'utf8')));

test('a brake resumed after the day\'s batch run reopens the batch', () => {
  assert.ok(files.length, 'no file in MANIFEST defines fn_sales_engineer_supplier_outreach_tick');
  const src = readFileSync(SQL + files.at(-1), 'utf8');
  const body = src.slice(src.search(DEF)).split(/\$function\$;/)[0];
  assert.match(body, /max\(b\.resumed_at\) into v_resumed from public\.invite_brake b/, `${files.at(-1)}: the tick no longer reads the day's resume`);
  const done = body.slice(body.indexOf('into v_daily_done, v_batch_done') - 900, body.indexOf('into v_daily_done, v_batch_done'));
  assert.match(done, /a\.started_at > v_resumed/, `${files.at(-1)}: a batch run before the resume still counts as today's batch`);
});

// Review of #1787. A held row with no reason was also what the supplier_emails_enabled kill switch wrote, so a release keyed on
// "held, no reason" could undo a founder pause; and a release at apply ignored the go switch and the bounce brake (ledger 1449).
const FIX = 'a_resumed_invitation_day_sends_the_same_day.sql';
const fix = existsSync(SQL + FIX) ? readFileSync(SQL + FIX, 'utf8') : '';
const release = fix.slice(fix.search(/create or replace function public\.fn_sales_engineer_releases_the_invitations_held_stale_on_2_nov\(/i)).split(/end \$fn\$;/)[0];

test('the release names its 18 ids and nothing else', () => {
  assert.match(release, /where n\.id between 116650 and 116668\b/, 'the release is not bounded to the 18 rows it was written for');
  assert.doesNotMatch(fix.replace(/^\s*--.*$/gm, ''), /^\s*do \$/m, 'a release runs at apply, outside the go switch and the brake');
});

test('the release asks the go switch and the bounce brake before it touches a row', () => {
  const update = release.search(/update public\.notifications n/);
  assert.ok(update > 0, 'the release no longer updates the outbox');
  const gates = release.slice(0, update);
  assert.match(gates, /key = 'invite_enabled'/, 'the release does not read invite_enabled');
  assert.match(gates, /fn_supplier_outreach_golive\(\)/, 'the release does not read supplier_outreach_golive');
  assert.match(gates, /fn_invite_send_health\(now\(\) - interval '3 days'\)/, 'the release does not read the brake\'s 3-day window');
});

test('the kill-switch hold in send_outbox says why, so no release can mistake it for a stale hold', () => {
  const outbox = readFileSync('supabase/functions/send_outbox/index.ts', 'utf8');
  assert.match(outbox, /!supEnabled && !docReq\) \{ await admin\.from\('notifications'\)\.update\(\{ status: 'held', last_error: /,
    'send_outbox holds supplier mail for supplier_emails_enabled with no last_error');
});
