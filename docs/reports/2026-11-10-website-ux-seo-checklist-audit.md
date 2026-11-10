# Website, app, SEO and UI checklist audit (10 Nov 2026)

Founder ledger 1605 asked whether a list of website, app, SEO and UI basics is done for QuotesDone.
This report gives each item a status and one line of evidence. Seat: customer_support, with marketing
for the search items. Branch: `customer_support-website-ux-seo-audit-10-nov`. No PR and no deploy, so
every fix below is on the branch and **not live yet**.

## How it was measured

- **Live, read-only, on 10 Nov 2026 (before any fix).** Every check below was run against
  `https://quotesdone.com`. Nothing was submitted, no chat message was sent, and nobody was signed up.
  - **curl:** status, headers and `<head>` of the key URLs.
  - **Crawl of all 146 sitemap URLs:** title, description, canonical, robots, h1/h2, img alt, JSON-LD
    and word count per page. Every internal link found on those pages (500 targets) was then fetched.
  - **Playwright, iPhone viewport (390x844, deviceScaleFactor 1, touch):** 10 pages, cold and warm.
    Measured with the Performance API (TTFB, FCP, LCP, CLS), plus horizontal overflow, tap-target sizes
    in the first screen, fixed/sticky elements, cookies, localStorage and third-party requests.
  - **SSR check:** the same pages with JavaScript off.
  - **Lighthouse-style pass:** CDP throttling at Slow 4G (150 ms RTT, 1.6 Mbps) with 4x CPU, on
    `/`, `/ar`, a blog post and a service page, two runs each.
- **Local proof of the fixes.** The branch was built with `next build --webpack` and served with
  `next start`. It was then driven with curl and Playwright at 320, 360 and 390 px widths.
- **Code:** file:line references are on this branch.

Statuses: **DONE**, **PARTIAL**, **MISSING**, **N-A**. "Fixed here" means changed on this branch and
held by a check: `scripts/checks/the_site_basics_of_the_10_november_audit_stay_fixed.test.mjs` (11
tests) and `scripts/checks/a_wrong_url_gets_the_designed_404_in_its_language.test.mjs` (5 tests).

## Website basics

