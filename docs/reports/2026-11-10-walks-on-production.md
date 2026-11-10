# Walks on production after #1880 and #1881, 10 Nov 2026 (afternoon)

Seat: customer_support. Founder priorities: supplier registration 100%, customer sign-up 100%, WhatsApp perfect.
Every run used ZZ DEMO / QD Demo identities on reserved domains, its own run tag and rehearsal window, and was torn down.
Branch `customer_support-walks-10-nov`. "Measured" means run here today; times are database UTC.

## Preconditions (measured)

- #1881's edge deploy had finished: supplier_api v420 at 14:14:58Z, supplier_catalog_ingest v335 at 14:15:05Z,
  supplier_portal v363 at 14:15:21Z (all after 14:12Z). `verify_deploy_parity.mjs` on supplier_api, supplier_portal,
  supplier_catalog_ingest, wa_inbound, customer_portal, customer_api and sales_engineer: 7 MATCH, 0 STALE.
- Vercel production deployment `dpl_C7V7GJaXR3CQeNfNWrTa3rVz4j4o` READY on main `6f9ebbd9b` (Merge #1881).
- No open rehearsal window at the start. Two other sessions' windows opened later (`qd_run:1cb58b6d`, `qd_run:464fa52e`,
  cap USD 4); they are not mine and were not touched.

## Results per walk

| Walk | Before (10 Nov morning) | After (this run) | AI spend (USD) | Leftovers |
|---|---|---|---|---|
| 1. journey f, customer EN/AR desktop+mobile and supplier EN desktop+mobile (`run.mjs --journey f`, `QD_E2E_DEADLINE_MS=4500000`) | 2 of 10 Arabic mobile destinations reached before the 20-min limit; 14 FAIL on a new empty mobile account | **139 PASS, 0 FAIL, 0 SKIP, complete** (tag c47515e7, 1,909 s). Arabic mobile: 10/10 destinations, 23 steps, no console errors. First attempt (e7ce0514) failed at fixture setup, see F1 | 0.00 | 0 / 0 |
| 2a. supplier_registration_error_paths | — | **21/21 PASS** (2971f745) | 0.00 | 0 |
| 2b. supplier_registration_walk (en/ar x desktop/mobile) | services confirm: 2 statement timeouts + one 40.4 s; agreement not landed after 60 s in 1 of 13 | **104/104 PASS** (52e4912a). Every confirm HTTP 200; supplier_api 148 POSTs during the walk: max 6.1 s, p95 1.57 s, 0 HTTP 5xx, 0 over 8 s. Signed agreement present in 4/4 matrices and on all 3 journey-f fixtures (7/7) | 0.0060 | 0 |
| 2c. customer_signup_walk (real e-mailed code via the Resend sink) | — | **29 PASS, 0 FAIL, 1 NOT REAL** (the SMS code: a fixture number is refused before Twilio, by design) (c885b1e8) | 0.1775 | 0 |
| 2d. supplier_full_walk, mobile, production | — | **22 PASS, 8 FAIL lines** (7 distinct; c is reported twice) (5f11150a). Causes F2-F6 | 0.0243 | 0 |
| 2d'. supplier_full_walk, mobile, local `next build && next start` of the branch | — | run 1 (3aa19ee5): 24 PASS / 6 FAIL; run 2 (86372307, Node-routed, e/f fixed): 25 / 5; **run 3 (84deb06e, Node-routed): 27 PASS / 2 FAIL**: a, b, c, d, f and g-l pass; e fails (F5, product, open); the Stripe console error is environment (F6b) | 0.0056 + 0.0057 + 0.0197 | 0 / 0 / 0 |
| 3. wa_exchange_real | — | **incomplete**, see F7 (fbc40fbd killed by the harness wall; f5d32825 stopped by its cap) | 0.5526 + 0.4694 = **1.0220** | 0 |
| 4. general matching on live | — | answers; see "Matching" | 0.00 | — |

Dispatch: journey f "nothing the run caused was dispatched" PASS (email/suppressed 4, whatsapp/suppressed 4); the
registration walk's approval notices suppressed in all 4 matrices; the sign-up walk 0 of 2 notices live; and across
all of today's tags, 0 notifications to an @example.invalid or @resend.dev address in sent/queued/pending since 14:15Z.

## Failures, root cause and fix

