// EVERY SEAT READS ONE POOL (ceo, 13 Nov 2026, founder ledger 1688):
//   "there is like a shared pool where they all know what's going on around. So it can't be like the case where a sales
//    engineer is done verifying a customer or whatever, and then the IT is not aware of that ... everyone should know."
// Measured that day: company_event took 59,933 rows of 84 types in 30 days and event_subscription had 0 rows; no seat's model
// context carried what another seat did. scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql built the
// pool; _shared/seat_pool.ts reads it on every seat's model path. This fails when:
//   1. a live event type (or one the sibling branches emit) has no owner seat and no stated audience in the seed, a row names
//      a seat that does not exist, a 'handover' row names no hand-over kind, or a reason is empty -- and a NEW type with no
//      row fails the same rule (the rule is tested on a made-up type, so it cannot pass by being empty);
//   2. a model path stops reading the pool (think's synthesis, aiReply, the CEO's judgement), or the block's budget grows
//      past 1,300 characters (about 300 tokens; ruling 1619, the prompt diet);
//   3. the department dispatcher comes back: the per-statement trigger, org_tasks in fn_event_dispatch, or a second schedule;
//   4. a decision point names neither the grant it acts under nor the gap (decision_point_grants.json), or names a grant
//      that is not seeded for its seat;
//   5. (with a token) production has a live type the table does not cover; and, at release only (QD_POOL_RELEASE_REHEARSAL=1),
//      the probe -- three seats on one subject, the founder's supplier.approved example, the overdue escalation, the budget --
//      does not answer PROBE OK, rolled back.
//   node --test scripts/checks/every_seat_reads_one_pool.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { supabaseTokenOrEmpty } from '../lib/supabase_token.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql';
const PROBE = 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back_probe.sql';
const SEATS = ['customer_support', 'sales_engineer', 'marketing', 'it_engineer', 'ceo', 'accountant'];
// what the sibling branches of 13 Nov emit (sales_engineer: a paid request is closed; accountant: a payment is booked)
const SIBLING_TYPES = ['request.reveal_outcome', 'request.reveal_period_ended', 'request.reopened', 'request.step_failed',
  ...['sale.made', 'payment.exception', 'payment.unrecorded', 'reveal.reconcile'].map((k) => `handoff.${k}.sent`)];

/** The seed rows of the file: [event_type, seat, owns, delivery, reason]. */
export function seedRows(sql) {
  const start = sql.indexOf('insert into public.event_subscription (event_type, agent_key, owns, delivery, reason) values');
  assert.ok(start >= 0, 'the seed insert is gone');
  const body = sql.slice(start, sql.indexOf(';\n', start));
  return [...body.matchAll(/\(\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)',\s*(true|false),\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)'\s*\)/g)]
    .map((m) => [m[1], m[2], m[3] === 'true', m[4], m[5].replace(/''/g, "'")]);
}
/** What is wrong with the table for these types; [] when every type has one owner and a stated audience. */
export function coverageFindings(rows, types, seats = SEATS) {
  const out = [];
  const by = new Map();
  for (const r of rows) { if (!by.has(r[0])) by.set(r[0], []); by.get(r[0]).push(r); }
  for (const t of types) {
    const rs = by.get(t) ?? [];
    const owners = rs.filter((r) => r[2]);
    if (!rs.length) out.push(`${t}: no row at all (no owner, no audience)`);
    else if (owners.length !== 1) out.push(`${t}: ${owners.length} owner rows, must be exactly 1`);
  }
  for (const r of rows) {
    if (!seats.includes(r[1])) out.push(`${r[0]}: ${r[1]} is not a live seat`);
    if (!['digest', 'handover', 'none'].includes(r[3])) out.push(`${r[0]}/${r[1]}: delivery ${r[3]}`);
    if (!r[4].trim()) out.push(`${r[0]}/${r[1]}: no reason`);
  }
  return out;
}

const sqlText = read(FILE);
const rows = seedRows(sqlText);