| item | status | evidence | fix / commit |
|---|---|---|---|
| Favicon set | DONE | `/favicon.ico` 64px, `/icon.png` 256px, `/apple-icon.png` 180px, all 200 live; manifest icons 192 and 512 (maskable) | — |
| Custom 404 page | PARTIAL → fixed here | Live, `/ar/zz-nope` and `/services/zz-nope` get the designed page (`src/app/[locale]/not-found.tsx`). `/zz-nope` and `/about/zz` got Next's bare white "404: This page could not be found", with no `lang`, header or links (screenshot taken). Cause: the middleware matcher named only known paths. | Fixed here: catch-all matcher entry in `src/middleware.ts`, compiled by Next's own `getMiddlewareMatchers` in the check. Local build: `/zz-nope` and `/about/zz` return 404 with the designed page in the visitor's language; `/api/health`, `/robots.txt`, `/sitemap.xml`, `/en/opengraph-image` and `/u/unsubscribe` are untouched. |
| One CTA above the fold | DONE | At 390px the only teal button is "Get quotes" (`/me`). Customer portal, Supplier portal and the "Describe your job" box are secondary. | — |
| Title on every page | DONE | 146 of 146 sitemap pages have a `<title>`; 0 duplicates | — |
| Meta description per page | DONE | 146 of 146, 0 duplicates, all 70–160 characters. `/supplier-agreement`'s description was the document switcher's link labels. | Fixed here (legal render, see SEO) |
| Social share image (OG/Twitter) | DONE | 146 of 146 have `og:image` 1200x630 and `twitter:card summary_large_image`; `/en/opengraph-image` and `/ar/opengraph-image` are 200 PNG; each blog post has its own card | — |
| sitemap.xml | DONE | 146 URLs, all 200; `src/app/sitemap.xml/route.ts`. The 336 emirate variants are left out on purpose: they canonicalise to the parent (`src/lib/seo.ts` splitServiceSlug) | — |
| robots.txt | DONE | `Allow: /` plus the sitemap line. `/me` and `/portal` are `noindex, nofollow` (header and meta). Archived legal versions are `noindex, follow`. | `/complaints/status` was `index, follow`; now `noindex, follow` (fixed here) |
| Alt text on every image | DONE | 2 `<img>` across 146 pages, both with `alt`. The rest is SVG/CSS. | — |
| Works on every phone | DONE (emulated) | 0 px horizontal overflow on 10 live pages at 390px, and on `/` and `/ar` at 320/360/390 locally; `lang`/`dir` correct. Not tested on real Safari or real devices. | — |
| Sticky mobile CTA | DONE | The header is `sticky top-0` (`SiteHeader.tsx:33`) and carries "Get quotes" on every public page | — |
| Loads under 2 seconds | PARTIAL | Unthrottled (datacentre): TTFB 130–350 ms, LCP 0.4–1.2 s, CLS 0 on `/`, `/ar`, the blog post and a service page. Slow 4G + 4x CPU: LCP `/` 1.9–2.3 s, `/ar` 1.7–2.5 s, blog 1.3–1.7 s, service 2.1 s. Total blocking time 300–1,300 ms; about 200 KB of JS per page. | Open (see "What is left", item 3) |
| Forms show errors | DONE | Contact form: native `required` and `type=email`, server error text in `#cmsg`, submit locked while sending (`ContactInner.tsx:36-48`). The message was not announced to screen readers, and the phone field opened the letter keyboard. | Fixed here: `role=status aria-live=polite`, `type=tel` (EN and AR) |
| Thank-you page after request / sign-up | PARTIAL | The contact form confirms in place ("Thanks — we will be in touch", or a ticket number and a status link). A posted request lands on the dashboard or a "posted" state (`NewRequest.tsx`). There is no thank-you URL, so no conversion can be counted. | Open (only useful once analytics exists) |
| Cookie banner | N-A (a notice is shown anyway) | Only essential storage is used. Cookies: `NEXT_LOCALE`. localStorage: `qd-chat-conv`, the consent record, portal tokens. No third-party request except our Supabase. The banner says "essential cookies only" and has one button (`CookieConsent.tsx:9-15`). | — |
| Privacy policy page | DONE | `/privacy` and `/ar/privacy` 200; linked in the footer (`SiteFooter.tsx:28`) | — |
| Analytics installed | MISSING | No analytics script or request on any page (no Vercel Insights, GA, Plausible or PostHog). `FirstTouch.tsx` only keeps the first UTM in localStorage for supplier sign-up. | Open: marketing's call, and the cookie text must change with it |
| Real contact details | DONE | `/contact`: management@quotesdone.com and WhatsApp +1 218 316 6814. Legal texts: phone +971 56 791 8605. The founder's mobile is gone (ledger 1482, pinned by a check). | — |

## App essentials (the /me and supplier portals)

| item | status | evidence | fix / commit |
|---|---|---|---|
| Onboarding flow | DONE | Customer: `ProfileGate.tsx`, `ConciergeSteps.tsx`, first request guided and confirmed (check `a_first_request_is_guided_and_confirmed`). Supplier: `portal/supplier/core/Onboarding.tsx`, `GetMatched.tsx` steps. | — |
| Empty states | DONE | `CustomerPortalView.tsx`, `Comparison.tsx`, `AssistantPanel.tsx`; supplier intelligence panels show an explicit "not available yet" basis | — |
| Offline error handling | PARTIAL | Failed calls show a message, and the public client and portal uploads retry once on a gateway failure (checks `public_site_client_retries_a_gateway_failure_once`, `a_supplier_upload_survives_one_gateway_failure`). No `navigator.onLine` or `offline` event anywhere in `src`, and no offline banner. | Open |
| Delete account button | DONE | `PrivacyControls.tsx:72`: `pdpl_request_me('delete')` with an emailed code, a 7-day cancel window and Cancel on any device. Present in both portals' settings. | — |
| Privacy policy link (in the app) | PARTIAL → fixed here | Inside both portals the only legal link was the terms at sign-up (`ProfileGate.tsx:87`) | Fixed here: "Read our Privacy Policy" / «اطّلعوا على سياسة الخصوصية» in the account data controls (`PrivacyControls.tsx`); Arabic line recorded in both reviewed lists |
| Crash reporting | PARTIAL | Server render errors post to `site_error_ingest` (`src/instrumentation.ts:39`, `onRequestError`), and `[locale]/error.tsx` shows a reference. Client-side JS errors are not reported (only `console.error`), and Sentry is not wired. | Open |
| Analytics | MISSING | As above | Open |

