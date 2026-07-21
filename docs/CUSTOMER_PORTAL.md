# Customer Portal — complete reference

**Chapter status: CLOSED and fully cleaned.** Audited line by line, dead code and
duplication removed, legacy backend retired, everything deployed and verified
(22 Jul 2026).

This document is the single source of truth. A developer who has never seen the
codebase can open `src/components/me/CustomerPortal.tsx` and, with this file,
understand every part of the customer surface, every backend it talks to, and every
business rule it enforces. If code and this file ever disagree, one of them is a bug.

---

## 0. Architecture at a glance

```
Browser (Next.js on Vercel)                    Supabase (edge functions + Postgres)
─────────────────────────────                  ────────────────────────────────────
/me , /ar/me                                    customer_api      (inquiries, reveal, PDFs)
  └─ CustomerPortal.tsx  ──── fetch ───────────▶ customer_portal   (dashboard overview only)
       (one client component,                    refund_flow       (escalation: state / notify)
        ~1440 lines, bilingual)                  kyc               (identity + verification)
                                                 messages_api      (customer ↔ supplier chat)
                                                 login_otp         (sign-in codes)
                                                 role_guard        (customer vs supplier)
                                                 stripe_checkout   (reveal payment)
                                                 stripe_confirm    (payment confirmation)
                                                 quote_compare     (AI comparison report)
                                                 inquiry_intake    (conversational intake)
                                                 transcribe        (voice → text)
                                                        │  Postgres
                                                        ▼
                                                 customers, inquiries, quotes, transactions,
                                                 reviews, notifications, pricing_config,
                                                 decision_policy, public_holidays
                                                 fn_refund_state / fn_notify_supplier / fn_*_working_day(s)
```

Every edge function runs `verify_jwt = false` and implements its own auth. **Never
redeploy one with JWT verification on** — the gateway would 401 every caller before
the function body runs. (When deploying via the Supabase CLI, use `--no-verify-jwt`.)

---

## 1. Routes

| URL | Serves | Notes |
|---|---|---|
| `/me`, `/ar/me` | `src/app/[locale]/me/page.tsx` → `<CustomerPortal/>` | **The one canonical customer URL.** |
| `/customer`, `/ar/customer` | → 307 redirect to `/me` | Was a duplicate route rendering the identical component; removed 22 Jul. |
| `/app`, `/ar/app` | → 307 redirect to `/me` | Legacy URL. |

---

## 2. Frontend — `src/components/me/CustomerPortal.tsx`

One client component (`'use client'`). The most-connected node in the codebase
(graphify: 59 edges). Bilingual — every visible string has `en` and `ar` forms in
the `T` dictionary, selected by `lang`. **Zero dead symbols** after the 22 Jul audit
(removed the unused `Kpi` atom).

### Module utilities
`call()` (the single fetch wrapper), `initLang`, `T`/`t`/`tf` (i18n), `aed`,
`EMIRATES`, file/audio helpers (`fileToImages`, `ensurePdfjs`, `encodeWav`,
`blobToWavB64`), design primitives (`S`, `MOTION_CSS`, `rise`, `fmtDate`, `refOf`),
and `editState` — which **recomputes** the 1-hour edit window from `created_at`
because the API's `editable` flag used a 24 h window that disagreed with the server.

### Component tree (every function is reachable from here)
```
CustomerPortal            root: language, session/token, sign-out → Login | Authed
├─ Login                  OTP sign-in/up (role_guard + login_otp)
└─ Authed                 loads kyc.state → ProfileGate | Portal
   ├─ ProfileGate         name/phone/DOB, verify mobile+email, accept terms (kyc)
   └─ Portal              tabbed app: Overview | Requests | Messages | Account
      ├─ Overview         greeting, alerts, 6 KPIs, 12-month chart, recent 3
      ├─ Account          profile, verification checks, lifetime stats
      ├─ RequestList → RequestRow      all requests (combined projects group children)
      ├─ RequestDetail    edit/cancel, SupplierBrief, Comparison, quotes
      │  ├─ SupplierBrief   anonymised brief + Save-as-PDF (customer_api.brief_pdf)
      │  ├─ useComparison   one quote_compare fetch, shared by report + quote order
      │  ├─ Comparison      AI side-by-side table + Save-as-PDF (compare_pdf)
      │  └─ QuoteCard → QuotePdfLink / ValueRing / Contact
      │     └─ Contact      revealed supplier: contact, profile, rate, hire, ESCALATION
      ├─ Messages → Thread   gated assistant chat (messages_api)
      └─ NewRequest        conversational intake: text / file / voice (inquiry_intake)
```

