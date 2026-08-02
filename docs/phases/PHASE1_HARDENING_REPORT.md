# Phase 1 hardening — report

**2 August 2026 · Supabase `htdblwldjkcgjvmqkbeh` · branch `feature/phase1-safety-and-decisions` · commits `e3fba06`, `92ddda0`**

**Three of the four items are complete and tested. Item 3 cannot complete until you register the refund events in Stripe — I verified from your account that the endpoint still carries only `checkout.session.completed`.**

**Phase 2 has not been started.**

---

## 1. Control Mode fails closed

You were right, and it was worse than the report said. The old gate returned `allowed: true` for any action missing from the registry, and its own comment claimed the case was audited — it was not. Two actions were already sitting in that gap on the day Phase 1 shipped:

| Action | What it does | What the old default did |
|---|---|---|
| `secretary_chat` | Forwards `message` / `decision` / `confirm_token` to `secretary_act`, **which acts** | Unregistered → treated as read-only → **ungated** |
| `record` | `fn_os_record`, marked `STABLE` — a pure read | Registered as **mutating** → every record you opened would have demanded a phone code |

**Now:** three classifications, no default, enforced in two independent places.

| Class | Count | Behaviour |
|---|---:|---|
| `read_only` | 44 | Allowed in Observe Mode |
| `mutating` | 14 | Requires an open Control Mode session |
| `mode_control` | 4 | Control Mode's own plumbing — see below |
| **Unclassified** | — | **`action_classification_required`, 403** |

`mode_control` is the one place your two-way rule was not sufficient, so I did not pretend otherwise. `control_mode_open` cannot require Control Mode without being unopenable. That class holds exactly four names — `status`, `open`, `close`, `challenge` — pinned by a `CHECK` constraint in the database and by a test in the build, so it cannot quietly grow into the loophole this exercise exists to close.

`requires_control` is now a generated column derived from `classification`, because it was a second hand-kept copy of the same fact and the two had already disagreed about `record`.

**A third defect, found on the way.** The gate's failure path swallowed every error from the database and continued. A momentary database problem silently downgraded every mutation to ungated. A failed lookup now refuses anything this file does not already know is a read (`control_mode_unavailable`, 503).

---

## 2. Control Mode MFA is purpose-bound

`fn_control_mode_open` consumed any unused `phone_verifications` row matching the phone. That table is written by `login_otp` (sign-in) and `kyc` (customer and supplier contact confirmation). **A code you requested in order to sign in was a valid privilege-escalation credential.** You consented to logging in, not to Control Mode. It also accepted the code in plaintext as well as hashed, so any path that ever wrote an unhashed code was a second way in.

Replaced with a challenge that exists only for this purpose:

| Property | Value |
|---|---|
| Bound to | a registered identity in `control_mode_identity` — not to whoever knows a phone number |
| Purpose | `control_mode`, enforced by a `CHECK`, so it cannot be minted for anything else |
| Phone | resolved at challenge time from `app_secrets` via the identity's `phone_secret_key`. **Not in source, not in the request, not returned to the browser** — only the last four digits are |
| Nonce | 36 hex chars, one-time; the challenge id alone is not enough |
| Expiry | 5 minutes |
| Attempts | 5, then the challenge closes even against the correct code |
| Rate limit | 5 codes per hour per identity |
| Consumption | single; requesting a new code voids the previous one |
| Code | `crypto.getRandomValues`, never `Math.random`; only its HMAC is stored |

The old function signature is **dropped**, not left beside the new one. Two identities were seeded straight from `app_secrets.admin_emails` — no address was retyped into a migration and none appears in the repository.

**A fourth defect, and the most embarrassing one.** `control_mode_open` in `os_api` read `u?.user?.id`, but `u` is declared with `const` inside the `else` branch of the auth block. At runtime that is a `ReferenceError`, caught by the outer handler and returned as an opaque 500. **Control Mode could never actually be opened through the API** — while all eleven database-level tests of it passed. Phase 1 tested the function and not the path. Fixed, and `deno check` now runs in CI precisely because that is the class of bug a database test cannot see.

