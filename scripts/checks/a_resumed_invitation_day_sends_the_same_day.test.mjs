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
