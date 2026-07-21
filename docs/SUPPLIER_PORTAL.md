# Supplier Portal — complete reference

**Chapter status: CLOSED and cleaned.** Audited line by line, dead code removed,
the repo mirror reconciled to production, everything byte-verified (22 Jul 2026).

This document is the single source of truth for the supplier surface. A developer
who has never seen the codebase can open `src/components/portal/SupplierPortal.tsx`
and, with this file, understand every part of the supplier experience, every backend
it talks to, and every business rule it enforces. If code and this file ever
disagree, one of them is a bug.

> **Note vs the customer portal.** The supplier surface is *not* self-contained. Its
> quote, document, matching and reputation machinery is shared with the QuotesDone OS
> and the autonomy engine (crons + SQL functions). Several backend functions with no
> portal caller are alive because Postgres invokes them. Deletions here were held to a
> higher bar than the customer chapter: a function was removed only when proven dead
> across **all five** invocation vectors — frontend, other edge functions, SQL
> functions, cron jobs, and database‑webhook triggers.

---

## 0. Architecture at a glance

```
Browser (Next.js on Vercel)                 Supabase (edge functions + Postgres)
─────────────────────────────              ─────────────────────────────────────────
/portal , /ar/portal                        supplier_api      (profile, RFQ inbox, quotes)
  └─ SupplierPortal.tsx  ─── fetch ─────────▶ supplier_portal   (dashboard / documents / eligibility)
       (one client component,                 supplier_pay      (dues → Stripe checkout)
        ~896 lines, bilingual)                role_guard         (supplier vs customer)
                                              login_otp          (sign-in codes)
                                              kyc                (mobile/email verify, terms)
                                              messages_api       (customer ↔ supplier chat)
                                              rfq_flag           (ask customer to clarify)
                                              sign_upload        (signed storage upload)
                                              wa_optin_set       (WhatsApp opt-in)
                                                     │  invokes server-side ▼
                                              quote_extract  license_extract  profile_ai
                                              supplier_review  fn_quote_structured_score
                                                     │  Postgres
                                                     ▼
                                     leads (the supplier record), inquiries, inquiry_matches,
                                     quotes, quote_items, notifications, pricing_config,
                                     decision_policy, doc_reviews
                                     fn_supplier_stats / fn_supplier_expiries / fn_reconcile_doc_blocks
                                     match_suppliers_kw / fn_match_capability / route_inquiry (matcher)
```

Every edge function runs `verify_jwt = false` and implements its own auth. **Never
redeploy one with JWT verification on** — the gateway would 401 every caller before
the function body runs. (Supabase CLI: deploy with `--no-verify-jwt`.)

The supplier record **is the `leads` table.** A supplier "account" is a `leads` row
with `claimed = true` and `claimed_by = <their email>`. This is the same table that
holds the ~20,465 scraped listings; a self-registered supplier is a `leads` row with
`source = 'self_registered'`.

---

## 1. Routes

| URL | Serves | Notes |
|---|---|---|
| `/portal`, `/ar/portal` | `src/app/[locale]/portal/page.tsx` → `<SupplierPortal/>` | The one canonical supplier URL. |
| `/suppliers`, `/suppliers/*` | → 307 redirect to `/portal` | Legacy URL (`next.config.mjs`). |

---

## 2. Frontend — `src/components/portal/SupplierPortal.tsx`

One client component (`'use client'`, `@ts-nocheck`). Bilingual — every visible
string has `en` and `ar` forms in the `T` dictionary, selected by `lang` and
`t(lang,key)`. Auth token is held in `localStorage['qd-sup-token']`; the Supabase
session mirrors it under `storageKey: 'qd-portal-auth'`.

### Module utilities
`call(path, body, token)` (the single fetch wrapper), `aed`, `EMIRATES`, `t`/`initLang`
(i18n), file/PDF helpers (`fileToB64`, `ensurePdfjs`, `fileToImages` — renders up to 6
PDF pages to JPEG client-side), `signUpload` (signed storage upload), and the `S`
style map.