---

## 3. Backends and every action

`customer_api` **v35** (58,450 bytes, deployed == repo, byte-verified). All 14
actions are live and used by the portal — **no dead or legacy actions remain**.

| Action | Purpose |
|---|---|
| `me` / `my_inquiries` | Load customer; all requests + quotes + `matched_suppliers` |
| `create_inquiry` | Post a request (single / multi-split / turnkey) |
| `edit_inquiry` / `cancel_inquiry` | 1-hour edit window; cancel an open request |
| `complete_inquiry` | Mark a supplier hired (notifies the others) |
| `reveal` | Reveal a supplier (returns contact if already paid) |
| `request_refund` | Set `refund_status='requested'` → founder queue |
| `rate_supplier` | 1–5 rating; blocks a later refund |
| `supplier_history` | Revealed supplier profile + past projects |
| `analyze_drawing` | Uploaded drawing/photo → BOQ |
| `brief_pdf` / `quote_pdf` / `compare_pdf` | Branded PDFs via `pdf_native` |

Other functions (all `verify_jwt=false`): `customer_portal` v2 (`overview` only),
`refund_flow` v2 (`state`/`notify`/`list`), `kyc` v5, `messages_api` v5, `login_otp`
v5, `role_guard` v2, `stripe_checkout` v3, `stripe_confirm` v2, `quote_compare` v20,
`inquiry_intake` v9, `transcribe` v4.

Auth pattern: `Authorization: Bearer <jwt>` → `admin.auth.getUser(jwt)` → look up
`customers` by lowercased email; ownership re-checked against `customer_id`
server-side on every action.

---

## 4. Database

### Functions (working days are UAE: Fri IS a working day; weekend = Sat + Sun)

| Function | Purpose |
|---|---|
| `fn_refund_state(transaction)` | The escalation state machine — single authority on where a reveal stands. |
| `fn_notify_supplier(transaction, actor)` | Tri-party email, stamps `customer_notified_at`, **extends `refund_deadline`** to call-due + claim window. Idempotent. |
| `fn_is_working_day` / `fn_add_working_days` / `fn_working_days_between` | UAE working-day math (Asia/Dubai, minus `public_holidays`). |
| `add_working_days(ts,n)` / `(date,n)` | Legacy duplicates of `fn_add_working_days`; verified identical output. Still called by the reveal insert paths. |

### Tables
`customers`, `inquiries` (`status`/`outcome`/`hired_supplier_id`/`matched_suppliers`),
`quotes`, `transactions` (`revealed_at`/`refund_deadline`/`customer_notified_at`/
`refund_status`/`fee_status`), `reviews`, `notifications`, `pricing_config`
(`refund_window_working_days`=3), `decision_policy`
(`refund_call_after_working_days`=3, `refund_claim_after_call_working_days`=3),
`public_holidays` (16 rows to Dec 2027).

---

## 5. The unresponsive-supplier escalation

```
reveal paid
   │  1 working day
   ▼
notify_available ─── customer presses "Notify supplier"
   │                 → ONE email: supplier addressed, customer + management@quotesdone.com cc'd
   │                 → stamps customer_notified_at; EXTENDS refund_deadline to call_due + 3 wd
   │  3 working days
   ▼
call_due ────────── founder calls; the SAME button becomes "Request refund"
   │                 → refund_status='requested' → founder approval queue (refunds_api)
   ▼
founder approves
```

`fn_refund_state` returns: `not_revealed`, `waiting`, `notify_available`,
`notified_waiting`, `call_due`, `supplier_responded`, `refunded`. The portal renders
exactly one affordance per state and never computes a date itself.

