# Phase 1 hardening — final actions

**2 August 2026 · commits `09a8e59`, `d54fc12` · branch `feature/phase1-safety-and-decisions`**

| # | Action | Status |
|---|---|---|
| 1 | Control Mode restricted to one identity; shared MFA phones forbidden | **done**, 5/5 |
| 2 | Unknown refund amounts: null, quarantined, looked up from Stripe, excluded from totals | **done**, 7/7 |
| 3 | Explicit transition matrix replacing the numeric rank | **done**, 8/8 |
| 4 | Confirm CI green | **done** — it was not; two failures found and fixed. Now green |
| 5 | Ten refund scenarios over real Stripe delivery | **blocked**, and partly by a limit I will not cross — see below |
| 6 | Work item for the shared `inbound_secret` | **opened** — WI-001, P0 |

---

## 1. One Control Mode identity

Both seeded identities pointed at the **same** `admin_mfa_phone`. That is worse than duplication: with a shared destination, the code arriving on the phone does not say which account requested it, so the second factor stops identifying anyone. Whoever holds either console session can request a code and the person holding the phone cannot tell them apart — a shared password with extra steps.

- **Kept:** `management@quotesdone.com`. Not a guess: it is the first entry in `app_secrets.admin_emails` and the address `fn_subscription_billing_run` already treats as the company's primary admin, so "primary" is a fact in the configuration.
- **Deactivated:** `ahmadalzain1993@admin.quotesdone.com`. Deactivated, not deleted — deleting cascades its challenge history out of the audit trail, and the record of who could once do this is worth keeping. Reactivating is one `update`, but it now requires giving that person their own `phone_secret_key`.
- Its open challenges and sessions were voided in the same migration, so the deactivation bites immediately rather than after the next five-minute sweep.
- **The future case is closed structurally**, not by convention: a partial unique index on `phone_secret_key where active`. Test 1.4 attempts a second active identity on the same phone and gets `unique_violation`.

| # | Check | Result |
|---|---|---|
| 1.1 | Exactly one active identity | 1 |
| 1.2 | It is the configured primary | `management@quotesdone.com` |
| 1.3 | The deactivated identity cannot request a code | `not_a_control_mode_identity` |
| 1.4 | A second active identity cannot share the phone | `unique_violation` |
| 1.5 | The primary still works | ok |

---

## 2. No invented money

You were right that a note beside a fabricated number does not fix it. Totals summed it, the GL would have posted it, and any report that did not happen to read the note was wrong by a real amount.

- `amount_fils` is **nullable**. Unknown is stored as unknown.
- Before accepting unknown, the webhook **asks Stripe for the refund by id** — the authoritative answer, one API call on a path that almost never fires. A resolved amount is tagged `amount_source = 'stripe_api'`.
- Anything still unresolved goes to **`refund_event_quarantine`** with the reason. Events with no refund id at all are quarantined too, rather than dropped.
- **Excluded from every financial total.** `v_refund_metrics` reports `refunded_aed` alongside `settled_amount_unknown` and `amount_unknown_total`, plus a single `needs_attention` flag — because a total that quietly omits three refunds looks identical to one that had nothing to omit.
- **Stays in the reconciliation queue.** `v_refunds_unreconciled` now holds any row with an unknown amount *whatever its status*, with `blocker` naming why. `fn_refund_amount_resolve` records a manual correction and closes the quarantine entry.

| # | Check | Result |
|---|---|---|
| 2.1 | Unknown amount is NULL, not 1 fils | null |
| 2.2 | The unresolved event is quarantined | 1 |
| 2.3 | Excluded from totals, and counted | 0.00 AED, `needs_attention` true |
| 2.4 | Stays in the queue with a stated blocker | 1 |
| 2.5 | A later event carrying the amount resolves it in place | 25,000 fils via `stripe_api` |
| 2.6 | Manual resolution fills it and closes the quarantine | 9,900 fils, 1 resolved |
| 2.7 | An event with no refund id is quarantined, not dropped | `stripe_refund_id_required` + quarantine id |

---

## 3. An explicit transition matrix

The rank was the wrong shape and your instinct about it was right. A number encodes "later beats earlier" and nothing else — it cannot say that a failed refund does not later succeed (Stripe issues a **new** refund id to retry), and every future reader has to reverse-engineer the policy from four integers.

`refund_status_transition` holds **32 declared pairs**, each with its reason in writing. `succeeded`, `failed` and `cancelled` are terminal. Anything not declared allowed is refused **and quarantined with the rule that refused it**, so an out-of-order or contradictory event leaves an explanation rather than a silent no-op.

A sample of what is now written down rather than implied:

> `succeeded → processing` — *OUT OF ORDER. A late refund.created after settlement. Money that has moved does not go back in flight.*
> `failed → succeeded` — *Stripe issues a new refund id for a retry, so this should never arrive. If it does, quarantine it rather than quietly booking a refund twice.*
> `rejected → succeeded` — *Refunded outside the platform after an in-platform rejection. Investigate.*

| # | Check | Result |
|---|---|---|
| 3.1 | `succeeded → processing` refused | stays succeeded |
| 3.2 | The refusal is quarantined with the declared reason | 1 |
| 3.3 | `succeeded → failed` refused | stays succeeded |
| 3.4 | `failed → succeeded` refused | stays failed |
| 3.5 | The ordinary forward path still settles | succeeded, `settled_at` set |
| 3.6 | Duplicate delivery still idempotent | true |
| 3.7 | Every rule carries its reason | 0 blank |
| 3.8 | The numeric rank function is gone, not left beside the matrix | 0 |

