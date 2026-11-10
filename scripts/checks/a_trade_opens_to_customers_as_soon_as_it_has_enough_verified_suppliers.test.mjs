// A TRADE OPENS TO CUSTOMERS AS SOON AS IT HAS ENOUGH VERIFIED SUPPLIERS.   seat: ceo · 10 Nov 2026 · ledger 1614, 1616
//
// Measured 10 Nov 2026: fn_ceo_launch_readiness held customers out until all 223 trades had 10 suppliers ("Customers launch
// only when every trade is covered"), and nothing at the customer doors read coverage at all. This fails if:
//   A. the canonical launch gate (MANIFEST plus pending, the file that wins) still needs every trade, or mails the founder;
//   B. the opening floor stops being the schema (CHECK 5..25, floor = 5), or a demo supplier starts to count;
//   C. a customer door stops asking: create_inquiry before the intake is claimed, the WhatsApp interview, and every reveal
//      (reveal_guard.ts canReveal, failing closed);
//   D. with a token: the file and its probe in one rolled-back transaction do not answer PROBE OK.
//
//   node --test scripts/checks/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql';
const PROBE = FILE.replace('.sql', '_probe.sql');
const read = (p) => readFileSync(path.join(REPO, p), 'utf8');
const noComments = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();

// the file the apply order makes canonical for a routine: the LAST manifest (or pending) entry that defines it
function canonicalBody(name) {
  const order = manifestWithPending();
  let body = null;
  for (const f of order) {
    if (!existsSync(path.join(REPO, f))) continue;
    const src = noComments(read(f));
    const m = src.match(new RegExp('create or replace function public\\.' + name + '\\([\\s\\S]*?\\$fn\\$[\\s\\S]*?\\$fn\\$', 'i'));
    if (m) body = { file: f, text: m[0] };
  }
  return body;
}

test('A. the launch gate is trade by trade and mails nobody', () => {
  const g = canonicalBody('fn_ceo_launch_readiness');
  assert.ok(g, 'fn_ceo_launch_readiness has no canonical file');
  assert.doesNotMatch(g.text, /v_ready\s*=\s*v_total/, `${g.file}: the gate still needs every trade (ledger 1614)`);
  assert.doesNotMatch(g.text, /every trade is covered/i, `${g.file}: the gate still says every trade`);
  assert.doesNotMatch(g.text, /fn_seat_handoff\(|recipient_role'\s*,\s*'founder/, `${g.file}: the gate mails the founder (ledger 1616)`);
  assert.match(g.text, /trade_customer_opening/, `${g.file}: the gate does not read the per-trade opening`);
});

test('B. the floor is the schema and a demo supplier never counts', () => {
  const src = noComments(read(FILE));
  assert.match(src, /open_at_suppliers\s+integer not null check \(open_at_suppliers between 5 and 25\)/, 'the CEO can set the threshold outside 5..25');
  assert.match(src, /floor_suppliers\s+integer not null default 5 check \(floor_suppliers = 5\)/, 'the floor is no longer fixed at 5 in the schema');
  const count = src.match(/function public\.fn_trade_verified_suppliers\([\s\S]*?\$fn\$[\s\S]*?\$fn\$/)[0];
  assert.match(count, /\(not coalesce\(l\.is_demo, false\) or p_with_fixtures\)/, 'a demo supplier counts for a real customer, or never for a demo one');
  // the fixture flag comes only from the estate's demo markers, never from a caller's word
  const join = src.match(/function public\.fn_trade_waitlist_join\([\s\S]*?\$fn\$[\s\S]*?\$fn\$/)[0];
  assert.match(join, /v_fixture := \(v_customer is not null and public\.fn_customer_is_demo\(v_customer\)\)\s+or \(p_phone is not null and public\.fn_is_demo_phone\(p_phone\)\)/, 'the door decides "demo" from something other than the demo markers');
  const rev = src.match(/function public\.fn_trade_reveal_allowed\([\s\S]*?\$fn\$[\s\S]*?\$fn\$/)[0];
  assert.match(rev, /v_fixture := public\.fn_inquiry_is_demo\(i\.id\)/, 'the reveal decides "demo" from something other than fn_inquiry_is_demo');
  const tick = src.match(/function public\.fn_ceo_trade_opening_tick\([\s\S]*?\$fn\$[\s\S]*?\$fn\$/)[0];
  assert.match(tick, /where sc\.confirmed_at is not null and not coalesce\(l\.is_demo, false\)/, 'the real opening state counts demo suppliers');
  assert.match(count, /confirmed_at is not null[\s\S]*fn_is_matchable\(/, 'the count is not the supply gap predicate (confirmed + matchable)');
  // hysteresis: opens at the threshold, closes only under the floor
  assert.match(src, /when o\.is_open then excluded\.verified_suppliers >= r\.floor_suppliers else excluded\.verified_suppliers >= excluded\.open_at/, 'opening/closing lost its hysteresis');
  // a fixture is told without a message
  assert.match(src, /fn_customer_is_demo\(w\.customer_id\)[\s\S]*?fn_is_demo_phone\(w\.phone\)[\s\S]*?'fixture', true/, 'a fixture on the waiting list can be sent a real notice');
  for (const t of ['trade_opening_rule', 'trade_customer_opening', 'customer_trade_waitlist']) {
    assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}[^;]*using \\(false\\) with check \\(false\\)`), `${t} has no policy`);
    assert.match(src, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t} is not revoked`);
  }
  for (const [, name] of src.matchAll(/create or replace function public\.(\w+)\(/g)) {
    assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated;`), `${name} is not revoked`);
  }
  assert.ok(pendingNotes().has(FILE) !== read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('C. every customer door asks, and the reveal fails closed', () => {
  const create = read('supabase/functions/customer_api/actions/inquiry_create.ts');
  const ask = create.indexOf('joinIfNotOpen(admin');
  assert.ok(ask > 0, 'create_inquiry does not ask whether the trade is open');
  assert.ok(ask < create.indexOf('await claimIntake('), 'the trade is asked after the intake is claimed: a waiting request would be consumed');
  assert.match(create, /tg\.state === 'not_open'\) \{ const a = notOpenAnswer\(tg\); return J\(a\.body, a\.status\); \}/, 'a not-open trade still posts');
  const say = read('supabase/functions/wa_inbound/say.ts');
  assert.match(say, /joinIfNotOpen\(admin, \{ slugs: ctx\.codes, channel: 'whatsapp'/, 'the WhatsApp interview does not ask whether the trade is open');
  assert.match(say, /if \(ex\?\.waiting && !lane\) must = /, 'the WhatsApp reply is not bound to carry the waiting sentence');
  const guard = read('supabase/functions/_shared/reveal_guard.ts');
  assert.match(guard, /rpc\('fn_trade_reveal_allowed'[\s\S]{0,200}if \(tr\?\.error\) throw/, 'the reveal does not fail closed on the trade floor');
  assert.match(guard, /allowed === false\) return refuse\('trade_below_floor'\)/, 'a reveal under the floor is not refused');
  const shared = read('supabase/functions/_shared/trade_opening.ts');
  assert.match(shared, /status: 409[\s\S]*message_ar/, 'the portal refusal does not carry both languages');
});

test('D. the file and its probe, rolled back', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const text = (pendingNotes().has(FILE) ? read(FILE) + '\n;\n' : '') + read(PROBE);
  await assert.rejects(replaySql(text, { label: 'the trade-opening probe' }), /PROBE OK/, 'the probe did not end PROBE OK');
});
