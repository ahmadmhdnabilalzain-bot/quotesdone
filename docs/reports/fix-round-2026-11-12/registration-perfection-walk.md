# REPORT (text for `walk/REPORT.md`)

customer_support seat's auditor, 12 Nov 2026, 05:01–06:08 UTC. Founder rulings 1644, 1645, 1646. Production https://quotesdone.ae; source read from `origin/main` b2bf64c82. The repository's source root is `src/`, not `website/src/`. Models OFF (`models_allowed=false`, cap USD 0.01). I fixed, deployed and applied nothing.

Folder `walk/` = `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/walk/`: 601 screenshots in `shots/` (142 MB), contact sheets in `sheets/`, measures as JSON in `measures/`, per-screen table in `tables.md`, scripts beside them.

## 1. Verdict

NO. The founder's four examples, measured:

| his words (ruling 1645) | measured |
|---|---|
| "no loading animation when you are submitting something" | 0 running animations and no progress element during every submit: code request, Verify, Create company, licence read (5–102 s), Submit (8.2–10.1 s). Only the words change. |
| "some buttons are not clickable" | Seven presses on the form change nothing he can see; the answer is 459–1,046 px away under Submit. |
| "a text box that is small or hidden or not showing" | Every text box 15 px (lists and text areas 14 px). Two boxes that look like inputs cannot be typed in. The agreement line is in four columns. The sign-in box is below the first screen. |
| "typing takes time" | Not found: p50 16–40 ms, worst 96 ms. |

Sizes: **i** = 390x844 touch with the certification's phone network and CPU; **a** = 360x740 touch, same; **d** = 1440x900. Shot names are files in `walk/shots/<folder>/`.

## 2. Findings

### BLOCKER

**B1. A phone photo of the licence does not upload on a slow mobile connection, and he is told the file is at fault.** (i; a shares the code)
- Measured (`measures/recheck/_out.json` `phone_photo_iphone`, `phone_photo_desktop`; `measures/scen_resume/_out.json` `slow_3g_4mb_photo`): 4.32 MB JPEG (4032x3024) → **17.29 MB** request. At 1.5 Mbit/s up: "Reading licence…" for **102.4 s**, `net::ERR_ABORTED`, nothing stored, "We could not store your licence file. Please try again with a PDF or a clear photo." 993 px below, off-screen. 3G: 101.7 s, same. Unthrottled: 9.7 s, HTTP 200.
- Shots: `recheck_photo_iphone/01_photo_after_5s.png`, `02_photo_after_45s.png`, `04_photo_answer_where_he_looks.png` (sheet `sheets/misc/sheet_01.png`).
- Cause: `src/components/portal/supplier/core/ProfileForm.tsx:121` sends `license: { original_b64: b64, file_b64: b64, images }`; `src/components/portal/supplier/core/upload.ts:28` puts the same base64 into `images`. `src/components/portal/supplier/api.ts:85` `REASONING_TIMEOUT_MS = 90000`.
- Fix: send the licence as the profile goes: `uploadDirect('licence', file, token)` then `process_docs { license: { path } }` (server branch exists: `supabase/functions/supplier_api/actions/documents.ts:66`). Until then send the bytes once and shrink a photo to 2,000 px JPEG in the browser.
- Scope: on a fast line it works. He meets it on weak signal. 8 MB photos fail below about 3 Mbit/s by the same arithmetic (not run).

### HIGH

**H1. What goes wrong mid-form is said at the bottom of the form, off-screen.** (all sizes, 8 cases)
One message line after Submit (`ProfileForm.tsx:328`, state `:102`), written to by the licence, mobile and e-mail steps (`:66`, `:76`, `:83`, `:114`, `:131`).

| he does | sentence | where |
|---|---|---|
| attaches a .docx as licence | "Could not load this section. Please try again." | 1,046 px below (i) |
| attaches a HEIC | same, after 25.5–27.9 s | 1,046 px below |
| attaches a 15.3 MB scan | "That file is 14.6 MB. We can read files up to 10 MB here…" | 1,046 px below; nothing changes where he looks |
| loses the connection during the upload | "We could not store your licence file…" | 961 px below |
| presses "Get the code on WhatsApp" with a bad number | "Enter a UAE mobile number…" | 673 px below (a), 459 px (d) |
| the code request fails | server's sentence | 673 px (a), 459 px (d) |
| wrong mobile code, Verify | server's sentence | 661 px (a), 501 px (d) |
| Submit with something missing | "Still needed to register: …" | d: 8 px off the 900 px screen, no scroll; in view on i and a |

