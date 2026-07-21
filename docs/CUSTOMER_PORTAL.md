# Customer Portal — complete reference

**Chapter status: closed.** Audited line by line at commit `d2de536`+ (22 Jul 2026).
This document is written so a developer who has never seen the codebase can open
`src/components/me/CustomerPortal.tsx` and understand every part of it, every
backend it talks to, and every business rule it enforces.

It is the single source of truth. If the code and this file ever disagree, one of
them is a bug — fix one, never add a third description elsewhere.

---

## 0. TL;DR architecture

```
Browser (Next.js on Vercel)                    Supabase (edge functions + Postgres)
─────────────────────────────                  ────────────────────────────────────
/me , /ar/me                                    customer_api      (inquiries, reveal, PDFs)
  └─ CustomerPortal.tsx  ──── fetch ───────────▶ customer_portal   (dashboard overview only)
       (one client component,                    refund_flow       (escalation: state/notify)
        ~1440 lines, bilingual)                  kyc               (identity + verification)
                                                 messages_api      (customer ↔ supplier chat)
                                                 login_otp         (sign-in codes)
                                                 role_guard        (customer vs supplier)
                                                 stripe_checkout   (reveal payment)
                                                 stripe_confirm    (payment confirmation)
                                                 quote_compare     (AI comparison report)
                                                 inquiry_intake    (conversational intake)
                                                 transcribe        (voice → text)
                                                        │
                                                        ▼  Postgres
                                                 customers, inquiries, quotes,
                                                 transactions, reviews, notifications,
                                                 pricing_config, decision_policy,
                                                 public_holidays
                                                 fn_refund_state / fn_notify_supplier /
                                                 fn_*_working_day(s)
```

Every edge function runs with `verify_jwt = false` and implements its own auth.
**Never redeploy one with JWT verification on** — the gateway would 401 every
caller before the function body runs.

---

## 1. Routes

| URL | Serves | Notes |
|---|---|---|
| `/me`, `/ar/me` | `src/app/[locale]/me/page.tsx` → `<CustomerPortal/>` | **The one canonical customer URL.** |
| `/customer`, `/ar/customer` | → redirect to `/me` | Was a duplicate route file; removed 22 Jul, now a redirect in `next.config.mjs`. |
| `/app`, `/ar/app` | → redirect to `/me` | Legacy URL. |

The `me/page.tsx` file is three lines: set the locale, render `<CustomerPortal/>`.
All behaviour is in the component.

---

## 2. Frontend — `src/components/me/CustomerPortal.tsx`

One client component (`'use client'`, `// @ts-nocheck`). It is the most-connected
node in the whole codebase (graphify: 59 edges). Bilingual — every visible string
has an `en` and `ar` entry in the `T` dictionary, selected by `lang`.

### 2.1 Module-level utilities (top of file)

| Symbol | What it is |
|---|---|
| `URL`, `ANON`, `FN`, `SB` | Supabase project URL, anon key, functions base, browser client (`storageKey: 'qd-cust-auth'`). |
| `call(path, body, token)` | The single fetch wrapper. POSTs JSON to `FN/<path>` with a bearer token. Every backend call in the file goes through this. |
| `initLang()` | First-paint language: `localStorage['qd-lang']` → `NEXT_LOCALE` cookie → `'en'`. |
| `T`, `t(lang,k)`, `tf(lang,k,vars)` | i18n dictionary and lookups. `tf` interpolates `{n}`-style vars. |
| `aed(n)` | Formats a number as `AED 12,345`. |
| `EMIRATES` | The seven emirates, for the edit dropdown. |
| `fileB64`, `fileToImages`, `ensurePdfjs`, `encodeWav`, `blobToWavB64` | Client-side file/audio handling: image+PDF → base64 pages for drawing analysis; mic capture → 16 kHz WAV → base64 for `transcribe`. |
| `S`, `MOTION_CSS`, `Motion`, `rise`, `backArrow`, `fmtDate`, `refOf` | Design primitives: shared class strings, the injected-once animation stylesheet (every animation degrades under `prefers-reduced-motion`, nothing is hidden by default), date/reference formatting. |
| `EDIT_WINDOW_MS`, `editState(inq)` | **Anti-contradiction guard.** The DB (`fn_edit_inquiry`) allows edits for exactly 1 hour after `created_at`. The API's `editable` flag used a 24 h window that disagreed and produced an Edit button that always failed, so the window is recomputed here from `created_at`. |

