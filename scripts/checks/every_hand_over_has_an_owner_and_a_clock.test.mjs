// EVERY HAND-OVER HAS AN OWNER AND A CLOCK, AND CLOSES OR ESCALATES ONCE TO THE CEO (ceo, L4_LOOPS, 16 Nov 2026).
// Founder ledger 1535 ("Not a single thing in our app is one-way communication"), 1688, 1685; rulings 1696/1710 (nothing waits
// on the founder). Measured 16 Nov: 697 open hand-overs; the overdue escalation skipped 199 rows and every non-handoff row, the
// CEO's late-hand-over case shared a room the IT findings took whole (0 ever filed), its 'wait' re-asked for ever, and a missed
// directive was re-issued up to 4 times or left on a ceo_task nobody decides (114 missed from 103 chains).
// Offline, from the canonical text (a pending file wins over MANIFEST). This fails when:
//   1. a kind of pending work has no register entry with an owner rule, a handler that exists in the repository and a clock;
//   2. the sweep closes a row without its reason, closes an unregistered non-handoff row, or closes for any reason other than
//      no handler / test row / a later duplicate whose first copy stays open;
//   3. a late row is escalated to anyone but the CEO, or more than once, or a class of rows is skipped again (age, an old report);
//   4. the CEO's late-hand-over case loses its own room, offers 'wait', or a choice leaves the row open;
//   5. a directive is issued on a check that cannot run, a miss opens a ceo_task or is re-issued automatically, or the seat
//      audit counts a hand-over the seat answered that waits on its sender;
//   6. a routine of the file is not revoked from public, anon and authenticated with its search_path pinned, or the new table
//      has no policy, or the duty is not registered, or the probe stops ending in PROBE OK.
//   node --test scripts/checks/every_hand_over_has_an_owner_and_a_clock.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const FILE = 'scripts/sql/every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates.sql';
const PROBE = 'scripts/sql/every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates_probe.sql';
const read = (f) => readFileSync(f, 'utf8');
/** SQL with comments removed, so a check never matches the prose that explains it. */
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const fnBody = (text, name) => {
  const at = text.indexOf(`create or replace function public.${name}(`);
  return at < 0 ? '' : text.slice(at, text.indexOf('$fn$;', at));
};
/** The file that defines a routine last: a pending file wins over MANIFEST, as at apply. */
const canonical = (name) => {
  const def = new RegExp(String.raw`create\s+or\s+replace\s+function\s+public\.${name}\s*\(`, 'i');
  const defines = (f) => existsSync(f) && def.test(read(f));
  const pending = readdirSync('scripts/sql/pending').filter((n) => n.endsWith('.txt'))
    .map((n) => `scripts/sql/${n.replace(/\.txt$/, '.sql')}`).filter(defines);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql'))
    .map((l) => (l.startsWith('scripts/') ? l : `scripts/sql/${l}`)).filter(defines);
  return pending.at(-1) ?? manifest.at(-1);
};

test('0. the file exists and is the canonical definition of every routine it redefines', () => {
  assert.ok(existsSync(FILE), `${FILE} is missing`);
  for (const fn of ['fn_handoff_overdue_escalate', 'fn_ceo_files_judgements', 'fn_ceo_judgement_room', 'fn_reason_apply_ceo__overdue_handoff',
    'fn_ceo_directive_issue', 'fn_ceo_directive_run', 'fn_ceo_directive_review', 'fn_handover_sweep', 'fn_handover_close',
    'fn_handover_clock_tick', 'fn_directive_missed_to_the_ceo', 'fn_ceo_overdue_room']) {
    assert.equal(canonical(fn), FILE, `${fn} is defined later elsewhere (${canonical(fn)}); this rule no longer holds there`);
  }
  const inManifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).some((l) => l.trim().endsWith('every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates.sql'));
  const pendingNote = existsSync('scripts/sql/pending/every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates.txt');
  assert.ok(inManifest !== pendingNote, 'the file is either applied (MANIFEST line) or pending (note), never both or neither');
});

