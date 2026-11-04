// EVERY DUTY HAS AN OWNER AND A CLOCK (22 Sep 2026, ceo; founder instruction 583).
//
// What fails if the causes of the staff audit's gaps come back:
//   * a clock routine loses its heartbeat step, its revoke, or its Arabic       -> the static tests
//   * a clock stops acting, acts twice, writes to a real address or the founder -> the live probe
//     (scripts/sql/complaints_quotes_reveals_and_support_replies_each_run_on_a_clock_probe.sql: a
//     rolled-back rehearsal on ZZ DEMO fixtures, zero residue, one verdict row)
// Ownership (a deployed function with no owner, or a stale owner row) is scripts/checks/
// every_deployed_function_has_an_owner.mjs, run by the same parity job.
//
//   node --test scripts/checks/every_duty_has_an_owner_and_a_clock.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { sql } from '../lib/db.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const CHANGE = R('scripts/sql/complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql');
const PROBE = R('scripts/sql/complaints_quotes_reveals_and_support_replies_each_run_on_a_clock_probe.sql');
const PING = R('supabase/functions/resilience_ping/index.ts');

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('the four clocks are one heartbeat step, scheduled and wired', () => {
  assert.match(PING, /seatClocks:\s*\{\s*run:\s*seatClocksTick\s*\}/, 'resilience_ping STEP_RUN has no seatClocks step');
  assert.match(PING, /rpc\('fn_seat_clocks_tick'\)/, 'seatClocksTick does not call fn_seat_clocks_tick');
  assert.match(CHANGE, /insert into public\.resilience_step[\s\S]{0,80}'seatClocks'/, 'no resilience_step row schedules seatClocks');
  for (const fn of ['fn_complaint_clock_tick', 'fn_rfq_short_of_quotes_tick', 'fn_reveal_outcome_check_tick', 'fn_support_reply_watch_tick']) {
    assert.match(CHANGE, new RegExp(`then public\\.${fn}\\(|else public\\.${fn}\\(`), `fn_seat_clocks_tick does not run ${fn}`);
  }
});

test('every routine the file creates is revoked from anon and authenticated and pins its search_path', () => {
  const made = [...CHANGE.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]);
  assert.ok(made.length >= 12, `expected the clock routines, found ${made.length}`);
  for (const fn of made) {
    assert.match(CHANGE, new RegExp(`revoke execute on function public\\.${fn}\\([^)]*\\) from public, anon, authenticated`), `${fn} is not revoked`);
    const body = CHANGE.slice(CHANGE.indexOf(`create or replace function public.${fn}(`)).split('$fn$')[0];
    assert.match(body, /set search_path to 'public', 'pg_temp'/, `${fn} has no pinned search_path`);
  }
});

test('every customer- and supplier-facing message is written in English and in Arabic', () => {
  for (const kind of ['rfq_invite', 'rfq_quote_reminder', 'rfq_short_of_quotes', 'reveal_outcome_check']) {
    const at = CHANGE.indexOf(`p_kind = '${kind}'`);
    assert.ok(at > 0, `no text for ${kind}`);
    const branch = CHANGE.slice(at, CHANGE.indexOf('elsif p_kind', at + 1) > 0 ? CHANGE.indexOf('elsif p_kind', at + 1) : CHANGE.indexOf('else\n    raise', at));
    assert.match(branch, /if v_ar then[\s\S]*[؀-ۿ][\s\S]*else[\s\S]*v_subj :=/, `${kind} has no Arabic branch`);
    assert.match(branch, /تحية طيبة وبعد/, `${kind}: the Arabic is not in the formal register`);
  }
  // Nothing addresses the founder: no founder role, no fn_notify_founder, only the CEO report and the seat.
  assert.doesNotMatch(CHANGE, /fn_notify_founder\(|to_role['"]?,\s*'founder'/, 'a clock addresses the founder');
});

// ONE SUPPRESSION RULE IN TWO LANGUAGES (instruction 632, PR #804). send_outbox applies the TS policy; the
// seat clocks apply the SQL mirror before they queue. If the lists drift, a clock queues what the outbox then
// suppresses (or refuses what the outbox would send) -- so the two lists must be identical, and the SQL answers
// must equal the TS rule on every (reason, type) pair.
const POLICY_TS = R('supabase/functions/_shared/suppression_policy.ts');
const listOf = (src, re) => { const m = src.match(re); assert.ok(m, 'list not found'); return [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]); };
const TS_LIST = listOf(POLICY_TS, /export const OPT_OUT_TYPES[^=]*=\s*\[([^\]]*)\]/);
// THE NEWEST COMMITTED DEFINITION (28 Oct 2026, ledger 1401 audit S6): fn_opt_out_types() moved to
// a_supplier_who_said_stop_is_never_nudged.sql, which adds supplier_invite_nudge. While that file is
// pending (applied at merge), the list it will make live is the one compared; once applied it is the MANIFEST's last.
const OPT_OUT_DEF = /create or replace function public\.fn_opt_out_types\(\)[\s\S]*?select array\[([^\]]*)\]/;
const OPT_OUT_FILE = (() => {
  const pending = existsSync(join(ROOT, 'scripts/sql/pending')) ? readdirSync(join(ROOT, 'scripts/sql/pending')).map((n) => 'scripts/sql/' + n.replace(/\.txt$/, '.sql')) : [];
  const manifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).filter((l) => l.endsWith('.sql')).reverse();
  return [...pending, ...manifest].find((f) => existsSync(join(ROOT, f)) && OPT_OUT_DEF.test(R(f)));
})();
const OPT_OUT_PENDING = !!OPT_OUT_FILE && existsSync(join(ROOT, 'scripts/sql/pending', OPT_OUT_FILE.split('/').pop().replace(/\.sql$/, '.txt')));
const SQL_LIST = listOf(R(OPT_OUT_FILE), OPT_OUT_DEF);