test('1. every live event type, and every type the sibling branches emit, has one owner and a stated audience', () => {
  const fixture = JSON.parse(read('scripts/fixtures/company_event_types_2026-11-13.json'));
  assert.equal(fixture.types.length, 84, 'the 13 Nov measurement had 84 live types');
  assert.deepEqual(coverageFindings(rows, [...fixture.types, ...SIBLING_TYPES, 'handoff.overdue.escalated']), []);
  // the rule itself: a new type with no row fails, a second owner fails, a ghost seat fails
  assert.deepEqual(coverageFindings(rows, ['brand.new_type']), ['brand.new_type: no row at all (no owner, no audience)']);
  assert.equal(coverageFindings([...rows, ['supplier.approved', 'marketing', true, 'digest', 'x']], ['supplier.approved']).length, 1);
  assert.equal(coverageFindings([['x.y', 'department_head', true, 'digest', 'x']], ['x.y']).length, 1);
  // the founder's example has its reader
  assert.ok(rows.some((r) => r[0] === 'supplier.approved' && r[1] === 'it_engineer' && r[3] === 'digest'), 'the it_engineer must hear supplier.approved');
  assert.ok(rows.some((r) => r[0] === 'supplier.approved' && r[1] === 'sales_engineer' && r[2]), 'the sales engineer owns supplier.approved');
  // a 'handover' row must name the kind it files (the table also refuses it: event_subscription_handover_names_its_kind)
  assert.match(sqlText, /check \(delivery <> 'handover' or nullif\(btrim\(action_class\), ''\) is not null\)/);
});

test('2. every seat model path reads the one pool, inside the budget', () => {
  const pool = read('supabase/functions/_shared/seat_pool.ts');
  const max = Number(pool.match(/export const POOL_MAX_CHARS = (\d+);/)?.[1]);
  assert.ok(max > 0 && max <= 1300, `POOL_MAX_CHARS ${max}: the pool is at most about 300 tokens (ruling 1619)`);
  assert.match(pool, /\(POOL_HEADER \+ '\\n' \+ raw\)\.slice\(0, POOL_MAX_CHARS\)/, 'the header counts inside the budget');
  assert.match(sqlText, /'YOUR HAND-OVERS: ' \|\| v_wait end\), 1300\);/, 'fn_seat_pool_context cuts its block at 1,300');
  assert.match(sqlText, /left\(concat_ws\(' ',[\s\S]*?\), 700\),/, 'the digest body is cut at 700');
  const engine = read('supabase/functions/_shared/think/engine.ts');
  assert.match(engine, /seatPool\(deps, req\.seat, poolSubject\(req\.subject, ctx\.case, ctx\.profile\), audience\)/, 'think() reads the pool for every seat');
  assert.match(engine, /\.\.\.\(pool\.block \? \{ shared_pool: pool\.block \} : \{\}\)/, 'the synthesis carries it');
  const reply = read('supabase/functions/_shared/ai_reply.ts');
  assert.match(reply, /r\.poolSubject \? seatPool\(deps, r\.seat, poolSubject\(r\.poolSubject\), r\.audience\)/, 'aiReply reads the pool');
  assert.match(reply, /\(pool\.block \? pool\.block \+ '\\n\\n' : ''\)/, 'aiReply puts it in the input, after the cached prefix');
  assert.match(read('supabase/functions/ceo_agent/index.ts'), /seatPool\(admin, 'ceo', null, 'internal'\)/, 'the CEO judges with the pool');
  // an external reader gets kinds and states only
  assert.match(sqlText, /case when \(select yes from ext\) then coalesce\(' \(' \|\| x\.state \|\| '\)', ''\)/);
});

