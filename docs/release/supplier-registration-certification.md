# Supplier registration certification: "ready to invite"

Seat: `customer_support`. Founder ruling 1620 (10 Nov 2026): he will invite general managers and senior people from his
own network to register as suppliers, and only once IT confirms the registration is flawless. In his words: "not laggy,
reads their trade licence, understands what they do… I don't want to get embarrassed."

**The registration is READY TO INVITE only when a PAID run of
`scripts/e2e/supplier_registration_certification.mjs` reports every criterion below as PASS, on two runs, the same day.**
A free run proves the flow and the speed. It never proves the reading, so it never certifies.

## What it drives

Production (`https://quotesdone.ae`, project `htdblwldjkcgjvmqkbeh`) in Chromium. The founder's contacts are in the UAE, and a UAE visitor to quotesdone.com is sent to quotesdone.ae, which serves the same production build. This container is in the US and is never redirected, so the walk opens .ae itself (`QD_SITE` overrides it). There are eight registrations, each
with its own ZZ DEMO company. Desktop and phone registrations run side by side.

| journey | screen | door | trade licence | company profile | must end |
|---|---|---|---|---|---|
| J1 | desktop | public sign-up | L1 Dubai DET, English + Arabic, clean PDF | P1 MEP contractor | verified |
| J2 | phone | invitation link `/portal?t=` | L2 Abu Dhabi ADDED, clean PDF | P2 joinery | verified |
| J3 | desktop | public sign-up | L3 JAFZA, clean PDF | P3 building materials trader (DOCX) | verified |
| J4 | phone | public sign-up | L4 Ajman, phone photo of the printed page | P4 HVAC | verified |
| J5 | desktop | public sign-up | L5 RAKEZ, image-only scan | P5 packaging manufacturer, image-only brochure | verified |
| J6 | phone | public sign-up | L6 Sharjah SEDD, clean PDF | P6 staff transport / bus rental, English + Arabic | verified |
| J7 | desktop | public sign-up | L7 DMCC, clean PDF | none: the walk stops once the licence is read | licence read |
| J8 | phone | public sign-up | L8 RAK DED, EXPIRED 31 Aug 2026 | P1 (any profile, so Submit can be pressed) | flagged, never approved |

The registrations run one at a time. Run side by side in one container, a desktop "Verify" took 25.9 s against 2.9 s alone,
so a parallel run measures the container's load, not the supplier's screen. `--parallel` runs desktop and phone together.

A registration through the public sign-up follows the product's own order:

1. the door
2. the e-mail code, sent to Resend's own sink and read back from Resend
3. company name and trade (the invited company already exists)
4. the mobile (the harness path, see below)
5. "All emirates"
6. the trade licence, uploaded and read, with what was read shown back
7. the company profile
8. the Supplier Agreement page, then the tick to accept it
9. Submit for approval
10. the Services tab: services proposed from his documents, unticked; "Tick all proposed services"; a role; "Confirm my
    services"
11. approved and verified, with the six mandatory items complete (`fn_supplier_mandatory_six` = `{}`)
12. the portal home

**An invited supplier (J2) walks the same registration form.** Verify claims the listed company and opens the registration form,
headed "Finish registering <company>", with what we hold about the company. Steps 5 to 12 then follow as above. Until 11 Nov 2026
Verify opened the **workspace** and registration was finished in three places: the Documents tab, then Profile in the Account
menu, then Services (free-round finding 7). Since then the portal opens the form for any company that has not submitted its
registration, and that includes a public registrant who reloads before Submit.

The founder's list puts the proposed services before the mobile and the agreement. In the product they come after
Submit, because the Services tab belongs to the workspace. The certification walks the product's order.

Every step is timed, photographed full-page and judged. Each registration is screen-recorded (one `.webm` per journey).
Each run writes `certification.json` and `CERTIFICATION.md` to `--out` (default `/tmp/qd-reg-cert/<free|paid>-<time>`).
Binaries never enter git.

## Pass criteria (measured by the script; the bar is `scripts/e2e/registration_certification_judge.mjs`)