test('the SQL opt-out list is the TS opt-out list', () => {
  assert.deepEqual(SQL_LIST, TS_LIST, 'fn_opt_out_types() and OPT_OUT_TYPES disagree');
  assert.ok(TS_LIST.includes('supplier_rfq_widened_invite'), 'the cold widened invitation is not opt-out-eligible');
  for (const t of ['rfq_quote_reminder', 'rfq_short_of_quotes', 'reveal_outcome_check']) {
    assert.ok(!TS_LIST.includes(t), `${t} is transactional and must not be stopped by an opt-out`);
  }
});

test('fn_suppression_stops answers what suppressionStops answers, on every reason and type', { skip: SKIP }, async () => {
  const reasons = ['unsubscribe', 'UNSUBSCRIBE ', 'hard_bounce:permanent', 'spam_complaint', 'blocked: pattern', ''];
  const types = [...TS_LIST, 'rfq_quote_reminder', 'rfq_short_of_quotes', 'reveal_outcome_check', 'new_inquiry', 'login_otp'];
  const pairs = reasons.flatMap((r) => types.map((t) => `('${r}','${t}')`)).join(',');
  // A pending definition is replayed first, in the same rolled-back request, so production answers what it WILL answer.
  const ask = `select r, t, public.fn_suppression_stops(r, t) as stops from (values ${pairs}) v(r, t)`;
  const rows = OPT_OUT_PENDING ? await replaySql(R(OPT_OUT_FILE) + '\n' + ask + ';', { retry: false, rows: true }) : await sql(ask);
  assert.ok(Array.isArray(rows) && rows.length === reasons.length * types.length, JSON.stringify(rows).slice(0, 300));
  for (const x of rows) {
    const ts = String(x.r).trim().toLowerCase() !== 'unsubscribe' || TS_LIST.includes(x.t);   // suppressionStops, verbatim rule
    assert.equal(x.stops, ts, `reason '${x.r}', type ${x.t}: SQL ${x.stops}, TS ${ts}`);
  }
});

// The probe's "nothing to a real address" count must be of ITS OWN writes. Counting every notification with id > the start
// id also counts another session's rows (2 Nov 2026: a live WhatsApp walk's skipped support_reply, to_email null, failed
// PR #1650). This fails on the old probe, whose count had no created_at = now() scope.
test('the real-address count in the probe is scoped to its own transaction, not other sessions rows', () => {
  const at = PROBE.indexOf('went to a real address or to the founder');
  assert.ok(at > 0, 'the real-address assertion is gone');
  const stmt = PROBE.slice(PROBE.lastIndexOf('select count(*) into v_n from public.notifications', at), at);
  assert.match(stmt, /created_at\s*=\s*now\(\)/, 'the real-address count reads other sessions rows too');
  assert.match(stmt, /not public\.fn_is_demo_email\(to_email\)[\s\S]*'founder', 'admin'[\s\S]*founder_alert/, 'the assertion was weakened');
});

test('the rolled-back rehearsal on production answers PROBE OK', { skip: SKIP }, async () => {
  // A deadlock with the live resilience_ping tick is contention, not a finding (12 Oct 2026: 3 of ~10 CI runs). The
  // probe rolls back everything it writes, so it is re-run, at most three times, on that one error and no other.
  let verdict = "";
  for (let i = 0; i < 3; i++) {
    const r = await replaySql(PROBE, { retry: false, rows: true });
    verdict = Array.isArray(r) && r[0] ? String(r[0].verdict) : JSON.stringify(r).slice(0, 500);
    if (!/deadlock detected/.test(verdict)) break;
  }
  assert.match(verdict, /^PROBE OK/, verdict);
});