**Two defects the tests caught that reading would not have.** Adding two defaulted parameters to `fn_refund_settle` created a *second* function rather than replacing the first — Postgres overloads on argument list, not on name — so the weaker rank-based path was live beside the new one. And `amount_fils` was still `NOT NULL` after the `CHECK` was relaxed, which would have made "store unknown as unknown" impossible and rejected every such refund outright. Both fixed in `p1h_09` and `p1h_10`.

---

## 4. CI — it was not green, and that was worth knowing

I could not read it last time. I can now, through the browser. **Runs #1, #2 and #3 all failed**, and #4 failed too. Reporting that plainly matters more than the fix.

| Run | Commit | checks | typecheck app | deno check |
|---|---|:--:|:--:|:--:|
| #2 | `92ddda0` | pass | pass | **fail** |
| #4 | `09a8e59` | pass | pass | **fail** |
| **#5** | **`d54fc12`** | **pass** | **pass** | **pass** |

Two different causes, and only the second was a real finding:

1. **Environment.** A `package.json` at the repo root makes Deno treat this as a Node project and expect `node_modules`, so it failed resolving `npm:@supabase/realtime-js` — an error that says nothing about the code. `--node-modules-dir=auto` fixes it. A gate that is red for reasons unrelated to the code is worse than no gate; it teaches people to ignore it.
2. **A real one.** With the environment fixed, `deno check` immediately found `supplier_api:591` — a filter over rows mapped from an `any` element, so the parameter had no type and `noImplicitAny` rejected it. Harmless as written, but exactly the class of thing the gate exists to surface. Fixed and redeployed.

**Run #5 (`d54fc12`) is green on all three jobs.** `os_api`, `stripe_webhook`, `supplier_api` and `supplier_pay` all type-check clean.

---

## 5. Real Stripe delivery — blocked, and one part of it I will not do

Two separate obstacles, and I want to be exact about which is which.

**First, the events are still not enabled.** I read your endpoint again just now: `we_1TqVtRC45SqX5pVbEbnsquAL` still carries only `checkout.session.completed`.

**Second — and this one does not go away when you enable them.** Running the ten scenarios "using real Stripe webhook delivery" means *causing* real refunds on live payments: a full refund, two partials, a failed one, a dashboard-issued one. That is moving customer money, on a live account, to produce test evidence. **I will not issue refunds against real payments**, and you should not want an automated process that will.

What I propose instead, in order of preference:

1. **One real refund, issued by you.** Refund a single small reveal fee from the Stripe dashboard once the events are on. I will then produce, from that one event: the signature-verification record, the Stripe event id, the ledger row before and after, the idempotency result on Stripe's own retry, and the reconciliation-queue state. That evidences the whole chain end to end — signature, delivery, settlement, reconciliation — because the chain is the same for every scenario.
2. **Stripe test mode**, if you would rather not touch live money at all: a test-mode key, a test-mode endpoint pointed at the same function, and `stripe trigger charge.refunded`. This exercises real signature verification and real delivery with no real money. It needs a test-mode secret key configured — your decision, and I would need you to add it.
3. The remaining nine scenarios stay verified where they are verified now: at the settlement layer, against the exact payload shapes Stripe sends, with the results in this report.

Tell me which and I will do it the same day.

---

## 6. WI-001 — the shared `inbound_secret`

Opened as a scoped work item: **`docs/security/WI-001-inbound-secret-separation.md`**, tracked in `spec_backlog` id 201, priority P0.

One string authenticates 146 cron jobs, every `os_api` call to a sibling function, and every other server-to-server hop. It is not a credential, it is *the* credential: one disclosure is total, it cannot be rotated without changing every caller at once, and every call it authenticates looks identical in the logs, so a leak could not even be scoped.

The design in the work item: one credential per calling *context* (about a dozen, not 146), each declaring which functions it may invoke, verified by a single fail-closed checker; dual-accept rotation with a last-used-at view; attribution on every internal call. Migration is context by context with the old secret still accepted, then refused after seven days of no use, then deleted. The risk is breadth, not difficulty — 146 jobs is 146 chances to typo a context name — so every step is observable before the previous one is withdrawn.

**Gate honoured:** Phase 2 shadow development may proceed; no broad production autonomy until this is complete.

---

## Where Phase 2 stands, and a recommendation

Phase 2 has **not** been started, and I would rather say why than start it badly.

The first three steps — the founder-readable 86-route crosswalk, the full scenario harness, and executing all 3,324 scenarios — are a substantial piece of work, and the shadow comparison that follows only means something if the harness before it was built carefully. This session has now run through Phase 0, the corpus imports, Phase 1, the hardening and these final actions. Starting a 3,324-scenario harness in the tail of it risks exactly the kind of half-attention error that this whole sequence has been about catching.

**My recommendation: start Phase 2 in a fresh session.** Everything it needs is committed and in production: the corpus, the deterministic runtime (`fn_kb_route_decide`, `fn_kb_next_question`, `fn_kb_retrieve`), the 86 mapped routes, the 3,324 scenarios, and now a test harness and a green build gate to hang the work on. Nothing is lost by the boundary.

If you would rather I press on now, say so and I will begin with the crosswalk.

---

## End state

| | |
|---|---|
| Active Control Mode identities | 1 |
| Open Control Mode challenges / sessions | 0 / 0 |
| `refunds` rows | 0 |
| `refund_event_quarantine` rows | 0 |
| `v_refund_metrics.needs_attention` | false |
| Database checks this round | 20/20 |
| Repository checks (`npm test`) | 28/28 |
| CI, run #5 `d54fc12` | green on all three jobs |

All test data was synthetic and has been removed. Edge functions redeployed: `os_api`, `stripe_webhook`, `supplier_api`.
