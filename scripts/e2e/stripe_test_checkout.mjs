// PAYING STRIPE'S HOSTED CHECKOUT WITH THE TEST CARD, AS A UAE CUSTOMER (accountant, 21 Sep 2026).
//
// MEASURED. Journey d failed on every nightly run from 15 to 21 Sep ("landed on
// https://checkout.stripe.com/c/pay/cs_test_…"), while the same session shape paid and returned
// three times on 21 Sep from a machine in the UAE (cs_test_b1wQTT…, cs_test_b16djQ…, cs_test_b1oNiv…,
// all status=complete, payment_status=paid). The sessions are identical field for field; the
// difference is where the browser is. Stripe pre-selects the billing country from the visitor's IP:
// in the UAE it is "AE", which asks for no postal code; a GitHub runner is in the United States, so
// the form pre-selects "US" and adds a required ZIP field. The harness filled card, expiry, CVC and
// name, pressed Pay, and Stripe held the form on the empty ZIP — no charge, no return, and the
// session expired an hour later (checkout.session.expired in agent_runs, 19-21 Sep). Reproduced
// 21 Sep by selecting "United States" on a fresh TEST session: a ZIP field appears and Pay stays on
// the page.
//
// So the test was wrong, not the payment path: no real customer met this (0 live Checkout Sessions
// and 0 non-demo transactions in the 30 days measured). The fix pins the country to the market the
// company serves, and when Stripe still holds the form, the step names the field it held it on.
//
// No imports on purpose: scripts/checks/the_nightly_payment_pins_the_uae_billing_country.test.mjs
// drives these functions against a recording page, with no browser and no network.

export const TEST_CARD = { number: '4242 4242 4242 4242', expiry: '12 / 34', cvc: '123', name: 'ZZ DEMO Customer' };

// Fills the hosted page and presses Pay. The country is set BEFORE Pay, whatever Stripe pre-selected.
export async function payHostedTestCheckout(p) {
  await p.locator('#cardNumber').fill(TEST_CARD.number);
  await p.locator('#cardExpiry').fill(TEST_CARD.expiry);
  await p.locator('#cardCvc').fill(TEST_CARD.cvc);
  await p.locator('#billingName').fill(TEST_CARD.name).catch(() => {});
  const country = p.locator('#billingCountry');
  if (await country.count()) await country.selectOption('AE');
  await p.locator('button[type=submit]').click();
}

// What Stripe is holding the form on, when the page did not return: visible text inputs left empty
// or marked invalid (Stripe marks no `required` attribute, so emptiness is what is read). Read-only;
// used only to word the failed step. Measured 21 Sep: on a US page this names billingPostalCode.
export async function checkoutBlockers(p) {
  return p.evaluate(() => [...document.querySelectorAll('input')]
    .filter((e) => e.offsetParent && e.id && !['checkbox', 'radio', 'hidden'].includes(e.type)
      && (e.getAttribute('aria-invalid') === 'true' || !e.value))
    .map((e) => e.id)).catch(() => []);
}
