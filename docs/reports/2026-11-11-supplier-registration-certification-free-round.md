# Supplier registration certification, free round: 11 Nov 2026

Seat: `customer_support`. Founder ruling 1620. The bar and how to run it are in
`docs/release/supplier-registration-certification.md`, and the driver is
`scripts/e2e/supplier_registration_certification.mjs`.

**Verdict: NOT READY TO INVITE.** No free round can certify. This one also found two defects that would embarrass the
founder today, both fixed on this branch but not yet deployed, and five more that are reported below.

## What was run

- Production `https://quotesdone.com`, models OFF (rehearsal window `models_allowed = false`), two full runs one after the
  other. Run 1 had tag `f331a927` (00:42–00:55 UTC); run 2 had tag `506f549f` (01:01–01:14 UTC). Each run made 8
  registrations, one at a time: 4 on a 1440x900 desktop and 4 on an iPhone 13 on a 9 / 1.5 Mbit/s, +60 ms, CPU 2x network.
- Safety:
  - Model spend was **USD 0.0000** by tag in both runs, and untagged reader spend in each run's window was also 0. Between
    00:42 and 01:20 UTC, `ai_cost_log` holds 32 `license_extract` and 48 `supplier_doc_trades` rows: every one is model
    `none`, USD 0, untagged (the fixture stub). The only other rows in that window are the platform's own
    `resilience_ping`, not this run.
  - **0 notifications dispatched.** Each run had 8 e-mail and 8 WhatsApp notifications, all `suppressed` (the demo
    guard), counted before teardown.
  - **0 leftovers**: teardown by tag, plus the Resend sink accounts, plus 0 fixture licence numbers still held.
- 16 screen recordings and full-page screenshots of every step are on the session's disk, not in git.

## Verdict per criterion (both runs, the final judge)

