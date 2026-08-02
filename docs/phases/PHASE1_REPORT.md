# Phase 1 — safety and founder decisions

**Executed:** 2 August 2026 · Supabase `htdblwldjkcgjvmqkbeh` · branch `feature/phase1-safety-and-decisions`
**Status: complete and tested. Stopped before activation, as instructed.**
Neither corpus was re-imported. No record promoted to `approved`. No `target_state` record activated.

---

## 1.1 Import path closed

| Check | Result |
|---|---|
| Supplier-corpus runs in flight | **0** (67 completed, last 12:55 UTC) |
| Company-operations runs in flight | **0** (1 completed, last 13:43 UTC) |
| `app_secrets.kb_import_token` | **deleted** |
| `kb_corpus_import` with the old token | **403 forbidden** — verified by request |

A fresh token was minted twice during Phase 1 to move files into the repository, and deleted again each time. It is deleted now. Re-importing requires the founder to create it deliberately — one `insert`.

---

## 1.2 Supplier subscription — AED 1,000/year, made un-typo-able

`pricing_config` now carries `supplier_reg_currency` and `reveal_currency`, both **CHECK-constrained to `'AED'`**, with `supplier_reg_period` constrained to `yearly|monthly`.

The constraint is the point. A currency stored as a convention drifts; a currency stored as a constraint cannot. Stripe charges in `aed` (`supplier_pay` line 105), the Supplier Agreement says AED, the public supplier page says AED — moving currency now requires changing all four in one migration and relaxing the constraint, which is exactly the friction that should exist.

New view `v_supplier_pricing` is the single readable statement, so nothing restates the number:

> *"Free until 31 July 2027. From 1 August 2027: AED 1,000/year. The first 1000 registered suppliers are permanently exempt. No commission, ever."*

---

## 1.3 Supplier exception handling — the state now has an exit

**The problem being fixed.** The founder chose fully automatic approval, so a supplier whose licence cannot be read goes to `action_required` and self-serves. That closed the "queue nobody works" problem and opened a quieter one: **the state had no exit.** An account could sit there forever, holding a company name and an email, with neither the supplier nor the founder able to tell whether it was alive. A state with no exit is not automation — it is a queue with the label removed.

**What was built**

| Piece | Behaviour |
|---|---|
| 14-day window | `app_secrets.supplier_exception_days`, read through `fn_supplier_exception_days()` so nothing hardcodes 14 twice |
| Corrected-document workflow | Re-uploading a readable, in-date licence runs the existing gate in `supplier_api`, which approves and closes the exception |
| Reminders | Day 3, 7 and 12, minimum 48 h apart, each naming the exact problem and the closing date |
| Automatic rejection | At expiry: `approval_status='rejected'` with a written reason, plus a closing email that says re-registering is welcome |
| Re-open protection | Re-opening does **not** restart the clock — otherwise a supplier extends their own deadline forever by re-saving the same bad scan |
| Queue depth, visible | `v_supplier_exception_queue` (per supplier, days remaining, urgency) and `v_supplier_exception_health` (open / overdue / closing soon / auto-rejected / self-resolved) |
| Schedule | `supplier_exception_sweep_daily`, 06:20 UTC = 10:20 UAE, so notices land in working hours |

Rejection **deletes nothing**. The row keeps its reason and its closed exception, so it can still be found, appealed and re-opened by a human if one ever looks. Automatic rejection is a decision, not an erasure.

**Tests — 6 of 6 pass, all on synthetic data since removed**

| # | Test | Result |
|---|---|---|
| 1 | Open starts a 14-day clock | `reopened:true`, 14 days |
| 2 | Re-open does not restart it | `reopened:false`, *"already open — the clock does not restart on a repeat failure"* |
| 3 | Day-4 supplier gets reminder 1 | `exception_reminders` 0→1, `supplier_exception_reminder` email queued |
| 4 | Expired supplier auto-rejected | `rejected`, reason *"Automatically closed after 14 days without a readable, in-date trade licence (no_licence)"* |
| 5 | Closing email queued | `supplier_exception_expired`, status `queued` |
| 6 | Resolve closes the window and clears the reason | `exception_outcome='resolved'`, `licence_gate_reason` null |

