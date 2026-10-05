// THE FOUNDER BRIEF SAYS SEVEN THINGS, IN PLAIN WORDS.            seat: ceo · 21 Sep 2026 · instruction 587
//
// The founder, 21 Sep 2026: the daily brief was "completely useless in the format its shared". He named
// seven things he must always know, in order. The brief that failed him was an operations dump whose
// numbers came partly from status columns (a status column is an intention, not a delivery: 171 leads
// once read "invited" when nothing had been sent) and included demo rows.
//
// This check fails if the same causes come back:
//   A. any of the seven items is missing, renamed out of recognition, or out of order;
//   B. a zero day stops saying "none today" plainly;
//   C. a count reads a status column instead of its event / delivery record;
//   D. a count stops excluding demo data (ZZ DEMO / example.invalid / is_demo);
//   E. the customer PDF path is unhooked from the heartbeat;
//   F. (live, when a management token is present) a fixture day stops reading zero on all six counts
//      while its demo rows are still counted as excluded. The day is 18 Sep 2026, whose demo rows are
//      the PERSISTENT founder demo accounts (qd-founderdemo-*: 2 customers, 3 requests; kept by
//      instruction 571). It was 21 Sep, whose demo rows were leftovers of harness runs 7e3a1c99 and
//      12ddadff; the nightly now sweeps runs that are over (22 Sep 2026, it_engineer), and a check whose
//      evidence is litter fails the day the litter is cleaned.
//
//   node --test scripts/checks/the_founder_brief_says_seven_things.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL_FILE = 'scripts/sql/the_founder_brief_says_seven_things_in_plain_words.sql';
const sql = readFileSync(path.join(REPO, SQL_FILE), 'utf8');
const noComments = (s) => s.replace(/--[^\n]*/g, '');

const fnBody = (name) => {
  const m = sql.match(new RegExp('create or replace function public\\.' + name + '\\([\\s\\S]*?\\n\\$fn\\$;'));
  assert.ok(m, `${name} is not defined in ${SQL_FILE}`);
  return m[0];
};

export const SEVEN = [
  /'1\. Supplier invitations sent: '/,
  /'2\. Suppliers registered: '/,
  /'3\. Customer inquiries received: '/,
  /'4\. Customers registered: '/,
  /'5\. Comparison reports generated: '/,
  /'6\. Customers who paid a reveal fee: '/,
  /'7\. The plan for tomorrow:'/,
];

test('A. all seven items are in the brief text, in the founder\'s order', () => {
  const body = fnBody('fn_founder_brief_text');
  let at = -1;
  SEVEN.forEach((re, i) => {
    const m = body.slice(at + 1).match(re);
    assert.ok(m, `item ${i + 1} is missing or out of order (${re})`);
    at = at + 1 + m.index;
  });
});

test('B. every one of the six counts says "none today" on a zero day', () => {
  const body = fnBody('fn_founder_brief_text');
  const n = (body.match(/'none today\.'/g) || []).length;
  assert.equal(n, 6, `expected 6 plain zero phrasings, found ${n}`);
});

const counts = () => {
  // The markers are comments, so find them in the raw body and strip comments from the slice.
  const raw = fnBody('fn_founder_brief_figures');
  const a = raw.indexOf('-- COUNTS BEGIN'), b = raw.indexOf('-- COUNTS END');
  assert.ok(a > 0 && b > a, 'the COUNTS BEGIN / COUNTS END markers are gone');
  return noComments(raw.slice(a, b));
};

test('C. no count reads a status column', () => {
  const c = counts();
  const bad = c.match(/\b\w*status\b|\bpublication_state\b|\binvited_at\b|\bcontacted\b|\bapproved_at\b/gi);
  assert.equal(bad, null, `a count reads a status column: ${bad}`);
  // ...and each reads its delivery / event record.
  for (const [what, re] of [
    ['invitations: the provider accepted the message', /n\.provider_message_id is not null/],
    ['invitations: sent in the window', /n\.sent_at >= p_from/],
    ['suppliers: registration submitted', /registration_submitted_at >= p_from/],
    ['inquiries: created', /i\.created_at >= p_from/],
    ['customers: created', /c\.created_at >= p_from/],
    ['comparisons: created', /q\.created_at >= p_from/],
    ['reveal fees: Stripe payment id', /t\.payment_ref ~ '\^\(pi\|ch\|py\)_'/],
  ]) assert.match(c, re, what);
});

test('D. every count excludes demo data', () => {
  const sections = counts().split(/with d as \(/).slice(1);
  assert.equal(sections.length, 6, `expected 6 counted sections, found ${sections.length}`);
  sections.forEach((s, i) => {
    assert.match(s, /ZZ DEMO/, `count ${i + 1} does not exclude ZZ DEMO names`);
    assert.match(s, /example\.invalid/, `count ${i + 1} does not exclude example.invalid addresses`);
    assert.match(s, /is_demo/, `count ${i + 1} does not exclude is_demo rows`);
    assert.match(s, /filter \(where not demo\)/, `count ${i + 1} counts demo rows`);
  });
});

test('E. the customer PDF is rendered on the heartbeat and attached, never skipped', () => {
  const rp = readFileSync(path.join(REPO, 'supabase/functions/resilience_ping/index.ts'), 'utf8');
  assert.match(rp, /fn_ceo_daily_digest_attach_pdf/);
  assert.match(rp, /pdf_pending/);
  const submit = fnBody('fn_ceo_daily_digest_submit');
  assert.match(submit, /waiting for the customer list PDF/, 'a day with customers could be sent without its PDF');
  // Applied -> a MANIFEST line; committed and not yet applied -> a note in scripts/sql/pending/. Neither = orphan.
  const listed = readFileSync(path.join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8')
    .split(/\r?\n/).some((l) => l === SQL_FILE) || pendingNotes().has(SQL_FILE);
  assert.ok(listed, 'the file is neither in MANIFEST.txt nor pending (scripts/sql/pending/)');
});

// F. Live replay of the fixture day. The three pure functions are created in pg_temp inside one
//    implicit transaction on the one project; nothing persistent is written, no row is touched.
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

test('F. the 18 Sep 2026 fixture day (the founder demo accounts) reads zero, with its demo rows counted as excluded', async (t) => {
  if (!token) { t.skip('no management token, so production cannot be read'); return; }
  const temp = ['fn_founder_brief_figures', 'fn_founder_brief_text']
    .map((n) => fnBody(n).replace('public.' + n, 'pg_temp.' + n)).join('\n');
  const query = temp + `\nselect f, pg_temp.fn_founder_brief_text(f) as body from (select pg_temp.fn_founder_brief_figures(
      timestamptz '2026-09-18 00:00+04', timestamptz '2026-09-18 20:00+04') f) z;`;
  const rows = await replaySql(query, { rows: true, label: 'routine bodies replayed in pg_temp' });
  const [{ f, body }] = rows;
  for (const k of ['invitations', 'suppliers_registered', 'inquiries', 'customers', 'comparisons', 'reveal_fees'])
    assert.equal(Number(f[k].count), 0, `${k} counted a demo row on the fixture day`);
  const excluded = ['suppliers_registered', 'inquiries', 'customers', 'reveal_fees'].reduce((a, k) => a + Number(f[k].demo_excluded), 0);
  assert.ok(excluded >= 4, `the fixture day's demo rows were not seen at all (${excluded}) - the test would prove nothing`);
  for (let i = 1; i <= 7; i++) assert.match(body, new RegExp('^' + i + '\\. ', 'm'), `item ${i} missing from the rendered brief`);
  assert.equal((body.match(/none today\./g) || []).length, 6);
});
