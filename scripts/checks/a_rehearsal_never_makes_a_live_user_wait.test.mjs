// A REHEARSAL NEVER MAKES A LIVE USER WAIT (it_engineer, 13 Nov 2026). Offline: no database.
//
// On 13 Nov 2026 rolled-back rehearsals of whole SQL files on production held ACCESS EXCLUSIVE on quotes, inquiries and
// transactions for 12-15 s at a time; 103 live requests waited behind 28 of them, and the functions' 8 s statement
// timeout killed a supplier's agreement certificate write (07:46:10), a supplier's spec_fill at the hold desk (08:11:08)
// and 29 dashboard reads at 08:03 and 08:08 (scripts/lib/replay_guard.mjs header). This fails if any path that sends a
// replay to production loses the guard: the refusal of hot-table DDL, the 1 s lock_timeout, the transaction_timeout, one
// replay at a time, the lowered lock_timeout of a file's own SET, and the apply's own lock_timeout.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { HOLD_LIMIT, HOLD_LIMIT_HOT, planReplay, stallsLiveUsers, strongTableLocks, tightenLimits } from '../lib/replay_guard.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');

// The lock-taking statements of the sales_engineer W2 file whose rehearsals held quotes and inquiries on 13 Nov.
const W2 = [
  'alter table public.inquiries add column if not exists reveal_open_until timestamptz;',
  'alter table public.quotes drop constraint if exists quotes_vat_treatment_known;',
  'drop trigger if exists z33_a_quote_moves_its_requests_reveal_period on public.quotes;',
  'create trigger z33_a_quote_moves_its_requests_reveal_period after update of status, expires_at on public.quotes for each row execute function public.fn_x();',
  'alter table public.quotes alter column quote_amount drop not null;',
  "do $p$ begin raise exception 'PROBE OK'; end $p$;",
].join('\n');

test('the W2 rehearsal is refused before anything is sent, naming every statement that would stall live users', () => {
  const stalls = stallsLiveUsers(W2);
  assert.deepEqual(stalls.map((s) => `${s.line} ${s.kind} ${s.table}`),
    ['1 ALTER TABLE inquiries', '2 ALTER TABLE quotes', '3 DROP TRIGGER quotes', '4 CREATE TRIGGER quotes', '5 ALTER TABLE quotes']);
  assert.throws(() => planReplay(W2, { label: 'w2' }), /SAFE REPLAY REFUSED: w2 takes a strong lock on a hot table[\s\S]*line 1 ALTER TABLE inquiries/);
});

test('accepted by the operator, it runs with a 1 s lock_timeout, a short hard cap and one replay at a time', () => {
  const { prelude } = planReplay(W2, { acceptStall: true });
  assert.match(prelude, /^set local lock_timeout = '1s'; /);
  assert.ok(prelude.includes(`set local transaction_timeout = '${HOLD_LIMIT_HOT}'`), prelude);
  assert.match(prelude, /pg_try_advisory_xact_lock\(hashtext\('qd_safe_replay_one_at_a_time'\)\)/);
  assert.ok(!prelude.includes('\n'), 'one line, so the text keeps its line numbers');
  assert.ok(parseInt(HOLD_LIMIT_HOT, 10) <= 5, 'a stall a live user can feel is at most 5 s');
});

test('a routine-only file is not refused and still runs capped, behind the same lock_timeout', () => {
  const t = "create or replace function public.fn_x() returns int language sql as $f$ alter table public.leads add column z int; select 1 $f$;\n";
  assert.deepEqual(stallsLiveUsers(t), [], 'DDL inside a routine body is not run by the replay');
  const { prelude } = planReplay(t);
  assert.ok(prelude.includes(`transaction_timeout = '${HOLD_LIMIT}'`) && prelude.includes("lock_timeout = '1s'"), prelude);
});

test('a table the file creates is its own: indexing and securing it is not a stall', () => {
  const t = 'create table if not exists public.request_reveal_outcome (id int);\ncreate index if not exists r_idx on public.request_reveal_outcome (id);\n'
    + 'alter table public.request_reveal_outcome enable row level security;\n';
  assert.equal(strongTableLocks(t).length, 2);
  assert.deepEqual(stallsLiveUsers(t), []);
});

test("a file's own lock_timeout above 1 s is lowered in the replay; a transaction_timeout of its own is refused", () => {
  const t = "-- set lock_timeout = '9s' in a comment stays\nset local lock_timeout = '5s';\nset lock_timeout to '15s';\nset local lock_timeout = '250ms';\n"
    + "create function public.fn_y() returns int language sql set lock_timeout to '2s' as $f$ select 1 $f$;\n";
  const out = tightenLimits(t);
  assert.equal(out.split('\n').length, t.split('\n').length, 'line numbers kept');
  assert.match(out, /^-- set lock_timeout = '9s' in a comment stays\nset local lock_timeout = '1s';\nset local lock_timeout = '1s';\nset local lock_timeout = '250ms';\n/);
  assert.match(out, /set lock_timeout to '2s' as \$f\$/, "a routine's own SET attribute is not a statement of the replay");
  assert.throws(() => tightenLimits("set local transaction_timeout = '10min';"), /transaction_timeout/);
});

test('every path that sends a replay to production goes through the guard, and none loosens it', () => {
  const door = read('scripts/lib/safe_replay.mjs');
  assert.match(door, /planReplay\(sanitized/, 'replaySql plans every production replay through replay_guard');
  assert.match(door, /plan\.prelude \+ \(rows \? rowsBody\(body, label\) : body\) \+ TAIL/, 'the prelude goes in front of the text sent');
  assert.match(door, /BUSY_MARK/, 'a busy production is waited for outside any transaction, never queued inside one');
  for (const f of ['scripts/ci/rehearse_this_prs_manifest_lines.mjs', 'scripts/lib/canonical_body.mjs']) {
    const s = read(f);
    for (const m of s.matchAll(/lock_timeout = '(\d+)(ms|s)'/g)) assert.ok((m[2] === 's' ? Number(m[1]) * 1000 : Number(m[1])) <= 1000, `${f}: lock_timeout ${m[1]}${m[2]}`);
    assert.doesNotMatch(s, /transaction_timeout/, `${f} must not set its own transaction_timeout`);
  }
  const apply = read('scripts/apply_sql.mjs');
  assert.match(apply, /set local lock_timeout = '\$\{APPLY_LOCK_TIMEOUT\}'/, 'the real apply carries its own lock_timeout');
  assert.match(apply, /const APPLY_LOCK_TIMEOUT = '[12]s'/);
});

test('every committed SQL file can be tightened (none sets a transaction_timeout of its own)', async () => {
  const { readdirSync } = await import('node:fs');
  for (const f of readdirSync(join(REPO, 'scripts/sql')).filter((x) => x.endsWith('.sql'))) tightenLimits(read(`scripts/sql/${f}`), f);
});