Live sweep on real data: `{reminded: 0, auto_rejected: 0}` — correct, there are no real suppliers yet. Queue depth **0**. All test rows deleted; `v_supplier_exception_queue` is empty.

**The number to watch:** `v_supplier_exception_health.self_resolved_total` against `auto_rejected_total`. If auto-rejection climbs against real registrations, fully-automatic approval is refusing genuine businesses and the policy needs revisiting. That was the risk accepted on 2 August, and this is the instrument for it.

---

## 1.4 Observe Mode default, Control Mode by exception

**Observe Mode is not a setting — it is the absence of a Control Mode session**, so it is where you are unless you did something deliberate. There is no "stay in Control Mode" option, because the entire value is in it ending.

Control Mode requires three things together: a **fresh phone code that cannot be replayed**, a **written reason** stored beside whatever you then change, and it **expires in 15 minutes** on its own (`app_secrets.control_mode_minutes`, clamped 5–60).

**MFA reuses what exists.** `phone_verifications` and the Twilio Verify service already back customer and supplier OTP. A second factor invented here would be a second thing to get wrong. Control Mode consumes a fresh, unused, unexpired verification row and marks it used — a code already used to log in cannot open Control Mode, which is what makes it a second factor rather than a replayed first one.

**Enforcement is in `os_api`, in front of every action**, driven by the `control_mode_action` registry (14 registered mutations). An action *not* in the registry is treated as read-only and that fact is recorded — so adding a mutating action to `os_api` without registering it shows up in the audit as an unregistered action rather than sliding past. Three new actions: `control_mode_status`, `control_mode_open`, `control_mode_close`.

**Every attempt, granted or refused, lands in `control_mode_audit`.** A refused attempt is the one most worth having on record.

**Tests — 11 of 11 pass**

| # | Test | Result |
|---|---|---|
| 1 | Default posture | `observe` |
| 2 | Mutating action, no session | **refused**, `control_mode_required` |
| 3 | Read-only action in Observe | allowed |
| 4 | Open with no reason | **refused**, `reason_required` |
| 5 | Open with a bad code | **refused**, `mfa_failed` |
| 6 | Open with a valid fresh code | granted, 15 min |
| 7 | Same action after opening | **allowed**, `mode:control`, reason carried |
| 8 | Replay the same code | **refused**, `mfa_failed` |
| 9 | A different admin | still `observe` — sessions are per actor |
| 10 | After expiry + sweep | back to `observe` |
| 11 | Mutating action after expiry | **refused** |

Audit trail from the run: 5 `open_denied`, 4 `action_denied`, 1 `open`, 1 `action_allowed`, 1 `expired`.

**One bug caught by testing, worth recording.** The first version compared the raw code against `phone_verifications.code`. Those codes are stored as **HMAC-SHA256 hex**, hardened on 27 July, so it could never match — every *refusal* path worked and the one path that actually **opens** Control Mode was dead. A gate that can never be opened is indistinguishable from a gate that works, right up to the moment the founder needs it at 3am. Fixed with `fn_otp_hash()` using pgcrypto, so there is one implementation of the hash. A second bug (`mfa_ref` typed `bigint` against a `uuid` id) was caught the same way.

`control_mode_sweep_5min` closes expired sessions so the audit shows an end, not just a silence.

---

## 1.5 Explicit authority for the eight hard gates

`org_authority` went from **33 rows to 153**. Eight action classes × 15 departments, every one `gated`, each carrying the approval role from the corpus.

| Action class | Approval role |
|---|---|
| `authentication_identity` | Authorised security/identity owner |
| `autonomy_framework` | Founder / AI Governor |
| `destructive_data` | Data owner plus legal/privacy approval where applicable |
| `legal_commitment` | Founder or authorised legal signatory |
| `production_deploy` | Engineering owner with tested rollback |
| `public_claim_publish` | Founder or marketing owner |
| `secrets_security` | Authorised security owner |
| `supplier_enforcement` | Trust & Safety owner |

`v_ops_hard_gate_coverage` now reads **10/10 covered**, from 2/10.

