// NO MONEY MOVES BEFORE THE ACCOUNTANT'S SCREEN (accountant, 29 Sep 2026; founder ledger 1018).
//
// scripts/sql/the_accountant_screens_every_party_and_holds_money_for_review_before_it_moves.sql built
// fn_accountant_money_screen: a high-severity fraud flag on the customer or the supplier holds a reveal or a
// refund for review. A screen nobody calls holds nothing, so this fails when either money door stops asking it
// first:
//   * the reveal: _shared/reveal_guard.ts canReveal, the one door stripe_checkout, stripe_confirm and customer_api
//     reveal all pass, must ask the screen and refuse 'under_review' on a hold (its behaviour is proved by
//     reveal_guard.test.ts; this proves the three doors still go through it);
//   * the refund: accountant execute_refunds must ask the screen for every CEO-approved refund BEFORE stripeRefund(
//     is called, and skip a held one.
// Run: node --test scripts/checks/no_money_moves_before_the_accountants_screen.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (f) => readFileSync(join(REPO, f), 'utf8');
const SCREEN = /\.rpc\(\s*'fn_accountant_money_screen'/;

test('every reveal door passes canReveal, and canReveal asks the screen and refuses a hold', () => {
  const guard = read('supabase/functions/_shared/reveal_guard.ts');
  assert.match(guard, SCREEN, 'reveal_guard.ts no longer asks fn_accountant_money_screen');
  assert.match(guard, /hold === true\) return refuse\('under_review'\)/, 'reveal_guard.ts does not refuse a held reveal');
  for (const f of ['stripe_checkout', 'stripe_confirm', 'customer_api']) {
    // customer_api is index.ts plus its modules since 9 Nov 2026 (the reveal action is in actions/reveal.ts)
    assert.match(f === 'customer_api' ? functionSource(f) : read(`supabase/functions/${f}/index.ts`), /canReveal\(admin,/, `${f} no longer passes canReveal`);
  }
});

test('execute_refunds asks the screen for each approved refund before Stripe is called', () => {
  const src = read('supabase/functions/accountant/index.ts');
  const start = src.indexOf("if (action === 'execute_refunds')");
  assert.ok(start > 0, 'execute_refunds is gone from the accountant');
  const body = src.slice(start, src.indexOf('// A single named refund', start));
  const screen = body.search(SCREEN);
  const stripe = body.indexOf('stripeRefund(');
  assert.ok(screen > 0, 'execute_refunds no longer asks fn_accountant_money_screen');
  assert.ok(stripe > screen, 'the refund reaches stripeRefund( before the screen answers');
  assert.match(body.slice(screen, stripe), /hold === true\)[^\n]*continue;/, 'a held refund is not skipped');
});
