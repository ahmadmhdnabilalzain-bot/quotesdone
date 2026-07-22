# QuotesDone — Public Website

_Chapter reference for the public-facing website: the landing page and every
marketing, content, legal, and blog surface — everything reachable from the
public header and footer. Companion to `CUSTOMER_PORTAL.md` and
`SUPPLIER_PORTAL.md`._

**Last audited:** 2026-07-22 · **Code commit:** `9bb445f` · **Docs commit:** `e1f24a9`
· **Stack:** Next.js 14 (App Router) on Vercel, bilingual EN/AR via `next-intl`.
Live-verified on production (quotesdone.com) — see §11.

---

## 1. What the public website is

The public site is the marketing and content layer of the QuotesDone Next.js
app (`quotesdone-next`). It is **content-driven**: page copy lives in versioned
JSON under `src/content/`, is paired with a scoped CSS blob, and is injected
into a shared React shell. There is **no CMS and no runtime database read** for
public pages — the content ships in the bundle, so pages are static, fast, and
fully build-time cacheable.

Every public route exists in two locales. `next-intl` serves English at `/<route>`
and Arabic (RTL) at `/ar/<route>` from the same components; UI chrome strings
come from `messages/en.json` + `messages/ar.json`, long-form copy comes from the
per-locale content JSON.

Two — and only two — public pages call the backend: the **contact form** and the
**AI chat widget**. Everything else is static.

---

## 2. Route map

Public, indexable routes (each also served under `/ar/…`):

| Route | Renderer | Content source | EN/AR |
|---|---|---|---|
| `/` | `page.tsx` → Hero · HowItWorks · WhyAnonymous · Categories · CtaBand | `messages/*.json` (i18n) | EN + AR |
| `/about` | `MarketingDoc slug="about"` | `content/marketing.json` + `marketingCss` | EN + AR |
| `/services` | `MarketingDoc slug="services"` | `content/marketing.json` | EN + AR |
| `/contact` | `SiteHeader` + `ContactInner` + `SiteFooter` | `content/marketing.json` → posts to `contact_submit` | EN + AR |
| `/faq` | `SiteHeader` + `FaqInner` + `SiteFooter` | `content/marketing.json` (+ live search filter) | EN + AR |
| `/services/[slug]` | `ServiceDoc` | `content/services.json`, `{service}-in-{emirate}` templating | EN + AR |
| `/blog` · `/blog/[slug]` | `BlogPost` | `content/blog.json` (32 posts) | EN only¹ |
| `/terms` `/privacy` `/cookie-policy` `/refund-policy` `/supplier-agreement` `/acceptable-use` `/disclaimer` `/complaints` | `LegalDoc` | `content/legal.json` + `legalCss` | EN + AR |
| `/sitemap.xml` · `/robots.txt` | route handlers | generated | — |

¹ Blog is English-only by design; `BlogPost` shows a localized "available in
English" notice on `/ar`.

**Not part of this chapter** (app / internal surfaces, documented elsewhere):
`/me` (customer portal), `/portal` and its alias `/supplier` (supplier portal),
`/os` and `/console` (internal OS console — both `robots: noindex`). Legacy paths
`/app`, `/customer`, `/suppliers`, `/os2`, `/os3`, `/crm`, `/admin` are 307
redirects in `next.config.mjs` to their canonical routes.

---

## 3. The content model

To change public copy you edit data, not components:

- `src/content/legal.json` — the 8 legal documents, each `{ en: {html}, ar: {html} }`.
  Verified this audit: **all 8 slugs have both EN and AR**.
- `src/content/marketing.json` — `about`, `contact`, `faq`, `services`, `blog` HTML.
- `src/content/services.json` — service pages, with `{{LOC}}` / `{{LOC_THE}}`
  placeholders substituted per emirate by `ServiceDoc`.
- `src/content/blog.json` — 32 posts (`body_html`, meta, slug).
- CSS blobs — `legalCss.ts`, `marketingCss.json`, `servicesCss.ts` — scoped
  styles injected alongside each document.

Content is rendered with `dangerouslySetInnerHTML`. This is safe here because the
HTML is **first-party, build-time content** authored in this repo — never user
input. (User-supplied strings, e.g. the chat, are escaped before rendering; see §7.)

---

## 4. Shared chrome

One header and one footer render on every public page, so navigation can't drift.

**`SiteHeader` (52 lines)** — logo → `/`; nav = How it works (`/#how`), Why
anonymous (`/#why`), For suppliers (`/portal`), Blog (`/blog`); `LangSwitch`;
Log in (`/me`); "Get quotes" CTA (`/me`). `MobileNav` (113 lines, focus-trapped,
Escape-to-close, scroll-locked) reuses the exact same nav array — it cannot fall
out of sync with the desktop header.