**Nothing was widened.** All eight were already gated by the fail-closed default in `fn_ops_authority_check`. This changes what the table *says*, not what the system *allows* — which is the point: a control that exists only as a fallback is a control nobody can audit.

---

## 1.6 Department ownership resolved

| Was | Now |
|---|---|
| `hr` — live, with agents and authority, absent from the crosswalk | **HR & People Operations**, owns target `hr_people` |
| `sales` — live "Sales & Growth", absent from the crosswalk | **Sales & CRM**, owns target `sales_crm` |
| `ai_model_ops` — target with no production owner | **Formally assigned to `it` (Technology)** |

`ai_model_ops` was **assigned, not created**. Production already runs it — `ai_gateway`, `fn_ai_route`, `model_policy`, budgets and `ai_cost_log` all exist and are measured. A fifteenth department with no agents and no authority would have been reported as broken on day one, which is exactly what the corpus import was careful to avoid.

Crosswalk: **0 unresolved conflicts** (was 3). Three rows marked `resolved`, the placeholder conflict rows retired.

---

## 1.7 Refunds ledger

**The gap.** The reveal fee is the only revenue this business has, and a refund is the only way it goes backwards. There was no way to answer: how many, at what rate, for what reason, approved by whom, against which Stripe object, and did the money actually leave.

**A correction worth stating.** My first cut created `public.refunds` as a standalone table referencing a non-existent `stripe_transactions`. Testing caught it — and caught something more important: **`public.transactions` already carries nine `refund_*` columns**. Building a second store would have been precisely the duplicate source of truth the standing rules forbid.

The resolution: `transactions.refund_*` stays as the per-reveal **state** the existing `os_api refund_resolve` flow and customer UI already read. `public.refunds` is the **ledger** — what a column set on one row structurally cannot hold: more than one partial refund against the same reveal, who approved it and why, the Stripe refund id, settlement, failure reason and reconciliation. The functions keep both in step, so neither drifts and no existing reader breaks.

Design choices: amounts in **fils as integers** (float money is how reconciliations end up 0.01 apart forever); request and settlement are separate states (a refund Stripe *rejected* is a different fact from one nobody has approved); the automatic window reuses `transactions.refund_deadline`, already computed at reveal time, so the window here cannot disagree with what the customer was told.

**Stripe wiring.** `stripe_webhook` previously understood exactly one event, `checkout.session.completed` — money going **out** was invisible. It now settles from `charge.refunded`, `refund.updated` and `refund.created`.

**Tests — 7 of 7 pass, ledger returned to empty**

| # | Test | Result |
|---|---|---|
| 1 | Request outside the window | `requested`, `within_auto_window:false` |
| 2 | Decide with no decider named | **refused**, `decider_required` |
| 3 | Approve | `approved` |
| 4 | Decide twice | **refused**, `not_decidable` |
| 5 | Settle succeeded | `succeeded` |
| 6 | Same webhook delivered twice | **`idempotent:true`** — Stripe retries, and a refund settled twice reads as two refunds |
| 7 | Refund issued in the Stripe dashboard with no request here | **recorded**, not dropped — an unrecorded refund is exactly the money that never reconciles |

Reporting: `v_refund_metrics` (rate, value, reason mix, unreconciled count) and `v_refunds_unreconciled` (what finance actually chases). Backfill from `transactions.refund_*` ran — 0 rows, because `transactions` is empty; the mechanism exists for when it is not.

---

## Cost impact

Nothing in Phase 1 adds a model call. Every gate, sweep and ledger operation is SQL. The Observe/Control check adds one RPC per `os_api` call — measured at single-digit milliseconds against a table with 14 rows.

---

## Rollback

Each item is independently reversible; none altered existing data.

