// A MONEY COLUMN IS NEVER NEGATIVE AND NEVER PAST ITS CENTS (accountant, 28 Sep 2026; deep audit finding 7).
//
// Fails if any of the 17 money CHECK constraints is missing from the schema, or stops testing >= 0.
// Source: the fix file while its scripts/sql/pending note exists, then the live mirror.
//
//   node --test scripts/checks/a_money_column_is_never_negative.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FIX = 'scripts/sql/a_money_column_is_never_negative_and_never_past_its_cents.sql';
const PENDING = 'scripts/sql/pending/a_money_column_is_never_negative_and_never_past_its_cents.txt';
const SRC = existsSync(join(REPO, PENDING)) ? read(FIX) : read('supabase/schema/full_schema.sql');

const SIGNED = [
  'quotes_customer_price_money_ck', 'quotes_app_fee_money_ck', 'quotes_vat_amount_money_ck', 'quotes_amount_as_stated_money_ck',
  'quote_items_unit_price_money_ck', 'quote_items_amount_money_ck', 'quote_committed_items_unit_price_money_ck',
  'quote_committed_items_line_amount_money_ck', 'ap_bills_amounts_money_ck', 'budget_lines_amount_money_ck',
  'po_lines_unit_price_money_ck', 'expenses_amount_money_ck', 'expense_entries_amount_money_ck',
  'stripe_payout_amount_fils_money_ck', 'pricing_config_nonresponse_fee_money_ck', 'leads_registration_fee_due_money_ck',
];

for (const name of SIGNED) {
  test(`${name} refuses a negative amount`, () => {
    const m = new RegExp(`add constraint ${name} check \\(([^\\n]*)\\);?`, 'i').exec(SRC);
    assert.ok(m, `${name} is not in the schema`);
    assert.match(m[1], />=\s*\(?0/, `${name} no longer tests >= 0`);
  });
}

test('quotes_quote_amount_scale_ck keeps quote_amount to 2 dp', () => {
  assert.match(SRC, /add constraint quotes_quote_amount_scale_ck check \(\(?quote_amount = round\(quote_amount, 2\)/i);
});