### Component tree (every function is reachable from here)
```
SupplierPortal              root: language, token, phase (login | app)
├─ Login                    OTP sign-in/up  (role_guard conflict check → login_otp send/verify)
└─ Dashboard                loads supplier_portal.overview  →  Onboarding | tabbed app
   ├─ Onboarding            no company yet → NewCompany, else ProfileForm
   │  └─ NewCompany         create the leads row (supplier_api.create_company)
   ├─ Overview              alerts, EligibilityPanel, 6 KPIs, Funnel, Earnings, price positioning, 12-mo Spark
   │  └─ EligibilityPanel   "why am I not matched" (supplier_portal.eligibility)
   ├─ Rfqs                  matched RFQ inbox (supplier_api.inbox)
   │  └─ QuoteForm          upload→read (extract_quote) or manual items; Check (dry_run) → submit_quote
   │     └─ QuoteCheck      readiness score vs the 70 pass mark (from fn_quote_structured_score)
   ├─ Documents             document centre (supplier_portal.documents / save_documents)
   │  └─ DocRow             per-document upload/replace + expiry, server-computed status
   ├─ ProfilePanel          established-supplier profile editor (supplier_api.me → ProfileForm)
   │  └─ ProfileForm        contact/licence/offer/bank; kyc mobile verify; wa_optin_set; process_docs + save_profile
   ├─ Projects              won projects (supplier_api.projects)
   ├─ Messages → Thread     gated customer chat (messages_api)
   └─ BillingPanel          dues + pay (supplier_pay list / checkout)
```

---

## 3. Backends and every action

Auth pattern (all supplier functions): `Authorization: Bearer <jwt>` →
`admin.auth.getUser(jwt)` → look up `leads` by lowercased `claimed_by`; ownership is
re-checked server-side on every action.

### `supplier_api` (298 lines, byte-verified == prod)