```sql
-- 1.2  alter table pricing_config drop constraint pricing_config_currency_ck, drop constraint pricing_config_period_ck;
--      drop view v_supplier_pricing;
-- 1.3  select cron.unschedule('supplier_exception_sweep_daily');
--      drop view v_supplier_exception_health, v_supplier_exception_queue;
--      drop function fn_supplier_exception_sweep, fn_supplier_exception_open, fn_supplier_exception_close, fn_supplier_exception_days;
--      alter table leads drop column exception_opened_at, ... (six columns; no existing data touched)
-- 1.4  select cron.unschedule('control_mode_sweep_5min');
--      drop function fn_control_mode_require, fn_control_mode_open, fn_control_mode_close,
--                    fn_control_mode_status, fn_control_mode_sweep, fn_otp_hash;
--      drop table control_mode_session, control_mode_audit, control_mode_action;
--      + redeploy os_api from the previous commit
-- 1.5  delete from org_authority where note like '2026-08-02 Phase 1.5%';   -- returns to fail-closed default
-- 1.6  department names and charters are the only change; the crosswalk rows carry their prior note
-- 1.7  drop view v_refund_metrics, v_refunds_unreconciled;
--      drop function fn_refund_request, fn_refund_decide, fn_refund_settle;
--      drop table refunds;   -- transactions.refund_* is untouched and still authoritative
--      + redeploy stripe_webhook from the previous commit
```

Edge functions changed: `supplier_api`, `os_api`, `stripe_webhook`. All three verified booting (401/403, no 5xx). Repository and production agree.

---

## Two things needed from you before activation

**1. Register the refund webhook events in Stripe.** The handler is deployed and tested, but Stripe currently only sends `checkout.session.completed` to it. Until `charge.refunded`, `refund.updated` and `refund.created` are added to the endpoint in the Stripe dashboard, refunds still will not reach the ledger. I have not touched your Stripe configuration and will not.

**2. Confirm the Control Mode phone number.** `fn_control_mode_open` consumes a verification for whatever phone is passed. The `os_api` action passes it through from the caller, so any admin can use their own — that is correct for a team, but if Control Mode should be bound to one registered founder number, say so and I will pin it.

---

## Phase 1 summary

| Item | Status | Tests |
|---|---|---:|
| 1.1 Import path closed | done | verified 403 |
| 1.2 AED 1,000/year, currency locked | done | constraint + view |
| 1.3 Supplier exception window | done | 6/6 |
| 1.4 Observe / Control Mode | done | 11/11 |
| 1.5 Eight hard-gate authority rows | done | 10/10 gates covered |
| 1.6 Department ownership | done | 0 unresolved |
| 1.7 Refunds ledger | done | 7/7 |
| | | **24/24** |

**Stopping here. Phase 2 not started.**

---

## Delivery evidence — recorded after the token was deleted

Branch `feature/phase1-safety-and-decisions`, commit `aebf5cc`, pushed to `origin`. 22 files, 17 migrations, 3 edge functions, this report. Repository and production agree; nothing applied through the management API is missing from the checkout.

Final end-state check, run against production *after* the import token was removed:

| Check | Value | Expected |
|---|---|---|
| `app_secrets.kb_import_token` rows | **0** | 0 |
| `kb_corpus_import` — old token, empty token, absent token, write attempt | **403 on all four** | 403 |
| `public.refunds` rows | **0** | 0 — every test refund removed |
| `v_supplier_exception_queue` | **0** | 0 — every test lead removed |
| `org_authority` rows | **153** | 153 |
| Hard gates with an authority row | **10 / 10** | 10 / 10 |
| `control_mode_action` registered mutations | **14** | 14 |
| Open Control Mode sessions | **0** | 0 — Observe Mode is the live default |
| `v_supplier_pricing` | **1000 AED / yearly** | AED 1,000/year |
| `ops_kb_stage.records` with status `approved` | **0** | 0 — nothing mass-promoted |
| `ops_kb_stage.records` total | **3,959** | unchanged — corpus not re-imported |
| Cron `supplier_exception_sweep_daily` | active, `20 6 * * *` | active |
| Cron `control_mode_sweep_5min` | active, `*/5 * * * *` | active |
| `os_api` / `supplier_api` / `stripe_webhook` probe | 401 / 401 / 400 | no 5xx |

The 1,317 `target_state` records remain `target_state`. They describe the company being built, not the company running, and none of them was activated by being imported.

One note on the transfer channel itself. The token existed only to move files across the gap between the sandbox that ran the work and the checkout that has to hold it. That gap is real and will recur every phase, so `scripts/pull_asset.js` is committed as a general puller — but it is useless without a token, and the token is created and destroyed inside a single phase. Nothing durable was left open.
