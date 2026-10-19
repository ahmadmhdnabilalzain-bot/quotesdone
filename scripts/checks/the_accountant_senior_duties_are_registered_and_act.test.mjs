// The six accountant senior contributions of ledger 1003 stage 2 (ACC-C11 to ACC-C16) are seat_duties that ACT.
// Seat: accountant. 19 Oct 2026: each was partial or missing on the seat audit -- receipts, recovery, the 13-week forecast and the
// year end ran with no seat_duty of their own; nothing watched the VAT thresholds; no variance was explained; the CEO had no
// weekly collections, exceptions and decisions. This reads the NEWEST definition of each routine (MANIFEST order, then files pending apply) and
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
  'ACC-C11': ['accountant.receipt_intake', 'fn_accountant_receipt_intake_duty', /accountant_mailbox_check[\s\S]*raise exception[\s\S]*fn_expense_post_to_gl[\s\S]*owner_role = 'accountant'/],
  'ACC-C12': ['accountant.charge_recovery', 'fn_accountant_charge_recovery_duty', /fn_accountant_recovery_tick\(\)/],
  'ACC-C13a': ['accountant.cash_forecast_weekly', 'fn_accountant_cash_forecast_week', /insert into public\.accountant_cash_forecast_week[\s\S]*fn_support_report_to_ceo/],
  'ACC-C13b': ['accountant.budget_variance', 'fn_accountant_budget_variance', /insert into public\.accountant_budget_variance[\s\S]*explanation[\s\S]*fn_support_report_to_ceo/],
  'ACC-C14': ['accountant.vat_threshold', 'fn_accountant_vat_threshold', /375000[\s\S]*187500[\s\S]*insert into public\.accountant_vat_threshold_check[\s\S]*fn_support_report_to_ceo/],
  'ACC-C15': ['accountant.finance_week', 'fn_accountant_finance_week', /'collections'[\s\S]*'exceptions'[\s\S]*'decisions_needed'[\s\S]*fn_support_report_to_ceo/],
  'ACC-C16': ['accountant.year_end', 'fn_accountant_year_end_duty', /50000000[\s\S]*fn_accountant_year_end_tick\(\)/],
};

for (const [c, [duty, fn, acts]] of Object.entries(DUTIES)) {
  test(`${c}: ${duty} is registered on ${fn} and acts`, () => {
    const reg = new RegExp(String.raw`\('${duty.replace('.', '\.')}',\s*'accountant',\s*interval '[^']+',\s*'${fn}'`);
    assert.match(all, reg, `${duty} is not registered as an accountant seat_duty running ${fn}`);
    const { file, body } = newest(fn);
    assert.match(body, acts, `${file}: ${fn} no longer writes what makes ${c} act`);
    assert.doesNotMatch(body, /fn_notify_founder|'admin'/, `${file}: ${fn} must not reach the founder`);
  });
}

