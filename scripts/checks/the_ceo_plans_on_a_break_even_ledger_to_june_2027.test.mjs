// THE CEO PLANS ON A BREAK-EVEN LEDGER TO 30 JUNE 2027.   seat: ceo · 10 Nov 2026 · ledger 1609
//
// Measured 10 Nov 2026: the CEO's only plan was the 24 Sep investor model (cost ceilings with the founder's fee and ads, 325
// suppliers in January); no ceo_* table held a break-even number. This fails if:
//   A. the ledger stops being the founder's figure + the accountant's measured lines + the licence, or counts a ZZ DEMO
//      reveal as revenue, or the invitation target can exceed the warm-up guardrail;
//   B. the CEO's run writes anything but plan rows (a cap, a switch, a notification, a task);
//   C. the year plan is not re-based, or the 24 Sep plan is deleted instead of archived;
//   D. with a token: the trade-opening file, this file and its probe, rolled back, do not answer PROBE OK.
//
//   node --test scripts/checks/the_ceo_plans_on_a_break_even_ledger_to_june_2027.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_ceo_plans_on_a_break_even_ledger_to_june_2027.sql';
const OPEN = 'scripts/sql/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql';
const PROBE = FILE.replace('.sql', '_probe.sql');
const read = (p) => readFileSync(path.join(REPO, p), 'utf8');
const src = read(FILE).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const fnBody = (name) => {
  const m = src.match(new RegExp('function public\\.' + name + '\\([\\s\\S]*?\\$fn\\$[\\s\\S]*?\\$fn\\$'));
  assert.ok(m, `${name} is not in the file`); return m[0];
};
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();

test('A. the ledger is the founder\'s figure, the books and the licence; demo is never revenue; the guardrail caps invitations', () => {
  assert.match(src, /values \(1, 19000, date '2026-11-10', date '2027-06-30', date '2027-01-01', 1200, date '2027-06-24'/, 'the basis is not ledger 1609\'s');
  const l = fnBody('fn_break_even_ledger');
  assert.match(l, /v_cost := b\.founder_spent_aed \+ v_monthly \* v_months \+ case when v_day <= b\.licence_due then b\.licence_aed else 0 end/, 'the cost to cover is not founder + running + licence');
  assert.match(l, /not coalesce\(c\.is_demo, false\)/, 'a ZZ DEMO reveal can count as revenue');
  assert.match(l, /0\.9643 \* t\.reveal_fee - 1\.05/, 'revenue is not net of the absorbed Stripe fee');
  assert.match(l, /'invitations_target', least\(v_inv_need, v_cap\)/, 'the invitation target can exceed the guardrail');
  assert.match(fnBody('fn_break_even_invite_capacity'), /fn_invite_founder_cap\(/, 'the guardrail is not fn_invite_founder_cap');
  for (const k of ['github', 'ubicloud', 'namespace', 'apify']) assert.match(src, new RegExp(`\\('${k}', [^)]*'excluded'`), `${k} is carried as a running cost`);
});

test('B. the CEO\'s run writes plan rows only', () => {
  const run = fnBody('fn_ceo_break_even_run') + fnBody('fn_break_even_ledger') + fnBody('fn_break_even_cost_refresh');
  assert.doesNotMatch(run, /update public\.app_secrets|insert into public\.(notifications|org_tasks|ceo_directive)|fn_seat_handoff\(|fn_notify_founder/, 'the break-even run writes outside its plan tables');
  assert.match(run, /channels beyond e-mail/, 'a miss past the guardrail does not point at the channels beyond e-mail');
  for (const t of ['break_even_basis', 'break_even_cost_line', 'ceo_break_even_month', 'ceo_seat_month_target', 'ceo_break_even_replan', 'ceo_year_plan_archive']) {
    assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}[^;]*using \\(false\\) with check \\(false\\)`), `${t} has no policy`);
    assert.match(src, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t} is not revoked`);
  }
  for (const [, name] of src.matchAll(/create or replace function public\.(\w+)\(/g))
    assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated;`), `${name} is not revoked`);
});

test('C. the year plan is re-based and the 24 Sep plan archived, never deleted', () => {
  assert.match(src, /insert into public\.ceo_year_plan_archive\s+select y\.\*/, 'the 24 Sep plan is not archived');
  assert.doesNotMatch(src, /delete from public\.ceo_year_plan|truncate/i, 'the plan is deleted');
  const rows = [...read(FILE).matchAll(/\('(20\d\d-\d\d-01)', (\d+), (\d+), (\d+), (\d+), (\d+), (\d+), (\d+), (\d+), (\d+)\)/g)];
  assert.equal(rows.length, 12, 'the re-base does not carry twelve months');
  assert.ok(rows.slice(0, 3).every((r) => Number(r[4]) === 0 && Number(r[6]) === 0), 'customer activity before the January 2027 launch');
  assert.ok(pendingNotes().has(FILE) !== read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('D. the files and the probe, rolled back', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const pend = pendingNotes();
  const text = [OPEN, FILE].filter((f) => pend.has(f)).map(read).join('\n;\n') + '\n;\n' + read(PROBE);
  await assert.rejects(replaySql(text, { label: 'the break-even probe' }), /PROBE OK/, 'the probe did not end PROBE OK');
});
