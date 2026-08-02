# Frontend current state â audit

**Repository:** `ahmadmhdnabilalzain-bot/quotesdone`, branch `main` at `47f92ce`
**Audited:** 2 August 2026
**Production deployment:** `dpl_6A5JViDXn4DAprAsfbBLmFkWfXBR`, READY, commit `47f92ce`
**Method:** static analysis of the checked-out repository plus live HTTP verification of the deployed build. No code changed.

---

## 0. The headline

The package assumed the frontend might be large and unverifiable. It is neither. **The entire application is 21 pages and 34 components, and three of those components are the whole product**: `OsxShell.tsx` (2,210 lines) *is* the Executive OS, `SupplierPortal.tsx` (886 lines) *is* the supplier portal, `CustomerPortal.tsx` (521 lines) *is* the customer portal. Each is mounted by a page that does nothing but render it.

That is good news for this upgrade and bad news for the roadmap's assumptions. Good, because there is no tangled legacy UI to unpick and no second portal to reconcile â the "do not build a parallel portal" rule is easy to honour. Bad, because almost none of the P1 surfaces in the three traceability CSVs exist in any form, and 3,617 lines of single-file client components is not a base you can safely extend by another 5,000.

---

## 1. Stack

| | |
|---|---|
| Framework | Next.js **16.2.11**, App Router, Turbopack |
| React | 19.2.8 |
| i18n | `next-intl` 4.13.4 â `en` (default, unprefixed) + `ar` (`/ar`), `localePrefix: 'as-needed'` |
| Styling | Tailwind + Radix primitives (dialog, tabs, tooltip, scroll-area, separator, slot) |
| Command UI | `cmdk` 1.1.1 |
| Motion | `motion` ^12.42.2 |
| Audio | `wavesurfer.js` 7.8.6 |
| Backend client | `@supabase/supabase-js` 2.110.8 |
| **Tests** | **none â no test framework, no test file, no `test` script** |

`package.json` scripts are `dev`, `build`, `start`, `typecheck`. Nothing else.

---

## 2. Route inventory

All 21 pages live under `src/app/[locale]/`. Two route handlers: `robots.txt`, `sitemap.xml`.

**Marketing / public (14):** `/`, `/about`, `/contact`, `/faq`, `/services`, `/services/[slug]`, `/blog`, `/blog/[slug]`, `/terms`, `/privacy`, `/cookie-policy`, `/refund-policy`, `/supplier-agreement`, `/acceptable-use`, `/disclaimer`, `/complaints`

**Application (5):**

| Route | Renders | Notes |
|---|---|---|
| `/os` | `OsxShell` | `force-dynamic`, `robots: noindex` |
| `/console` | `OsxShell` | **byte-identical to `/os` apart from the title** |
| `/portal` | `SupplierPortal` | |
| `/supplier` | `SupplierPortal` | **byte-identical to `/portal`** |
| `/me` | `CustomerPortal` | verified live: HTTP 200, `x-robots-tag: noindex`, hreflang en/ar present |

**Duplicate route finding.** `/os` â¡ `/console` and `/portal` â¡ `/supplier`. Four routes, two products. Each duplicate is a second URL people can bookmark, a second entry in the middleware matcher, and a second thing to remember when auth or layout changes. One of each pair should redirect, not re-render.

Every application route is in the `next-intl` middleware matcher, so `/ar/os`, `/ar/me`, `/ar/portal` all resolve.

---

## 3. Component inventory

34 `.tsx` files. Ownership is extremely concentrated:

| Component | Lines | Owns |
|---|---:|---|
| `osx/OsxShell.tsx` | **2,210** | The entire Executive OS: 26 `os_api` actions, command palette, realtime, dashboards, boards, marketing studio, knowledge, inbox, files |
| `portal/SupplierPortal.tsx` | **886** | Whole supplier portal: login, onboarding, docs, RFQ inbox, quoting, billing |
| `me/CustomerPortal.tsx` | **521** | Whole customer portal: login, inquiries, quotes, reveal |
| `motion/primitives.tsx` | 276 | Shared animation primitives |
| `NodeField.tsx` | 205 | Background canvas field |
| `LiveMatch.tsx` | 148 | Marketing "live matching" animation |
| `ChatWidget.tsx` | 116 | Site assistant launcher |
| 9 Ã `ui/*` | 7â37 each | Radix wrappers (button, card, dialog, command, sheet, input, badge, separator, scroll-area) |
| remaining 16 | 19â108 | Marketing sections and legal/document renderers |