### 2.2 Shared UI atoms

`Motion`, `Section`, `Stat`, `Pill`, `Empty`, `Skeleton`, `Steps`. Small, reused
across every view. (There is **no** `Kpi` atom — it was defined-but-never-used and
was removed in the 22 Jul audit.)

### 2.3 Component tree

```
CustomerPortal            root: language, session/token, sign-out; renders Login or Authed
├─ Login                  OTP sign-in / sign-up (role_guard + login_otp)
└─ Authed                 loads kyc.state; routes to ProfileGate or Portal
   ├─ ProfileGate         completes name/phone/DOB, verifies mobile+email, accepts terms
   └─ Portal              the tabbed app: Overview | Requests | Messages | Account
      ├─ Overview         greeting, alerts, 6 KPIs, 12-month activity chart, recent 3
      ├─ Account          profile details, verification checks, lifetime stats
      ├─ RequestList      all requests (combined projects group their children)
      │  └─ RequestRow    one request card with status + Steps progress
      ├─ RequestDetail    one request: edit/cancel, SupplierBrief, Comparison, quotes
      │  ├─ SupplierBrief   the anonymised brief + Save-as-PDF (customer_api.brief_pdf)
      │  ├─ useComparison   one quote_compare fetch, shared by report + quote ordering
      │  ├─ Comparison      the AI side-by-side table + Save-as-PDF (compare_pdf)
      │  └─ QuoteCard       one quote; reveal → Stripe; then Contact
      │     ├─ QuotePdfLink   view a supplier's quote PDF (quote_pdf)
      │     ├─ ValueRing      the value-score dial
      │     └─ Contact        revealed supplier: contact, profile, rate, hire, ESCALATION
      ├─ Messages          thread list (messages_api)
      │  └─ Thread          one conversation; gated assistant chat
      └─ NewRequest        conversational intake: text / file / voice (inquiry_intake)
```

Every function in the file is reachable from this tree — the 22 Jul audit confirmed
**zero dead symbols** after removing `Kpi`.

---

## 3. Backends and every action

Legend: **● portal** = called by this portal · **○ legacy** = only the retired
`app`/`app-ar` pages call it · **✗ dead** = called by nothing anywhere.

### `customer_api` (v33, 64,290 bytes — repo == deployed, byte-verified)

| Action | Used | Purpose |
|---|---|---|
| `me` | ● | Load the customer record |
| `my_inquiries` | ● | All requests + quotes + `matched_suppliers` count |
| `create_inquiry` | ● | Post a request (from `NewRequest`) |
| `edit_inquiry` | ● | Edit within the 1 h window |
| `cancel_inquiry` | ● | Cancel an open request |
| `complete_inquiry` | ● | Mark a supplier as hired |
| `reveal` | ● | Reveal a supplier (returns contact if already paid) |
| `request_refund` | ● | Set `refund_status='requested'` → founder queue |
| `rate_supplier` | ● | 1–5 rating; blocks a later refund |
| `supplier_history` | ● | Revealed supplier's profile + past projects |
| `analyze_drawing` | ● | Read an uploaded drawing/photo → BOQ |
| `brief_pdf` | ● | Anonymised brief PDF (via `pdf_native`) |
| `quote_pdf` | ● | A supplier's quote PDF |
| `compare_pdf` | ● | The comparison report PDF |
| `analyze_quotation` | ○ | Legacy app only |
| `close_inquiry` | ○ | Legacy app only (portal uses `cancel`/`complete`) |
| `detect` | ○ | Legacy app only |
| `specs` | ○ | Legacy app only |
| `save_me` | ✗ | Dead — portal writes profile via `kyc.save_customer` |
| `confirm_reveal` | ✗ | Dead — superseded by `reveal` |
| `reveal_quote` | ✗ | Dead — superseded by `reveal` |