**`SiteFooter` (82 lines)** — three link columns, all resolving to real routes:
- **Company:** `/about`, `/contact`, `/faq`, `/services`
- **Legal:** `/terms`, `/privacy`, `/cookie-policy`, `/refund-policy`
- **More:** `/supplier-agreement`, `/acceptable-use`, `/disclaimer`, `/complaints`
- **Social:** Instagram `official.quotesdone`, LinkedIn `company/quotesdone`,
  X `QuotesdoneUAE`, Facebook `quotesdone.UAE`
- Copyright: "QuotesDone Technologies · Dubai DET E-Trader Licence No. 1633275"

All 12 footer links + 4 socials verified to resolve. `LangSwitch` (20 lines)
toggles locale preserving the current path.

---

## 5. Landing sections

`Hero` (109) · `HowItWorks` (45) · `WhyAnonymous` (54) · `Categories` (52) ·
`CtaBand` (39). All copy comes from i18n messages (not content JSON); all CTAs
point to `/me` and `/portal` (both valid). `Categories` normalizes `·`-delimited
tag strings via its `toTags` helper. No dead code.

---

## 6. Content renderers

Three renderers share a thin shell (`SiteHeader` → inject content → `SiteFooter`)
but each carries genuinely different logic, and all three delegate their SEO to
one shared helper (`src/lib/seo.ts` — `buildMeta` + `textFromHtml`), so the shell
is the only overlap:

- **`LegalDoc` (31)** — one `legalCss` blob + `.legalx`/`.docwrap` wrappers; `metaFor()`.
- **`MarketingDoc` (29)** — per-slug CSS from `marketingCss`; `mkMeta()`.
- **`ServiceDoc` (64)** — parses `{service}-in-{emirate}`, substitutes location
  placeholders, rewrites internal links for `/ar` (`arLinks()`), and generates
  static params (`svcParams()`); `svcMeta()`.
- **`BlogPost` (106)** — renders `blog.json` posts, breadcrumb + CTA aside → `/me`,
  English-only with an AR notice.
- **`FaqInner` (32, client)** — renders FAQ HTML + a live client-side search filter.
- **`ContactInner` (31, client)** — renders the contact HTML and wires the form
  to the `contact_submit` edge function using the **public** Supabase anon key.

_Optional future consolidation:_ the 3-renderer shell could be unified behind one
`<Doc>` component, but they diverge in CSS/wrapper handling and `ServiceDoc` adds
substantial templating; the shared SEO logic is already centralized, so the
remaining overlap is small and unifying it would put 17 legal+marketing routes at
risk for a cosmetic gain. Left as-is deliberately.

---

## 7. Widgets (layout-level)