---

## 3. Stripe refund events — built and tested, blocked on your configuration

I read your webhook configuration (read-only) and it still carries one event:

```
we_1TqVtRC45SqX5pVbEbnsquAL → checkout.session.completed
```

`charge.refunded`, `refund.created` and `refund.updated` are not registered, so no refund reaches the ledger yet. I have not touched your Stripe configuration and will not.

Everything that does not depend on delivery has been built and tested against the exact payload shapes Stripe sends. **Two defects found:**

**Out-of-order delivery lost money-truth.** Stripe guarantees at-least-once delivery, not ordering. `refund.updated` (succeeded) followed by a late `refund.created` (pending) walked a settled refund back to `processing` — a refund that had completed then read as still in flight, and finance would chase money that had already left. It needs no unusual conditions; two events emitted milliseconds apart routinely arrive reversed. Status is now monotonic by rank (`processing → cancelled → failed → succeeded`), `succeeded` is absorbing, and a late lower state is recorded in the reconciliation note and discarded.

**A refund event with no amount was stored as 1 fils, silently.** The `amount_fils > 0` constraint meant a missing amount became a plausible-looking wrong number with no marker. It is still 1 fils — the constraint is right — but it now says so in the reconciliation note, so it gets fixed instead of reconciled.

### 10 of 10 delivery scenarios pass

| # | Scenario | Result |
|---:|---|---|
| 1 | Full refund, requested in-platform | succeeded, 30,000 fils, linked to the request |
| 2 | Duplicate delivery of the identical event | one row, `idempotent: true` |
| 3 | Late `pending` after `succeeded` | stays succeeded, `out_of_order: true` |
| 4 | Two partial refunds on one charge | two rows, 15,000 fils, neither overwrites the other |
| 5 | Failed refund | `failed`, reason kept, **not** marked settled |
| 6 | Refund issued in the Stripe dashboard | recorded, `requested_by=stripe_webhook`, `decided_by=stripe_dashboard` |
| 7 | Event carrying no amount | flagged for review, not silently wrong |
| 8 | `refund.updated` arriving before `refund.created` | ends succeeded |
| 9 | Finance reconciliation | all settled refunds appear in `v_refunds_unreconciled` |
| 10 | One row per Stripe refund id | 7 ids, 7 rows, no duplicates |

Plus five repository checks that the webhook still recognises all three event types, reads **both** payload shapes (`charge.refunded` nests refunds in an array; `refund.*` is the refund itself), passes all six fields, still verifies the signature **before** touching refunds, and does not reimplement settlement in TypeScript.

**What I still cannot test:** live delivery, real signature verification end-to-end, and Stripe's actual event ordering. Register the three events and I will run the same ten scenarios against real deliveries.

---

## 4. Pricing consistency — and the mismatch it found

The check found the thing it was written to find, on its first run.

**Phase 1.2 CHECK-locked `pricing_config` — which nothing that charges a supplier reads.** The real chain is:

```
app_secrets.supplier_subscription_aed
      → fn_subscription_billing_run  →  leads.registration_fee_due
      → supplier_api pay_registration → Stripe Checkout (aed)
```

Both say 1,000 today, so there was no live discrepancy — but the constraint was guarding a value the biller never looked at, and two sources that agree by luck are one edit away from two that do not.

**Fixed by collapsing them.** `fn_supplier_subscription()` is now the only resolver: `pricing_config` first (constrained), `app_secrets` second (still honoured as an operational override), literal last. `v_supplier_billing` and `fn_subscription_billing_run` both read it.

| Fact | Resolved | `pricing_config` | `app_secrets` | Agree |
|---|---|---|---|:--:|
| Annual fee | 1000 | 1000 | 1000 | ✓ |
| Currency | AED | AED | — | ✓ |
| Period | yearly | yearly | — | ✓ |
| Billing starts | 2027-08-01 | — | 2027-08-01 | ✓ |
| Free registrations | 1000 | 1000 | 1000 | ✓ |

