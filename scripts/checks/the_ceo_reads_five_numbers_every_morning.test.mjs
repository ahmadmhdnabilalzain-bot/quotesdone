// THE CEO READS FIVE NUMBERS EVERY MORNING (founder ruling 1209, 13 Oct 2026). Assigned: ceo.
// Offline: reads the SQL file the release operator applies at merge. Fails when:
//   1. one of the five numbers is counted without its demo exclusion (a ZZ DEMO run would inflate the CEO's morning);
//   2. the report is delivered anywhere but a ceo -> ceo handoff (it must never reach the founder);
//   3. a new routine is left executable by PUBLIC, anon or authenticated, or without a pinned search_path;
//   4. the duty is not scheduled daily, or the aborted-transaction probe stops asserting the demo exclusion.
//   node --test scripts/checks/the_ceo_reads_five_numbers_every_morning.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SRC = readFileSync(join(REPO, 'scripts/sql/the_ceo_reads_five_numbers_every_morning.sql'), 'utf8');
const PROBE = readFileSync(join(REPO, 'scripts/sql/the_ceo_reads_five_numbers_every_morning_probe.sql'), 'utf8');
const code = (s) => s.split(/\r?\n/).map((l) => l.replace(/--.*$/, '')).join('\n');
const body = (name) => {
  const m = code(SRC).match(new RegExp(`function public\\.${name}\\([\\s\\S]*?\\$fn\\$([\\s\\S]*?)\\$fn\\$`, 'i'));
  assert.ok(m, `public.${name} is not defined`);
  return m[1];
};

test('each of the five numbers excludes demo rows', () => {
  const b = body('fn_ceo_five_numbers');
  const expr = (key) => {
    const i = b.indexOf(`'${key}'`);
    assert.ok(i >= 0, `${key} is not in the payload`);
    const next = b.slice(i + key.length + 2).search(/\n\s*'[a-z_0-9]+',/);
    return b.slice(i, next < 0 ? undefined : i + key.length + 2 + next);
  };
  for (const k of ['requests_created', 'quotes_received', 'reveals_paid', 'disputes']) {
    assert.match(expr(k), /fn_inquiry_is_demo|is_demo|livemode/, `${k} is counted without a demo exclusion`);
  }
  // the response rate reads the inv set, which excludes demo suppliers and demo requests
  assert.match(b, /inv as \([\s\S]*not coalesce\(l\.is_demo, false\) and not public\.fn_inquiry_is_demo\(m\.inquiry_id\)/,
    'the invitations behind the response rate are not demo-filtered');
  assert.match(expr('supplier_response_rate'), /from inv/, 'the response rate is not quoted / invited over the filtered set');
  assert.match(expr('disputes'), /s\.livemode/, 'Stripe TEST-mode disputes are counted');
});

test('the report goes to the CEO and never to the founder', () => {
  const duty = body('fn_ceo_five_number_report');
  assert.match(duty, /fn_seat_handoff\('ceo', 'ceo', 'report\.five_numbers'/, 'the duty does not hand the numbers to the ceo');
  assert.doesNotMatch(code(SRC), /founder|fn_notify_founder|takes_delivery|insert into public\.notifications/i,
    'the five-number report must not be mailed: it is the CEO\'s, not the founder\'s');
  assert.match(SRC, /values \('report\.five_numbers', 'ceo', 'ceo',[\s\S]*'fn_ceo_reads_five_numbers'/, 'the handoff kind is not registered');
});

test('every new routine is closed and pins its search_path', () => {
  for (const [fn, sig] of [['fn_ceo_five_numbers', 'date'], ['fn_ceo_reads_five_numbers', 'bigint'], ['fn_ceo_five_number_report', '']]) {
    assert.match(SRC, new RegExp(`function public\\.${fn}\\([^)]*\\)[\\s\\S]*?set search_path to 'public', 'pg_temp'`, 'i'), `${fn} has no pinned search_path`);
    assert.ok(SRC.includes(`revoke execute on function public.${fn}(${sig}) from public, anon, authenticated;`), `${fn}(${sig}) is not revoked`);
  }
});

test('the duty runs daily and the probe proves the demo exclusion in an aborted transaction', () => {
  assert.match(SRC, /\('ceo\.five_number_report', 'ceo', interval '1 day', 'fn_ceo_five_number_report'/);
  assert.match(PROBE, /raise exception 'CHK<<%>>'/, 'the probe does not abort its transaction');
  assert.match(PROBE, /"qd_run":"probe5num"/, 'the probe no longer writes a demo request to prove it is excluded');
  assert.match(PROBE, /\+ 1 then/, 'the probe no longer asserts the non-demo request counts');
});
