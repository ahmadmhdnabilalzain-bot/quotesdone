// THE ACCOUNTANT'S CLOSE NEVER WAITS BEHIND ANOTHER DUTY (accountant / it_engineer, 16 Nov 2026; operations hole H12).
// fn_accountant_duties ran sixteen duties, the month close among them, as ONE statement under PostgREST's 8 s timeout: a
// statement timeout is not caught by `when others`, so one slow duty rolled back every duty of the hour, the close included
// (cancelled twice in 20 days on production, 10 and 13 Nov). Each duty is now a public.seat_duty row of its own: its own
// statement, its own statement_timeout (its pg_cron job sets 60 s), its own result row. This fails if the hourly call
// takes a duty back, if a moved duty loses its hourly seat duty, if the close stops running hourly on its own job, or if the
// chain that must keep its order (expenses, costs, owner card, books) is split or reordered.
// Reads the file that defines fn_accountant_duties LAST (MANIFEST order, then pending files by name), so it judges
// what production runs once the pending file is applied, not an older copy.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const SQL = join(REPO, 'scripts', 'sql');
const MANIFEST = readFileSync(join(SQL, 'MANIFEST.txt'), 'utf8').split(/\r?\n/);
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const rank = (f) => { const i = MANIFEST.indexOf('scripts/sql/' + f); return i < 0 ? 1e9 : i; };
const files = readdirSync(SQL).filter((f) => f.endsWith('.sql') && !f.endsWith('_probe.sql'))
  .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
// a file counts only if it is applied (MANIFEST) or waiting to be (its pending note)
const live = files.filter((f) => rank(f) < 1e9 || existsSync(join(SQL, 'pending', f.replace(/\.sql$/, '.txt'))));
const lastDefining = (name) => {
  const re = new RegExp(`create or replace function public\\.${name}\\(`, 'i');
  const f = [...live].reverse().find((x) => re.test(code(readFileSync(join(SQL, x), 'utf8'))));
  assert.ok(f, `${name} is defined by no applied or pending file`);
  return f;
};
const bodyOf = (src, name) => {
  const at = src.search(new RegExp(`create or replace function public\\.${name}\\(`, 'i'));
  const tag = src.slice(at).match(/as \$(\w*)\$/i);
  const open = src.indexOf(tag[0], at) + tag[0].length;
  return src.slice(open, src.indexOf('$' + tag[1] + '$', open));
};

const FILE = lastDefining('fn_accountant_duties');
const SRC = code(readFileSync(join(SQL, FILE), 'utf8'));
const DUTIES = bodyOf(SRC, 'fn_accountant_duties');
// the duty routines the hourly call used to run itself, each now a seat duty of its own
const MOVED = {
  'accountant.bank_reconcile': 'fn_accountant_bank_reconcile', 'accountant.collections': 'fn_accountant_collections_tick',
  'accountant.subscriptions': 'fn_accountant_subscription_tick', 'accountant.disputes': 'fn_accountant_disputes_tick',
  'accountant.recovery': 'fn_accountant_recovery_tick', 'accountant.renewals': 'fn_accountant_renewals_tick',
  'accountant.bank_balance': 'fn_accountant_bank_balance_tick', 'accountant.year_end_pack': 'fn_accountant_year_end_tick',
  'accountant.books_chain': 'fn_accountant_cost_booking_tick', 'accountant.ceo_reports': 'fn_ceo_accountant_reports_sweep',
};

test('the hourly call runs only what the runtime reads from Stripe, never a duty that can run on its own', () => {
  for (const f of ['fn_accountant_month_close_tick', ...Object.values(MOVED), 'fn_accountant_expense_duty', 'fn_accountant_owner_card_tick',
    'fn_accountant_books_duty', 'fn_accountant_reports_complete']) {
    assert.doesNotMatch(DUTIES, new RegExp(`public\\.${f}\\(`), `${FILE}: fn_accountant_duties still runs ${f} inside its one statement`);
  }
  assert.match(DUTIES, /fn_accountant_payouts_record\(/, 'the Stripe payouts are no longer recorded');
  assert.match(DUTIES, /fn_accountant_charge_audit_record\(/, 'the charge audit is no longer recorded');
  assert.match(DUTIES, /'job', 'duties'/, 'the agent_runs row fn_accountant_duties_due reads is no longer written');
});

test('every moved duty is an hourly seat duty whose routine, defined in the same file, runs it', () => {
  const rows = [...SRC.matchAll(/\(\s*'(accountant\.[a-z_]+)',\s*'(?:[^']|'')*',\s*'([^']+)',\s*true,\s*'(fn_[a-z0-9_]+)'/g)];
  const byDuty = new Map(rows.map(([, d, every, fn]) => [d, { every, fn }]));
  for (const [duty, inner] of Object.entries(MOVED)) {
    const r = byDuty.get(duty);
    assert.ok(r, `${FILE}: ${duty} is not registered as a seat duty`);
    assert.equal(r.every, '1 hour', `${duty} does not run every hour`);
    assert.match(bodyOf(SRC, r.fn), new RegExp(`public\\.${inner}\\(`), `${r.fn} does not run ${inner}`);
  }
});

test('the close runs every hour on its own job, isolated before anything else', () => {
  assert.match(SRC, /update public\.seat_duty\s+set every = '1 hour'[\s\S]*?where duty = 'accountant\.close_by_day_five'/,
    'accountant.close_by_day_five is not hourly');
  const iso = SRC.indexOf("fn_seat_duty_isolate('accountant.close_by_day_five')");
  assert.ok(iso > 0, 'the close is not given its own job');
  assert.ok(!/fn_seat_duty_isolate\(/.test(SRC.slice(0, iso)), 'another duty is isolated ahead of the close');
});

test('the chain keeps its order: expenses, costs, owner card, books, each its own stage', () => {
  const chain = bodyOf(SRC, 'fn_accountant_books_chain_duty');
  const at = ['fn_accountant_expense_duty', 'fn_accountant_cost_booking_tick', 'fn_accountant_owner_card_tick', 'fn_accountant_books_duty']
    .map((f) => chain.indexOf(`public.${f}(`));
  assert.ok(at.every((i, k) => i > 0 && (k === 0 || i > at[k - 1])), `the chain is out of order: ${at}`);
  assert.match(chain, /'expenses', 'costs', 'owner_card', 'books'/, 'a step of the chain lost its stage finding');
});