| criterion | verdict | measured |
|---|---|---|
| 1 not laggy (3 s desktop / 5 s phone) | **FAIL** | 162 timed steps; 7 over budget. On desktop, "the code verifies → Register your company" took a median of **3.48 s** (max 4.64 s, 6 of 8 over 3 s): a serial chain of `login_otp verify` (1.0–1.6 s), then `supplier_api me`, `supplier_portal dashboard` and `kyc state` (0.8–1.6 s each). On the phone, the invitation's Verify into the workspace took 5.7 / **7.4 s** (`supplier_portal dashboard` 5.0 s, `me` 4.4 s). The portal home on desktop took 2.6 s median, 3.4 s max. |
| 2 reads the trade licence (≥ 7 of 8, all five fields) | **FAIL** | Production today, CODE reading (free): **1 of 5** judged licences per run read whole (DMCC, J7). The cuts: L1 legal name read as "ZZ DEMO Saker Electromechanical", and its authority carries the row's Arabic label; L2, L3 and L6 each lost their wrapped third activity. The photo and the scan need the paid reader. **With this branch's fix, code reads all 6 text licences whole** (offline, the product's own `licence_fields.ts`). |
| 3 expired licence flagged | **PASS** | Submit answers "Still needed to register: the trade licence on file has expired." The registration stays `action_required` / `licence_expired`, never approved. The licence step itself shows only "Read your licence, expires 2026-08-31." (see finding 6). |
| 4 understands what they do | NOT RUN | That is the paid reader's work. CODE alone proposed: J2 joinery + doors (right), J6 staff_transport (right), J3 plumbing only (acceptable, but the right trade, building_materials, is missing), J1 nothing. |
| 5 no error, no dead end | PASS | 0 console errors and 0 5xx. The 4xx answers are product states (`dashboard` 400 = "no company yet", which opens the registration; `save_profile` 400 = the expired licence; `services_save_rewrite` 400 = "Tick at least one service"). |
| 6 no Arabic to a supplier | **FAIL** | The Supplier Agreement page prints QuotesDone's Arabic registered name "كوتس دن للتكنولوجيا". Reported apart: the `/supplier` page and the agreement page carry an "العربية" language switch, and it leads to a full Arabic supplier page, `/ar/supplier`. |
| 7 plain and polite | PASS | Every message read is in `certification.json`. None carries a code, status or stack. |
| 8 under 10 minutes of the supplier's own time | NOT RUN | The two registrations a free run could finish (J2 invitation, phone; J6 Sharjah, phone) took **2.7–2.8 min** in each run. The other four need the reader to propose services. |
| 9 reproducible | PASS | Both runs gave the same outcome per journey: verified or not, licence fields, trades proposed. |

## Timings per step (both runs; median / max in ms, n = measurements)

| step | desktop | budget | phone | budget |
|---|---:|---:|---:|---:|
| the supplier page is interactive | 338 / 540 (8) | 3000 | 351 / 483 (6) | 5000 |
| the sign-up form opens | 1,411 / 2,017 (8) | 3000 | 1,429 / 1,547 (6) | 5000 |
| "Create my account" sends the code (code box open) | 2,041 / 4,698 (8) | 10000 | 1,557 / 2,567 (8) | 15000 |
| the code e-mail is accepted by Resend (after the click) | 0.9–4.1 s (16 sends) | | | |
| the code verifies → "Register your company" | **3,482 / 4,644 (8)** | 3000 | 2,909 / 3,883 (6) | 5000 |
| "Create company" → the registration form | 2,257 / 2,793 (8) | 3000 | 2,217 / 2,924 (6) | 5000 |
| the licence is read, screen answers (code; model stubbed) | 7,590 / 11,959 (6) | 45000 | 7,800 / 8,488 (4) | 45000 |
| the Supplier Agreement page opens | 344 / 487 (6) | 3000 | 373 / 729 (8) | 5000 |
| "Submit for approval" → workspace (acknowledged at once) | 7,967 / 8,836 (6) | 20000 | 7,523 / 9,056 (4) | 30000 |
| the Services tab opens | 114 / 829 (6) | 3000 | 107 / 2,150 (6) | 5000 |
| services shown from his documents | 10,220 / 10,426 (2) | 120000 | 14,123 / 18,116 (4) | 120000 |
| "Confirm my services" | 1,499 / 1,539 (2) | 20000 | 1,416 / 2,013 (4) | 30000 |
| confirm → approved and verified | – | | 2,048 / 2,332 (4) | 60000 |
| the portal home opens | 2,594 / **3,395** (6) | 3000 | 2,787 / 3,349 (6) | 5000 |
| invitation: the link opens the sign-up | – | | 1,649 / 1,746 (2) | 5000 |
| invitation: Verify → the workspace | – | | **5,686 / 7,397** (2) | 5000 |
| invitation: Documents tab / licence read / profile upload | – | | 1,450 / 2,456 / 3,945 | 5000 / 45000 / 30000 |
| invitation: Profile tab / "Save changes" | – | | 241 / 2,954 | 5000 / 30000 |

The harness's mobile step held the form's one read for 3.7–11.2 s, inside the portal's 20 s abort. It is not counted in the
supplier's time.

## Defects found and fixed on this branch (each with a test that fails on main; NOT deployed)

1. **A licence value that wraps is cut, and the company is renamed to the cut name**
   (`_shared/document_expiry/licence_fields.ts`). The Dubai DET bilingual licence's legal name wraps in its table cell. Code
   read the first line, and ruling 1176 then renamed "ZZ DEMO Saker Electromechanical Contracting LLC" to "ZZ DEMO Saker
   Electromechanical" and e-mailed the supplier that his licence prints it. Seen on production in both runs. The same fault
   glued the row's Arabic label onto the authority and cut the activities.
   - Fixed: a value takes the lines it wrapped onto, and an English value drops an Arabic tail.
   - Prevented by: `a_wrapped_licence_value_is_read_whole.test.ts`.
   - The 33 text licences of the intake accuracy corpus read identically before and after.
2. **The form shows empty "Trade licence no." and "Licensing authority" after a licence read whole by code**
   (`supplier_api/actions/documents.ts`). Only the model's answer filled them. Seen on every direct registration in both runs.
   - Fixed: the answer carries what the row recorded (`lib/licence_shown_back.ts`).
   - Prevented by: `licence_shown_back.test.ts`.
3. **Harness:** `fixture_mobile.recordFixtureMobile` reloads the page to show "Mobile verified", but on production a reload
   after "Create company" lands in the workspace, so the walk never saw the form again. Fixed with
   `recordFixtureMobileBeforeTheForm`. `evidence_pack.mjs` still uses the reload path.

## Found, not fixed (not contained enough to fix blind, or the founder's own documents)

4. **When the reader proposes nothing, the supplier cannot finish.** The trade he picks at sign-up is not on the Services
   checklist: it lists only `supplier_capabilities.trades` and document trades. So with nothing proposed, "Confirm my
   services" stays disabled and he stays "Pending, services unconfirmed". The only other door, "Rewrite my services", is
   also the model. Seen on J1, J4 and J5 in the free round. On production this is every registration during a model
   outage.
5. **A building-materials trader is offered plumbing, not building materials** (J3, code). "Building Materials Trading" and
   "Tiles and Ceramics Trading" mapped to no trade. The paid round will show whether the profile's model reading adds it.
6. **An expired licence is not called expired when it is read**: the licence step shows only "Read your licence, expires
   2026-08-31". He learns it at Submit.
7. **An invited supplier never sees the registration form.** After Verify he lands in the workspace ("Pending", profile score
   0/100, nine to-dos that mix the six mandatory items with optional ones). He must finish through Documents, then Profile
   (inside the Account menu), then Services. The free round got through it in 2.7 min, but nothing on screen says
   "here is what is left to register".
8. **Arabic a supplier can see**: QuotesDone's Arabic name in the Supplier Agreement, and the "العربية" switch that opens
   `/ar/supplier` in Arabic (ruling 1008: suppliers are always written to in English).
9. **Lag after the e-mail code on desktop**: 3.5 s median for Verify → "Register your company". It is a serial chain of
   four calls, made after the code is checked.

## What would embarrass the founder today

- His contact's company **renamed to half its name**, with an e-mail saying his licence prints it (defect 1). This is
  fixed on the branch, but production does it until the readers are deployed.
- **"We read the number, authority, expiry and TRN automatically" above two empty fields** (defect 2), fixed on the branch.
- A contact who arrives during a model outage **cannot finish** (finding 4). A building-materials trader is offered
  **plumbing** (finding 5).
- An invited contact lands on a **0/100 profile score** page with no "finish registering" form (finding 7).

## The paid round

```bash
NODE_USE_ENV_PROXY=1 node scripts/e2e/supplier_registration_certification.mjs --paid --runs 2 --cap-usd 1.50
```

Run it **after** defects 1 and 2 are deployed (supplier_api, supplier_portal and every reader of
`_shared/document_expiry`). Until then, J1 is renamed to half its name on production and reads 2 of 5.

**Expected cost**, from `--estimate` (`ai_cost_log`, last 30 days, these readers' calls):
- at the median: **USD 0.28 per run, 0.55 for the two**
- at the 90th percentile: USD 0.88 per run (0.67 of it reading 14 documents for trades)
- for comparison, the 10 Nov evidence registration (licence + profile + catalogue) cost USD 0.0245

**Hard cap: USD 0.75 per run, 1.50 total**, enforced in the database by `fn_kernel_paid_provider_gate`. A run that reaches its
cap is refused further model calls, and the reads it did not get are reported as failed.

The paid run reports its tagged reader spend and the untagged reader spend in its window. In this free round, every reader
call was untagged (`license_extract`, `supplier_doc_trades`), so check that the paid run's reader rows carry its tag and
real spend. If they do not, its reading verdicts stand for code alone.