| # | criterion | bar |
|---|---|---|
| 1 | not laggy | Every page and step must be **interactive within 3 s on desktop and 5 s on the phone profile**. Interactive means the screen has answered and the next control is on screen and usable. Some steps make the server do real work: sending the code, Submit (upload, save, signed agreement), reading the licence, proposing services, approval. These must **acknowledge** within the same 3 s / 5 s and **finish** within a ceiling: send code 10 s / 15 s, Submit 20 s / 30 s, licence read 45 s, proposals 120 s, approval 60 s. |
| 2 | reads the trade licence | On **≥ 7 of 8 licences**, all five fields are read correctly: licence number, legal name, issuing authority, expiry and **every** activity. They are compared with `scripts/e2e/fixtures/registration/expected.json`. An authority with an Arabic tail fails. The form must show the number and authority back to the supplier. |
| 3 | the expired licence | The supplier is **told** the licence has expired (on screen), and it is **never approved**. Whether the licence step itself says so, before Submit, is reported beside it. |
| 4 | understands what they do | For each of the 6 profiles, at least one proposed trade is in the profile's **right** list, and **no** proposed trade falls outside its right and **acceptable** lists (`expected.json`). Proposals start **unticked**, and "Tick all proposed services" ticks every one of his own (a service his documents say goes through a partner, reader @5, is ticked by him alone). |
| 5 | no error, no dead end | Every registration reaches its end. There are no console errors (third-party noise excluded, `browser.mjs` `realErrors`), and no edge-function call answers 5xx or fails. A 4xx is the product's own answer, which the page turns into a message (an account with no company opens the registration; a refused Submit says what is still needed). It is judged by criterion 7 and listed in the report, so the browser's "Failed to load resource … 4xx" line is not counted here. For the expired licence (J8), Submit refused with the reason is the expected end. |
| 6 | no Arabic to a supplier | Ruling 1008: no Arabic in any message the run sends a supplier, on any channel (e-mail, WhatsApp, SMS, PDF). The walk reads the sign-in code e-mail and every notification the run caused (subject, text and HTML; an attachment is listed by name, not opened). No Arabic on an English supplier page either, with two exceptions that are not messages: the Supplier Agreement's legal text (ruling 342: its Arabic text prevails, and it names QuotesDone by its Arabic registered name), and Arabic the supplier chose himself (the language switch, or a page he opened in Arabic). Both are reported as allowed. |
| 7 | plain and polite | No message (`role=alert` / `role=status`) shows a code, a status, a stack, JSON or a raw platform error, and none is curt ("invalid", "denied", "not allowed", "you must"). Every message read is listed in the report for a person to read too. |
| 8 | the supplier's own time | From the first click to **verified** must take **under 10 minutes** of the supplier's own time. That is the script's wall time with the harness's mobile step replaced by 60 s, the time a person needs to receive and type a code. |
| 9 | reproducible | Two runs give the same outcome per journey: verified or not, licence fields correct, trades proposed. |

**Phone profile:** Playwright's iPhone 13 (390x844, DPR 3, touch, iOS Safari user agent) on Chromium. The network is 9
Mbit/s down, 1.5 Mbit/s up and 60 ms added round trip, with the CPU slowed 2x, applied through the Chrome DevTools
Protocol. On a paid run the page's function calls are routed through Node (the container cuts a browser connection at
about 30 s). That network is then simulated on those calls in the route. **Desktop:** 1440x900 on the container's own
network.

## How to run

```bash
# FREE (models off, USD 0): the flow, the speed on both screens, the messages, and what CODE reads off text documents
NODE_USE_ENV_PROXY=1 node scripts/e2e/supplier_registration_certification.mjs

# the paid round's expected cost, nothing run
NODE_USE_ENV_PROXY=1 node scripts/e2e/supplier_registration_certification.mjs --estimate

# PAID: the readers on, two runs, a database-enforced cap of USD 0.75 per run (1.50 total)
NODE_USE_ENV_PROXY=1 node scripts/e2e/supplier_registration_certification.mjs --paid --runs 2 --cap-usd 1.50
```

