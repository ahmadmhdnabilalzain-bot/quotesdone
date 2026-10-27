# Stage 2 rerun, 27 Oct 2026: the 33 failures of run 0a717394

Seat: it_engineer. Founder ledger 1121 and 1261, with the registration part of 1230. AI on for every seat (ruling 1260).
Branch `it_engineer/stage2-fixes-27-oct`, draft PR __PR__.

## What was measured before any change

- **The run's date.** Run `0a717394` is the 19 Oct run, not a 26 Oct run. `stage2_0a717394.log` and `scenario_log.json`
  carry 2026-10-19 timestamps. It ran on the founder's laptop: its output path is `C:\Users\Opera\Desktop\...`.
- **The run's data is not kept.** The brief said the demo data was kept. `cleanup_0a717394.json` and production
  disagree: the run was cleaned, and the verification found only 3 `ai_cost_log` rows. On 27 Oct, measured on
  production: 0 leads, 0 customers and 0 `ai_cost_log` rows for `0a717394`. Nothing of `0a717394` was touched
  in this step.
- **The failure count.** There are 33 `FAIL` lines in `stage2_0a717394.log`. They are listed one by one below.
- **Work already done elsewhere.** Six of the 33 were fixed on 19 Oct by PRs that are already merged. Five more are
  in two open PRs. Both are listed and neither is duplicated here.

## Each failure: its class, its fix and the rerun result

Classes: **P** is a product defect, **H** a harness defect, **C** a cascade from an earlier failure in the same run,
**E** the environment.