- **`NodeField` (162)** — the signature animated background (canvas 2D "field of
  anonymous points of light"). `aria-hidden`, gated on `prefers-reduced-motion`.
  See §9 for this chapter's mobile-performance rewrite.
- **`CookieConsent` (47)** — `localStorage`-gated banner, "Accept all" /
  "Essential only", links `/cookie-policy`; hidden inside the OS console.
- **`ChatWidget` (126)** — the AI assistant. Posts to the `site_assistant` edge
  function with the public anon key; escapes all model output before rendering
  and linkifies internal paths, emails, and URLs (each wrapped in `<bdi>` so links
  stay readable inside RTL Arabic).

---

## 8. Backend dependencies

Only two edge functions serve the public site. Both were **byte-verified
production == repo** this audit:

| Function | Called by | Purpose | Verify |
|---|---|---|---|
| `contact_submit` | `ContactInner` | receives contact-form submissions | prod == repo ✓ |
| `site_assistant` | `ChatWidget` | AI answers about how QuotesDone works | prod == repo ✓ |

The anon key embedded in these client components is the **publishable** Supabase
anon key — it is designed to be public and is not a secret.

**SEO infrastructure:** `sitemap.xml` and `robots.txt` are Next route handlers;
each public page sets `metadata` via the shared `seo.ts` helper.

---

## 9. Changes made this chapter

**1. Mobile background jank — fixed (`NodeField`).**
The animation stuttered on phones. Two per-frame operations were the cause: a
full-surface `destination-in` composite (`fillRect` over the whole canvas, which
reads back and re-blends every pixel each frame) and an O(n²) "constellation"
line pass. On phones both are now dropped entirely — the radial light falloff is
instead **baked into each dot's alpha** (O(n), not O(pixels)), the loop runs at
~24fps, pointer-parallax is disabled (phones have no hover), and resize fires
**only on a width change** so the mobile address bar collapsing mid-scroll can no
longer re-initialize the canvas. The desktop path is byte-unchanged.

**2. Stale portal routes — fixed (`site_assistant` + `ChatWidget`).**
The AI assistant told customers to "post a job at `/app`" and suppliers to
"register at `/suppliers`" — both are now only 307 redirects. Corrected the
assistant's facts to the canonical `/me` and `/portal`, and updated the
ChatWidget linkifier to recognize `/me` and `/portal` (it previously linkified
the retired paths). `site_assistant` was redeployed and re-verified prod == repo.

---

## 10. Audit findings

The public site was rebuilt clean in the design-system chapter and holds up:

- **EN/AR parity:** all 8 legal docs and all marketing pages present in both locales.
- **No dead code:** zero `console.log`, `TODO`, `FIXME`, or commented-out blocks.
- **No dead components:** every `src/components/*.tsx` is imported and used.
- **No orphan content:** every JSON/CSS content blob is imported.
- **SEO centralized:** `buildMeta`/`textFromHtml` live once in `seo.ts`, shared by
  all renderers — not duplicated.
- **All links resolve:** every header, footer, nav, and CTA target maps to a real
  route (or an intentional `next.config` redirect).

Nothing dead or duplicated remained to delete — the only fixes needed were the
two above.

---

## 11. Verification & sync (live-verified 2026-07-22)

Everything below was checked against the running production site and the live
backend, not just the source.

**Vercel deploy — live.** The shipped bundle (`layout-f15ce9b8…js`, fresh hash)
was fetched from production and fingerprinted: it contains the new ChatWidget
linkify (`contact|me|portal`), the old one (`contact|app|suppliers`) is gone, and
the NodeField mobile branch is present (`Math.hypot` per-dot falloff — which never
existed in the old code — plus the `innerWidth<760` gate). Both fixes were one
atomic commit built together, so commit `9bb445f` is fully live including the
mobile background rewrite. (Vercel has no usable MCP/CLI in this environment; the
bundle fingerprint is a stronger check than a deploy-status API — it inspects the
actual served artifact.)

**Every public route renders.** A live sweep of the sitemap (444 URLs) plus each
hand-checked route returned HTTP 200: landing, all 8 legal pages, the 4 marketing
pages, `/blog` + posts, `/services` + service pages, the Arabic twins,
`/sitemap.xml`, `/robots.txt`. Legacy paths (`/app`, `/customer`, `/suppliers`,
`/os2`) correctly redirect. **No console errors** on the pages loaded (landing, FAQ).

**Locale routing — correct (not a bug).** During testing, English URLs appeared to
redirect to their `/ar/` twins; this was a stale `NEXT_LOCALE=ar` cookie in the test
browser from earlier Arabic QA. With an English preference every English URL serves
200 direct. This is standard next-intl cookie-based locale routing.

**`site_assistant` — end-to-end live.** Called the function the way the ChatWidget
does (POST with the public anon key). It returned 200 and replied *"To post a job…
go to /me… To register as a supplier: go to /portal…"* — references `/me` and
`/portal`, and does **not** reference the retired `/app` or `/suppliers`. The route
fix is effective in real production responses.

**Supabase (via MCP).** Project `htdblwldjkcgjvmqkbeh` is `ACTIVE_HEALTHY`
(Postgres 17.6). Both public-site functions were byte-verified prod == repo via the
CLI. Advisor scan: **zero ERROR/CRITICAL** on either axis — security 210 notices
(193 INFO, 17 WARN), performance all INFO except one WARN (a duplicate index on
`supplier_capabilities`). Every advisory is backend/DB (RLS-no-policy, mutable
function `search_path`, security-definer grants, unused indexes) and pre-existing;
the website work touched no schema, RLS, or grants, so it introduced none. The
retired customer-pages table shows only as an archived `_legacy_customer_pages_*`
(no primary key, INFO) — confirming public content is served from in-bundle JSON,
not the database.

**GitHub.** Verified via the host git CLI: code `9bb445f` and docs `e1f24a9` pushed,
`main == origin/main`, clean tree. (The GitHub MCP requires auth not completable in
this session; the host CLI is authoritative.)

**Sentry.** Org `quotesdone` exists but has **no project wired**, and an org-level
unresolved-issue search returned zero. No runtime errors surfaced — but note that
front-end error monitoring is not actually connected. Wiring a Sentry (or
equivalent) browser SDK into the Next.js app is a worthwhile future improvement so
real user-facing errors become visible; it is not a defect in the site itself.

**The one thing not verifiable from here:** real mobile-GPU smoothness. This
browser window won't drop below ~1440px, and desktop retina hardware wouldn't
reproduce a phone GPU's load regardless (the old per-frame composite readback was
expensive specifically on mobile silicon). The mobile code is confirmed deployed and
correct; the definitive smoothness check is scrolling quotesdone.com on a real phone.
