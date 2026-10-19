// The six sales_engineer senior contributions of ledger 1003 stage 2 (SE-C03 C04 C07 C12 C13 C14) are seat_duties that ACT.
// Seat: sales_engineer. 19 Oct 2026: each was partial or missing on the seat audit -- no levelled comparison written on a
// clock, no stage conversion, every supply gap deferred with no brief to marketing, no negotiation round, no win/loss
// review, no framework. This reads the NEWEST definition of each routine (MANIFEST order, then files pending apply) and
// fails if a duty is unregistered, its routine stops writing what makes it act, or it reaches the founder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
  .filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
const pending = readdirSync('scripts/sql/pending').filter((f) => f.endsWith('.txt') && !f.endsWith('_probe.txt'))
  .map((f) => `scripts/sql/${f.replace(/\.txt$/, '.sql')}`);
const files = [...manifest, ...pending].filter(existsSync);
const all = files.map((f) => readFileSync(f, 'utf8')).join('\n');

function newest(fn) {
  const def = new RegExp(String.raw`create\s+or\s+replace\s+function\s+public\.${fn}\s*\(`, 'i');
  const file = files.filter((f) => def.test(readFileSync(f, 'utf8'))).pop();
  assert.ok(file, `no file defines ${fn}`);
  return { file, body: readFileSync(file, 'utf8').split(def).pop().split(/\$(?:function|fn)\$;/)[0] };
}

// contribution -> [duty, routine, what the routine must write for the duty to act]
const DUTIES = {
  'SE-C03': ['sales_engineer.comparison_report', 'fn_sales_engineer_comparison_report', /insert into public\.sales_engineer_comparison_report[\s\S]*fn_sales_engineer_writes\('comparison_ready'/],
  'SE-C04': ['sales_engineer.onboarding_conversion', 'fn_sales_engineer_onboarding_conversion', /fn_ceo_improvement_open\('funnel_stage_drop'[\s\S]*insert into public\.sales_engineer_onboarding_week/],
  'SE-C07': ['sales_engineer.supply_gap_recruitment', 'fn_sales_engineer_supply_gap_recruitment', /'rule:pre_launch_build'[\s\S]*fn_sales_engineer_supply_gap_to_recruitment_brief/],
  'SE-C12': ['sales_engineer.negotiation_round', 'fn_sales_engineer_negotiation_round', /'negotiation_clarify'[\s\S]*'negotiation_best_and_final'[\s\S]*insert into public\.sales_engineer_negotiation_round/],
  'SE-C13': ['sales_engineer.win_loss_review', 'fn_sales_engineer_win_loss_review', /leakage[\s\S]*fn_ceo_improvement_open[\s\S]*insert into public\.sales_engineer_win_loss_month/],
  'SE-C14': ['sales_engineer.framework_proposal', 'fn_sales_engineer_framework_proposal', /insert into public\.sales_engineer_framework_proposal[\s\S]*fn_ceo_task_open/],
};

for (const [c, [duty, fn, acts]] of Object.entries(DUTIES)) {
  test(`${c}: ${duty} is registered on ${fn} and acts`, () => {
    const reg = new RegExp(String.raw`\('${duty.replace('.', '\.')}',\s*'sales_engineer',\s*interval '[^']+',\s*'${fn}'`);
    assert.match(all, reg, `${duty} is not registered as a sales_engineer seat_duty running ${fn}`);
    const { file, body } = newest(fn);
    assert.match(body, acts, `${file}: ${fn} no longer writes what makes ${c} act`);
    assert.doesNotMatch(body, /fn_notify_founder|'admin'/, `${file}: ${fn} must not reach the founder`);
  });
}

// demo never reaches a real person: every routine that writes to a supplier or customer reads fixtures only in fixture mode
for (const fn of ['fn_sales_engineer_comparison_report', 'fn_sales_engineer_negotiation_round', 'fn_sales_engineer_framework_proposal']) {
  test(`${fn} keeps fixtures and real requests apart`, () => {
    const { file, body } = newest(fn);
    assert.match(body, /fn_inquiry_is_demo\([^)]*\)\s*=\s*\(coalesce\(current_setting\('qd\.duty_fixtures', true\)/, `${file}: ${fn} no longer separates fixtures from real requests`);
  });
}
