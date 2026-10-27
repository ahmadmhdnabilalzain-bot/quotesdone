# Supplier registration, end to end in a real browser on quotesdone.com — 27 Oct 2026

**Assigned:** `it_engineer` (the walk) · `sales_engineer` (the supplier portal, his surface).
**Asked by the founder:** "is the browser test for the supplier register journey done?"

**Answer:** the walk ran on the live site, on production at commit `107120ce` (#1654). That deploy is READY and includes #1642. Coverage was en and ar, on desktop (1440×900) and mobile (390×844), with ZZ DEMO identities only.

- **6 of 7 steps pass in all four modes.**
- **Ruling 1230 passes in all four modes.** Each supplier reached `approved`, with a signed certificate, mobile and e-mail verified, the acceptance hashed, and all 7 emirates stored.
- **Step 6 (the Services confirm) fails on screen in all four.** The save itself lands every time.

The cause is found and fixed in **#1668**, which is open for review and not merged.

## Per-step result (final run, production, one process per mode)

| # | founder's step | en / desktop | en / mobile | ar / desktop | ar / mobile |
|---|---|---|---|---|---|
| 1 | supplier landing page → sign-up form | PASS 5.8 s | PASS 5.3 s | PASS 5.0 s | PASS 6.1 s |
| 2 | e-mail verification | PASS 12.5 s | PASS 10.8 s | PASS 12.0 s | PASS 11.7 s |
| 3 | company details + trade; emirates (no restriction) | PASS 15.4 s | PASS 16.0 s | PASS 14.2 s | PASS 15.8 s |
| 4 | company profile upload completes | PASS 31.3 s | PASS 35.0 s | PASS 34.1 s | PASS 32.5 s |
| 5 | catalogue upload completes | PASS 16.2 s | PASS 18.5 s | PASS 16.7 s | PASS 15.9 s |
| 6 | page set up ("Set up my page" → Services confirm) | **FAIL** 138.7 s | **FAIL** 137.0 s | **FAIL** 77.1 s | **FAIL** 78.3 s |
| 7 | dashboard loads; "Inquiries received" visible and settles | PASS 3.2 s | PASS 4.1 s | PASS 3.0 s | PASS 3.3 s |
| — | ruling 1230: registration completes 100% on ZZ DEMO | PASS | PASS | PASS | PASS |

Run tags: `568f8530`, `8f7a06b9`, `8e4b29e6` and `d7f57502`. Every assertion and timing is in `summary_<mode>.json`.

### What each step proves

1. `/supplier` shows "Quote on real UAE jobs. Keep 100% of what you win." In Arabic it shows "قدّموا عروضكم…". Its button opens `/portal`, where the form reads "Register as a supplier". Suppliers are always English (ruling 1008), so the ar leg lands on the Arabic page and registers in English.
2. The real form refuses the reserved test domain **before any code is sent**. The code is then seeded hashed and verified through the real `login_otp` endpoint, which is the harness's existing OTP path (`docs/e2e.md` §1). Nothing in production code is bypassed.
3. "Register your company" takes the name and the trade (`aluminium`, stored in `leads.sector`). "Emirates you serve" is marked **Optional** and offers **All emirates**. Ticking it ticks all 8 boxes and stores the 7 emirates. **No emirate restriction**, consistent with the founder's ruling that every UAE supplier covers the whole country.
4. Licence, company profile and catalogue are picked on the registration form, then Submit.
   - **The upload completes.** The Submit ends in 16–18 s.
   - The profile is stored with its object in `supplier-docs`.
   - The licence is read in about 15 s.
   - Before #1642 this ended in "Something went wrong saving your profile" with nothing stored. That was reproduced twice on the live site today.
5. The catalogue is stored with its object in `supplier-docs`.
6. **No "Set up my page" control exists** in the portal source or on the live site. The step that publishes what a supplier offers is the Services tab:
   - The supplier writes the services in its own words.
   - The sales engineer rewrites them ("Sales engineer's version").
   - The supplier presses "Confirm my services".

   The rewrite works. The confirm shows **"Could not save your services."** although the server saved it: a `supplier_capability_confirmation` row exists every time. See the defects below.
7. The dashboard tabs (Services, Inquiries received, Quotations submitted, Messages, Documents, Insights) all settle in under 5 s. "Inquiries received" opens. There are no page errors.

## Defects found

| # | defect | evidence | fix |
|---|---|---|---|
| 1 | Profile and catalogue upload hung or failed (`SB().storage` undefined) | Pre-fix runs `13bebce9` and `829ab868`: Submit ended in "Something went wrong saving your profile", profile none, catalogue none | #1642 (merged `a13d9cd5`). After it, steps 4 and 5 PASS in all four modes |
| 2 | The Services confirm was cut off by the portal at 20 s | The save answered HTTP 200 after 36,959 ms; the portal had aborted at 20 s and said "Could not save your services." | #1654 (merged `107120ce`): the reasoning calls wait 90 s. Regression check `scripts/checks/a_services_save_that_reasons_is_not_cut_off_by_the_portal.test.mjs` |
| 3 | The Services confirm keeps the supplier waiting 37–67 s, because it reads each own word by reasoning before it answers | See "Step 6" below | **#1668** (open, **not merged**, needs review + `deploy_functions … supplier_api`). Regression tests in `supabase/functions/_shared/supplier_services_save.test.ts`: red on old code, 10/10 on the fix |

### Step 6, measured

- **Server side.** `function_edge_logs` shows every browser save answered **HTTP 200** (42,610 ms; 42,675 ms; 67,097 ms…), with the capability confirmed.
- **Browser side.** Chromium in this cloud container gave up at **30.2–31.8 s** on every leg. The error was `net::ERR_FAILED`, with CDP reporting `corsError: MissingAllowOriginHeader` on a connection to the container's egress proxy at `127.0.0.1`. The page showed "Could not save your services."
- **Disabling HTTP/2 did not change it.** The failure was at 30.2 s with `--disable-http2`.
- **The same request from other clients gets the 200 with the right CORS header:**
  - Node fetch, without `apikey` (the portal's header set): 44.1 s
  - Node fetch with Chrome's exact User-Agent: 46.6 s
  - curl through the same proxy with Chrome's User-Agent: 57.9 s
  - A bare `fetch` from a quotesdone.com page in Chromium, with no portal code at all, fails at 31.4 s.

**Conclusion.** The 30 s cut belongs to this container's browser network path, not to production. That cannot be verified here for a real supplier's browser. The real exposure is the 37–67 s wait itself: any intermediary that gives up in under a minute (a corporate proxy, a mobile carrier) produces the same false "Could not save". #1668 answers the confirm at once when it already names a trade and reads the words after the response. **Step 6 cannot turn green until #1668 is reviewed, merged and `supplier_api` deployed.** Re-run with:

```
node scripts/e2e/supplier_registration_walk.mjs --fresh --lang en,ar --vp desktop,mobile --cap-usd 3 --summary <file> --shots <dir>
```

### Other observations (not failures)

- `license_extract`'s model call logs `ok=false` on every licence (2 calls per supplier, around 3 s each). The licence is still read by code: number, expiry 14 Mar 2028 and name all match, and approval passes. Worth a look by `sales_engineer`.
- Both pre-fix runs showed that `file_scan` leftovers (`supplier_api.license`) were not removed by teardown. Those rows were removed by id at the time. #1642's teardown fix now handles them: 0 orphan rows after the final runs.

## Harness (S26's registration piece, extended; no new harness)

`scripts/e2e/supplier_registration_walk.mjs --fresh` walks a supplier who was **not** invited, through the founder's seven steps, timed per step (`--summary`). The invited legs are unchanged.

- In this PR, step 6 now records the browser's own failure reason (`requestfailed`) and the CDP network view, so a failure names its cause instead of "no answer".
- The licence step is timed by its own request: about 1.7 s on the client to render the PDF, about 12 s on the server.
- `scripts/e2e/browser.mjs` accepts `QD_CHROMIUM_ARGS` for diagnostic switches.
- The rehearsal window uses `--cap-usd 3`.

## Teardown, spend, switches (read back from production after the last run)

- **Teardown.** The harness `leftovers()` total is **0** across all 16 run tags of this session.
  - Rows carrying those tags in `assistant_logs`, `sales_decision_log`, `support_reply_readability` and `supplier_lead_intake`: **0**
  - ZZ DEMO leads named by those tags: **0**
  - Auth users: **0**
  - Orphan supplier `file_scan` rows since 15:00Z: **0**
  - Orphan `taxonomy_trade_proposal` rows: **0**
  - Open rehearsal windows: **0**
  - Two runs were cut off before their own teardown (a 1000 s shell cap, and one stopped diagnostic). Each was torn down afterwards with the harness's own teardown by its exact tag, and verified at 0.
- **Spend.** 167 model calls, **AED 0.951 (USD 0.26)**, under the USD 3 cap. Two early runs (a preview attempt and a crashed browser) made no model calls.
- **Switches.** `invite_enabled = false` and `wa_supplier_invite_golive = false`, read back at the end.

## Screenshots

`screenshots/` holds 40 images: 10 per mode (landing, sign-up form, reserved-domain refusal, company + trade, all emirates, profile + catalogue picked, after Submit, sales engineer's rewrite, services confirm, inquiries received). They are downscaled JPEGs, 2.1 MB in total. Names are `<lang>_<viewport>_<nn>_<step>.jpg`. The full-size PNGs from the run were not kept.