| # | Scenario: what failed | Class | Cause (measured) | Fix | Rerun |
|---|---|---|---|---|---|
| 1 | S04 C9 waterproofing: intake held, `specs_unanswered: area` | H | The fact sheet answered the area key with the built-up size, not the area of the part being waterproofed | #1573 (merged 19 Oct) | not rerun (blocked, see Rerun) |
| 2-7 | S06 C2, C3, C5, C6, C7, C10: matched `[]` | H | The demo fixture stated services for only 3 trades. `fn_services_effective('{}', [trade], '{}')` is `{}`, so the services gate dropped every other supplier | #1576 (merged 19 Oct) | not rerun (blocked, see Rerun) |
| 8 | S09 comparison in Arabic: HTTP 504 | P | `customer_api compare_pdf` reasoned the Arabic lines one after another and hit the 150 s edge wall (504 at 150,269 ms) | **#1574, open, not merged.** Not duplicated | not rerun (blocked, see Rerun); the fix is in #1574 |
| 9 | S10 the Arabic customer reveals: quote HTTP 404 on electrical | C of 2-7 | The electrical supplier was never invited, so it could not quote | #1576 | not rerun (blocked, see Rerun) |
| 10 | S10 Arabic reveal receipt: 0 rows | C of 9 | No reveal, so no receipt | #1576 | not rerun (blocked, see Rerun) |
| 11 | S19 model route `intent_detection:openai/gpt-6-luna` | P | A gateway cache hit was served from a model the route does not allow | #1575 (merged 19 Oct) | not rerun (blocked, see Rerun) |
| 12-20 | S21 nine shapes: the profile's trades were not all proposed | H for 6, P for 3 | **Harness (6 shapes):** S21 asserted the row while the profile still said `reading`. Shapes `ded_old_text`, `det_text`, `det_png`, `abu_dhabi_added_jpg`, `sharjah_sedd_skewed` and `sharjah_sedd_bi_phone` read `proposed []`, and the same check counted `reading` as read. **Product (3 shapes, read to the end):** `scan_pdf` missed fire_fighting, `adgm_rotated90` missed landscaping and `ajman_lowdpi` missed aluminium and glazing | Harness: this branch (S21 waits for `readingSettled`; `docIsRead` refuses `reading`). Product: sales_engineer #1483 (merged 27 Oct, "profile reading fixes for the held-out misses") | not rerun (blocked, see Rerun). The harness fix is proved offline (`stage2_reading.test.mjs`, 5 pass) |
| 21 | S21 `lic_dubai_det_text`: the gate said `pending (documents_being_read)` | H | Same early read. The gate holds a supplier until the profile is read, then gates it again | This branch | not rerun (blocked, see Rerun). The harness fix is proved offline (`stage2_reading.test.mjs`, 5 pass) |
| 22 | S21 crashed with 23505 `leads_claimed_company_name_uidx` (zz demo dune plumbing llc) | H | After the profile was read, the second gate wrote the licence name back over the name S21 had released (`a_licence_name_becomes_the_company_name...sql`). The next Dune Plumbing shape then collided with it. Its Dropbox folder `ZZ DEMO Dune Plumbing LLC (147143)` is the only one without a release suffix | This branch: S21 waits for the reading to end, and gives back any name this run's own ZZ DEMO leads still hold before it registers the next shape | not rerun (blocked, see Rerun). The harness fix is proved offline (`stage2_reading.test.mjs`, 5 pass) |
| 23 | S22 `customer_api accept_terms`: 401 `UNAUTHORIZED_ASYMMETRIC_JWT` | H | The fixture's access token expired: the run went past 3,600 s | #1572 (merged 19 Oct) | not rerun (blocked, see Rerun) |
| 24, 25 | S26 inquiry box, EN + AR (`could not open New request`), and the browser `inquiry_box` row | H | `customerAr` was C1, who is registered in English. Once signed in, the registered language wins, so `/ar/me` rendered English and `طلب جديد` never appeared | **#1571, open (ledger 1250, other agent).** Not duplicated | not rerun (blocked, see Rerun); the fix is in #1571 |
| 26, 27 | S26 journey C1 desktop/mobile AR: terms step timed out | H | Same identity as 24 | #1571 | not rerun (blocked, see Rerun); the fix is in #1571 |
| 28, 29 | S26 journey C1 desktop/mobile EN: "no request of this customer has a quote on screen" | H | The step gave up after 20 s (the step took 22,480 ms). The screenshot taken straight after it (evidence `.../C1_journey_desktop_en/quotes_and_comparison_report.png`) shows the `Revealed · Aluminium · Dubai · 4 quotes` card: the list arrived late, it was not missing | This branch: the step waits 60 s and names any wait over 10 s as SLOW, with the time | not rerun (blocked, see Rerun). The harness change is proved offline (`browser_walk.test.mjs`, 6 pass) |
| 30, 31 | S26 journey C2 desktop/mobile AR: no quote on screen | C | C2's electrical request was never matched (2-7), so it had no quote. #1571 also moves the AR journey to the Arabic customer quoted in S10 | #1576 + #1571 | not rerun (blocked, see Rerun). The harness change is proved offline (`browser_walk.test.mjs`, 6 pass) |
| 32 | S26 supplier registration with licence upload: `{"lic":true,"prof":false}`, then no approval, no certificate, no notice | **P** | **No supplier could upload a company profile or catalogue from the portal from 19 Oct.** `uploadDirect` (#1496) calls `SB().storage.from('supplier-docs').uploadToSignedUrl`. `SB()` is `supaClient()`, which has built an auth-only client since 28 Sep, so `.storage` is undefined. The upload threw before sending anything, the Documents tab stayed on "Uploading…", and Save answered "Still needed to register: Company profile". Reproduced on production on 27 Oct with a ZZ DEMO supplier (walk `390dafcc`; the screenshots are in `.stage2_out`, not committed) | This branch: `src/lib/signedUpload.ts` sends the same signed-URL PUT that storage-js sends, by hand, and returns errors instead of throwing | **Reproduced on the live site** (walk `390dafcc`: `prof:false`, "Uploading…" never ends). **The fix was run against production**: a ZZ DEMO supplier (run `0bef79e2`) used `src/lib/signedUpload.ts` itself. `upload_url` returned 200, the signed PUT returned `{"error":null}`, `save_documents` returned 200 with `saved:["profile"]`, and `company_profile_doc_path` was set. The browser leg on a local build of this branch did not finish: the browser died mid-walk and another session closed the run's window (see Rerun) |
| 33 | S24 an Arabic customer receives Arabic, including `reveal_receipt`: 0 | C of 9-10 | No Arabic reveal took place | #1576 | not rerun (blocked, see Rerun) |

**Totals by class:**

| Class | Count | Failures |
|---|---:|---|
| Product (P) | 5 | S09, S19, three S21 trade misses |
| Product, found in this step | 1 | supplier profile upload, #32 |
| Harness (H) | 21 | |
| Cascade (C) | 6 | |
| Environment (E) | 0 | |

None of the 33 was caused by the environment. In the cloud container one thing differs: `cdn.jsdelivr.net` is refused by the
egress proxy. It is used only by the DWG check (a known main failure) and the browser OCR worker, and it did not affect
any step measured here.

## Fixes on this branch

1. `scripts/e2e/stage2.mjs` and `scripts/e2e/stage2_reading.mjs` (S21):
   - S21 waits up to 300 s for `readingSettled`: no document is `reading`, `retry` or `queued`, and there is no
     `documents_being_read` hold.
   - `docIsRead` refuses `reading`.
   - Before each shape, S21 releases any name this run's own ZZ DEMO leads still hold. The release is scoped to the
     run's lead ids, `@example.invalid` and `ZZ DEMO%`.
   - Test: `scripts/e2e/stage2_reading.test.mjs` (5 pass).
2. `src/lib/signedUpload.ts` and `src/components/portal/SupplierPortal.tsx`: the profile and catalogue upload.
   - Test: `scripts/checks/a_supplier_document_upload_never_calls_a_client_the_portal_does_not_build.test.mjs`. It
     fails 2 of 4 on the old file and passes 4 of 4 on the fix.
3. `scripts/e2e/browser_walk.mjs` (S26 quotes step): the step waits 60 s and reports a slow list as SLOW.
   - Test: `scripts/e2e/browser_walk.test.mjs` (6 pass).

No SQL changed. No MANIFEST line is needed.

## Rerun

**The full stage-2 rerun was NOT run, because running it would not have been safe.** These were the conditions,
measured before and during the step:

- **Other sessions' runs were open the whole time.** `stage2.mjs --dry-run` refused on its own precondition:
  "no other harness run is open (rehearsal windows) — 9 open". The count of live windows was 11 at 09:11 UTC, 17 at
  09:39 and 10 at 11:00. The windows are `demo_factory.withRun`, `scripts/e2e/run.mjs` and check windows, all opened
  by other sessions. Two E2E runs on the one production database count and remove each other's fixtures
  (memory: post-deploy-smokes-overlap-manual-e2e). That is not a measurement.
- **Another session interfered with this one.** The local-build registration walk (`80b034ca`) lost its browser in the
  middle of the walk; no Chromium process was left. Its rehearsal window was closed at 10:28:21 UTC, and this session
  did not close it. Its demo lead was removed while the walk was still waiting.
- **The management API was rate-limited the whole time.** Single read-only queries came back HTTP 429 for minutes.
  One `--cleanup-only` took more than 60 minutes. A full stage-2 run makes thousands of management calls.

What WAS executed against production, on ZZ DEMO and `@example.invalid` identities only:

1. `supplier_registration_walk.mjs --lang en --vp desktop` on the live site, run `390dafcc`. It reproduced failure
   #32 exactly: `{"lic":true,"prof":false}`, the Documents tab stuck on "Uploading…", and Save answering "Still
   needed to register: Company profile".
2. The upload fix itself, run `0bef79e2`. All four steps worked, as shown in row #32 above. Its teardown left 0 rows.

`invite_enabled` was `false` before the step and `false` after it, last updated 2026-10-19 14:05 UTC. This step
never wrote it.

**What the next rerun needs:** zero live rehearsal windows, a quiet management API, and #1571, #1574 and this
branch merged and deployed. Then run `node scripts/e2e/stage2.mjs --run --cap-usd 15`.

## Cleanup and spend

__CLEANUP__