**Why the deadline is extended (bug fixed 21 Jul):** the window used to close at
reveal + 3 wd, but the ladder reaches `call_due` at reveal + 1 + 3 = 4+ wd, so
`request_refund` always refused. `fn_notify_supplier` now pushes the deadline out
(`GREATEST`, so it can only lengthen). A customer who never notifies keeps the
original 3-wd window.

---

## 6. Money

| Item | Value | Where |
|---|---|---|
| Reveal fee | `pricing_config` rate/cap | `customer_api.reveal` → `stripe_checkout` → `stripe_confirm` |
| Refund window (no escalation) | 3 working days | `pricing_config.refund_window_working_days` |
| Late fee on recovery | 9% **per annum** (Fed. Decree-Law 50/2022) | `src/content/legal.json` |
| Admin/collection fee | **AED 250 per claim** | `src/content/legal.json` |
| Refund processing deduction | 3% | Refund policy |
| Refund payout time (after approval) | 7–14 working days | Refund policy §6 |

Two clocks, do not conflate them: **3 working days** is the window for the supplier
to respond / the customer to become eligible; **7–14 working days** is how long the
payout itself takes after approval. Working days are **Sat + Sun excluded** (Friday
IS a working day) everywhere — code and legal text now agree (the refund policy and
complaints page previously carried the pre-2022 "Fri + Sat" weekend; corrected).

Legal text served to users comes from **`src/content/legal.json`** via
`src/components/LegalDoc.tsx` — NOT the Supabase `pages` table.

---

## 7. What the cleanup did (22 Jul)

**Frontend — provably clean.** Read all ~1,440 lines; every symbol reachable.
Removed the unused `Kpi`; fixed the Arabic refund confirm and a false "one
implementation" comment; removed the duplicate `/customer` route (now a redirect).

**`customer_api` — cleaned and deployed (v33 → v35).**
- Removed 3 dead-everywhere actions. One, `confirm_reveal`, was an **authenticated
  reveal-payment bypass**: it inserted a paid transaction with a stub payment ref and
  no money taken, reachable by any logged-in customer. Closed.
- Removed 4 more actions (`analyze_quotation`, `close_inquiry`, `detect`, `specs`)
  once their only caller — the legacy app — was deleted.
- 21 → 14 actions. Deployed via the Supabase CLI (exact disk bytes) and
  byte-verified identical to the repo; `verify_jwt=false` preserved.

**Legacy customer app — fully retired.**
- Deleted the 4 edge functions `app`, `app-ar` (served the old page HTML),
  `customer_profile` (superseded by `kyc`), `dispute_api` (broken: gated on a
  `refund_status='window_open'` that no path ever sets). All 4 now 404; recoverable
  from git history.
- Archived and deleted 4 legacy `pages` rows (`app`, `app-ar`, and their `_prev`
  backups) → table `public._legacy_customer_pages_20260722` (reversible).

**Verified:** repo == production for the customer surface; `/customer` → 307 → `/me`;
`customer_api` unauth → 401; Vercel build Ready; `legal.json` valid with the AED 250
clause in EN + AR.

---

## 8. Remaining (cosmetic, no bug, no duplication)

Not blocking; noted for completeness.

1. **`customer_portal`** is a separate function for a single action (`overview`). It
   is live and correct, just architecturally tidier folded into `customer_api`. Low
   priority.
2. **Three working-day functions** coexist (`fn_add_working_days` + two
   `add_working_days` overloads). Verified identical; consolidation is cleanup only.
3. **Founder decision (not code):** Supplier Agreement §6 promises a refund at "3
   working days" while the ladder delivers at 4+. Either expose the request at 3 wd
   or amend the wording. Legal call.

---

## 9. How to verify this chapter is still true

```bash
graphify query "how does the refund escalation reach the supplier"
git status --porcelain            # empty
git rev-parse HEAD origin/main    # match

# repo == production for edge functions (needs the CLI's stored session):
npx supabase@latest functions download customer_api --project-ref htdblwldjkcgjvmqkbeh
#   then diff against supabase/functions/customer_api/index.ts  → must be identical
```

Do **not** audit the mirror by file timestamp — `route_inquiry` once had a file date
newer than its deploy while its content was a version behind. Only a real download
tells the truth. `customer_api` was verified this way at every deploy.