## SEO

| item | status | evidence | fix / commit |
|---|---|---|---|
| Search Console verification | PARTIAL (unverified) | No `google-site-verification` meta and no verification file. DNS TXT could not be read: the DoH resolvers are blocked by the proxy, and Vercel returns 403 on the domain records. PR #1484 ("so Search Console folds them") suggests a property exists. | Founder or marketing to confirm in Search Console (DNS verification is normal) |
| Core Web Vitals | PARTIAL | Lab: CLS 0.000 on every page; LCP within 2.5 s even throttled; TBT high (see above). No field data: there is no RUM, and CrUX was not queried. | Open |
| Orphan pages | DONE | Every one of the 146 sitemap URLs has at least one inbound internal link from another sitemap page | — |
| Schema markup | DONE | Organization + WebSite on every page (`seo.ts siteLd`). Service + BreadcrumbList on services, BlogPosting + BreadcrumbList on posts, FAQPage (52 pages), HowTo on /how-it-works. All parsed. | — |
| H1/H2 structure | PARTIAL → mostly fixed here | Live: 16 legal pages had 2 `<h1>` (one hidden by CSS); `/supplier-agreement` had 3, 2 visible, plus a printed document switcher. Cause: the agreement's `.body` is never closed (8 `<div>` open, 7 close, in v10–v17, both languages). `/how-we-verify` has 0 `<h2>`: its steps are `<b>`. | Fixed here: `src/lib/docHtml.ts` closes the body at render and drops the duplicate h1. legal.json is untouched, because its sha256 is what live suppliers accepted. Local build: 1 `<h1>` on every legal page, description is now the agreement's opening line. `/how-we-verify` h2: open. |
| Original content | DONE | 32 first-party posts and 24 service pages from committed JSON; copy claims guarded by `site_copy_claims_only_what_matching_and_redaction_do` | — |
| Quality backlinks (report only) | not measured | No backlink index is available to this session. Owned profiles: Instagram, LinkedIn, X, Facebook (`seo.ts SOCIALS`) | Report only |
| Broken links and 404s | DONE | 146 of 146 sitemap URLs return 200; 500 of 500 internal link targets return 200. Unknown URLs now get the designed 404 (fixed here). | — |
| Crawlable JS (SSR vs CSR) | DONE | With JS off: `/` 1,465 words vs 1,503 with JS; `/ar` 1,326 vs 1,400; blog 739 vs 777; h1 present. Pages are prerendered (`x-vercel-cache: PRERENDER/HIT`). `/me` is client-only by design (noindex). | — |
| No cannibalization | DONE | 0 duplicate titles and 0 duplicate descriptions in 146 pages. The 336 emirate variants canonicalise to their service. Service pages are transactional, blog guides informational. | — |
| Mobile friendly | DONE | As "works on every phone" | — |
| Author bios on blog | PARTIAL | Byline is "QuotesDone" (28 posts) or "QuotesDone Team" (4). BlogPosting author is the Organization. No person or bio. | Open: needs a real named author; none was invented |
| Titles under 60 characters | PARTIAL → partly fixed here | Live: 111 of 146 titles over 60 characters, mostly from the " \| QuotesDone" / " — QuotesDone" and " — Get Free Quotes" tails | Fixed here: `src/lib/titleFit.ts` drops those tails only while a title is over 60 (OG and Twitter keep the full title). Simulated on the crawl: 111 → 49 over, all titles still unique; every service title now fits, EN and AR. Still over: 45 blog titles ("…(2026 price guide)"), `/ar`, `/supplier` EN+AR, `/ar/how-it-works`. Those need rewording by their owner. |
| Unique descriptions | DONE | 146 unique | — |
| Merge thin pages | DONE | Under 350 words: only `/contact` (67) and `/ar/contact` (64), utility pages, plus `/ar/how-we-verify` 318 and `/ar/how-it-works` 306. The 336 emirate near-duplicates are already folded by canonical. | — |
| Compressed images | DONE / N-A | No raster content images on public pages. OG PNGs are 129–133 KB; icons 8–21 KB; fonts self-hosted woff2, one preload per locale | — |
| Search intent | DONE (report) | Service pages: transactional, with a CTA to `/me`. "Cost of X in the UAE (2026 price guide)" posts: price intent, with tables. FAQ: informational, FAQPage schema. | Report only |
| Low-competition keywords (report only) | not measured | No keyword tool in this session. The long-tail price guides and their Arabic twins («كم تكلفة … في الإمارات») are the natural low-competition set, but this is unmeasured. | Report only |

