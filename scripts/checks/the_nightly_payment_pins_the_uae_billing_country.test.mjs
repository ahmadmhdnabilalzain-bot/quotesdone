// THE NIGHTLY PAYMENT PINS THE UAE BILLING COUNTRY (accountant, 21 Sep 2026).
//
// Journey d (checkout and reveal) failed every night 15-21 Sep because Stripe's hosted Checkout
// pre-selects the billing country from the browser's IP; the GitHub runner is in the US, so the form
// asked for a ZIP the harness never filled and Pay stayed on the page. Measurement and fix:
// scripts/e2e/stripe_test_checkout.mjs. This check replays that page — country pre-selected "US" —
// against a recording page object, and fails if the harness would press Pay without first setting
// the country to AE, or if journey d stops using the helper.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { payHostedTestCheckout, TEST_CARD } from '../e2e/stripe_test_checkout.mjs';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

// A hosted Checkout page as a US runner sees it: country "US", so a required ZIP is shown.
function usRunnerPage() {
  const state = { billingCountry: 'US', filled: {}, ops: [] };
  const locator = (sel) => ({
    fill: async (v) => { state.ops.push(['fill', sel]); state.filled[sel] = v; },
    count: async () => 1,
    selectOption: async (v) => { state.ops.push(['select', sel, v]); if (sel === '#billingCountry') state.billingCountry = v; },
    click: async () => {
      state.ops.push(['click', sel]);
      // Stripe's rule, as observed: a US billing country needs a ZIP before it will charge.
      state.charged = sel === 'button[type=submit]' && !(state.billingCountry === 'US' && !state.filled['#billingPostalCode']);
    },
  });
  return { state, locator };
}

test('journey d pays from a US runner: the country is set to AE before Pay, so Stripe charges', async () => {
  const p = usRunnerPage();
  await payHostedTestCheckout(p);
  const sel = p.state.ops.findIndex((o) => o[0] === 'select' && o[1] === '#billingCountry' && o[2] === 'AE');
  const pay = p.state.ops.findIndex((o) => o[0] === 'click' && o[1] === 'button[type=submit]');
  assert.ok(sel >= 0, 'the billing country is never set; a US runner is left on US + a required ZIP');
  assert.ok(pay > sel, 'Pay is pressed before the billing country is set');
  assert.equal(p.state.charged, true, 'the replayed US page would hold the form, as it did 15-21 Sep');
});

test('only Stripe\'s TEST card is ever typed', async () => {
  const p = usRunnerPage();
  await payHostedTestCheckout(p);
  assert.equal(TEST_CARD.number.replace(/\s/g, ''), '4242424242424242');
  assert.equal(p.state.filled['#cardNumber'], TEST_CARD.number);
});

test('journey d fills the hosted page through the helper, not by hand', () => {
  const src = fs.readFileSync(path.join(ROOT, 'scripts', 'e2e', 'journeys.mjs'), 'utf8');
  const d = src.slice(src.indexOf('export async function journeyPayment'), src.indexOf('export async function journeyInvoiceRefund'));
  assert.ok(d.includes('await payHostedTestCheckout(p)'), 'journeyPayment no longer calls payHostedTestCheckout');
  assert.ok(!d.includes(".locator('button[type=submit]')"), 'journeyPayment presses Pay itself again, bypassing the country pin');
});
