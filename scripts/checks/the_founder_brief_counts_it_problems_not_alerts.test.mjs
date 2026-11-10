// THE FOUNDER BRIEF COUNTS THE IT ENGINEER'S PROBLEMS, NOT HIS ALERTS (it_engineer, 10 Nov 2026).
//
// Item 7 of the daily brief said "The IT engineer works on N open technical problem(s)" with N = one per open
// it_engineer_finding row, and the founder read N as that many bugs: 1 Oct 60, 25 Oct 626, 2 Nov 833, 9 Nov 277.
// One fault opens many rows (duty:delivery 2,773 rows for one burst on 2-4 Nov; duty:credential_rotation_age 43 rows
// for one batch of credentials). Measured 10 Nov: 266 open rows = 51 problems, 0 of which need him.
// scripts/sql/the_founder_brief_counts_it_problems_not_alerts.sql made the line count problems (fn_it_open_problems:
// the first two parts of the issue key) and name only those the IT digest's rule says are his.
//
// This fails if the brief goes back to counting rows, if the grouping or the "needs you" rule goes from
// fn_it_open_problems, or if the IT digest changes its founder rule without this copy following it. It reads the
// schema mirror (what production runs) together with the MANIFEST-listed SQL in order (what merges apply), and the
// LAST definition of each routine wins, as at apply. Comments are stripped so prose cannot satisfy it.
//
//   node --test scripts/checks/the_founder_brief_counts_it_problems_not_alerts.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const ROOT = join(import.meta.dirname, '..', '..');
const SQL_FILE = 'scripts/sql/the_founder_brief_counts_it_problems_not_alerts.sql';
const manifest = readFileSync(join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split('\n').map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#')).map((l) => (l.startsWith('scripts/') ? l : `scripts/sql/${l}`));
const applied = manifest.filter((f) => existsSync(join(ROOT, f))).map((f) => readFileSync(join(ROOT, f), 'utf8')).join('\n');
const code = (readSchemaMirror() + '\n' + applied).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

const lastDefinition = (name) => {
  const re = new RegExp(`create or replace function public\\.${name}\\([^]*?\\n\\$(fn|function)\\$;?`, 'gi');
  const all = [...code.matchAll(re)];
  return all.length ? all[all.length - 1][0] : null;
};

// The IT line of item 7: from its opening phrase to the end of the statement that builds it.
const itLine = () => {
  const fig = lastDefinition('fn_founder_brief_figures');
  assert.ok(fig, 'fn_founder_brief_figures is not defined');
  const at = fig.indexOf("'The IT engineer has no open technical problems.'");
  assert.ok(at > 0, 'the brief no longer has the IT engineer line');
  const start = fig.lastIndexOf('v_plan := v_plan || (', at);
  const end = fig.indexOf(');', fig.indexOf('from ', at));
  assert.ok(start > 0 && end > at, 'the IT engineer line could not be isolated');
  return fig.slice(start, end + 2);
};

test('the file is listed last-wins in MANIFEST.txt', () => {
  assert.ok(manifest.includes(SQL_FILE), `${SQL_FILE} is not in MANIFEST.txt`);
});

test('the brief counts PROBLEMS from fn_it_open_problems, not one per open alert row', () => {
  const line = itLine();
  assert.match(line, /from public\.fn_it_open_problems\(\)/, 'the IT line must read fn_it_open_problems()');
  assert.doesNotMatch(line, /fn_it_open_findings\(\)/,
    'the IT line reads the open alert rows directly again: one fault would be counted once per row');
  assert.doesNotMatch(line, /\bopen technical problem\(s\)/, 'the old "N open technical problem(s)" wording is back');
  assert.match(line, /count\(\*\)::int as n/, 'the number of problems is the number of fn_it_open_problems rows');
  assert.match(line, /sum\(p\.alerts\)/, 'the alerts behind the problems are counted separately');
  assert.match(line, /'The IT engineer is working on ' \|\| s\.n/, 'the sentence leads with the number of problems');
  assert.match(line, /', raised as ' \|\| s\.a/, 'the sentence says how many alerts the problems were raised as');
  assert.match(line, /'None of them needs you\.'/, 'a day with nothing for him must say so plainly');
  assert.match(line, /filter \(where p\.needs_founder\)/, 'only problems that need him may be named');
  assert.match(line, /s\.t\[1:3\]/, 'at most three are named');
});

test('fn_it_open_problems groups the ONE definition of open by the first two parts of the issue key', () => {
  const p = lastDefinition('fn_it_open_problems');
  assert.ok(p, 'fn_it_open_problems is not defined');
  assert.match(p, /from public\.fn_it_open_findings\(\) f/, 'it must read fn_it_open_findings() (one definition of open)');
  assert.match(p, /substring\(f\.issue_key from '\^\[\^:\]\+\(\?::\[\^:\]\+\)\?'\)/, 'the problem key is the first two parts of issue_key');
  assert.match(p, /group by o\.problem/, 'one row per problem');
  assert.match(p, /count\(\*\)::int/, 'each problem carries its alert count');
  assert.match(p, /security definer\s+set search_path to 'public', 'pg_temp'/i, 'definer routines pin search_path');
  assert.match(code, /revoke execute on function public\.fn_it_open_problems\(\) from public, anon, authenticated/);
});

// The founder rule exists twice: in the 19:00 IT digest and in fn_it_open_problems. If the digest changes, this fails,
// so the brief cannot tell him something needs him that the digest kept internal, or the reverse.
const FOUNDER_RULE = [
  ['ruling 1090: a credential only he can renew is never his line', /public\.fn_it_credential_founder_required\(f\.issue_key, f\.title, f\.evidence\)/],
  ['5 Oct: an integration marked notify=false is the IT engineer\'s', /f\.issue_key like 'duty:integration:%' and f\.evidence->>'notify' is distinct from 'true'/],
  ['the register of his decisions', /from public\.it_founder_decision_class c/],
  ['a to_founder=false class wins, then the most specific', /order by c\.to_founder, length\(c\.issue_key_like\) desc limit 1/],
  ['ruling 1254: only his three categories', /'money', 'destructive_production_change', 'fact_only_he_holds'/],
];

test('fn_it_open_problems and the IT digest apply the same founder rule', () => {
  const p = lastDefinition('fn_it_open_problems');
  const digest = lastDefinition('fn_customer_support_sends_the_it_digest');
  assert.ok(p && digest, 'fn_it_open_problems or fn_customer_support_sends_the_it_digest is not defined');
  for (const [what, re] of FOUNDER_RULE) {
    assert.match(p, re, `fn_it_open_problems lost: ${what}`);
    assert.match(digest, re, `the IT digest changed (${what}); change fn_it_open_problems to match, then this check`);
  }
});
