---
name: an-intercepted-browser-cannot-prove-what-a-real-browser-allows
description: "13 Nov 2026: 'Download my data (PDF)' passed two signed-in walks on the live site, the author's browser proof and three reviews, and had never worked in a real browser: the page sent an apikey header the function's preflight did not allow. Every one of those browser runs used Playwright request interception, which is not held to the preflight's header list. A browser proof made through interception proves the server, not the browser's own rules; and a preflight is proven by what it allows, not by its status."
metadata:
  type: feedback
  modified: 2026-11-13
---

**What happened (13 Nov 2026, ledger 1679).** The founder pressed "Download my data" on his own iPhone, on
quotesdone.ae, hours after the session had told him the PDF door was live and proven. He got "Something went wrong.
Please try again." The edge log for his press shows two `OPTIONS 200` for `my_data_pdf` and no `POST`.

**Cause.** `src/components/portal/PrivacyControls.tsx` called the function with the headers `apikey`, `Authorization`
and `Content-Type`. `supabase/functions/my_data_pdf/door.ts` answered the preflight with
`Access-Control-Allow-Headers: authorization, content-type`. A browser sends the request only if the preflight allows
every header on it. It had never worked in any real browser, on either domain.

**Why nothing caught it.**
- The two signed-in walks on the live site, and the author's own browser proof, drove Playwright with **request
  interception on** (`context.route(..., route.continue({ headers }))`, which the test factory uses to add the run tag
  that marks demo traffic). A request continued through interception is not held to the preflight's header list. The
  PDF arrived, so each run reported a pass. The certification harness tags its traffic the same way.
- Three independent reviews, and the session itself with `curl`, checked that the preflight **answered 200**. None
  compared the list it returned with the headers the page sends.
- The function's own test asserted only that the list contained `authorization`.

**How to apply.**
- A claim that something works "in a browser" is made in a browser context with **no interception at all** for the
  step that is being proven: no `route`, no extra-headers shim. If signing in needs the run tag, sign in in one
  context and carry the session into a clean one (`storageState`). Prove the clean context enforces the rule by
  showing a deliberately disallowed header is blocked there.
- A preflight is checked by its **content**: every header the page sends is in `Access-Control-Allow-Headers`, the
  origin is echoed for every domain the site is served on (quotesdone.com and quotesdone.ae, with www), and the
  response the page must read carries the origin header too. The status alone proves nothing.
- The mechanical check now exists: `scripts/checks/every_header_the_site_sends_a_function_is_allowed_by_its_preflight.test.mjs`
  reads both sides for every function the site calls through `fnUrl('<name>')` with headers written inline. Its
  blind spots, said in the file: calls whose headers come through a variable or a spread, and a function whose
  allow-list comes from a shared helper.
- Before telling the founder a screen is proven, ask which browser rules the test tool switched off, and say which
  real device has not been tried. "Real iPhone Safari not driven by us" was said; "our browser runs skip the
  preflight rule" was not known, and is the kind of thing to find out first.

**What the harness's interception hides, and what it does not (measured on the third walk, 13 Nov 2026).** The test
factory intercepts only calls to the Supabase host's `/functions/v1/*`, to add the run-tag headers. On those calls two
browser rules are not applied: the preflight's header list (the run-tag headers themselves are not in any allow-list,
and nobody noticed for that reason), and the browser's HTTP cache. Still enforced while intercepting: the site's
content-security policy, mixed-content blocking, and the cross-origin rules on every call that is NOT intercepted
(`/rest/v1`, which is why the JSON copy worked for the founder; `/auth/v1`; storage). Cookies are not in play: the
portal keeps its session token in the page.

**The proof that replaced the false one.** Six walks in fresh Chromium contexts with no route, no extra headers, no
service worker (sign-in included), on quotesdone.ae and quotesdone.com, phone size and desktop, supplier and
customer: every press shows `OPTIONS 200` then `POST 200 application/pdf`, ready in 2.9 to 3.4 s. Each context was
first shown to enforce the rule: a fetch with a header that is not allowed was blocked by the browser
(`HeaderDisallowedByPreflightResponse`), the same fetch without it reached the function. Playwright's own request
events never show a preflight; the browser's network log does.

**Left open by this, said plainly.** 25 edge functions allow only `authorization, content-type`. Every caller in the
website sends exactly those two today (the static check for inline headers, a reviewer's reading of the eight helper
callers, and a live preflight sweep of the 27 functions a browser calls all agree). A new caller that adds `apikey`
or uses supabase-js `functions.invoke` (which sends `apikey` and `x-client-info`) to one of them fails the same way.

Related: [[nothing-is-done-until-a-browser-proved-it]], [[release-lessons-of-the-12-nov-fix-round]] (lesson 14: a guard
is not proven until someone tries to defeat it).