## UI tips

| item | status | evidence | fix / commit |
|---|---|---|---|
| Skeleton loaders | DONE | `src/components/ui/skeleton.tsx`, used in 14 files; one loading system with a 150 ms show delay (`ui/busy.tsx:136-141`) | — |
| Optimistic updates | PARTIAL | Rating stars fill at once and roll back on failure (`me/requests/Contact.tsx:68`); other writes wait for the server | — |
| Command menu | DONE (not N-A) | Customer portal ⌘K/Ctrl-K search (`me/PortalShell.tsx:130`); supplier `SupplierCommandPalette.tsx:21` | — |
| Shortcut hints | DONE | `⌘K` key hint in the portal search (`me/PortalShell.tsx:232`) | — |
| Undo toasts | PARTIAL | Supplier trade removal can be undone until Update (`ServicesTab.tsx:253,448`); account erase has a 7-day cancel. No undo toast. | — |
| Stale-while-revalidate | PARTIAL | Pages come from Vercel's prerender cache; fonts `stale-while-revalidate=86400` (`next.config.mjs:127`); portal tabs prefetch then read fresh (`supplier/tabPrefetch.ts`). No SWR data cache. | — |
| Pre-rendering | DONE | Static generation (local build: 522 pages generated), `x-vercel-cache: PRERENDER` live | — |
| BlurHash placeholders | N-A | No raster photos on the public pages | — |
| View transitions | MISSING | 0 uses of `startViewTransition` / `@view-transition` | Open |
| Swipe-to-dismiss sheets | MISSING | The mobile menu sheet closes by button or Escape only (`MobileNav.tsx`) | Open |
| Interruptible animations | DONE | Motion springs and CSS transitions; `prefers-reduced-motion` honoured (`NodeField.tsx:32`, `globals.css:980`) | — |
| Predictive back | N-A | An Android system gesture for native apps; on the web the browser's own back applies. (The mobile menu does not add a history entry, so Back leaves the page.) | — |
| Hit slop (taps ≥ 44 px) | PARTIAL → header fixed here | Live at 390px: header "Get quotes" 93x36, menu 36x36, logo link 36 high | Fixed here: all 44 px on phones (local: 93x44, 44x44, 148x44, no overflow at 320 px). Still small: blog/FAQ contents anchors 30 px, breadcrumb links 16–24 px, home example chips 31–34 px. |
| Safe-area insets | PARTIAL | `env(safe-area-inset-bottom)` on the portal tab bar (`me/PortalShell.tsx:303,311`), but the viewport has no `viewport-fit=cover` (`[locale]/layout.tsx` `viewport`). So the inset is 0 on iPhone, while the manifest is `standalone` with a black-translucent status bar. | Open (site-wide layout change, not taken as low-risk) |
| One-time-code autofill | PARTIAL → fixed here | 7 of 8 code fields had `autoComplete="one-time-code"`; the customer e-mail code field did not (`me/auth/ProfileGate.tsx:85`) | Fixed here; the check sweeps every numeric code field in `src` |
| Tabular numbers on prices | PARTIAL → fixed here | The home worked-case quotes were `tabular-nums` live. The blog's 50 price tables and the price guide bands were `normal`. | Fixed here: `.qd-prose th/td` and the PriceGuide amount |
| Balanced headlines | DONE | `h1–h4 { text-wrap: balance }`, `p { text-wrap: pretty }` (`globals.css:535-543`); measured `balance` live | — |
| Continuous corners | MISSING | No `corner-shape: squircle` (Chromium-only CSS); cosmetic | Not proposed |
| Idempotency (double submit) | PARTIAL → client fixed here | Quote form: ref guard plus DB unique 23505 (`QuoteForm.tsx:64-67`, `supplier_api/actions/quotes.ts:367`). Repeat request: unique partial index. Contact form: locked while sending. The request composer's Send had no in-flight guard, and `create_inquiry` reads the intake as `ready` (`customer_api/actions/inquiry_create.ts:134`) and marks it consumed later (`:352`), with no DB guard. | Fixed here: one post per press in `me/NewRequest.tsx`. Server-side claim still open. |
| Amazon safe triangle | DONE | The Services mega-menu's hover zone is one wrapper holding trigger and panel (`AudienceNav.tsx:114`), with a 140 ms close grace (`:87`). Diagonal travel into the panel does not close it. | — |

