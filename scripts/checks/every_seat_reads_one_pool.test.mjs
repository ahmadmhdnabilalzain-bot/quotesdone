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
// applied BEFORE the pool file (docs/runbooks/apply-the-shared-pool.md step 1): the authority check reads its limits
const LIMITS = 'scripts/sql/the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql';
const SEATS = ['customer_support', 'sales_engineer', 'marketing', 'it_engineer', 'ceo', 'accountant'];
// what the sibling branches of 13 Nov emit: the sales engineer's request events, and the accountant's hand-over kinds
const SIBLING_TYPES = ['request.reveal_outcome', 'request.reveal_period_ended', 'request.reopened', 'request.step_failed'];
const SIBLING_KINDS = [['reveal.reconcile', 'sales_engineer'], ['sale.made', 'accountant'], ['payment.exception', 'accountant'],
  ['payment.unrecorded', 'accountant'], ['overcharge.customer_notice', 'accountant']];
const STATUSES = ['sent', 'waiting', 'done', 'failed'];

/** The seed rows of the file: [event_type, seat, owns, delivery, reason]. */
export function seedRows(sql) {
  const start = sql.indexOf('insert into pool_seed (event_type, agent_key, owns, delivery, reason) values');
  assert.ok(start >= 0, 'the seed insert is gone');
  const body = sql.slice(start, sql.indexOf(';\n', start));
  return [...body.matchAll(/\(\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)',\s*(true|false),\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)'\s*\)/g)]
    .map((m) => [m[1], m[2], m[3] === 'true', m[4], m[5].replace(/''/g, "'")]);
}
/** Every hand-over kind any SQL file registers: [type, from_seat, to_seat]. */
export function handoffKinds() {
  const out = [];
  for (const f of readdirSync(join(REPO, 'scripts/sql')).filter((x) => x.endsWith('.sql'))) {
    const t = readFileSync(join(REPO, 'scripts/sql', f), 'utf8');
    // only inside the VALUES of an insert into seat_handoff_kind (a call like fn_seat_duty_cross_review('x.y', 'ceo', ...) is not one)
    for (const ins of t.matchAll(/insert into public\.seat_handoff_kind[^;]*?values([\s\S]*?);/gi))
      for (const m of ins[1].matchAll(/\(\s*'([a-z_]+\.[a-z_.]+)',\s*'([a-z_]+)',\s*'([a-z_]+)',\s*'/g)) if (SEATS.includes(m[2]) && SEATS.includes(m[3])) out.push([m[1], m[2], m[3]]);
  }
  return out;
}
/** The types the table must cover: live, every registered kind's echoes, the siblings' and this file's own. */
export function requiredTypes(live) {
  const kinds = [...handoffKinds().map((k) => k[0]), ...SIBLING_KINDS.map((k) => k[0])];
  return [...new Set([...live, ...SIBLING_TYPES, 'handoff.overdue.escalated', ...kinds.flatMap((k) => STATUSES.map((s) => `handoff.${k}.${s}`))])];
}
/** What is wrong with the table for these types; [] when every type has one owner and a considered audience. */
export function coverageFindings(rows, types, seats = SEATS) {
  const out = [];
  const by = new Map();
  for (const r of rows) { if (!by.has(r[0])) by.set(r[0], []); by.get(r[0]).push(r); }
  for (const t of types) {
    const rs = by.get(t) ?? [];
    const owners = rs.filter((r) => r[2]);
    if (!rs.length) out.push(`${t}: no row at all (no owner, no audience)`);
    else if (owners.length !== 1) out.push(`${t}: ${owners.length} owner rows, must be exactly 1`);
    else if (rs.length === 1 && !/nobody else/.test(owners[0][4])) out.push(`${t}: no audience and no "nobody else: <reason>"`);
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
const LIVE_FIXTURE = JSON.parse(read('scripts/fixtures/company_event_types_2026-11-13.json')).types;

test('1. every live type, every registered hand-over kind and the siblings\' types: one producing owner and an audience', () => {
  assert.equal(LIVE_FIXTURE.length, 84, 'the 13 Nov measurement had 84 live types');
  assert.deepEqual(coverageFindings(rows, requiredTypes(LIVE_FIXTURE)), []);
  // the rule itself fails a new type, a second owner, a ghost seat
  assert.deepEqual(coverageFindings(rows, ['brand.new_type']), ['brand.new_type: no row at all (no owner, no audience)']);
  assert.equal(coverageFindings([...rows, ['supplier.approved', 'marketing', true, 'digest', 'x']], ['supplier.approved']).length, 1);
  assert.equal(coverageFindings([['x.y', 'department_head', true, 'digest', 'x']], ['x.y']).length, 2);
  // the owner of a hand-over echo is its PRODUCER: the one seat that sends the kind (review, 13 Nov: it was the first receiver)
  const kinds = [...handoffKinds(), ...SIBLING_KINDS.map(([t, f]) => [t, f, null])];
  const wrong = [];
  for (const t of new Set(kinds.map((k) => k[0]))) {
    const from = [...new Set(kinds.filter((k) => k[0] === t).map((k) => k[1]))];
    if (from.length !== 1) continue;
    const o = rows.find((r) => r[0] === `handoff.${t}.sent` && r[2]);
    if (o && o[1] !== from[0]) wrong.push(`${t}: owner ${o[1]}, producer ${from[0]}`);
  }
  assert.deepEqual(wrong, []);
  // the founder's example has its reader; the three cases that must act file a hand-over
  assert.ok(rows.some((r) => r[0] === 'supplier.approved' && r[1] === 'it_engineer' && r[3] === 'digest'));
  for (const t of ['request.step_failed', 'supplier.applied']) assert.ok(rows.some((r) => r[0] === t && r[3] === 'handover'), `${t} files no hand-over`);
  assert.match(sqlText, /\('event\.act', 'sales_engineer', 'sales_engineer',/, 'the event.act kind is registered');
});

test('1b. a re-run never wipes or overwrites a row someone edited', () => {
  assert.doesNotMatch(sqlText, /delete\s+from\s+public\.event_subscription/i, 'the seed must merge, never wipe');
  assert.match(sqlText, /on conflict \(agent_key, event_type\) do update[\s\S]{0,300}where s\.edited_by is null;/);
  assert.match(sqlText, /new\.edited_by := coalesce\(nullif\(current_setting\('qd\.edited_by', true\), ''\), session_user\);/);
});

test('2. every seat model path reads the one pool; the important line first; inside the budget', () => {
  const pool = read('supabase/functions/_shared/seat_pool.ts');
  const max = Number(pool.match(/export const POOL_MAX_CHARS = (\d+);/)?.[1]);
  const budget = Number(pool.match(/export const SQL_BUDGET = (\d+);/)?.[1]);
  const header = pool.match(/export const POOL_HEADER = '([^']*)';/)?.[1] ?? '';
  assert.ok(max > 0 && max <= 1300, `POOL_MAX_CHARS ${max}: about 300 tokens at most (ruling 1619)`);
  assert.ok(header.length + 1 + budget <= max, 'the header fits beside a full block; nothing is cut in TS');
  assert.doesNotMatch(pool, /\.slice\(0, POOL_MAX_CHARS\)/, 'TS must not cut the block (a cut drops the end, not the least important)');
  assert.match(sqlText, /v_budget int := least\(greatest\(coalesce\(p_budget, 1200\), 200\), 1200\);/);
  const ctx = sqlText.slice(sqlText.indexOf('create or replace function public.fn_seat_pool_context('));
  const iWait = ctx.indexOf("'YOUR HAND-OVERS: '"), iSubj = ctx.indexOf("'THIS SUBJECT (newest first):'"), iToday = ctx.indexOf("'THE COMPANY TODAY (built '");
  assert.ok(iWait > 0 && iWait < iSubj && iSubj < iToday, 'the order is: your hand-overs, the subject, the company today');
  assert.doesNotMatch(ctx.slice(0, ctx.indexOf('end $fn$;')), /fn_seat_pool_digest_build/, 'the context never builds the digest');
  const engine = read('supabase/functions/_shared/think/engine.ts');
  assert.match(engine, /seatPool\(deps, req\.seat, poolSubject\(req\.subject, ctx\.case, ctx\.profile\), audience\)/);
  assert.match(engine, /\.\.\.\(pool\.block \? \{ shared_pool: pool\.block \} : \{\}\)/);
  const reply = read('supabase/functions/_shared/ai_reply.ts');
  assert.match(reply, /r\.poolSubject \? seatPool\(deps, r\.seat, poolSubject\(r\.poolSubject\), r\.audience\)/);
  // an external reader: its own events only, neutral words
  assert.match(sqlText, /where \(p_audience = 'supplier' and k like 'supplier:%'\) or \(p_audience = 'customer' and k like 'customer:%'\)\);/);
  assert.match(sqlText, /\|\| case when v_ext then ': ' \|\| public\.fn_pool_neutral\(x\.what\)/);
});

test('2b. the CEO judges: no code acknowledgement, the routine route, a daily cap held as data, the founder told, never asked', () => {
  assert.match(sqlText, /update public\.seat_handoff_kind set handler = 'fn_ceo_takes_it_finding'\s+where type = 'it\.finding' and from_seat = 'it_engineer' and to_seat = 'ceo';/);
  const take = sqlText.slice(sqlText.indexOf('create or replace function public.fn_ceo_takes_it_finding('), sqlText.indexOf('revoke execute on function public.fn_ceo_takes_it_finding('));
  assert.doesNotMatch(take, /acknowledged/, 'an acknowledgement that decides nothing is not an answer');
  // ceo.authority too (third review, item 4: it ran on the CEO's Opus route at ~AED 0.42 a call against a cap priced at 0.0106)
  assert.match(read('supabase/functions/_shared/think/routing.ts'), /EASY_DUTY_SURFACE = \/(\\\.\(knowledge_refresh\|it_finding\|overdue_handoff\|authority\)\$|\(\\\.\(knowledge_refresh\|it_finding\|overdue_handoff\|authority\)\|\^ceo\\\.order_\(answer\|response\|next\)\)\$)\//);
  assert.match(sqlText, /\('ceo_daily_judgements', '\{"items": 30, "aed": 0\.5, "per_tick": 5, "unit_aed_default": 0\.0106\}'::jsonb,/);
  assert.match(sqlText, /'ceo\.company_pool', 'ceo', interval '15 minutes', 'fn_company_pool_tick'/);
  assert.match(sqlText, /begin v := v \|\| jsonb_build_object\('ceo', public\.fn_ceo_files_judgements\(\)\);/);
  // founder ledger 1696 (15 Nov 2026): nothing waits on the founder. The pool no longer mails him questions; the CEO's daily
  // summary (information only) is sent by the coverage file's duty.
  assert.doesNotMatch(sqlText, /fn_ceo_tells_the_founder_daily\(\)\);|ceo_needs_the_founder'|ask_founder'|needs_founder:/, 'no path in the pool asks the founder');
  const cov = read('scripts/sql/the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql');
  assert.match(cov, /begin v := v \|\| jsonb_build_object\('founder', public\.fn_ceo_daily_summary_to_the_founder\(now\(\)\)\);/);
  assert.doesNotMatch(sqlText, /ceo_model_slot'\)/, 'the CEO\'s judgement is not gated on ceo_model_slot');
});

test('3. one mechanism, and the busy-table locks last', () => {
  const body = sqlText.slice(sqlText.indexOf('create or replace function public.fn_event_dispatch('), sqlText.indexOf('revoke execute on function public.fn_event_dispatch('));
  for (const gone of ['org_tasks', 'os_department', 'org_agents', "'assigned'"]) assert.ok(!body.includes(gone), `fn_event_dispatch still names ${gone}`);
  assert.match(body, /public\.fn_seat_handoff\(/);
  assert.match(read('scripts/sql/DROPPED.txt'), /^trg_company_event_dispatch\(\) :: /m);
  assert.match(sqlText, /set local lock_timeout = '1500ms';/);
  // Review of 13 Nov evening, item 6: no DROP TRIGGER on a busy table in this file (ACCESS EXCLUSIVE, first apply and every
  // re-run); CREATE OR REPLACE TRIGGER (SHARE ROW EXCLUSIVE) after every definition, company_event's last; the department
  // dispatcher's body is a no-op here and its trigger goes alone in its own file.
  assert.doesNotMatch(sqlText, /drop trigger[^;]*on public\.(company_event|agent_actions|seat_judgement|customers)\b/, 'no DROP TRIGGER on a busy table');
  const lastFn = sqlText.lastIndexOf('create or replace function');
  const onAgent = sqlText.indexOf('create or replace trigger zz_pool_link after insert on public.agent_actions');
  const onEvent = sqlText.indexOf('create or replace trigger zz_pool_link after insert on public.company_event');
  assert.ok(onAgent > lastFn && onEvent > onAgent, 'the link triggers come after every definition, company_event last');
  assert.ok(sqlText.lastIndexOf('alter table public.event_subscription') < onEvent && sqlText.lastIndexOf('alter table public.event_subscription') > onAgent,
    'event_subscription\'s DDL comes after the trigger whose lock may wait and before the event stream\'s');
  assert.match(sqlText, /create or replace function public\.trg_company_event_dispatch\(\)[\s\S]{0,300}RETIRED[\s\S]{0,300}return null;/);
  const drop = read('scripts/sql/the_department_dispatcher_trigger_goes_once_its_body_is_a_no_op.sql');
  assert.match(drop, /set local lock_timeout = '1500ms';[\s\S]*drop trigger if exists trg_company_event_dispatch on public\.company_event;/);
  assert.ok(existsSync(join(REPO, 'scripts/sql/pending/the_department_dispatcher_trigger_goes_once_its_body_is_a_no_op.txt')), 'the drop file has its pending note');
  assert.doesNotMatch(sqlText, /create index (?!if not exists (subject_link_key_idx|pool_event_class_at_idx|event_subscription_one_owner))/, 'no index on a busy table');
});

test('4. every decision point says: grant named AND checked, grant named and NOT checked, or no grant', () => {
  const points = JSON.parse(read('supabase/functions/_shared/decision_points.json')).points;
  const j = JSON.parse(read('supabase/functions/_shared/decision_point_grants.json'));
  const bad = []; const n = { checked: 0, not_checked: 0, none: 0 };
  for (const p of points) {
    const e = j.points[p.id];
    if (!e) { bad.push(`${p.id}: no entry`); continue; }
    if (e.seat !== p.seat) bad.push(`${p.id}: seat ${e.seat} is not ${p.seat}`);
    if (e.status === 'grant named AND checked in code') {
      n.checked++;
      const [file, line] = String(e.checked_at ?? '').split(':');
      if (!file || !existsSync(join(REPO, file)) || !/fn_(agent|support)_may_act/.test(read(file).split('\n')[Number(line) - 1] ?? '')) bad.push(`${p.id}: checked_at ${e.checked_at} is no grant check`);
    } else if (e.status === 'grant named, NOT checked') { n.not_checked++; if (!e.grant) bad.push(`${p.id}: names no grant`); }
    else if (e.status === 'no grant') { n.none++; if (!(e.gap ?? '').trim()) bad.push(`${p.id}: no gap reason`); }
    else bad.push(`${p.id}: status ${e.status}`);
  }
  console.log(`decision points: ${n.checked} grant named AND checked in code, ${n.not_checked} grant named NOT checked, ${n.none} no grant`);
  assert.deepEqual(bad, []);
  for (const d of ['resend_inbound.unsubscribe_request', 'email.unsubscribe_request', 'org_task.faq_answered', 'marketing.outreach_reply'])
    assert.ok(j.dangerous.some((x) => x.point === d), `${d} must be on the founder's dangerous list`);
});

const TOKEN = !!supabaseTokenOrEmpty();
const SKIP = TOKEN ? false : 'no Supabase management token in this environment';

test('5a. (production, SELECT) every type emitted in the last 30 days is covered', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const live = (await sql(`select distinct event_type from public.company_event where occurred_at > now() - interval '30 days'`)).map((r) => r.event_type);
  assert.deepEqual(coverageFindings(rows, requiredTypes(live)), []);
});

// LOCAL: a throwaway Postgres 16 built from the mirror (docs/runbooks/apply-the-shared-pool.md). QD_POOL_LOCAL_PG is a psql
// connection string to a database that already holds the mirror; the test copies it, applies the file and the probe there.
const LOCAL = process.env.QD_POOL_LOCAL_PG;
test('5b. (local Postgres) the file applies, the probe answers PROBE OK, and a re-run keeps an edited row', { skip: LOCAL ? false : 'QD_POOL_LOCAL_PG not set', timeout: 600000 }, async () => {
  const { spawnSync } = await import('node:child_process');
  const psql = (args, input) => spawnSync('psql', [LOCAL, '-v', 'ON_ERROR_STOP=1', '-q', ...args], { encoding: 'utf8', input });
  const db = 'pool_check_' + process.pid;
  psql(['-c', `create database ${db} template ${process.env.QD_POOL_LOCAL_TEMPLATE ?? 'qd_base'}`]);
  const at = (x) => spawnSync('psql', [LOCAL.replace(/dbname=\S+/, 'dbname=' + db), '-q', ...x], { encoding: 'utf8' });
  try {
    // the limits file goes first (15 Nov 2026, ledger 1696): the authority check reads fn_company_limit and the classifiers
    assert.equal(at(['-v', 'ON_ERROR_STOP=1', '-1', '-f', join(REPO, LIMITS)]).status, 0, 'the limits file does not apply');
    assert.equal(at(['-v', 'ON_ERROR_STOP=1', '-1', '-f', join(REPO, FILE)]).status, 0, 'the file does not apply');
    assert.match(at(['-f', join(REPO, PROBE)]).stderr, /PROBE OK/);
    at(['-c', "update event_subscription set delivery = 'none', reason = 'edited by the check' where event_type = 'supplier.approved' and agent_key = 'it_engineer'"]);
    at(['-1', '-f', join(REPO, FILE)]);
    assert.match(at(['-tAc', "select reason from event_subscription where event_type = 'supplier.approved' and agent_key = 'it_engineer'"]).stdout, /edited by the check/);
  } finally { psql(['-c', `drop database if exists ${db}`]); }
});

const REHEARSE = TOKEN && process.env.QD_POOL_RELEASE_REHEARSAL === '1' ? false
  : 'the rolled-back production rehearsal runs only at release (QD_POOL_RELEASE_REHEARSAL=1), never during work';
// (5c needs the limits file applied first on production: step 1 of the runbook)
test('5c. (release, rolled back) the probe on production', { skip: REHEARSE, timeout: 300000 }, async () => {
  const { rehearse } = await import('../ci/rehearse_sql.mjs');
  assert.equal(await rehearse(sqlText, read(PROBE), FILE), 'PROBE OK');
});