test('3. one mechanism: no per-statement dispatcher, no departments, one schedule', () => {
  assert.match(sqlText, /drop trigger if exists trg_company_event_dispatch on public\.company_event;/);
  const body = sqlText.slice(sqlText.indexOf('create or replace function public.fn_event_dispatch('), sqlText.indexOf('revoke execute on function public.fn_event_dispatch('));
  assert.ok(body.length > 100, 'fn_event_dispatch is defined here');
  for (const gone of ['org_tasks', 'os_department', 'org_agents', "'assigned'"]) assert.ok(!body.includes(gone), `fn_event_dispatch still names ${gone}`);
  assert.match(body, /public\.fn_seat_handoff\(/, 'a hand-over subscription is filed through fn_seat_handoff');
  assert.match(sqlText, /\('ceo\.company_pool', 'ceo', interval '15 minutes', 'fn_company_pool_tick'/);
  assert.match(read('scripts/sql/DROPPED.txt'), /^trg_company_event_dispatch\(\) :: /m, 'the dropped trigger function is recorded');
  // the order inside the file: the trigger goes BEFORE the first subscription row exists
  assert.ok(sqlText.indexOf('drop trigger if exists trg_company_event_dispatch') < sqlText.indexOf('insert into public.event_subscription'));
});

test('4. every decision point names the grant it acts under, or the gap', () => {
  const points = JSON.parse(read('supabase/functions/_shared/decision_points.json')).points;
  const map = JSON.parse(read('supabase/functions/_shared/decision_point_grants.json')).points;
  const seeded = new Map();
  for (const f of readdirSync(join(REPO, 'scripts/sql')).filter((x) => x.endsWith('.sql'))) {
    const t = readFileSync(join(REPO, 'scripts/sql', f), 'utf8');
    if (!t.includes('ceo_standing_grant')) continue;
    for (const m of t.matchAll(/\(\s*'([a-z_]+\.[a-z_]+)',\s*'([a-z_]+)'/g)) if (SEATS.includes(m[2])) seeded.set(m[1], m[2]);
  }
  assert.ok(existsSync(join(REPO, 'scripts/sql/the_ceo_is_the_final_internal_authority_and_nothing_waits_for_the_founder.sql')));
  const bad = [];
  for (const p of points) {
    const e = map[p.id];
    if (!e) { bad.push(`${p.id}: no entry`); continue; }
    if (e.seat !== p.seat) bad.push(`${p.id}: seat ${e.seat} is not the point's ${p.seat}`);
    if (e.grant && e.gap) bad.push(`${p.id}: both a grant and a gap`);
    if (!e.grant && !(e.gap ?? '').trim()) bad.push(`${p.id}: neither a grant nor a gap`);
    if (e.grant && p.seat === 'ceo' && e.grant !== 'ceo.final_internal_authority') bad.push(`${p.id}: the CEO acts under the constitution`);
    if (e.grant && p.seat !== 'ceo' && seeded.get(e.grant) !== p.seat) bad.push(`${p.id}: ${e.grant} is not a grant seeded for ${p.seat}`);
  }
  for (const id of Object.keys(map)) if (!points.some((p) => p.id === id)) bad.push(`${id}: in the grant map, not a decision point`);
  assert.deepEqual(bad, []);
});

const TOKEN = !!supabaseTokenOrEmpty();
const SKIP = TOKEN ? false : 'no Supabase management token in this environment';

test('5a. (production) every type emitted in the last 30 days is covered by the seed', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const live = (await sql(`select distinct event_type from public.company_event where occurred_at > now() - interval '30 days'`)).map((r) => r.event_type);
  assert.deepEqual(coverageFindings(rows, live), []);
});

// NEVER DURING ITERATION (coordinator, 13 Nov 2026): a rehearsal holds the file's locks on production for its whole
// transaction, and that day's rehearsals made live readers and writers time out. Only the release step runs it, on purpose.
const REHEARSE = TOKEN && process.env.QD_POOL_RELEASE_REHEARSAL === '1' ? false
  : 'the rolled-back production rehearsal runs only at release (QD_POOL_RELEASE_REHEARSAL=1)';
test('5b. (release, rolled back) three seats on one subject, supplier.approved, the overdue escalation, the budget', { skip: REHEARSE, timeout: 300000 }, async () => {
  const { rehearse } = await import('../ci/rehearse_sql.mjs');
  assert.equal(await rehearse(sqlText, read(PROBE), FILE), 'PROBE OK');
});