## N-A: native store app items

QuotesDone is a website and an installable PWA, not a store app, so these do not apply:

- **Paywall after onboarding:** the customer pays 3% at reveal and suppliers pay nothing to quote. No subscription paywall.
- **Restore purchases button:** a store in-app-purchase rule. Payments here are Stripe Checkout per reveal.
- **Sign in with Apple:** required by the App Store only when other social logins are offered. Sign-in is email or mobile with a code.
- **App icon and splash screen:** a store build asset. The web equivalent is DONE: favicon set, manifest icons 192/512 maskable, and `background_color` for the Android PWA splash.
- **Push notifications as a store feature:** notices go by email and WhatsApp to the confirmed number. Web push is not used.

## Changed on this branch

- `src/middleware.ts`: catch-all matcher entry, so every unknown URL gets the designed 404.
- `src/lib/docHtml.ts` (new; tag scan moved out of `DocFrame.tsx`), `src/components/LegalDoc.tsx`:
  the Supplier Agreement body is closed at render, and the duplicate `<h1>` is dropped.
- `src/lib/titleFit.ts` (new), `src/lib/seo.ts`: `<title>` tails dropped only while over 60 characters.
- `src/app/[locale]/complaints/status/page.tsx`: `noindex, follow`.
- `src/components/AudienceNav.tsx`, `MobileNav.tsx`, `SiteHeader.tsx`: 44 px tap targets on phones.
- `src/components/me/NewRequest.tsx`: one post per press.
- `src/components/me/auth/ProfileGate.tsx`: one-time-code on the e-mail code field.
- `src/content/marketing.json` (contact form, EN and AR): `type=tel`, `role=status aria-live=polite`.
- `src/app/globals.css`, `src/components/PriceGuide.tsx`: tabular figures on price tables.
- `src/components/portal/privacy.ts`, `PrivacyControls.tsx`: Privacy Policy link in both portals.
- `scripts/checks/arabic_reviewed_strings.json`, `scripts/checks/nothing_a_supplier_reads_can_be_arabic.gated.json`:
  one reviewed line (`250a8b8b8ae3`), inserted by text.
- Two new checks, named above. Each one fails on main and passes on the branch.

## What is left, in priority order

1. **Deploy this branch.** Until then production still serves the bare 404 on `/zz-nope`, the
   3-`<h1>` Supplier Agreement with the switcher as its description, 111 long titles and 36 px header taps.
2. **Analytics** (MISSING, marketing seat). A cookieless option such as Vercel Web Analytics keeps the
   cookie text true. Anything that sets an analytics cookie needs a consent choice and the
   cookie-policy text changed with it. Thank-you URLs for request and contact only become useful after this.
3. **JavaScript weight / TBT.** About 200 KB of JS per public page; TBT is 300–1,300 ms on a
   throttled phone. LCP is under 2.5 s but at the edge on `/ar` (2.5 s on the first run). Set a budget
   in the gate and look first at what the layout ships to every page (ChatWidget, NodeField, motion).
4. **Server-side double-post guard on `create_inquiry`.** Claim the intake atomically
   (`update … set status='consumed' where id=$1 and status='ready' returning id`) or add a unique key on
   the inquiry's intake. The client guard added here covers double taps, not two tabs.
5. **Client crash reporting.** Browser errors reach nobody. `site_error_ingest` needs a public,
   rate-limited client path (it is secret-authenticated today), or a hosted SDK.
6. **Blog titles over 60** (45 posts) and **author bios**: content owner's rewording, CEO review per the
   blog ruling. A named author needs a real person; none was invented.
7. **Search Console:** confirm the property and DNS verification for quotesdone.com and quotesdone.ae.
   This session could not read DNS.
8. **Safe area:** `viewport-fit=cover`, plus top and side padding for the installed-PWA status bar.
   Test on an iPhone before shipping.
9. **Smaller tap targets** (contents anchors, breadcrumbs, example chips), **offline banner**,
   **`/how-we-verify` h2s**, **swipe-to-dismiss** on the mobile menu, **view transitions**.