| Action | Status | Purpose |
|---|---|---|
| `me` | **live** | The supplier's `leads` row (profile + licence + registration). |
| `create_company` | **live** | Create a new `leads` row (self-registration); sets free/paid registration. |
| `process_docs` | **live** | Store licence/profile/catalogues; OCR licence + profile via `license_extract`; append catalogues (never replace). |
| `save_profile` | **live** | Save profile; records terms accept **+ IP**; `aiSummarize`→`profile_ai`, `aiReview`→`supplier_review`; notifies admin on first submit. |
| `inbox` | **live** | Matched RFQs (`inquiry_matches`) + this supplier's quotes; signs redacted drawing pages. |
| `projects` | **live** | Won projects (revealed `transactions`). |
| `extract_quote` | **live** | Read an uploaded quotation → `quote_extract` (OCR + anonymise). |
| `submit_quote` | **live** | Score (`fn_quote_structured_score`) + accept rule; **`dry_run`** preflight is non-mutating; coaching via `fn_quote_coach`. |
| `pay_registration` | **present, dormant** | Creates a Stripe Checkout Session for the AED 1,000 yearly fee. **Only** creates a session — `stripe_webhook` marks paid. Dormant while every supplier is free-tier; not yet surfaced in the portal UI. |
| `search` / `claim` | **backend-ready, not surfaced** | Search the scraped `leads` and claim an existing listing. No portal UI yet. **Needed for supplier activation (#51):** without it, `create_company` makes a *duplicate* lead for a company already scraped. |
**The `dry_run` preflight** is the one subtlety worth knowing: `submit_quote` with
`dry_run:true` runs the *real* scorer and the *real* accept rule, then restores the
quote's prior status so nothing reaches the customer and no coaching email fires. It
returns `accept_via` (`structured_score` | `form_complete` | `structured_not_required`)
so the portal can tell the supplier *why* a quote would send — because passing via
`form_complete` at 65 is not the same as clearing the 70 quality bar.

### `supplier_portal` **v5** (264 lines, byte-verified == prod)

| Action | Status | Purpose |
|---|---|---|
| `overview` | **live** | `fn_supplier_stats` + `buildAlerts` (doc-expiry, new-RFQ, draft-quote alerts) + active match count. |
| `documents` | **live** | Document centre over `DOC_KINDS` (8 types) + catalogues; server-computed status (missing / on_file / valid / expiring / expired). |
| `save_documents` | **live** | Upload documents; catalogues **append** (20-file ceiling); **per-file failures are returned** (a swallowed storage error once reported a licence as "on file" when nothing was written). |
| `eligibility` | **live** | "Why am I not matched" — mirrors the real clauses in `match_suppliers_kw`, separating what **blocks** matching from what only **improves** ranking. |
**v5 is the deployed version and it matters** (tasks #68/#69/#71). Earlier code told a
supplier that document expiry does *not* affect matching — technically true of
`match_suppliers_kw` in isolation, but **false in effect**: `fn_reconcile_doc_blocks`
runs daily and sets `matching_blocked` + `matching_block_reason` when a trade licence
or insurance lapses, and `match_suppliers_kw` *does* exclude `matching_blocked`. v5:
- reports an expired **licence** or **insurance** as a *blocker* — framed as
  auto-restorable ("upload a valid copy and your account is restored automatically,
  usually within a day. There is no fee"), not "contact our team";
- adds **expiring-within-30-days** warnings to *improving*, so a supplier is warned
  while it is still fixable, not after the account is already paused.

`DOC_KINDS`: `license` (**the only required doc**), `profile`, `vat`, `insurance`,
`iso`, `manufacturer`, `egr`, `iban`. The UI groups them: **Required to get verified**
(licence, profile, catalogues) and **Optional — get matched to more work** (insurance,
iso, manufacturer, egr). `vat` and `iban` are backend-supported but deliberately hidden
— the TRN is already read off the trade licence, and QuotesDone never holds a
supplier's bank details (money moves through Stripe both ways).

### `supplier_pay` (130 lines, byte-verified == prod)

| Action | Purpose |
|---|---|
| `list` | Outstanding dues (`supplier_dues`) + total owed. |
| `checkout` | Stripe Checkout Session for the dues. **Only creates the session** — never marks anything paid. |

**There is no commission on won work.** Dues arise *only* when a customer is refunded
because the platform could not reach the supplier — the reveal fee is recovered, plus a
late fee. `dues_interest_daily` accrues interest, `dues_ban_overdue_daily` bans on
prolonged non-payment.

### Helper functions (byte-verified == prod)
- **`rfq_flag`** — "scope unclear?" → asks the customer to add detail to an RFQ.
- **`sign_upload`** — issues a signed upload URL for the `supplier-docs` bucket (used for the EGR certificate).
- **`wa_optin_set`** — sets the supplier's WhatsApp-alert opt-in.

### Shared functions (verified == prod in the customer chapter; unchanged)
`role_guard` (blocks a customer email from signing in as a supplier), `login_otp`
(sign-in codes), `kyc` (`state` / `send_sms` / `verify_sms` / `accept_terms`),
`messages_api` (`threads` / `thread` / `send` / `request_chat`).

---

## 4. Backend constellation this surface depends on

These have **no portal caller** but are live because other edge functions, SQL
functions, or crons invoke them. **All byte-verified == prod. Do not delete.**

| Function | Reached by | Role |
|---|---|---|
| `quote_extract` | `supplier_api.extract_quote`, `quote_review_api` | Vision-reads an uploaded quotation, anonymises it (ADR-010 masking — supplier identity cannot leak to the customer). |
| `supplier_review` | `supplier_api.save_profile` | AI review of a submitted profile (severity + issues). |
| `supplier_ack` | `fn_customer_success`, `fn_refund_state`, `qd_recompute_response`, `qd_reveal_nudges` | Supplier acknowledgement / response tracking. |
| `quote_quality` | `fn_ai_trainer`, `fn_eval_snapshot`, `fn_exception_alerts`, `fn_health_index`, `fn_twin` | Quote scoring for the autonomy engine. |
| `quote_review` | `quote_review_api`, `fn_ai_trainer` | The quote-detailing agent. |
| `doc_extract` | cron `doc_process` (every 5 min) | Processes the inbound-document queue. |
| `doc_reminder` | cron `doc_reminders_daily` (`run_doc_reminders`) | Document-expiry reminder emails. |
| `route_inquiry` **v9** | `dispatch_inquiry` / matching pipeline | The **matcher**: builds each RFQ's supplier shortlist → `inquiry_matches`. v9 adds an opt-in structured-capability path (`decision_policy.use_capability_matching`): `inquiry_parse` → `fn_match_capability` hard gates → structured score → LLM adjudicator. Default is the untouched legacy keyword path. |

---

## 5. Database

### Key tables
- **`leads`** — the supplier record. `claimed_by`, `approval_status`, `registration_status`, `registration_fee_due`, `license_expiry`, `insurance_expiry`, `matching_blocked`, `matching_block_reason`, `permanently_closed`, `banned`, `capability_summary`, `sector`/`categories`/`products`/`services`, `service_emirates`, the `*_doc_path` columns + `catalog_doc_paths`, `accepted_terms_at`/`_version`/`_ip`.
- **`inquiries`**, **`inquiry_matches`** (the shortlist), **`quotes`** (+ `submittable`, `structured`, `source`), **`quote_items`**.
- **`quote_reviews` / `quote_review_messages` / `quote_committed_items`** — used only by `quote_review_api` (see §7).
- **`supplier_twin` / `supplier_reputation`** — read only by `supplier_me` (see §7).
- **`notifications`**, **`doc_reviews`** (inbound-document queue, read by the OS console).
- **`pricing_config`** (`supplier_free_count` = 1000, `supplier_reg_fee`, `auto_approve_suppliers`), **`decision_policy`** (`use_capability_matching`, `match_relevance_floor`).

### Key functions
| Function | Purpose |
|---|---|
| `fn_supplier_stats` | Every dashboard number (quotes, reveals, hired, win/response/reveal rates, lead time, deal value, 12-mo history). |
| `fn_supplier_expiries` | Per-document expiry status for alerts. |
| `fn_reconcile_doc_blocks` | **Daily.** Sets `matching_blocked` + `matching_block_reason` on an expired licence/insurance; restores automatically on renewal. This is the indirection that makes expiry gate matching. |
| `match_suppliers_kw` | Keyword shortlist; excludes `matching_blocked` / `banned` / `permanently_closed`. |
| `fn_match_capability` | v9 gated matching (trade intersection, role, exclusions, authority approvals, value band, confirmed scope). |
| `fn_quote_structured_score` / `fn_quote_coach` | Quote readiness score (70 pass mark) + coaching. |
| `registered_supplier_count` | Drives the free-tier cutoff. |

### Crons on the supplier surface
`doc_process` (doc_extract, 5 min), `doc_reminders_daily`, `doc_expiry_daily`
(`fn_doc_expiry_scan`), `licence_block_reconcile_daily` (`fn_reconcile_doc_blocks`),
`doc_final_notice_daily`, `supplier_success_daily`, `supplier_capability_chase_daily`,
`subscription_billing_daily`, `dues_interest_daily`, `dues_ban_overdue_daily`,
`embed_suppliers_daily` (`embed_leads`), `scan_new_supplier_categories`,
`capability_backfill_daily` (`enrich_capability`), `founding_rank_daily`,
`pending_suppliers_digest`.

---

## 6. Business rules

**Registration.** Free for the first 1,000 suppliers (`pricing_config.supplier_free_count`);
after that AED 1,000/year (`supplier_reg_fee`), paid via `supplier_api.pay_registration`
→ Stripe → `stripe_webhook`. Currently everyone is free-tier, so the fee path is
dormant. Approval is manual unless `auto_approve_suppliers` is set; `submit_quote` is
gated on `approval_status = 'approved'` ("within 3 working days").

**Documents & matching.** Only the **trade licence** is required, and it must stay
valid. An expired licence or insurance pauses matching automatically (via
`fn_reconcile_doc_blocks` → `matching_blocked`) and restores automatically on renewal,
with **no fee**. Everything else is optional and only widens reach.

**Quotes & anonymity.** A quote is read from an upload (`extract_quote` → `quote_extract`,
OCR + anonymise) or entered as line items. `submit_quote` scores it, runs the `dry_run`
preflight for pre-send feedback, then either sends it (`submitted`, customer notified)
or holds it as a `draft`. Quotes reach the customer **anonymised** — the customer pays
to reveal the supplier. Supplier identity must never leak through a quote (ADR-010).

**Money direction.** No commission on won work. The only supplier-side charges are
recovered reveal fees + late fees when the supplier was unreachable for a refunded
customer. QuotesDone never holds supplier bank details.

---

## 7. Registration, documents & verification

### Fields — what is needed vs optional
**Required to submit for approval** (enforced in `ProfileForm.save` + `supplier_api.save_profile`):
- Contact name and a **mobile that has been SMS-verified** (`kyc.verify_sms`).
- Trade licence number.
- A company profile document on file.
- Accepting the supplier terms.

**Optional** (they only widen reach / ranking): signatory name, products, services,
description, emirates served, licence authority / expiry / TRN, EGR number, company type
/ size, founded year, bank name / account, WhatsApp opt-in — and **every non-licence
document** (insurance, ISO, manufacturer authorisation, EGR card, catalogues). Only the
**trade licence** is a hard requirement, and it must stay valid to keep matching.

### One home per document — the Profile ↔ Documents de-duplication
`ProfileForm` is reused for two jobs: first-time **registration** (Onboarding) and an
established supplier **editing** their profile (the Profile tab). It now takes a `mode` prop:
- **register** — shows the document uploads (trade licence, company profile, catalogues),
  because a brand-new supplier has no Documents tab yet and must provide them to be approved.
- **edit** — hides those uploads and points the supplier to the **Documents tab**, the single
  home for every document file. The Profile tab keeps only *data* fields (contact, licence
  number / authority, products / services / description, emirates).

Before this, licence + company profile + catalogues appeared in **both** tabs — the same file
asked for twice. (EGR had already been de-duplicated to Documents-only; its leftover
`egrFile → signUpload → sign_upload` upload handler was dead code and was removed.)

### How the agent reads an attached PDF / photo
- **Trade licence** — `ProfileForm.upLicense` renders the file to page images client-side
  (`fileToImages`, up to 6 PDF pages) → `supplier_api.process_docs` → **`license_extract`**
  (vision OCR) → returns licence number, authority, city, expiry, emirate, TRN and the legal
  company name. The form auto-fills those fields; if the licence's legal name differs from what
  was typed, the company name is corrected and the change is flagged to the supplier.
- **Company profile** — same path in `profile` mode → `license_extract` returns a capability
  summary + products / services / emirates, which seed `capability_summary` (matching fuel)
  where the supplier left them blank.
- **Quotations** — `extract_quote` → **`quote_extract`** reads the quote and anonymises it
  (ADR-010 masking) so the supplier's identity cannot leak to the customer.

### How verification works
1. **Email** — proven by the OTP sign-in (`login_otp`); a customer email is blocked from
   registering as a supplier (`role_guard`).
2. **Mobile** — `kyc.send_sms` → `kyc.verify_sms`; **required** before a profile can be submitted.
3. **Terms** — `kyc.accept_terms` + `save_profile` records `accepted_terms_at`, the version, and
   the originating **IP** (evidence for the collections / legal path).
4. **Admin approval** — `approval_status` goes `pending → approved` (automatic if
   `auto_approve_suppliers` is set, otherwise a human reviews, assisted by the `supplier_review`
   AI check). `submit_quote` is gated on `approved`.

---

## 8. What the cleanup did (22 Jul)

**Deleted 7 dead functions** (production + repo; recoverable from git). Each was proven
dead across all five invocation vectors — frontend, other edge functions, SQL functions,
cron jobs, database-webhook triggers — before removal:

| Function | Why it was useless |
|---|---|
| `quote_ai` | Paste-text quote path; its portal UI was removed in the rebuild. Superseded by `quote_extract`. |
| `reembed_suppliers` | Completed one-shot embedding backfill. Superseded by the live `embed_leads` daily cron. |
| `quote_review_api` | Alternative interactive quote-detailing flow; its 3 tables held **0 rows** and no SQL function referenced them. The shipped path is `submit_quote` + the dry-run QuoteCheck. Old version. |
| `catalogue_ingest` | A 5th writer of `capability_summary`; that column is already filled by `profile_ai`, `enrich_capability`, `admin_detail` and `match_eval`, and this one was never called. Redundant. |
| `doc_review_api` | Orphaned admin doc-approver; `doc_extract` never fed its queue and nothing invoked it. |
| `supplier_me` | Superseded by `supplier_portal.overview`. The twin/reputation tables it read stay (the OS uses them via `fn_ws_supplier_360`); the dead supplier-facing reader does not. |
| `sign_upload` | Signed-upload helper whose only caller was the dead EGR path; 0 SQL/cron references. |

**Frontend dead code removed** (`SupplierPortal.tsx`): the `egrFile → signUpload → sign_upload`
chain (`setEgrFile` was never called, so it could never fire) and a duplicate `loading` key in
the bilingual dictionary. **Document uploads de-duplicated** between the Profile and Documents
tabs (§7).

**Reconciled 2 stale repo mirrors — prod → repo, no production change:** `supplier_portal`
(repo was pre-v5 238 lines; prod is **v5** 264, expiry-aware eligibility) and `route_inquiry`
(repo was pre-v9 143; prod is **v9** 229, structured capability matching). Both were deployed
work the earlier git re-sync (#94) never mirrored back — which is why the repo must be
byte-verified against production, not trusted (full 184-function audit open, #115).

**Also stripped the last 2 dead actions** — `supplier_api.dashboard` (+ its sole helper
`ratingOf`) and `supplier_portal.notifications` — then redeployed both via the file-based CLI,
byte-verified repo == prod with `verify_jwt = false` preserved. `search`/`claim` (the
claim-a-scraped-listing backend, needed for supplier activation #51) and `pay_registration`
(the registration-fee path) were **kept** — needed capabilities, not dead code.

**Verified:** repo == production for the entire supplier surface — every function in §3/§4
byte-identical; the supplier frontend compiles clean; function count **184 repo == 184 prod**
(191 − 7 deleted). `verify_jwt = false` preserved everywhere; 0 ERROR security advisories.

---

## 9. How to verify this chapter is still true

```bash
git status --porcelain                       # empty
git rev-parse HEAD origin/main               # match

# repo == production for any supplier function (needs the CLI's stored session):
npx supabase@latest functions download supplier_portal --project-ref htdblwldjkcgjvmqkbeh
#   then diff the download against supabase/functions/supplier_portal/index.ts → identical
```

Do **not** trust file timestamps or assume the repo mirror is current — `supplier_portal`
and `route_inquiry` both sat stale in the repo while production was two versions ahead.
Only a real download tells the truth. Every function on the supplier surface was
verified this way on 22 Jul 2026.