A free run reaches "verified" only where code can read. Since 11 Nov 2026 the trade picked at sign-up is always on the Services
checklist, and a licence's activities are read by their subject, so J1, J2, J3 and J6 can finish free. The photo (J4) and the
scan (J5) have no text for code: with the models off their licence is held as `licence_being_read` (`licence_read_state`
'ours_failed'). The supplier is told it is on our side, and the sweep reads it again once a model can (#1909). In a free run,
"approved and verified" for J4 and J5 is NOT RUN when, and only when, that is the only hold (`waitsOnTheModel` in the judge);
any other hold is judged. A free run reports what CODE proposed on its own; every proposal the model makes is NOT RUN (paid).

Options:

- `--only J1,J4`: run those journeys only
- `--runs N`
- `--no-video`
- `--keep`: tear down later with `node scripts/e2e/run.mjs --purge-tag <tag>`
- `--direct` / `--via-node`

In a cloud session, Node reaches the management API only through the session proxy, so set `NODE_USE_ENV_PROXY=1`.

**Run the paid round only after the readers carrying the 11 Nov fixes are deployed**: `supplier_api`, `supplier_portal` and
every function that reads `_shared/document_expiry`. Until then production cuts a wrapped licence value, and leaves the
form's licence number and authority empty (`docs/reports/2026-11-11-supplier-registration-certification-free-round.md`).

**Expected cost of the paid round** (`--estimate`, from `ai_cost_log` of the last 30 days): about **USD 0.28 per run at
the median (0.55 for two runs)**. The 90th percentile is USD 0.88 per run, of which USD 0.67 is reading the 14 documents
for trades. The cap holds it under USD 1.50 whatever happens: `fn_kernel_paid_provider_gate` refuses the run's next paid
call once its window's USD 0.75 is spent. For comparison, the 10 Nov evidence-pack registration (tag `8120d011`, one
licence + profile + catalogue) cost USD 0.0245.

**The paid round is not finished until it shows the paid spend.** A server-to-server read made after the answer can lose the
run tag. For a ZZ DEMO subject the call is then answered by the fixture stub, not by a model. So each run reports
untagged reader spend in its window beside its tagged spend. If tagged and untagged reader spend are both 0, the readers
were not reached, and the paid verdict on criteria 2 and 4 stands for code alone.

## What is not the real thing, said plainly

- **The mobile code.** The supplier's mobile is in the reserved block +971 50 000 0040–89. `kyc` refuses it before any SMS
  is sent; it is then recorded verified, and the form is loaded again once `kyc` says so (`scripts/e2e/fixture_mobile.mjs`).
  The supplier's time counts 60 s for this step in place of the harness's own time.
- **The invited listing.** J2's company is inserted as `enqueue_supplier_invites` leaves one: `invite_status 'sent'`, a
  claim token. The supplier's side of it is real.
- **The account e-mail** is `delivered+qd-<tag>-supN@resend.dev`, Resend's own sink: accepted, recorded as delivered, then
  dropped. Every other identity is ZZ DEMO / `@example.invalid`.

## Safety

- Before it starts, the run refuses unless the three demo guards are installed and no lead holds a fixture licence
  number or name (a leftover would be set aside as a duplicate, and the run would fail for the harness's reason).
- Every notification the run caused is counted by status **before** teardown. One that is sent, queued or pending exits 3.
  A free run that spent anything also exits 3.
- Teardown is `fixtures.closeRun` by the run tag, then `cleanSink` for each account. The report names any leftover and
  any fixture licence number still held.
- Nothing can reach a person. Mail goes to `@example.invalid` (suppressed) or to Resend's sink. The mobile block is refused
  before Twilio.

## The fixtures (`scripts/e2e/fixtures/registration/`)

`node scripts/e2e/registration_fixtures.mjs --write` regenerates them. Every company is "ZZ DEMO …", every licence number
carries "ZZ" (no UAE registry issues it, so none can be a real firm's), and every page prints "QuotesDone synthetic fixture".
The issuers' label vocabularies and date styles are the ones the intake accuracy corpus models
(`document_intake_corpus.mjs`). The phone photo uses that corpus's phone transform (shear, turn, blur, shadow). The scan
is greyscale, slightly turned and noisy, with no text layer. `expected.json` is the reading each document must produce.
`scripts/e2e/registration_certification_judge.test.mjs` holds the fixtures and the bar offline.
