# Monday 16 Nov 2026: every step an invited person can take, and the test that proves each

Seat: `customer_support`. Founder ledger 1692 (15 Nov 2026): he texts the invitation to his own network on Monday and wants
"perfection"; he will not accept "I tried to register but this happened" from anyone he invites, nor "I forgot to test this".
Ledger 1620/1646: the people are general managers of supplier companies he knows, reached by a text with a link; some may
also buy. The happy path is certified by `docs/release/supplier-registration-certification.md`. This file covers everything
around it that a real person meets and that certification does not prove.

Written 15 Nov 2026 from `origin/main` `ff5f74688`. How each fact was found is marked:
**READ** (from the code), **SELECT** (a light read of production), **GET** (a plain request to a public page or a
preflight, no sign-up), **LOCAL** (run offline or on a local Postgres). Nothing here was run as a browser walk, a sign-up or
a paid call against production; those are listed under "How to run, in order" for the coordinating session.

## The entry links

| link | who gets it | what it opens | proof |
|---|---|---|---|
| `https://quotesdone.com/portal?join=1` | **the link the founder texts** (`docs/reports/2026-11-12-monday-readiness.md`) | supplier portal on "Create account" (`SupplierPortal.tsx` reads `join=1`) | GET 200; READ |
| same link opened in the UAE | everyone he texts | Vercel sends a UAE address on quotesdone.com to `https://quotesdone.ae/portal?join=1` (308, `src/lib/domains.ts`); the same build | GET of the .ae target 200 |
| `http://`, `www.`, a trailing slash, on either domain | a link retyped or forwarded | one 308 to `https://<apex>/portal?join=1`, `?join=1` kept | GET, 8 of 8 |
| `https://quotesdone.com/supplier` (and .ae) | anyone who looks the company up | public supplier page; both buttons go to `/portal?join=1` | GET 200, buttons read from the HTML |
| `https://quotesdone.com/ar/supplier` | a person who switches to Arabic | Arabic supplier page; its buttons go to `/ar/portal?join=1`, which opens the English portal (ruling 1008) | GET 200, `lang="ar" dir="rtl"` |
| `https://quotesdone.com/portal?t=<token>` | only a lead that got an e-mail invitation (e-mail invitations are held; Microsoft fails placement) | "Your invitation" card naming the company, then "Create account" | READ; certification J2 |
| `https://quotesdone.com/portal` | a person coming back | "Sign in" | GET 200 |
| `/join`, any `/invite` path | nobody: no such route | designed 404 | GET 404 |

