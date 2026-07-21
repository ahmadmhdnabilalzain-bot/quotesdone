# Customer Portal — authoritative reference

Status: **closed chapter** as of commit `d2de536` (21 Jul 2026).
Everything a customer can do on QuotesDone, where it lives, and what governs it.

This file is the single source of truth. If something here disagrees with the code, the
code is wrong or this file is stale — fix one of them, do not add a third description.

---

## 1. Scope

The customer surface is the logged-in area where a person who needs work done posts a
request, receives quotes, pays to reveal a supplier, and escalates if that supplier goes
silent.

Everything is served by **Next.js on Vercel** (project `quotesdone-next`). The backend is
**Supabase edge functions** plus Postgres.

---

## 2. Routes

| URL | File | Notes |
|---|---|---|
| `/me`, `/ar/me` | `src/app/[locale]/me/page.tsx` | Canonical customer portal |
| `/customer`, `/ar/customer` | `src/app/[locale]/customer/page.tsx` | **Duplicate** — renders the identical component. See §8. |
| `/app` → `/me` | `next.config.mjs` redirect | Legacy URL, 307 |

Both route files are three lines and render the same `<CustomerPortal />`.

---

## 3. Frontend

**`src/components/me/CustomerPortal.tsx`** — the entire portal, one client component.
It is a god node in the graph (59 connections, the most in the codebase).

Responsibilities: auth/session, inquiry list and drill-down, quote comparison, reveal
payment, ratings, document upload, messaging, and the unresponsive-supplier escalation.

Bilingual throughout — every string has an `en` and `ar` form selected by `lang`.

---

## 4. Edge functions the portal calls

All are deployed with `verify_jwt = false` and implement their own auth. **Never redeploy
one of these with JWT verification on** — the gateway would 401 every caller before the
function body runs.

| Function | v | Calls from portal | Actions |
|---|---|---|---|
| `customer_api` | 33 | 16 | `me`, `save_me`, `my_inquiries`, `create_inquiry`, `edit_inquiry`, `cancel_inquiry`, `close_inquiry`, `complete_inquiry`, `reveal`, `confirm_reveal`, `reveal_quote`, `request_refund`, `rate_supplier`, `supplier_history`, `specs`, `detect`, `analyze_drawing`, `analyze_quotation`, `brief_pdf`, `quote_pdf`, `compare_pdf` |
| `kyc` | 5 | 8 | Identity / document verification |
| `messages_api` | 5 | 4 | Customer ↔ supplier messaging |
| `refund_flow` | 2 | 2 | `list`, `state`, `notify` |
| `login_otp` | 5 | 2 | Sign-in codes |
| `customer_portal` | 2 | 1 | `overview` only — dashboard aggregate |
| `stripe_checkout` | 3 | 1 | Opens a Checkout session for the reveal fee |
| `stripe_confirm` | 2 | 1 | Confirms payment, writes the transaction |
| `quote_compare` | 20 | 1 | Side-by-side comparison report |
| `inquiry_intake` | 9 | 1 | Structured intake |
| `role_guard` | 2 | 1 | Customer vs supplier routing |
| `transcribe` | 4 | 1 | Voice intake |

Auth pattern for the customer-scoped ones: `Authorization: Bearer <jwt>` →
`admin.auth.getUser(jwt)` → look up `customers` by lowercased email. Ownership is always
re-checked against `customer_id` server-side; never trust an id from the client.

---

## 5. Database

### Functions (working days are UAE: Fri **is** a working day, weekend is Sat + Sun)

| Function | Purpose |
|---|---|
| `fn_refund_state(p_transaction)` | The escalation state machine. Single authority on where a reveal stands. |
| `fn_notify_supplier(p_transaction, p_actor)` | Sends the tri-party email, stamps `customer_notified_at`, extends `refund_deadline`. Idempotent and re-checks its own gate. |
| `fn_is_working_day(date)` | Asia/Dubai, ISO dow < 6, minus `public_holidays` |
| `fn_add_working_days(ts, n)` | Forward N working days |
| `fn_working_days_between(a, b)` | Elapsed working days |
| `add_working_days(ts, n)` / `(date, n)` | **Legacy duplicates.** Verified identical output. See §8. |

### Tables

| Table | Role in this chapter |
|---|---|
| `customers` | Account record, keyed by email |
| `inquiries` | The request. `status`, `outcome`, `hired_supplier_id` |
| `quotes` | Supplier responses |
| `transactions` | One per paid reveal. Carries `revealed_at`, `refund_deadline`, `customer_notified_at`, `refund_status`, `refund_note`, `fee_status` |
| `reviews` | One per transaction; rating blocks a later refund |
| `notifications` | Outbox — `send_outbox` delivers |
| `public_holidays` | 16 rows to Dec 2027 |
| `pricing_config` | `refund_window_working_days` = 3 |
| `decision_policy` | `refund_call_after_working_days` = 3, `refund_claim_after_call_working_days` = 3 |

---