Shots: `scen_codes/15_lic_docx_answer_where_he_looks.png`, `17_…`, `19_…` (sheets `scen_codes/sheet_04`, `sheet_05`); `iphone/46_form_mobile_send_refused.png`, `50_form_mobile_wrong_code.png`; `sheets/iphone_full/sheet_02.png`, `sheet_03.png`.
Fix: one `role="alert"` message per step under its own control (`ProfileForm.tsx:260-263`, `:287`); for Submit, scroll the alert into view and focus it.

**H2. Nothing moves while he waits.** (all sizes)

| press | what shows | how long (i / a / d) |
|---|---|---|
| Create my account / Send me a code | "Sending…" | 2.1 / 2.0 / 1.6 s |
| Verify & continue | "Verifying…" | 1.4 / 1.2 / 1.1 s |
| Create company | "Sending…" | 2.7 / 2.7 / 2.6 s |
| Attach file (licence, text PDF) | 13 px grey "Reading licence…" | 6.2 / 5.2 / 7.0 s; small photo 7.6–15.8 s; 4.3 MB photo 102 s |
| WhatsApp answer, Continue | "Saving…" | 1.3 s |
| Submit for approval | "Submitting…", then 1.7 s "Loading your dashboard…" | 10.1 / 8.2 / 9.8 s |
| Save changes | "Saving…" | 2.5 (a) / 2.1 (d) s |

Submit uploads files of up to 100 MB each (`upload.ts:8`) with no percentage. A large file was not run (the container cuts a request at about 30 s).
Shots: `iphone/15_signup_submitting.png`, `61_form_submitting.png`, `scen_resume_later/12_submitting_on_3g_after_4s.png`.
Cause: `src/components/ui/button.tsx:28` has no busy state; `Login.tsx:128`, `:133`; `Onboarding.tsx:85`; `ProfileForm.tsx:260`, `:287`, `:324-327`.
Fix: a `busy` prop on `Button` adding a spinner (`lucide-react` `Loader2`, `animate-spin`); a progress bar per file (`upload.onprogress` in `src/lib/signedUpload.ts`).

**H3. Every text box is under 16 px.** (i, a; 24 fields) 15 px on every `<input>`, 14 px on `<select>` and `<textarea>` (`node summarize.mjs iphone`). The zoom is Safari's rule; not observable in Chromium. Cause: `src/components/ui/input.tsx:10` `text-copy` = 15 px (`src/app/globals.css:87`); `styles.ts:25-26`; `ServicesTab.tsx:491`. Fix: `pointer-coarse:text-[16px]`.