### Other functions (all `verify_jwt=false`)

| Function | v | Actions the portal uses |
|---|---|---|
| `customer_portal` | 2 | `overview` (the only action it has — dashboard aggregate) |
| `refund_flow` | 2 | `state`, `notify` (also `list` for internal callers) |
| `kyc` | 5 | `state`, `save_customer`, `send_sms`, `verify_sms`, `send_email`, `verify_email`, `accept_terms` |
| `messages_api` | 5 | `threads`, `thread`, `send`, `request_chat` |
| `login_otp` | 5 | `send`, `verify` |
| `role_guard` | 2 | customer-vs-supplier conflict check at sign-in |
| `stripe_checkout` | 3 | opens the reveal-fee Checkout session |
| `stripe_confirm` | 2 | confirms payment on return, writes the transaction |
| `quote_compare` | 20 | the AI comparison analysis |
| `inquiry_intake` | 9 | the conversational intake turn engine |
| `transcribe` | 4 | voice note → text |

---

## 4. Database

### Functions

| Function | Purpose |
|---|---|
| `fn_refund_state(transaction)` | The escalation state machine. **Single authority** on where a reveal stands. |
| `fn_notify_supplier(transaction, actor)` | Sends the tri-party email, stamps `customer_notified_at`, and **extends `refund_deadline`** to call-due + claim window. Idempotent; re-checks its own gate. |
| `fn_is_working_day(date)` | Asia/Dubai, ISO dow < 6, minus `public_holidays`. |
| `fn_add_working_days(ts, n)` | Forward N working days. |
| `fn_working_days_between(a, b)` | Elapsed working days. |
| `add_working_days(ts,n)` / `(date,n)` | **Legacy duplicates** of `fn_add_working_days`. Verified identical output across the 2–3 Dec holidays; still called by the reveal insert paths. Consolidation tracked (§8). |

Working days are UAE: **Friday IS a working day**; the weekend is **Saturday + Sunday**.

### Tables (this chapter)

| Table | Role |
|---|---|
| `customers` | Account, keyed by lowercased email |
| `inquiries` | The request: `status`, `outcome`, `hired_supplier_id`, `matched_suppliers` |
| `quotes` | Supplier responses (anonymised until reveal) |
| `transactions` | One per paid reveal: `revealed_at`, `refund_deadline`, `customer_notified_at`, `refund_status`, `fee_status` |
| `reviews` | One per transaction; a rating blocks a later refund |
| `notifications` | Outbox; `send_outbox` delivers |
| `pricing_config` | `refund_window_working_days` = 3 |
| `decision_policy` | `refund_call_after_working_days` = 3, `refund_claim_after_call_working_days` = 3 |
| `public_holidays` | 16 rows to Dec 2027 |

---

## 5. The unresponsive-supplier escalation (the flow to read in full)

```
reveal paid
   │  1 working day
   ▼
notify_available ─── customer presses "Notify supplier"
   │                 → ONE email: supplier addressed, customer + management@quotesdone.com cc'd
   │                 → stamps customer_notified_at
   │                 → EXTENDS refund_deadline to call_due + 3 working days
   │  3 working days
   ▼
call_due ────────── founder calls the supplier; the SAME button now reads "Request refund"
   │                 → sets refund_status='requested' → founder approval queue (refunds_api)
   ▼
founder approves
```

`fn_refund_state` returns one of: `not_revealed`, `waiting`, `notify_available`,
`notified_waiting`, `call_due`, `supplier_responded`, `refunded`. The portal renders
**exactly one affordance per state** (a status line where the customer waits, a
button where they act). The frontend never computes a date — it renders what the
server returns, so button, email and refund decision always agree.

### Why the deadline is extended (bug fixed 21 Jul)

`refund_deadline` starts at reveal + 3 working days. The ladder reaches `call_due`
at reveal + 1 + 3 = 4+ working days, so the window used to close **before** the
customer became entitled and `request_refund` always refused. `fn_notify_supplier`
now pushes the deadline out (wrapped in `GREATEST`, so it can only lengthen).
A customer who never notifies keeps the original 3-working-day window.

