// THE SENIOR VERDICT IS MEASURED AGAINST THE STANDARD IN THE REPOSITORY (ceo, 27 Oct 2026; founder ledger 1003).
//
// "Never call a seat 'good to go' on opinion." The weekly verdict runs in the database (fn_ceo_seat_senior_verdict); the
// standard and the judged exam live in the repository. MEASURED 27 Oct 2026: the standards still said 'missing' for
// thirteen contributions whose duties had been live since 19 Oct, so a verdict read from them measured its author, not
// the seat. This fails when:
//   * the seed block in the SQL file differs from knowledge/standards + knowledge/exams (+ judged) -- regenerate it with
//     node scripts/eval/seat_senior_standard_seed.mjs --write;
//   * a contribution names a duty key no scripts/sql file registers in seat_duty;
//   * the verdict's exam bars differ from scripts/eval/seat_senior_audit.mjs, a seat without a judged exam could be
//     mid or senior, or a missing measurement stops being a shortfall;
//   * the handoff measure goes back to the originator's close instead of the receiver's answer;
//   * the duty, a table's service-role policy or a definer's revoke disappears.
//
//   node --test scripts/checks/the_senior_verdict_is_measured_against_the_standard_in_the_repository.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { seedBlock, currentBlock, SQL_FILE } from '../eval/seat_senior_standard_seed.mjs';
import { SENIOR_BAR } from '../eval/seat_senior_audit.mjs';
import { definitions } from '../lib/canonical_sql.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const s = readFileSync(join(REPO, SQL_FILE), 'utf8');
const fn = definitions(s).find((d) => d.name === 'fn_ceo_seat_senior_verdict')?.stmt ?? '';
const audit = readFileSync(join(REPO, 'scripts/eval/seat_senior_audit.mjs'), 'utf8');

test('the seed block is exactly what the standards and the judged exams say', () => {
  const cur = currentBlock(s);
  assert.ok(cur, 'the seed markers are gone');
  assert.equal(cur, seedBlock(REPO), 'regenerate: node scripts/eval/seat_senior_standard_seed.mjs --write');
});

// The guard is against a key that was mistyped or never built: every named key must appear as a quoted literal in some
// scripts/sql file other than this seed (the seat_duty inserts spell them so), or be a key every_seat_reviews_itself_
// every_month.sql generates per seat (<seat>.self_review).
test('every duty a contribution names exists somewhere in scripts/sql, outside this seed', () => {
  const corpus = readdirSync(join(REPO, 'scripts/sql')).filter((n) => n.endsWith('.sql') && `scripts/sql/${n}` !== SQL_FILE)
    .map((n) => readFileSync(join(REPO, 'scripts/sql', n), 'utf8')).join('\n');
  const generated = /select s \|\| '\.self_review', s, interval '1 day', 'fn_' \|\| s \|\| '_self_review'/.test(corpus);
  const missing = [];
  for (const f of readdirSync(join(REPO, 'knowledge/standards')).filter((n) => n.endsWith('.json'))) {
    const std = JSON.parse(readFileSync(join(REPO, 'knowledge/standards', f), 'utf8'));
    for (const c of std.contributions) for (const d of c.duties ?? []) {
      if (generated && d === `${std.seat}.self_review`) continue;
      if (!corpus.includes(`'${d}'`)) missing.push(`${std.seat} ${c.id} -> ${d}`);
    }
  }
  assert.deepEqual(missing, [], 'a contribution names a duty no file registers');
});

test('the bars are the audit script\'s, and no measurement is never a pass', () => {
  assert.ok(fn, 'fn_ceo_seat_senior_verdict is not defined');
  assert.equal(Number(fn.match(/c_senior_exam\s+constant numeric := ([0-9.]+);/)?.[1]), SENIOR_BAR);
  const midExam = Number(audit.match(/\(m\.answered \?\? 0\) >= ([0-9.]+)/)?.[1]);
  assert.equal(Number(fn.match(/c_mid_exam\s+constant numeric := ([0-9.]+);/)?.[1]), midExam);
  // senior only when there is no shortfall at all; mid needs a judged exam over the bar (a null exam fails the test)
  assert.match(fn, /when cardinality\(v_short\) = 0 then 'senior'/);
  assert.match(fn, /when v_exam >= c_mid_exam and v_contrib > 0 and v_live::numeric \/ v_contrib >= c_mid_contrib then 'mid'/);
  assert.match(fn, /if v_exam is null then v_short := v_short \|\| 'stage 1: no judged exam'/);
  assert.match(fn, /if v_contrib = 0 then v_short := v_short \|\| 'stage 2: no senior contributions defined'/);
  assert.match(fn, /if v_duties = 0 or v_on_clock::numeric \/ v_duties < c_on_clock then/);
});

test('a contribution is live only when every named duty ran inside its own clock', () => {
  assert.match(fn, /cardinality\(sc\.duties\) > 0 and not exists \(/);
  assert.match(fn, /d\.last_ok_at >= p_at - \(d\.every \* 2 \+ interval '1 day'\)/);
});

test('a handoff is measured by the receiver\'s answer, not the originator\'s close', () => {
  assert.match(fn, /coalesce\(\(a\.detail->>'replied_at'\)::timestamptz, a\.decided_at\) <= a\.created_at \+ k\.reply_within/);
  assert.match(fn, /a\.status = 'pending' and not a\.detail \? 'replied_at' and a\.created_at < p_at - k\.reply_within/);
});

test('a level that falls is acted on, and everything is closed to the public', () => {
  assert.match(fn, /public\.fn_ceo_improvement_open\('seat_audit', 'senior:' \|\| s\.role_id \|\| ':' \|\| v_week/);
  assert.match(s, /\('ceo\.senior_verdict', 'ceo', interval '7 days', 'fn_ceo_seat_senior_verdict_now'/);
  for (const t of ['seat_senior_contribution', 'seat_senior_exam', 'seat_senior_verdict']) {
    assert.ok(s.includes(`alter table public.${t} enable row level security;`), `${t}: RLS`);
    assert.match(s, new RegExp(`create policy ${t}_service_role_only on public\\.${t}`), `${t}: policy`);
    assert.ok(s.includes(`revoke all on public.${t} from anon, authenticated;`), `${t}: revoke`);
  }
  for (const sig of ['fn_ceo_seat_senior_verdict(timestamptz)', 'fn_ceo_seat_senior_verdict_now()']) {
    assert.ok(s.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), `${sig} not revoked`);
  }
});