**H4. The agreement line is broken into four columns with a 13 px checkbox.** (i, a) "I accept the / QuotesDone" | "supplier / terms" | "." | "Required". Checkbox 13x13 (the emirates' are 20x20). The link inside the label is 76x42. Shots: `iphone/60_form_ready_to_submit.png`, `android/52_form_ready_to_submit.png`. Cause: `ProfileForm.tsx:322`, a `label.flex` with four separate flex items. Fix: `<label class="flex gap-2 items-start"><input class="h-5 w-5 mt-0.5 accent-primary shrink-0"/><span>…one sentence…</span></label>`; same for `:323`.

**H5. Account menu and bell open into the page; the bell panel is cut off.** (i, a, d) Measured (`scen_look/_out.json` `menu_bell`, `menu_account`): computed `position: relative`; heading jumps 150 px and 154 px; bell panel right edge at 441 px of 390. Shots: `iphone/78_ws_account_menu_open.png`, `iphone/85_ws_bell_open.png`, `android/77_…`, `desktop/69_ws_bell_open.png`. Cause: `src/app/globals.css:604-605` `.qd-panel{position:relative}` beats `absolute` on `HeaderMenus.tsx:76`, `:103`. Fix: an absolutely positioned wrapper around the `.qd-panel`.

**H6. The light theme is unfinished, one tap away, remembered (`qd-theme=light`).** (i, a, d) Contrast: tab labels 1.25:1; "Create account" 1.33:1; "SUPPLIER PORTAL" 1.38:1; "Get the code on WhatsApp →", "Get it by SMS", "Select all" 1.5:1; the sign-in e-mail box is a dark grey block. Sheets `look_light/sheet_01.png`, `sheet_02.png`. Cause: `globals.css:1669-1674`; `ui/input.tsx:10`; `ui/button.tsx:21`. Smallest fix: remove the toggle (`SupplierPortal.tsx:231`) until the theme is finished.

**H7. Reload, Back or a tab switch drops everything not yet submitted.** (i) Before and after a reload (`scen_resume` `reload_mid_form`): emirates 1 → 0; mobile → empty; contact name → empty; chosen profile file → gone; agreement tick → off. Only the uploaded licence stays. Back at the code step goes to /supplier; Forward returns without the code box. The form sends him out of the page three times (e-mail code, mobile code, agreement in a new tab). The iOS eviction itself was not reproduced; the reload was `page.reload()`. Shots: `scen_resume/10_…`, `11_form_after_reload.png`. Fix: draft in `sessionStorage` (`ProfileForm.tsx:32-44`); store profile and catalogues when picked; same for the sign-up step (`Login.tsx:99`).

**H8. On /portal the sign-in box is below the first screen, and its button leads to "Welcome back".** (i, a) E-mail box at y = 1,026 on an 844 px screen (`portal_cold_fold`). The first screen repeats the /supplier headline with "Become a Verified Supplier", which scrolls to the Sign-in tab: "Welcome back". It still works: a new address there gets a code and lands on "Register your company" (measured). Shots: `iphone/07_portal_as_it_opens.png`, `08_…`, `91_signed_out.png`. Cause: `src/components/portal/SupplierPortal.tsx:245-246`. Fix: `onStart` selects "Create account"; card first on phones.

**H9. After Submit nothing says "received"; a nine-line red paragraph heads every tab.** (i, a, d) "Why: your registration is complete except one step: … you are verified as soon as you confirm" (red, 13 px, no full stop), 9 lines at 390 px. Shots: `iphone/62_workspace_after_submit.png`, `72_ws_documents.png`. Cause: `Dashboard.tsx:178` `text-destructive`; `serverCopy.ts:17`. Fix: one plain card, "Registration received. One step left: confirm your services.", one button, not red.

**H10. A directory-listed company is registered a second time through the public link.** (server) Measured (`scen_company` `listed_company_public_signup`): unclaimed listing (lead 158191) existed; a public sign-up typed the same name; a second lead was created (158192, `self_registered`); the listing stayed invitable. A name held by a claimed company is refused (exact and "l.l.c."). Cause: `supabase/functions/supplier_api/create_company.ts:163-166` matches a listing by the account's e-mail and a name only among claimed rows; `:208` inserts. Fix: match an unclaimed listing by normalised name and emirate and claim it (`:196-201`). Tried once, one listing.

### MEDIUM

| # | finding | evidence | cause | fix |
|---|---|---|---|---|
| M1 | Wrong file type gets the wrong sentence. Server: "That licence file cannot be accepted. Please upload a PDF or a clear photo (JPEG or PNG)…"; page: "Could not load this section. Please try again." HEIC waits 25.5 s first. | `scen_codes` `licence_uploads` | `api.ts:112` gives a refusal without `code` the code `load_failed`; `serverCopy.ts:780` prefers it | `if (!j.code && !j.message)`; refuse wrong types in the browser (`ProfileForm.tsx:111`) |
| M2 | "Done" is untrue three ways: an empty file is announced "Licence uploaded…" (server stored nothing); "Done" stays beside the expired-licence alert; after a failed replacement the alert is gone and "Done" remains. | `scen_codes/13_…`; `sheets/misc/sheet_01.png` | `ProfileForm.tsx:133`, `:112`; `documents.ts:76` | "Done" only when a path is returned and not expired; refuse size 0 |
| M3 | No "send the code again", though two messages say "Please request a new one." After reload or Back the address is retyped under "Welcome back". The older of two code e-mails answers "Incorrect code." | `scen_codes` `expired_code`, `old_code`, `reload_at_code_step` | `Login.tsx:129-135` | add the link; keep step and address; say "use the newest code" |
| M4 | Stale errors: "Enter your company name." after typing it; "Still needed to register: Signed supplier terms." after ticking. | `explore2/18_…`; `iphone/60_…` | `Onboarding.tsx:86`; `ProfileForm.tsx:328` | clear on change |
| M5 | "Verify & continue" with an empty box does nothing. | `verify_empty_press` | `Login.tsx:111` | show `le_enter_code` |
| M6 | A dropped connection is not named: "Could not send a code." / "Something went wrong." / "Could not save your profile." / "We could not store your licence file. Please try again with a PDF or a clear photo." Nothing typed was lost in any of the four. | `scen_codes` `offline_send`; `scen_resume` `offline_*` | `api.ts:98` returns `network` / `timeout`; no copy | one sentence for both codes |
| M7 | A dead session at Submit shows "Invalid JWT". Real gateway answer: `401 {"code":"UNAUTHORIZED_LEGACY_JWT","message":"Invalid JWT"}` (probed); on the form the 401 was stood in. Token life 60 min, so 20 idle minutes change nothing. | `scen_resume_later/07_…` | `api.ts:108-112`; `ProfileForm.tsx:152` | own sentence for 401; refresh and retry once |
| M8 | "Trade licence no." and "Licensing authority" look like disabled inputs; the authority is cut off. | `sheets/iphone_full/sheet_01.png`; `desktop/44_…` | `ProfileForm.tsx:270-271` | plain text, after a read |
| M9 | "+971 050 …" and Arabic-Indic digits refused with only the general hint. | `mobile_formats_aria_invalid` | `uaeMobile.ts:6-7` | drop the 0; map ٠-٩ |
| M10 | Code step says add supplier@quotesdone.com; the e-mail comes from info@quotesdone.com. | `recheck` `code_email` | `copy.ts:10` | name the sender |
| M11 | Bell lists one event twice (one row per channel: notifications 143108, 143109). | `desktop/69_…` | `supabase/functions/supplier_portal/overview.ts:262` | one notice per event |
| M12 | Documents: "Your trade licence is on hold - see the notice on your overview" while the licence shows "Valid"; there is no overview. Three names for the one step left. "Not eligible yet". | `sheets/iphone_docs/sheet_01.png` | `supabase/functions/_shared/verified_badges.ts:22`; `GetMatched.tsx:85`, `:97` | real reason; one name |
| M13 | Company renamed at Submit with no word on screen (typed "…Walk Resume Trading LLC", headed "…Marina Steel Trading DMCC"; ruling 1176; an e-mail and WhatsApp are written). | `scen_resume_later/13_…` | by ruling | one line under the heading |
| M14 | Services tab AS LIVE, **may be superseded**: "could not be read just now … please upload it again later"; disabled "Speak your services"; "Press ⌘K" on a phone. | `sheets/iphone_full/sheet_07.png` | `servicesCopy.ts:69-72`; `SupplierCommandPalette.tsx:30` | hide what is not ready |
| M15 | Page jumps. CLS: /portal opening 0.18–0.36 (phones); after the WhatsApp answer 0.30 (i), 0.40 (a); Insights 0.55, 0.46; reload 0.35, 0.18, 0.25 (d). | `tables.md` | `PortalBootFallback.tsx`; `ProfileForm.tsx:299` | reserve heights |
| M16 | Keyboard alone cannot reach the three "Attach file" controls (20 Tab stops, none a file picker). Order otherwise top to bottom, ring at every stop. | `focus_order_form` | `helpers.tsx:71` `class="hidden"` | `sr-only` + `focus-within:ring` |
| M17 | Six Profile fields have placeholder-only labels. | `iphone/82_…` | `ProfileForm.tsx:286`, `:303-307` | visible labels |
| M18 | Sign-up address box has no `type="email"` or `inputmode`. `autocomplete` values are right. | `summarize.mjs` | `Login.tsx:127` | add them, `autoCapitalize="none"` |
| M19 | Explanations 13 px, hints 12 px, "Required" 11 px, errors 13 px. | `tables.md` | `styles.ts:10`, `:12`, `:13`; `helpers.tsx:27` | 14–15 px on touch |
| M20 | Under 44x44: text boxes 304x40 (code 239x40); agreement label 304x42; cookie "Got it" 358x40; logo 131x28; theme 40x44; footer links 28 px. Every button and tab is 44+. | `summarize.mjs iphone` | `ui/input.tsx:10`; `CookieConsent.tsx:35` | `pointer-coarse:min-h-11` |
| M21 | The form opens on the optional emirates list; Trade licence starts at y = 807 of 844. | `iphone/26_…` | `ProfileForm.tsx:250` | required first |
| M22 | Agreement: 5,035 words, 24,108 px (28 phone screens), new tab, no way back. | `agreement_page` | `ProfileForm.tsx:322` | sheet over the form, or H7 |
| M23 | A self-registered person reads "Finish registering … We already hold your company listing…" after a reload. | `scen_resume/11_…` | `Dashboard.tsx:77-78`; `copy.ts:15` | own wording |

### LOW

L1 ISO date in "expires 2027-05-03" (`ProfileForm.tsx:99`). L2 "Company profile (PDF):" though five types are accepted (`:315`). L3 "Done" beside "Required" (`:257`). L4 a 15.33 MB file called "14.6 MB" (`api.ts:146`). L5 sign-in errors lack `role="alert"` (`Login.tsx:136`). L6 at 200 % page zoom (195 px) the top bar's wordmark, theme button and "Sign out" overlap; with the root font at 200 %, 27 of 28 text elements stay under 20 px (`SupplierPortal.tsx:223-233`). L7 "Account · Profile ▾" on two baselines (`HeaderMenus.tsx:100-101`). L8 native "Choose File" in Supporting documents. L9 format hint stays under a verified mobile. L10 the phone menu lets the page show through after its fade (`MobileNav.tsx:76`; shot `recheck/menu_open_after_fade.png`). L11 "Press ⌘K" on every platform. L12 the code step does not say 10 minutes. L13 by ruling 1008 the Arabic landing opens an English portal: noted, not a defect.

### Looked for and right

Typing, press response, double press (Create my account, Verify, Create company, Submit: one request each). Typed text kept while a licence read lands. Code arrives in 1.2–1.7 s, accepted with spaces, asking again after 9 s and 19 s allowed. A new address in "Sign in" and a registered one in "Create account" both land correctly. A name with Arabic letters, an apostrophe and 78 characters. The expired licence is said at upload, where he looks. Invitation link and invalid link. Coming back in a new session opens the form with the licence on file. Landscape. The code e-mail (one card, code at 34 px).

## 3. Measures per screen and size

Full table: `walk/tables.md` (78 rows, 26 screens x 3 sizes; from `node tables.mjs`). Constant across all rows: horizontal scroll **no**; smallest text **12 px**; smallest input font **14–15 px**; press to first change **1–44 ms**; new console errors 0 except the browser's line for expected answers (wrong code 400, no company 400, two 415s).

Rows where the screen's own CLS is 0.05 or more:

| screen | i | a | d |
|---|---:|---:|---:|
| /portal as it opens | 0.36 | 0.36 | 0 |
| Sign-up card | 0.065 | 0.04 | 0 |
| Code box | 0.056 | 0.03 | 0 |
| Form: mobile, code, WhatsApp | 0.296 | 0.40 | 0 |
| Supplier Agreement page | 0.069 | 0.07 | 0.008 |
| Workspace after Submit | 0.116 | 0.155 | 0 |
| Insights | 0.547 | 0.46 | 0 |
| Workspace after reload | 0.346 | 0.18 | 0.255 |
| Signed back in | 0.082 | 0.002 | 0.143 |

Smallest tap target per screen group (phones): landing 41x28 footer link; every portal screen 131x28 top-bar logo; agreement 324x17 "ON THIS PAGE". Controls under 44x44 on the form: 8–10 (i, a).

Typing, quiet pass (3 passes x 30 characters; Event Timing, ms). The desktop typing figures in `tables.md` were taken while my own tooling used the CPU; these replace them.

| field | i p50 / worst | a | d |
|---|---|---|---|
| sign-in address | 16 / 40 | 16 / 24 | 40 / 96 |
| form: mobile | 16 / 32 | 16 / 56 | 32 / 80 |
| form: contact name | 16 / 24 | 16 / 24 | 32 / 64 |
| Services: own words | 16 / 40 | 16 / 24 | 32 / 72 |
| Profile: products | 16 / 24 | 16 / 24 | 40 / 48 |
| Profile: services | 16 / 24 | 16 / 32 | 40 / 56 |
| Profile: description | 16 / 24 | 16 / 24 | 32 / 64 |

Over 100 ms: 0 of 1,890. `ProfileForm` is one component; each key re-renders the whole form.

Times (ms; i / a / d): code box after "Create my account" 2,050 / 2,049 / 1,588; "Register your company" after Verify 1,422 / 1,227 / 1,147; form after "Create company" 2,658 / 2,654 / 2,624; workspace after Submit 10,100 / 8,157 / 9,762; after a reload 6,560 / 2,240 / 1,369.

## 4. Not covered

- **Safari and WebKit**: the zoom on focus (H3 rests on the measured font size), the real keyboard (emulated as a viewport 300 px shorter: every box and its button stayed in view except "Submit" under the contact name), the iPhone file and camera sheet, HEIC from the photo library, code autofill, a background tab reloaded for memory, WhatsApp's in-app browser.
- **The real mobile code**: `kyc send_sms` and `verify_sms` were stood in in the browser and the mobile recorded verified in the database, as the certification's harness does.
- **Everything the model does**: reading a photo or scan, proposed services, "verified", the approved workspace. "Confirm my services" stayed disabled.
- Native pickers (the 225-option trade list, dates). A 20–100 MB upload. Five wrong codes, "too many code requests", a customer's address, a sanctioned name (verifications are capped at 30 an hour per origin, shared with other audit agents).
- A real hour of idleness. Scenarios at 360x740 and 1440x900. The 200 % text setting of a real phone (emulated two ways). Screens with data. The invitation door past its first screen. The e-mail in a mail app. Screen readers.

## 5. Safety and teardown

- Windows `qd_run:f2dfff8d` and `qd_run:ab43f6f6`, both `models_allowed=false`, both closed.
- Made: 16 sink addresses, 7 ZZ DEMO companies through the form, 2 directory listings inserted.
- Notifications before teardown: 10, all `suppressed` (`registration_received` 4 e-mail + 4 WhatsApp; `company_name_from_licence` 1 + 1). Dispatched 0.
- Spend by tag: USD 0, 0 calls. Leftovers: total 0; checked again by query (0 leads, auth users, verifications, notifications, storage objects; 0 fixture licence numbers held). Proof: `walk/teardown_ab43f6f6.json`, `walk/teardown.log`.
- **For the main session.** Four paid untagged `supplier_doc_trades` calls at 05:46:04–05:46:47 (ai_cost_log 103885, 103889, 103908, 103913; USD 0.0099). Not provable by id. Evidence they are not this walk's: its own reader calls in that minute are `model_used = 'none'`, cost null (103869, 103870, 103905, 103907, 103909–103912); they are the only paid untagged reader calls of the hour against about 25 licence uploads and 4 Submits; window `qd_run:1f18dbf5` (sales_engineer `services_hard_profiles/run.mjs`) closed 88 s after the last.
- `fn_ai_subject_is_fixture` knows a fixture by an `@example.*` address; a supplier on a Resend sink address does not match it and is kept free by the run tag and the stub, not by that function.

## 6. Run it again

```
cd <scratchpad>/walk
NODE_USE_ENV_PROXY=1 node run_ctl.mjs open
NODE_USE_ENV_PROXY=1 node walk_main.mjs --size iphone --licence L2 --profile P2   # also android, desktop
NODE_USE_ENV_PROXY=1 node scenarios.mjs codes company resume look
NODE_USE_ENV_PROXY=1 node recheck.mjs        # alone: typing, the phone photo, the code e-mail
NODE_USE_ENV_PROXY=1 node run_ctl.mjs close  # counts notifications, tears down, proves leftovers 0
node summarize.mjs iphone ; node tables.mjs ; python3 sheet.py shots/iphone sheets/iphone
```
`lib.mjs` holds the measure pass, typing latency, press response, keyboard-up viewport, focus order and double press; it imports the certification's fixture helpers from `/tmp/claude-0/main-base` and writes nothing to the repository. No branch, commit or PR was made.

Worth a memory note (yours to land): the certification's photo fixture is 0.08 MB, so it cannot see B1; and the fixture function does not match sink addresses.
