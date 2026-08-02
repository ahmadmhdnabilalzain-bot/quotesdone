# Stripe webhook configuration — live refund events and a test-mode endpoint

**For the founder to perform. No Stripe settings were changed by the agent.**
Both endpoints point at the same function: `https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/stripe_webhook`

The handler already accepts two signing secrets and verifies each in full, so the two endpoints coexist without weakening live verification. A delivery matching neither secret is refused before the body is parsed.

---

## A. Live endpoint — add the four refund events

1. Stripe Dashboard → **Developers → Webhooks**, live mode.
2. Open the existing endpoint `we_1TqVtRC45SqX5pVbEbnsquAL` (described "Finalizes paid reveals…").
3. **Update details → Select events**, and add to the existing `checkout.session.completed`:
   - `charge.refunded`
   - `refund.created`
   - `refund.updated`
   - `refund.failed`
4. Save. Do **not** change the signing secret — `app_secrets.stripe_webhook_secret` already holds it.

Nothing else changes: the reveal flow keeps working exactly as it does now.

---

## B. Test-mode endpoint — new

1. Switch the dashboard to **Test mode** (toggle, top right).
2. **Developers → Webhooks → Add endpoint**.
3. URL: `https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/stripe_webhook`
4. Description: `Test-mode twin. Proves refund handling without refunding real payments.`
5. Events: the same five — `checkout.session.completed`, `charge.refunded`, `refund.created`, `refund.updated`, `refund.failed`.
6. Create it, then **reveal the signing secret** (`whsec_…`).

---

## C. Two secrets to store

Both go in `app_secrets`, not in code, not in this file, and not into chat.

| Key | Value | Where to find it |
|---|---|---|
| `stripe_webhook_secret_test` | the **test-mode endpoint's** signing secret | Test mode → Webhooks → your new endpoint → Signing secret |
| `stripe_secret_key_test` | your **test-mode** secret API key | Test mode → Developers → API keys → Secret key |

The second is needed because a test-mode refund id can only be read with a test-mode key; queried with the live key it returns 404, which the handler would otherwise read as "Stripe has no amount".

**Send me neither.** Paste them into `app_secrets` yourself, or tell me they are in place and I will verify by behaviour — the handler reports which mode verified a delivery, never the material.

---

## D. Then say the word

With those in place I will run all ten scenarios through **real Stripe test-mode delivery** — `stripe trigger` and test-mode dashboard refunds, no live money anywhere — and return: Stripe event ids, signature-verification evidence per delivery, the ledger row before and after each, idempotency results on Stripe's own retries, the quarantine entries for the unknown-amount and out-of-order cases, and the final reconciliation state.

One caveat worth setting now: **out-of-order delivery cannot be produced on demand.** Stripe will not deliver `refund.created` after `refund.updated` to order. That case stays proven where it is proven today — at the settlement layer, by calling the handler's own settlement path with the two events reversed. I will say so explicitly in the results rather than implying Stripe produced it.

---

## E. What is deliberately not automated

Creating endpoints, selecting events and holding signing secrets are account-configuration actions on a live payments account. They stay yours. The agent's side is the handler, the ledger and the evidence.