test('1. every kind of pending work is registered with an owner, a handler that exists and a clock', () => {
  const c = code(read(FILE));
  assert.match(c, /create table if not exists public\.agent_action_kind \([\s\S]*check \(\(retired_reason is null\) = \(close_within is not null\)\)/,
    'a kind is either live with a clock or retired with its reason');
  assert.match(c, /alter table public\.agent_action_kind enable row level security;[\s\S]*create policy agent_action_kind_service_role_only[\s\S]*revoke all on public\.agent_action_kind from anon, authenticated;/);
  const seed = c.slice(c.indexOf('insert into public.agent_action_kind'), c.indexOf('on conflict (kind)', c.indexOf('insert into public.agent_action_kind')));
  const rows = [...seed.matchAll(/\('([a-z_]+)', '(agent|detail_owner_seat)', '([^']+)', (interval '[^']+'|null), (null|'[^']*')/g)];
  const kinds = rows.map((r) => r[1]);
  // the kinds production held pending on 16 Nov 2026 (SELECT), and the one this file files
  for (const k of ['held_question', 'held_question_expired', 'backup_coverage', 'doc_trades_held', 'service_alias_review', 'directive_missed']) {
    assert.ok(kinds.includes(k), `kind ${k} is not registered`);
  }
  const allSql = readdirSync('scripts/sql').filter((n) => n.endsWith('.sql')).map((n) => read(`scripts/sql/${n}`)).join('\n');
  for (const [, kind, , handler, clock] of rows) {
    assert.notEqual(clock, 'null', `${kind} has no clock`);
    if (handler.startsWith('edge:')) {
      const [path, action] = handler.slice(5).split('#');
      assert.ok(existsSync(path) && read(path).includes(action), `${kind}: ${path} does not carry the action ${action}`);
    } else {
      assert.match(allSql, new RegExp(String.raw`function\s+public\.${handler}\s*\(`), `${kind}: its handler ${handler} is defined by no SQL file`);
    }
  }
});

test('2. the sweep closes only what can never complete, always with the reason', () => {
  const s = code(fnBody(read(FILE), 'fn_handover_sweep'));
  assert.match(s, /if r\.kind = 'handoff' and not r\.registered then/, 'only an unregistered HANDOFF is a dead letter; new work of an unregistered kind is never closed');
  const reasons = [...s.matchAll(/v_reason := '([^']*)'/g)].map((m) => m[1].split(':')[0].split(' #')[0].trim());
  for (const r of reasons) assert.ok(['no handler', 'test row', 'duplicate of'].includes(r), `the sweep closes for a reason it may not: ${r}`);
  assert.match(s, /r\.test_reason is not null and r\.created_at < now\(\) - interval '1 day'/, 'a test row a day old, never a live rehearsal');
  assert.match(s, /x\.id < r\.id/, 'a duplicate is the LATER copy; the first stays open');
  assert.match(s, /perform public\.fn_handover_close\(r\.id, 'ceo\.handover_clock', v_reason,/, 'every close goes through the one closer with its reason');
  const close = code(fnBody(read(FILE), 'fn_handover_close'));
  assert.match(close, /if coalesce\(btrim\(p_verdict\), ''\) = '' then raise exception/, 'a hand-over is never closed without its reason');
  assert.match(close, /not k\.originator_closes or a\.detail->>'from' = p_by/, '"done" only where this closer may close it');
  assert.match(close, /a\.detail->>'type' not in \('it\.finding', 'backup\.refile', 'backup\.remediate'\)/, 'a fault or a backup is finished only by its re-verification');
  assert.match(close, /set status = 'dismissed'/, 'otherwise it is dismissed with the reason, never shown as finished');
});

test('3. a late row is escalated once, to the CEO, whatever its kind or age', () => {
  const e = code(fnBody(read(FILE), 'fn_handoff_overdue_escalate'));
  assert.match(e, /from public\.v_handover_open v/, 'every open hand-over, of any kind');
  assert.match(e, /v\.overdue and v\.escalated_at is null/);
  assert.match(e, /not coalesce\(detail->'silence' \? 'escalated_at', false\)/, 'once: a row already escalated is never escalated again');
  assert.match(e, /'escalated_to', 'ceo'/);
  assert.doesNotMatch(e, /founder|escalated_report_id|interval '60 days'/, 'no founder, and no class of rows skipped again');
  const view = code(read(FILE)).slice(code(read(FILE)).indexOf('create or replace view public.v_handover_open'));
  assert.match(view, /fn_handoff_owing_seat\(a\.detail->>'awaiting', a\.agent\)/, 'the owner is the seat that owes the next move');
});

test('4. the CEO decides on his own room, and every choice closes the row', () => {
  const f = code(fnBody(read(FILE), 'fn_ceo_files_judgements'));
  assert.match(f, /v_ov := public\.fn_ceo_overdue_room\(\);/, 'the late hand-overs have their own room');
  assert.match(f, /v_auth_room := case when n <= 1 then n else n \/ 2 end;/, 'authority still takes at most half of the shared room');
  assert.doesNotMatch(f, /'id', 'wait'/, 'no choice re-asks for ever');
  assert.doesNotMatch(f, /needs_founder|ask_founder|'founder'/);
  assert.match(f, /when r\.kind = 'handoff' and r\.detail->>'type' = 'ceo\.order'\s+then jsonb_build_array\(jsonb_build_object\('id', 'withdraw'/, 'a late order is never chased');
  assert.match(code(fnBody(read(FILE), 'fn_ceo_judgement_room')), /where surface in \('ceo\.it_finding', 'ceo\.authority'\)/, 'the shared room no longer counts the late hand-overs');
  const a = code(fnBody(read(FILE), 'fn_reason_apply_ceo__overdue_handoff'));
  assert.match(a, /if not public\.fn_ceo_answer_is_offered\(q, p_result\) then[\s\S]*?return null;/, 'an answer not offered decides nothing');
  assert.match(a, /v_status := public\.fn_handover_close\(h\.id, 'ceo',/, 'every choice ends in the close');
  assert.doesNotMatch(a, /review_at|'wait'/, 'no decision schedules a second look at the same row');
  assert.match(a, /'ceo\.order'/, 'chase and reorder carry the work as an order with its own clock');
});

test('5. a directive has an owner and a check of its result, and its miss is the CEO\'s to decide', () => {
  const t = read(FILE);
  assert.match(code(fnBody(t, 'fn_ceo_directive_issue')), /exception when others then\s+return null;/, 'a check that cannot run issues nothing');
  assert.match(code(fnBody(t, 'fn_ceo_directive_issue')), /status = 'active'/, 'the owner is a live seat');
  const run = code(fnBody(t, 'fn_ceo_directive_run'));
  assert.doesNotMatch(run, /fn_ceo_task_open/, 'a miss no longer opens a ceo_task nobody decides');
  assert.match(run, /v_task := public\.fn_directive_missed_to_the_ceo\(d\.id, v_err\);/);
  assert.match(run, /from public\.v_handover_open h\s+where h\.owner_seat = %1\$L and case when h\.kind = 'handoff' then public\.fn_handoff_is_late\(/,
    'the seat audit counts the hand-overs the seat itself owes');
  const rv = code(fnBody(t, 'fn_ceo_directive_review'));
  assert.doesNotMatch(rv, /insert into public\.ceo_directive/, 'no automatic re-issue');
  assert.match(rv, /fn_directive_missed_to_the_ceo\(d\.id, null\)/);
  assert.match(code(t), /check \(status = any \(array\['open', 'met', 'escalated', 'missed', 'paused', 'withdrawn'\]\)\)/);
  assert.match(code(t), /update public\.ceo_directive\s+set status = 'withdrawn'[\s\S]*'reason', 'superseded: /, 'a withdrawn directive says why');
});

test('6. revokes, pinned search_path, the duty, and the probe', () => {
  const c = code(read(FILE));
  const defs = [...c.matchAll(/create or replace function public\.([a-z0-9_]+)\(/g)].map((m) => m[1]);
  assert.ok(defs.length >= 14, `expected the file's routines, found ${defs.length}`);
  for (const name of defs) {
    assert.match(fnBody(c, name), /set search_path to 'public', 'pg_temp'/i, `${name}: search_path not pinned`);
    assert.match(c, new RegExp(String.raw`revoke execute on function public\.${name}\(.*\) from public, anon, authenticated;`), `${name}: not revoked`);
  }
  assert.match(c, /revoke all on public\.v_handover_open from anon, authenticated;/);
  assert.match(c, /\('ceo\.handover_clock', 'ceo', interval '1 hour', 'fn_handover_clock_tick'/, 'the clock is a registered hourly CEO duty');
  assert.match(code(fnBody(read(FILE), 'fn_handover_clock_tick')), /fn_seat_duty_result_record\('ceo\.handover_clock'/, 'the duty names the result it moves');
  const p = read(PROBE);
  assert.match(p, /raise exception 'CHK<<PROBE OK>>';\s*end \$probe\$;\s*$/, 'the probe ends in PROBE OK and so always rolls back');
  assert.match(p, /live-handler rows were closed by the sweep/, 'the probe proves no live-handler row was closed');
});
