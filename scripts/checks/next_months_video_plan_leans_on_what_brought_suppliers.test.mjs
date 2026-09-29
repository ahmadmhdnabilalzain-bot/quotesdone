// NEXT MONTH'S VIDEO PLAN LEANS ON WHAT BROUGHT SUPPLIERS (marketing, founder instruction 1009, upgrade 6).
//
// Fails when the fn_marketing_month_plan_tick that wins (last in MANIFEST order, or a pending file) goes back
// to plain rotation: it must learn from fn_marketing_learning, order the shifted ideas first, print the
// evidence (fn_marketing_learning_text) and keep the learning in the plan. Also fails when the learning stops
// splitting by category or stops stating the organic-only rule, or when the no-data sentence disappears.
//
//   node --test scripts/checks/next_months_video_plan_leans_on_what_brought_suppliers.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (f) => readFileSync(join(REPO, f), 'utf8');
const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).filter((l) => l.endsWith('.sql'));
const pendingDir = join(REPO, 'scripts', 'sql', 'pending');
const pending = existsSync(pendingDir) ? readdirSync(pendingDir).filter((f) => f.endsWith('.txt')).map((f) => `scripts/sql/${f.slice(0, -4)}.sql`) : [];
const order = [...manifest, ...pending].filter((f) => existsSync(join(REPO, f)));
const winner = (name) => {
  const re = new RegExp(`create\\s+(or\\s+replace\\s+)?function\\s+public\\.${name}\\s*\\([\\s\\S]*?\\$(function|fn)\\$;`, 'i');
  const f = order.filter((x) => re.test(read(x))).pop();
  assert.ok(f, `no file defines ${name}`);
  return read(f).match(re)[0];
};

test('the monthly plan learns, shifts and shows its evidence', () => {
  const tick = winner('fn_marketing_month_plan_tick');
  assert.match(tick, /fn_marketing_learning\(/, 'the plan no longer reads what brought registrations');
  assert.match(tick, /array_position\(array\(select jsonb_array_elements_text\(v_shifted\)\)/, 'shifted ideas are no longer ordered first');
  assert.match(tick, /won_rank <= 6/, 'the shift is no longer capped at half the month');
  assert.match(tick, /fn_marketing_learning_text\(v_learned, v_shifted\)/, 'the email no longer carries the evidence');
  assert.match(tick, /'learned', v_learned/, 'the learning is no longer kept with the plan');
  assert.match(tick, /fn_marketing_video_days\(/, 'dates no longer come from the working-day calendar');
});

test('the learning splits by category, states the organic rule and says when there is no data', () => {
  const learning = winner('fn_marketing_learning');
  for (const dim of ["'channel'", "'topic'", "'format'", "'time'"]) assert.ok(learning.includes(dim), `dimension ${dim} missing`);
  assert.match(learning, /by_category/);
  assert.match(learning, /'organic_only'/);
  assert.match(learning, /not p\.is_demo/, 'demo posts must be excluded by default');
  assert.match(winner('fn_marketing_learning_text'), /The mix is kept as it is/);
});