**`OsxShell.tsx` is the single largest risk in this repository.** It is the only file using realtime subscriptions, the only consumer of 26 backend actions, and the only place the command palette exists. Every OS requirement in the traceability CSV lands in it. Adding Executive Home v2, live activity, org/employee workspaces, trace explorer and a simulation workspace to a 2,210-line client component is not an option; it needs decomposition before it needs features.

---

## 4. Data-fetching and state architecture

There is no state library. No Redux, Zustand, React Query or SWR. Every one of the three application components holds its own `useState` and calls the backend directly with `fetch`.

Two client paths:

**`src/lib/osClient.ts`** â OS only. Exports a hardcoded `SUPA_URL` and the **anon publishable key as a string literal in source**, plus `osApi(action, body)` which POSTs to `os_api` with the user's access token. Includes a thoughtful timeout split: 120 s for a `SLOW_ACTION` regex (`secretary_chat|exam_run|knowledge_refresh|knowledge_dispatch|extract_doc|report_pdf`), 30 s otherwise, with a human-readable abort message. This is the most mature piece of client code in the repo.

**A local `call()` helper duplicated inside each portal** â POSTs `{action, ...}` to a named edge function with the session token.

### Frontend â backend surface actually in use

| Edge function | Call sites |
|---|---:|
| `kyc` | 12 |
| `customer_api` | 12 |
| `supplier_api` | 11 |
| `messages_api` | 9 |
| `supplier_portal` | 4 |
| `login_otp` | 4 |
| `supplier_pay` | 2 |
| `role_guard` | 2 |
| `os_api` | 26 actions via `osApi` |
| single call each | `wa_optin_set`, `rfq_flag`, `quote_compare`, `stripe_confirm`, `stripe_checkout`, `customer_portal`, `transcribe`, `inquiry_intake`, `finance_doc`, `site_assistant`, `report_body`, `kb_fill_gap`, plus 9 `os_*` functions |

**Zero direct `supabase.rpc()` calls and zero direct table reads from the browser.** Everything goes through an edge function. Combined with the database posture (330 tables, RLS enabled on all 330, only 3 policies), this means the anon key can read essentially nothing directly â the portals are secure by construction rather than by policy. That is a genuinely strong position and must be preserved through this upgrade.

**`os_api` exposes 35 actions; the frontend uses 26.** Nine are unreachable from any UI: `exam_revert`, `nav`, `ping`, `prompt_approve`, `prompt_gate`, `prompt_rollback`, `prompt_view`, `report_pdf`, `search`. `nav` and `search` are exactly what the Command Palette requirement needs and are already built server-side.

---

## 5. Authentication, roles and locale

**Auth** â Supabase session (`persistSession`, `autoRefreshToken`) obtained via `login_otp`; each portal renders its own login screen when there is no session. `role_guard` is called twice. The OS relies on `os_api` returning 401/403, which `osClient` translates to "Session expired" / "Not authorized (admin only)". There is **no route-level guard and no middleware auth** â `/os` is publicly reachable and renders a shell that then fails its API calls. Acceptable today; it is not an Observe/Control-Mode foundation.

**Locale** â `src/i18n/routing.ts` defines `['en','ar']` with `localePrefix: 'as-needed'`. `src/middleware.ts` is a plain `next-intl` middleware with an **explicit matcher allowlist** rather than a catch-all; the comment records that `/blog/:path*` had to be added after individual posts became native pages. That pattern will bite again â every new route must be added by hand or it silently bypasses locale routing.

`src/app/[locale]/layout.tsx` sets `dir = locale === 'ar' ? 'rtl' : 'ltr'` on `<html>` and swaps font variables. Verified live: `/me` returns `lang="en" dir="ltr"` plus correct `hreflang` alternates for en, ar and x-default.

---

## 6. English / Arabic coverage â the most important frontend finding

There are **two unrelated translation systems**, and the portals are on the wrong one.

**Marketing pages** use `next-intl` with `messages/en.json` (5,451 bytes) and `messages/ar.json` (7,313 bytes). Locale comes from the URL, `<html dir>` follows it. This works.

**All three application components carry their own inline `EN`/`AR` string objects** and their own `lang` state with a local toggle button:

```
CustomerPortal.tsx:133   const rtl = lang === 'ar';
SupplierPortal.tsx:166   const rtl = lang === 'ar';
```

Consequences, all of them real:

1. **Visiting `/ar/me` does not give an Arabic portal.** The route locale is Arabic, `<html dir>` is `rtl`, and the portal still renders English until the user finds its own toggle.
2. **Direction is set twice and can disagree** â the layout sets `dir` from the URL, the portal sets `dir` from its own state.
3. **The portal strings are not in `messages/*.json`**, so they are invisible to any translation tooling and cannot be reviewed as a set.
4. The supplied audit lists "Arabic experience â full Arabic customer journey" as P1. It is **not achievable without unifying these two systems first**, and that unification is a prerequisite, not a feature.

A separate, smaller issue: `BlogPost.tsx` forces `lang="en" dir="ltr"` on headings even on the Arabic route, with a message key `blog.onlyEnglish` â an honest fallback, but it means the Arabic blog is English.

---

## 7. What already exists of the target vision

Worth knowing before estimating, because several P1 items are partly built:

- **Command palette** â `cmdk` is installed and `ui/command.tsx` exists; `OsxShell` uses it. The backend `os_api` already exposes `nav` and `search`, which the UI does not call. This is closer to done than the CSV suggests.
- **Realtime** â `OsxShell` is the only file that subscribes. The plumbing works; nothing else uses it.
- **PWA** â `manifest.webmanifest`, `theme-color`, apple touch icons, `mobile-web-app-capable` all present and served. The "responsive PWA first" recommendation is already half-satisfied.
- **Motion system** â `motion/primitives.tsx` (276 lines) plus an aurora background and a `NodeField` canvas. The visual layer is more developed than the functional one.
- **Voice** â `wavesurfer.js` is a dependency and `transcribe` is called. Voice input exists in some form.

## 8. What does not exist

No Executive Home v2, live activity stream, organisation chart, employee workspace, trace explorer, simulation workspace, Observe/Control Mode, mission control, digital twin view, timeline, graph view, notification centre, supplier product intelligence, opportunity ranking, customer project workspace, document vault, spending intelligence, enterprise accounts, or approval chains. No 3D anything â correctly, since the roadmap defers it.

**No tests of any kind.** The pack requires unit tests for every deterministic rule, contract tests for every action, integration tests, idempotency tests, provider-outage tests, privacy tests, Arabic/RTL tests and staging E2E. The current count is zero and there is no framework to write them in. This is the single largest gap between the current repository and the acceptance gates.

---

## 9. Dead code, duplication and drift

| Finding | Detail |
|---|---|
| Duplicate routes | `/os` â¡ `/console`; `/portal` â¡ `/supplier` |
| Duplicate `call()` helper | Reimplemented inside each portal component instead of shared in `src/lib` |
| Duplicate i18n | `next-intl` for marketing, inline dictionaries for portals |
| Unreachable backend actions | 9 of 35 `os_api` actions have no UI caller, including `nav` and `search` |
| Legacy naming in UI | `SupplierPortal` billing block still uses a variable named `d.commission`; the visible strings are already correct ("Reveal fee recovered", "there is no commission on won work"), so this is cosmetic â but it should go when billing is touched |
| Committed anon key | `src/lib/osClient.ts` hardcodes the publishable anon key rather than reading `NEXT_PUBLIC_*`. Not a secret leak â but it means a project rotation requires a code change and a redeploy |
| Middleware matcher | Explicit allowlist; new routes silently bypass locale routing unless added by hand |

---

## 10. Screenshots

**Not captured, and I will not claim otherwise.** The audit environment is a cloud sandbox whose egress allowlist does not include `quotesdone.com`; every navigation returned `ERR_CONNECTION_RESET`. Route existence and rendering were verified through the Vercel deployment API instead (`/me` â HTTP 200, correct title, locale and headers).

A ready-to-run capture script is committed at `scripts/audit-screenshots.mjs`. Run it from a machine with normal internet access:

```bash
npx playwright install chromium
node scripts/audit-screenshots.mjs           # writes docs/audit/screenshots/
```

It captures all 18 major routes at 1440Ã900 and 390Ã844 and writes `route_probe.json` with status and title per route. Until it is run, **no claim is made about visual quality, responsive behaviour or mobile layout** â those are the three things the requirement asked screenshots to prove, and they remain unverified.