**F1. Journey f fixture: `services_save_rewrite` HTTP 500 `services_rewrite_write_failed` (run e7ce0514).**
postgres_logs at 14:21:25Z: "canceling statement due to statement timeout". PostgREST's roles stop at 8 s
(`statement_timeout=8s`, `lock_timeout=8s`). In the same seconds another session's probe deleted every demo lead (28)
inside one transaction for 33,962 ms and rolled back ("PROBE OK: refused a purge reaching a real inquiry ... removes
28 demo lead(s)"). The upsert's foreign-key check on its new lead waited on that lock. Not a product defect. Fix
(harness, `861f3e36e`): the fixture's two services calls, idempotent SETs already retried on a gateway blip, also
retry a lock or statement timeout; any other 500 still fails. Re-run c47515e7: 139/139.

**F2. Full walk b, quote by PDF upload: held, and no way to release it on screen (product).** The quote was a draft
at 15:19:13Z and the sales engineer's hold (installation_included) opened at 15:19:34Z. QuotationsTab read the list
once, and SpecHoldPanel renders only where the list says `on_hold`. So the card read "Held — not sent yet" with no
"Fill in the missing details" until the supplier reloaded. Fix (sales_engineer, `5928e6e06`): while a live draft has
no hold yet, the list is read again every 5 s, at most 24 times per visit. Harness (`9346ea574`): settle() waits for
the hold row before it presses. Proved on a local build of the branch: b PASS (read 11,730, held, released, submitted).
Vercel deploys it on merge.

**F3. Full walk c, two-option PDF: the total never fills (environment).** quote_extract answered HTTP 200 at 46 s
(production) and 31 s (local), and the page received nothing. Production console: "blocked by CORS policy: No
'Access-Control-Allow-Origin' header". Locally, `waitForResponse` timed out at 300 s while the edge log shows the 200.
This container cuts a browser connection at about 30 s (the same fault was recorded 27 Oct at 30.2 s); Node and curl
get the 200. b's read took 23 s and passed. Harness (`c0d9903e6`): steps b, c and d now record what the browser was
told. A new opt-in `QD_ROUTE_FUNCTIONS_VIA_NODE=1` routes the page's function calls through Node so a run here judges
the product. Re-run with it (local run 3): **c PASS**. The read answered 200 with 2 options, the split notice was
shown, and two quotes were created with option numbers 1 and 2. In local run 2 the same read came back **HTTP 546
WORKER_RESOURCE_LIMIT** once, at 16:14:16Z, together with another in-flight supplier_api request on the same worker,
while another session's 189 KB document reads were going through. supplier_api had 0 responses with status 546 all
day before that minute and 3 in it. Not changed: the read takes 31-46 s for a two-option PDF, which is slow even
where nothing cuts it. Seen in passing, not investigated: `embed_ml` answered 546 to 406 of 6,769 requests in the
15:00Z hour.

**F4. Full walk d, "on hold" not on screen (environment).** The database had the held draft and its hold. Local run:
PASS, `submit_quote` answered `spec_hold` and the text was shown. Same container cut as F3.

**F5. Full walk e, refresh before reveal: a harness fault, then a product defect (OPEN, sales_engineer).**
(1) Harness: the walk changed the total to 10,900 and left the lines at 450 x 20 + 120 x 18 = 11,160, so the review's
rule 4 (line amounts add up to the total) held it, correctly. Fixed (`be0dfe6ed`): the line states the new price too
(120 x 15, total 10,800). (2) Product, measured in local run 3: the refresh still comes back `quote_review_changes`,
issues `["installation_included"]`. In scenario a the supplier answered "Is installation included? yes" in the
hold panel (`spec_fill`), and the quote was sent. A refresh resubmits the quote form, which has no installation
field, and `submit_quote` builds the review from the request body plus `quote_reviews.working`, not from the answers
the hold panel stored. So the question he already answered is asked again, as a review hold with no spec-hold panel:
the card reads "Held — not sent yet" with nothing on it to answer. **Not fixed here**: the fix (carry the confirmed
`spec_fill` answers into a refresh's review) is in the sales engineer's review inputs, needs its own Deno tests, and
cannot be deployed from this session.

**F6. Full walk f, withdraw (harness).** Withdraw asks for a second press ("Confirm withdraw") since the 19 Oct QA
walk. The walk pressed only the first "Withdraw", and on the newest job's card, not the PDF job it then checks.
Fix (harness, `be0dfe6ed`): the PDF job's own card, both presses. Local runs 2 and 3: f PASS (status withdrawn).

**F6b. Full walk "settings: no console errors" (environment).** `merchant-ui-api.stripe.com` ERR_TUNNEL_CONNECTION_FAILED:
the cloud proxy refuses Stripe here (also in the morning report). Checkout itself opened in TEST mode (step i PASS).

**F7. wa_exchange_real did not complete (harness, then the cap).** Run fbc40fbd (15:17-15:37Z): 120 model calls,
every one ok, USD 0.5526. The parent's fixed 20-minute spawn wall killed it during the file turns, and the driver
prints its RESULT only at the end, so every verdict was lost. Fix (`c0d9903e6`): the wall is 35 min
(`QD_WA_DRIVER_MIN` overrides), and the driver writes its finished turns to a partial file every 5 s. Re-run
f5d32825 was capped at USD 0.44 to keep the step near USD 1 in total. It spent USD 0.4694 (calls in flight overshoot
the cap), and from 15:56Z the gate refused 119 calls (`rehearsal_cap`). Measured before the cap: every parity message
answered (`unanswered_including_parity=0`), 1 mismatch (the lean classifier's first answer was unparseable and it fell back); the forged-signature
control 0 rows; supplier question, "Hi", Arabic fee answer and a stranger's "Hi" answered correctly in 28-43 s; the
document read by code; the bad image and bad PDF refused. From "fee" onward every reply is the outage text
(`circuit_open` = this run's cap), so fee, top-3, identity, reveal, the 10-turn memory, image and voice were **not
verified today**. WhatsApp spend is USD 1.022, USD 0.022 over the USD 1 limit. Replies took p50 32 s and p95 43 s,
and "I want to speak to a person" took 62 s on the old path and 79 s on the lean one.

## Matching on live (measured, read-only)

- `fn_match_capability` carries the adjacency path; 43 adjacent-trade pairs and 424 approved aliases are live.
- The phrases the design audit found resolving to nothing now resolve: "PVC decorative panels" -> wallpaper.wall_panels,
  "vinyl wrap" -> wallpaper.film_wrap, "roller shades" -> curtains_blinds.roller_blinds, "forklift on rent" ->
  material_handling.forklifts_sale_rent, "sworn translation" -> translation_interpretation.certified_legal_translation,
  "workers transportation" -> staff_transport.labour_transport.
- A fit-out request naming gypsum.false_ceiling reached the gypsum+painting supplier 126512 "through the named
  service's trade" (the new path b) and the fit-out supplier 155966 through implication.
- Gap: the 25 QD Demo corpus suppliers hold no stated services, so any request naming a service (aluminium windows,
  epoxy) routes to none of them, and the sign-up walk's posted aluminium request matched 0 suppliers. That is the
  services gate working on a corpus with no services. The corpus (demo_factory --corpus) should state services.

## Teardown

Every run: 0 leftovers (journey f "zero leftovers" PASS; the walks' own teardown totals 0). Checked again afterwards
for all nine production-walk tags: 0 leads, 0 customers, 0 auth users, 0 fixture WhatsApp rows; and the three local-build
runs (3aa19ee5, 86372307, 84deb06e): walk teardown 0 and 0 leads left.

The stale sweep: `fafbabb3` was no longer found at 14:20Z. The 11:23Z sweep took 1,904 s for 7 tags, and `fafbabb3`
removed 0 rows. Fix (`861f3e36e`): a refused auth-user delete is reported instead of counted as 0. A run the sweep can
remove nothing from is marked once (an already-ended window at its own last `ended_at`, so it hides nothing) and is
skipped after that.

## AI spend

USD 1.2608 in total, read from `ai_cost_log` by run tag: WhatsApp 1.0220 (fbc40fbd 0.5526, f5d32825 0.4694), sign-up 0.1775,
full walks 0.0553 (production 0.0243, local 0.0056 + 0.0057 + 0.0197), registration walk 0.0060, journey f and the error
paths 0.00.

## Commits on `customer_support-walks-10-nov`

`861f3e36e` stale sweep and fixture lock-wait retry; `5928e6e06` (sales_engineer) the Quotations list re-reads a draft
until its hold arrives; `9346ea574` settle() waits for the hold row; `c0d9903e6` WhatsApp driver wall and partial
results, full-walk answer capture; `be0dfe6ed` full walk e/f and the opt-in Node route; this report, its evidence in
`docs/reports/walks-2026-11-10/`, and the memory update on the 30 s browser cut.

## Still owed

- **F5, product:** a refresh re-asks a detail the supplier answered in the hold panel and gives him no field for it
  (sales_engineer).
- wa_exchange_real complete: fee, top-3, identity, reveal, 10-turn memory, image and voice. About USD 0.6 for one full
  run with the 35-minute wall. Not run again, because the USD 1 limit was already reached. WhatsApp replies take
  p50 32 s, p95 43 s, and up to 79 s for "speak to a person".
- The portal fix (F2) reaches production when the branch merges and Vercel deploys it; until then, on production, a
  PDF quote's hold appears only after a reload.
- The QD Demo corpus states no services, so general matching cannot route a service-naming demo request to it.