---

## 6. Money

| Item | Value | Where |
|---|---|---|
| Reveal fee | `pricing_config` rate/cap | `customer_api.reveal` → `stripe_checkout` |
| Refund window (no escalation) | 3 working days from reveal | `pricing_config.refund_window_working_days` |
| Late fee on recovery | 9% **per annum** (Federal Decree-Law 50/2022) | `src/content/legal.json` |
| Admin/collection fee | **AED 250 per claim** | `src/content/legal.json` |
| Refund processing deduction | 3% | Refund policy |

**Where the served legal text lives:** `src/content/legal.json`, rendered by
`src/components/LegalDoc.tsx`. It does **NOT** come from the Supabase `pages` table —
a 21 Jul edit to `pages.legal_supplier_body` never reached users for that reason and
was re-applied here.

---

## 7. Audit result (22 Jul)

**Frontend — clean.**
- Read all ~1,440 lines. Every symbol is reachable from the component tree.
- Removed `Kpi` (defined, never called).
- Fixed the Arabic refund confirm, which still said "only valid within 3 working
  days" while the English had been corrected.
- Corrected a comment that claimed "one implementation of 3 working days only" —
  false since `fn_notify_supplier` extends the deadline and three `add_working_days`
  variants exist.
- Removed the duplicate `/customer` route; it is now a redirect to `/me`.
- `esbuild` parses; production build Ready.

**Backend — verified, with documented residue.**
- `customer_api` repo is byte-identical to deployed v33.
- 3 actions (`save_me`, `confirm_reveal`, `reveal_quote`) are dead everywhere.
- 4 actions (`analyze_quotation`, `close_inquiry`, `detect`, `specs`) are used only
  by the retired `app`/`app-ar` pages.

---

## 8. Remaining duplication — an approval-gated plan (NOT yet executed)

These are **irreversible** (dropping live edge functions / DB rows). Per the
operating rule that significant irreversible changes need sign-off — and because
deleting live functions caused the 18 Jul orchestrator outage — they are listed
here for one explicit go-ahead, to be done one at a time with a snapshot first.

1. **Retire the legacy customer app.** Supabase `pages.app` / `app-ar` are a whole
   older customer app, still served by the ACTIVE `app` and `app-ar` edge functions
   on the Supabase URL. quotesdone.com redirects `/app` → `/me`, so users cannot
   reach it. Plan: pull `app`, `app-ar`, `customer_profile`, `dispute_api` into git
   (so they are recoverable), then delete the four functions and the `app*` pages.

2. **Then strip the 7 unused `customer_api` actions** (`save_me`, `confirm_reveal`,
   `reveal_quote` — dead now; `analyze_quotation`, `close_inquiry`, `detect`,
   `specs` — dead once the legacy app is gone) in a single careful `customer_api`
   redeploy (preserving `verify_jwt=false`).

3. **`dispute_api` is also broken**, independently of being legacy: it gates
   `can_request` on `refund_status='window_open'`, a value no reveal path ever sets,
   so the check can never be true. It goes away with step 1.

4. **`customer_portal`** is a third backend for one action (`overview`). It is a live
   dependency of the portal, so it stays until folded into `customer_api` — low
   priority, not dead.

5. **Consolidate the three working-day functions** into one, or make the legacy two
   delegate to `fn_add_working_days`. No live divergence today.

6. **Delete 10 stale `pages` rows** (`*_prev_*`, `*_backup_predesign`, `*_bak_*`).
   None are served.

Until these are approved and executed, the frontend is clean and the backend is
correct and fully documented; the residue above is inert (unreachable) but real.

---

## 9. How to verify this chapter is still true

```bash
graphify query "how does the refund escalation reach the supplier"
graphify path "CustomerPortal.tsx" "customer_api"

git status --porcelain            # empty
git rev-parse HEAD origin/main    # must match
```

Do **not** audit the edge-function mirror by file timestamp — `route_inquiry` once
had a file date newer than its deploy while its content was a version behind. Only a
real download tells the truth (`scripts/qd-pull-functions.ps1`). `customer_api` was
verified this way: byte-identical to v33.