## 6. The unresponsive-supplier escalation

The one flow worth reading in full, because three systems have to agree on it.

```
reveal paid
   │
   │  1 working day
   ▼
notify_available ──── customer presses "Notify supplier"
   │                  → ONE email: supplier addressed,
   │                    customer + management@quotesdone.com cc'd, single thread
   │                  → stamps customer_notified_at
   │                  → extends refund_deadline to call_due + 3 working days
   │
   │  3 working days
   ▼
call_due ──────────── founder calls the supplier personally
   │                  button changes to "Request refund"
   │                  → sets refund_status = 'requested'
   │                  → appears in refunds_api queue for founder approval
   ▼
founder approves
```

`fn_refund_state` returns one of: `not_revealed`, `waiting`, `notify_available`,
`notified_waiting`, `call_due`, `supplier_responded`, `refunded`.

The portal renders exactly one affordance per state — a status line where the customer
must wait, a button where they can act. `supplier_responded` renders nothing.

### Why `refund_deadline` gets extended

`refund_deadline` is set at reveal to reveal + 3 working days. The ladder reaches
`call_due` at reveal + 1 + 3 = 4 or more, so the window used to close **before** the
customer became entitled and `request_refund` always refused. Worked example:

```
revealed      Tue 21 Jul       can notify   Wed 22 Jul
old deadline  Fri 24 Jul       call due     Mon 27 Jul   <-- 3 days too late
new deadline  Thu 30 Jul
```

`fn_notify_supplier` now pushes the deadline out, wrapped in `GREATEST` so it can only
ever lengthen a window. A customer who never notifies keeps the original 3-working-day
window, which is what the reveal fee note and the supplier terms promise.

### Money

| Item | Value | Where |
|---|---|---|
| Reveal fee | Per `pricing_config` rate/cap | `customer_api.reveal` |
| Refund window | 3 working days from reveal | `pricing_config.refund_window_working_days` |
| Late fee on recovery | 9% **per annum** (Federal Decree-Law 50/2022) | `src/content/legal.json` |
| Admin/collection fee | **AED 250 per claim** | `src/content/legal.json` |
| Refund processing deduction | 3% | Refund policy |

Legal text served to users comes from **`src/content/legal.json`** via
`src/components/LegalDoc.tsx`. It does **not** come from the Supabase `pages` table.

---

## 7. Verified state at close

- Repo `HEAD` == `origin/main`, working tree clean
- Vercel production build **Ready**
- `fn_notify_supplier` confirmed live with the deadline write and the `GREATEST` guard
- `decision_policy` rows present; `pricing_config.refund_window_working_days` = 3
- `legal.json` valid, AED 250 clause present in EN and AR, old wording gone
- `CustomerPortal.tsx` parses
- **Zero transactions have ever been revealed** — the escalation path has no production data yet

---

## 8. Known duplication — not yet resolved

Listed honestly rather than quietly cleaned, because removing a live deployed function is
what caused the 18 Jul orchestrator outage.

1. **`/customer` duplicates `/me`.** Identical component, no redirect. Nothing links to
   `/customer` except `src/middleware.ts`. Should become a redirect to `/me`.

2. **A second customer app is still deployed.** The Supabase `pages` rows `app` / `app-ar`
   are a complete older customer app calling `customer_api`, `customer_profile`,
   `dispute_api`, `quote_compare`, `messages_api`. quotesdone.com redirects `/app` → `/me`,
   so users cannot reach it — but the `app` and `app-ar` edge functions are ACTIVE and
   serve it directly on the Supabase URL.

3. **`customer_profile` (v1) and `dispute_api` (v4)** exist only to serve that older app.
   Nothing in `src/` references either. `dispute_api` is additionally broken: it gates
   `can_request` on `refund_status = 'window_open'`, but no reveal path ever sets that
   value, so the check can never be true.

4. **`customer_portal` is a third backend** for a single action (`overview`). It belongs
   inside `customer_api`.

5. **Three working-day implementations** coexist. Verified identical across the 2–3 Dec
   holidays, so no live divergence — but `refund_flow`'s header claims "one implementation
   only", which is false.

6. **Stale `pages` rows**: `app_prev_20260719`, `app-ar_prev_20260719`,
   `portal_prev_20260719`, `portal_backup_predesign`, `home_prev_20260719`,
   `home_bak_v4_20260720`, `home_backup_predesign`, `home-ar_*`, `os3_prev_*`,
   `workspace_prev_20260719`. None are served.

None of the above changes behaviour today. Each needs a decision before deletion.

---

## 9. How to check this chapter is still true

```bash
graphify query "how does the refund escalation reach the supplier"
graphify path "CustomerPortal.tsx" "customer_api"

git status --porcelain          # must be empty
git rev-parse HEAD origin/main  # must match
```

Do **not** audit the edge-function mirror by file timestamp. `route_inquiry` once carried
a file date newer than its own deploy while its contents were a version behind. Only a real
download tells the truth — `scripts/qd-pull-functions.ps1`.