`v_pricing_consistency` reports this permanently. On the repository side, eight checks assert the same four facts in the Supplier Agreement, the public pages, the supplier portal and the Stripe checkout, and scan every shipped `.ts/.tsx/.json/.md` file for an annual AED price that is not 1,000 or a supplier commission rate.

One deliberate subtlety: the blog quotes real market prices ("between AED 1,200 and AED 3,000 per year for a comprehensive AC contract"). Those are not our fee and must not fail the build, so a match only counts when the surrounding text is about a subscription, registration fee or membership. There is a test that proves the guard still catches a genuinely wrong price, so it is not vacuous.

---

## Tests — 58 in total, from a repository that had none

| Suite | Where | Count |
|---|---|---:|
| Action classification, Control Mode invariants | `npm test` | 12 |
| Pricing consistency across four sources | `npm test` | 8 |
| Stripe refund event handling | `npm test` | 5 |
| Control Mode challenge, database | production, synthetic data | 18 |
| Refund delivery scenarios, database | production, synthetic data | 10 |
| Pricing facts, database | `v_pricing_consistency` | 5 |
| | | **58** |

`npm test` runs on Node's built-in test runner. **No test framework was added** — Vitest or Jest would mean a dependency tree, a config file and a version to maintain, for something `node --test` already does. When the suite needs browser E2E or snapshots, that is the moment to add one.

**The build gate you asked for.** `.github/workflows/checks.yml` runs three jobs on every push: the checks above, `tsc --noEmit`, and `deno check` over `os_api`, `stripe_webhook`, `supplier_api` and `supplier_pay`. A new action added without a classification fails the build — there is a test that simulates exactly that mistake and asserts it is caught. The remaining 187 edge functions are checked advisory-only; a permanently red gate teaches people to ignore gates.

**I could not read the CI result from here** — this machine has no GitHub credential (`gh auth login` is not done). The workflow is pushed and will have run on `92ddda0`. Please glance at the Actions tab, or run `npm test` locally.

---

## Rollback

```sql
-- 1  classification            alter table control_mode_action drop column classification cascade;
--                              + restore fn_control_mode_require from 20260802143520
--                              + redeploy os_api from d18a61b
-- 2  purpose-bound MFA         drop table control_mode_challenge, control_mode_identity cascade;
--                              drop function fn_control_mode_challenge_start, fn_control_mode_challenge_minutes;
--                              + restore fn_control_mode_open from 20260802143708  (reopens the login-code hole)
-- 3  refund ordering           restore fn_refund_settle from 20260802144301; drop function fn_refund_status_rank;
-- 4  pricing resolver          restore v_supplier_billing and fn_subscription_billing_run from before
--                              20260802151535; drop function fn_supplier_subscription; drop view v_pricing_consistency;
-- tests / CI                   delete scripts/checks/ and .github/workflows/checks.yml — no runtime effect
```

Every migration is additive. `os_api` was redeployed and probed: 401 unauthenticated, 401 on an unknown action with no auth (identity is still checked first), no 5xx.

**Test data.** All synthetic and removed: `control_mode_challenge` 0 rows, `control_mode_session` 0, `phone_verifications` 0, `refunds` 0, the temporary test phone secret deleted, two real admin identities remain.

---

## What I need from you

1. **Register `charge.refunded`, `refund.created` and `refund.updated`** on the existing webhook endpoint. Then say so and I will run the ten scenarios against live deliveries.
2. **Confirm the Control Mode identities.** Two admin emails were seeded from `app_secrets.admin_emails`, both pointing at `admin_mfa_phone`. If Control Mode should be one person only, say which and I will deactivate the other — it is one row.
3. **Optional but worth a minute:** check the Actions tab on `92ddda0`, since I cannot.

---

## Still outstanding, unchanged

The 146 cron jobs still authenticate with the single shared `inbound_secret`. Control Mode protects the console; it does nothing for the machine-to-machine surface behind it. That remains the highest-value security change available and it is still not done.

**Phase 2 not started.** It begins when item 3 can pass.