The preview card WhatsApp draws for the texted link (GET with a WhatsApp user agent, 15 Nov): title **"Supplier portal —
QuotesDone"**, description **"Quote on jobs from anywhere in the UAE, matched to your licence and trade."**, picture
`https://quotesdone.com/en/opengraph-image` (PNG 1200x630, 128,945 bytes, 0.35-0.72 s, "Anonymous quotes for every trade in
the UAE"). The picture is the site's general card, written for buyers, not a supplier card. The page carries
`noindex, nofollow`; WhatsApp ignores that.

## The checklist

"Last run" is the latest result found recorded in the repository or measured today. NONE means no test exists.
A row this branch added a test for says so in **bold**.

### 1. The link and the device

| step | variant | what the person sees and does | what can go wrong | the test that proves it | last run |
|---|---|---|---|---|---|
| link preview | WhatsApp card | title, one line, the picture | no card, a broken picture, a picture too large to show | **`scripts/e2e/invitation_link_probe.mjs`** (judges in `.test.mjs`) | 15 Nov, 38/38 PASS (GET) |
| link opens | .com, .ae, http, www, trailing slash | lands on "Create account" | `?join=1` lost on a redirect (opens on "Sign in") | **`invitation_link_probe.mjs`** | 15 Nov PASS (GET) |
| link opens | WhatsApp's in-app browser (Android) / Safari (iPhone) | same page | a session kept in the in-app browser is not in Safari the next day: he signs in again with a code | NONE (cannot be driven here) | not measured |
| link opens | phone set to Arabic | English portal; Arabic only on `/ar/supplier` | an Arabic phone is not detected (by design, `localeDetection` off) | GET of `/portal?join=1` with `Accept-Language: ar` returns the English page | 15 Nov (GET) |
| browser | iPhone Safari | the whole registration | keyboard over a field, HEIC from Files, upload on weak signal (readiness report) | NONE here: this container has Chromium only. The certification's phone profile is Chromium with the iPhone 13 user agent and size | founder's own iPhone registration, 12 Nov (approved) |
| browser | Android Chrome, desktop | the whole registration | | `supplier_registration_certification.mjs` (Chromium desktop 1440x900, phone 390x844) | paid J1/J2/J6/J11 PASS, 12-13 Nov night (`2026-11-12-evening-releases.md`) |
| screen | 360 px | upload and form | clipped buttons | browser walk at 360x740 and 390x844, 12 Nov (`upload.ts` header) | 12 Nov |
| screen | landscape phone | form | the cookie row or keyboard covers the fields | NONE | never |
| network | slow (9 / 1.5 Mbit/s, 60 ms) | upload with a percentage and Cancel | an upload cut on a weak link | certification phone profile; 15-minute upload safeguard (`upload.ts`) | 12 Nov |
| server | the five-minute marks | portal home 1.6-4 s slower at :x0 / :x5 | feels laggy for a few seconds | `fix-round-2026-11-12/five-minute-mark-relay-hold.md` | measured 12 Nov; not fixed |
| browser rules | each door the registration calls, from all four site origins | nothing: the browser must be allowed to send the request | a preflight that answers 200 but does not allow a header the page sends (the 13 Nov PDF defect) | **`invitation_link_probe.mjs` preflight checks** (login_otp, claim_lookup, supplier_api, kyc, supplier_portal, my_data_pdf) + `scripts/checks/every_header_the_site_sends_a_function_is_allowed_by_its_preflight.test.mjs` | 15 Nov 24/24 (GET OPTIONS); static check 3/3 (LOCAL) |

### 2. The e-mail code

| step | variant | what the person sees and does | what can go wrong | the test | last run |
|---|---|---|---|---|---|
| send | work e-mail | "We sent a 6-digit code to …", "check your spam/junk folder", "add info@quotesdone.com to your contacts" | the code e-mail never reaches the inbox | certification (Resend's own sink: proves sending, not placement) | 12 Nov PASS |
| delivery | Gmail | code e-mail from `info@quotesdone.com` via Resend | Promotions or Spam | NONE for the code e-mail. Invitation mail via M365 reached Gmail inbox 24/24 (GlockApps 10 Nov, a different sender and copy) | — |
| delivery | Outlook / Hotmail / company Microsoft 365 | the same | Junk, or quarantine by the company's own filter (then he never sees it) | NONE for the code e-mail. The only Resend placement test (5 Oct, `hello.` subdomain, invitation copy): Microsoft 2 of 16 inbox. M365 invitations: Microsoft 0/21 inbox on 10 Nov | — |
| delivery | real codes, last 60 days | | | SELECT `email_verifications` by mailbox provider, test addresses excluded: Gmail 4 addresses / 0 verified (last 10 Oct), two company domains 2 / 2 (11-12 Nov). **No Hotmail, Outlook or Live address has asked for or verified a code in 60 days**; whether a company domain is on Microsoft 365 was not classed | 15 Nov (SELECT) |
| code | wrong | "Incorrect or expired code." | | `supplier_registration_error_paths.mjs` ("wrong e-mail code refused") | not recorded |
| code | expired (10 min) | "That code has expired. Please request a new one." | | `supplier_registration_error_paths.mjs` | not recorded |
| code | resend; two tabs | "We sent a new code. Please use the newest one" | the older tab's code no longer works | `supplier_registration_error_paths.mjs` (the older code refused); `registrationDraft.test.mjs` (the step survives reload/Back) | not recorded / LOCAL |
| code | too many | "Too many attempts. Please request a new code." / 8 sends an hour | | `login_otp` tests, `verify_race.check.ts` | LOCAL |
| language | Arabic | the code e-mail is English for a supplier (ruling 1008, `fn_registered_locale`) | | `suppliers_are_always_written_in_english.test.mjs`; certification criterion 6 | 12 Nov PASS |
| abuse | the same e-mail twice | "This e-mail already has an account — sign in instead." | | `create_company.test.ts`; `error_paths.mjs` (no second login) | LOCAL 34/34 |
| abuse | a temporary inbox | code arrives, then the registration is refused | was "We could not register your company. Please try again" in a loop | **`create_company.test.ts` "a temporary inbox is told so"** (fix on this branch: `disposable_email`, deploy `supplier_api`) | LOCAL PASS |
| abuse | a mobile number typed instead of an e-mail at sign-up | "Please sign up with your work email" | | `signupEmail.test.mjs` | LOCAL |

### 3. Mobile, the agreement, the documents

| step | variant | what the person sees and does | what can go wrong | the test | last run |
|---|---|---|---|---|---|
| mobile | 05x, 5x, +971, 00971, 971, spaces, dashes, Arabic digits, "+971 050" | accepted, sent as +9715XXXXXXXX | | `uaeMobile.test.mjs` | LOCAL |
| mobile | a non-UAE number (+44, +966) | "Enter a UAE mobile number, e.g. 050 123 4567" | **he cannot finish**: there is no other way to verify a mobile | `uaeMobile.test.mjs` (refused) | LOCAL; a product decision, not a defect |
| mobile code | WhatsApp first, then SMS | the code by WhatsApp; an SMS by Twilio Verify when WhatsApp reports it undelivered or late (`otpFailover`) | WhatsApp template refused, so Verify SMS (safe by construction, `wa_code.ts`) | `wa_code.test.ts`, `own_whatsapp_code.test.ts`; certification uses the reserved block +971 50 000 0040-89, refused before Twilio | real codes, 30 days (SELECT): 1 WhatsApp code sent and verified (12 Nov), 1 SMS (30 Oct) |
| agreement | English page, Arabic page | `/supplier-agreement` and `/ar/supplier-agreement` | | GET 200 both (0.4-1.5 s) | 15 Nov (GET) |
| acceptance | first name only | "Please enter your full name: your first name and your family name." | | `the_agreement_is_accepted_at_its_own_step.test.ts`; paid J2/J6 12 Nov | PASS |
| acceptance | name in Arabic letters, apostrophe, hyphen, emoji, `<script>` | accepted; printed on the certificate | a name dropped from the PDF; markup | **`compliance_archive/a_name_typed_any_way_prints_on_the_certificate.test.ts`**: Arabic 0 glyphs dropped, apostrophe/hyphen whole, markup escaped, an emoji left out (2 glyphs) | 15 Nov LOCAL 3/3 |
| certificate | PDF on a phone | listed in Documents as signed terms; opens by a signed storage URL | | `every_pdf_we_issue_is_on_our_template.test.mjs`; certificate tests | LOCAL |
| licence | PDF | read in about 15 s and shown back: company, number, authority, expiry | | certification J1-J3, J6-J8 | paid 12 Nov PASS |
| licence | iPhone photo (HEIC) | a library photo is handed over as JPEG by iOS because the picker asks `image/*` only; a HEIC from Files is drawn as JPEG by Safari | a HEIC another browser cannot draw: "This photo is in Apple's HEIC format. Take a screenshot of it or pick a JPG or PDF." | **`fileCheck.test.mjs` "the pickers never name HEIC"**; `fileCheck.test.mjs` HEIC refusal | LOCAL. What iOS really hands over: the founder's iPhone only |
| licence | phone photo JPEG, 4-48 MP | made smaller in the page (long edge 3,000 px) | | `upload.ts` measured 12 Nov; certification J4 | paid 12 Nov PASS |
| licence | multi-page PDF; scanned PDF | read | | certification J5 (scan); intake corpus `lic_*_multipage` | J5 paid 11-12 Nov |
| licence | PDF of 15-25 MB | "That file is 18.2 MB. We can read a licence of up to 10 MB …" at once | an office scanner's high-resolution multi-page PDF is refused | `fileCheck.test.mjs` | LOCAL |
| licence | wrong document (profile, ID, chamber certificate) | "This looks like a company profile, not a trade licence…" | | certification J11; `a_company_profile_in_the_licence_slot_is_named.test.ts` | paid 12 Nov PASS |
| licence | expired | told at upload and at Submit; never approved | | certification J8 | PASS |
| licence | each licensing body | | a body the approval gate does not know is **held for a person** (`licence_authority_unconfirmed`), and a held licence has no accept screen | fixtures read end to end: DET, ADDED, JAFZA, Ajman, RAKEZ, SEDD, DMCC, RAK DED. Accuracy corpus adds ADGM, UAQ, Fujairah, DAFZA, DSO, IFZA, Meydan, Shams, DIFC. **SAIF, Masdar, KEZAD, Ajman FZ, Hamriyah, Fujairah FZ, UAQ FTZ: no fixture, never read.** The gate's classifier (SELECT over 52 printed spellings): all of them 'uae' **except "Department of Economy & Tourism" with no "Dubai": 'unknown', held** | fix on this branch, **`scripts/sql/an_ampersand_in_a_licensing_authority_reads_as_and.sql`** + probe: LOCAL PROBE FAILED before, PROBE OK after; not applied |
| licence | legal name differs from what he typed | nothing is typed since ruling 1672: the company is named by the licence | | certification J2/J6 | paid 12 Nov PASS |
| profile, catalogue | PDF, DOCX, PPTX, photo, up to 100 MB | uploaded direct to storage, read after the answer | a 14.5 MB+ scan hit the CPU cap in 28 Oct tests on the body path (fixed by #1721 for the body path); a large profile's later read is not measured | certification P1-P8; `supplier_document_walk.mjs` | profile read: paid 12 Nov; large-file read: NONE |
| company name | long, emoji, script tags | not typed (licence names it); the optional trading name is a text field rendered by React | | React escaping; certificate test above | LOCAL |

### 4. Submit, approval, messages, coming back

| step | variant | what the person sees and does | what can go wrong | the test | last run |
|---|---|---|---|---|---|
| submit | all present | "Registration received. One step left: confirm your services below." | | certification step 9 | paid 12 Nov PASS |
| services | rich profile | two sentences, then his services unticked, about 2 minutes ("you can carry on and come back") | 117-130 s against a 120 s bar | certification step 10; `servicesPoll.test.mjs` | paid 12 Nov, 10 s over the bar once |
| approval | Confirm my services | approved at once by code (`fn_sales_engineer_verifies_supplier_now`), no person | held: reader down, authority unknown, licence unread | certification step 11 | paid 12 Nov PASS |
| messages | after Submit, after approval | e-mail and WhatsApp "Thanks for registering with QuotesDone"; "You are verified on QuotesDone: please confirm your categories" | the approval e-mail speaks of "categories" and "Remove this trade" while the page says "services" | certification criterion 6 reads every notification | SELECT, 14 days: both sent by e-mail and WhatsApp on 12 Nov; one WhatsApp "registration received" and one "company name" were `held` on 11 Nov |
| reminder | not finished | "A last reminder: complete your QuotesDone supplier registration" | | NONE found by name | sent 12 Nov (SELECT) |
| come back | next day, same phone | the portal opens signed in (stored session, refreshed) | | `SupplierPortal.tsx` onAuthStateChange (READ) | — |
| come back | second device, after sign-out | "Sign in" with an e-mail code, or a mobile code once the number is verified | a shared mobile: "more than one account", asked for the e-mail | `error_paths.mjs` ("a mobile shared by two suppliers never selects an account") | not recorded |
| colleague | same company, another e-mail | registers; when his licence carries the same number: "A company with this name is already registered … sign in with the email used to register it, or write to management@quotesdone.com." | there is no "add a colleague" | `duplicate_company` tests; `error_paths.mjs` | LOCAL |
| existing lead | his e-mail already in our directory (unclaimed) | the listing is claimed in place, its history kept (needs a session opened by a code) | | `create_company.test.ts` (S7) | LOCAL |
| existing lead | a listing with the same name, another e-mail | his own new row; the listing is flagged for a person to merge (`possible_duplicate_listing`) | | `create_company.test.ts` (H10) | LOCAL |
| portal | home, Documents, Profile, Services, "Download my data (PDF)" | | the PDF door was blocked in every real browser until #1994 (13 Nov) | static preflight check; **live preflight in `invitation_link_probe.mjs`**; six clean-context walks 13 Nov (not a script in the repository) | 15 Nov preflight PASS (GET) |
| help | "Ask your sales engineer" in the portal; a WhatsApp message to us | an answer from the model; a written apology if the model call fails (`modelOrOutage`) | WhatsApp reply about 27 s behind the "one moment" line (last measured before 12 Nov) | `workspaceHelp.test.mjs`; `wa_exchange_real.mjs` (paid) | not re-measured |
| Arabic | the whole path | `/ar/supplier` and `/ar/supplier-agreement` in Arabic; the portal, every e-mail, WhatsApp and PDF in English (ruling 1008) | | `nothing_a_supplier_reads_can_be_arabic.test.mjs` (red on main today for `drawing_boq/quotation_gate.ts`, merged in #2001, not the registration) | LOCAL |
| models down | OpenRouter out of credit | licence: "our document reader has not finished reading your trade licence yet. That is on our side, not yours …"; nothing proposed on Services; not approved until a read lands (the sweep reads again) | | `a_licence_our_reader_failed_on_never_asks_the_supplier.test.mjs`; certification free run (models off) | free 11 Nov |

**Where the platform stops calling models (READ, SELECT).** Nothing stops a call on a balance or a daily cap: the gateway's
budget halt was removed by founder instruction 987 (`ai_gateway/index.ts`), and `fn_kernel_paid_provider_gate` checks only the
`no_paid_ai` switch, the founder's route hold, the model registry and each route's breaker. OpenRouter itself refuses with 402
when the credit is gone; that is classed `insufficient_credit`, which opens the route's breaker on the first refusal. The founder
is e-mailed when the balance is under USD 10 and again under USD 2, once a day per band (`fn_openrouter_low_balance_tick`,
hourly at :23). Balance read 15 Nov 10:30 UTC: **USD 13.91** (SELECT `openrouter_meter`). Spend per day, Dubai time: 13 Nov
0.68, 14 Nov 1.12, 15 Nov 0.20 so far. A registration costs about USD 0.003 to 0.016 in model calls (paid runs of 11-12 Nov).
So the alert is close (USD 3.91 away) and the credit runs out only if a paid test round is run, not from Monday's registrations.

## How to run, in order

All from a worktree of this branch, after `supplier_api` is deployed and the SQL file is applied, in a cloud session
(`NODE_USE_ENV_PROXY=1` for anything that reads production).

| # | what | command | cost | time |
|---|---|---|---|---|
| 1 | the offline tests this branch adds | `node --test scripts/e2e/invitation_link_probe.test.mjs src/components/portal/supplier/fileCheck.test.mjs` then `deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-read=. --allow-net=127.0.0.1 supabase/functions/supplier_api/create_company.test.ts supabase/functions/compliance_archive/` | USD 0 | 1 min |
| 2 | apply the authority fix | `node scripts/apply_sql.mjs scripts/sql/an_ampersand_in_a_licensing_authority_reads_as_and.sql --apply --ddl`, then its `_probe.sql` (must print PROBE OK), then the MANIFEST line and delete the pending note (`scripts/sql/pending/an_ampersand_…txt`) | USD 0 | 2 min |
| 3 | deploy `supplier_api` (the temporary-inbox answer) | the usual deploy; then parity | USD 0 | 3 min |
| 4 | the link, the card and the doors | `NODE_USE_ENV_PROXY=1 node scripts/e2e/invitation_link_probe.mjs` (38 checks, GET and OPTIONS only) | USD 0 | 30 s |
| 5 | the error paths | `NODE_USE_ENV_PROXY=1 node scripts/e2e/supplier_registration_error_paths.mjs` (ZZ DEMO, torn down) | USD 0 | about 5 min, teardown longer |
| 6 | the free certification, after the day's deploys (#2001 touched supplier pages) | `NODE_USE_ENV_PROXY=1 node scripts/e2e/supplier_registration_certification.mjs` | USD 0 | about 45 min (11 Nov: 44 min) |
| 7 | one paid registration through the texted door, only if step 6 shows a change to the reading path (ruling 1660) | `NODE_USE_ENV_PROXY=1 node scripts/e2e/supplier_registration_certification.mjs --paid --only J1,J6 --runs 1 --cap-usd 0.10` | about USD 0.02 (J1 0.0085, J6 about 0.005 on 12 Nov) | about 15 min |
| 8 | code e-mail placement (the founder's or the coordinator's call) | one GlockApps test of the sign-in code e-mail from `info@quotesdone.com` through Resend; it needs a script that sends the code template to the seed list | 1 GlockApps credit of the 2 left, USD 0 | 10 min to usable, hours to finish |

## What only the founder can check (five taps on his iPhone)

1. Send himself `quotesdone.com/portal?join=1` in WhatsApp, look at the card, tap it: it must open on "Create account".
2. In a registration, tap the trade licence box and pick a photo from Photos: it must be accepted and read (iOS's HEIC to JPEG).
3. Turn the phone sideways on the registration form: every field and button must still be reachable.
4. In Documents, tap the signed agreement, then "Download my data (PDF)": both must open.
5. In Safari (not WhatsApp), open `quotesdone.com/portal` the next day: he must still be signed in, or sign in with one code.

## Known risks

| risk | likelihood | what a person would see |
|---|---|---|
| The sign-in code lands in Junk, or in a company's Microsoft 365 quarantine | **High for at least one invitee**: many UAE companies are on Microsoft 365 or Etisalat mail; the code e-mail was never placement-tested; Microsoft placed 2/16 of Resend mail in the inbox on 5 Oct and 0/21 of our M365 mail on 10 Nov; no Hotmail/Outlook address has verified a code in 60 days | "We sent a 6-digit code to …" and nothing in his inbox. Junk: found if he looks (the screen tells him to). Quarantine: never seen, and **sign-up cannot be done any other way** (a mobile cannot create an account). Mitigation that costs nothing: the founder's text says "the code comes from info@quotesdone.com; if it is not in your inbox within a minute, look in Junk" |
| A registration held for a person: authority unknown (fix pending), licence unread, reader unsure | Low to medium | "Registration received" and a pending state; nobody can accept a held licence without a database write, so a session must watch Monday's registrations (as the readiness report says) |
| The approval e-mail asks him to "confirm your categories" and "Remove this trade" | Certain for every approved supplier | wording that does not match the "Confirm my services" page he has just used; no harm beyond that |
| A licence PDF over 10 MB | Low to medium (office scanners at 600 dpi) | refused at once in words, with what to do |
| A non-UAE mobile | Low | refused in words; he cannot finish without a UAE number |
| A rich profile's services take about 2 minutes | High, by design | told "This takes one to two minutes; you can carry on and come back" |
| A slow few seconds at :x0 / :x5 | Medium | the portal home opens 1.6-4 s slower |
| OpenRouter runs out | Low on Monday (USD 13.91 left, about USD 1 a day without tests) | the licence "is on our side", nothing proposed, not approved until credit returns |
| A colleague registers the same company | Low | told the company is registered and to sign in with the first e-mail or write to management@ |

Prevented and measured by: `scripts/e2e/invitation_link_probe.mjs` and its test, `fileCheck.test.mjs`,
`create_company.test.ts`, `compliance_archive/a_name_typed_any_way_prints_on_the_certificate.test.ts`,
`scripts/sql/an_ampersand_in_a_licensing_authority_reads_as_and_probe.sql`.
