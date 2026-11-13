# Where supplier registration stands for Monday 16 Nov 2026

Written 12 Nov 2026 by the it_engineer seat for the founder (founder rulings 1645, 1646, 1647, 1660), and brought up to
date at 17:30 UTC the same day after #1975 and #1976 went live and after the founder's summary of ruling 1661 was
answered. The audit that came before is in `2026-11-12-final-audit.md`; the reports written while fixing are in
`fix-round-2026-11-12/`.

> **Later the same evening (from 17:25 UTC): the first real phone test failed, and what follows was written before it.**
> The founder registered a company of his own from his iPhone. The portal refused it as "expired on 30 Oct 2026"; the
> licence is valid to 29 Oct 2027. Our code had read a wrong date and overrode the AI's reading (ledger 1662). He ruled
> that the AI reads a licence, a company profile and every chat, and that code does not interpret first (1663, 1664,
> 1666). No demo company had caught it, and no other real supplier was affected. The fix is PR #1978; the audit of every
> other place where code decided meaning is `2026-11-12-llm-first-audit.md`, with PRs #1979 and #1980. Until #1978 is
> live and his own re-upload reads correctly, the sentence "what a supplier meets now" below is not true for the trade
> licence step on a Dubai Economy and Tourism licence, and nobody should be invited.
>
> **13 Nov, 00:40 UTC: what was done about it is in `2026-11-12-evening-releases.md`.** #1978 is live and his own
> re-registration read the licence correctly and was approved; ten more changes followed the same evening, including
> the shorter sign-up he asked for (ruling 1672). The order "what a supplier meets now" below is superseded by that file.

Words used here: a **demo company** is a made-up company we register ourselves to test (its name starts "ZZ DEMO"; it
is deleted afterwards and no real person is messaged). A **free run** registers demo companies with the paid AI readers
switched off, so it tests the screens and the flow but not the reading; steps that need the reader are marked
"not run", never "passed". A **paid run** has the readers on.

## The link to text

`https://quotesdone.com/portal?join=1`

Opened on the live site on 12 Nov as a first-time visitor on three phone screen sizes: "Register as a supplier" appears
in 1.0 to 1.6 seconds, the cookie notice is one row at the top, and the Work email box and "Create my account" are fully
visible. `/portal` alone opens on "Sign in".

## What a supplier meets now, in order

1. **Create account.** E-mail, a code by e-mail, the code box. A moving ring on every submit.
2. **Company.** The legal name. A company that is already in our listing gets its own new row, and the listing is
   flagged for us to merge; nobody can take over a listing by typing its name.
3. **Trade licence.** A photo from the phone or a PDF. Files of 3 MB or less go as they are; a larger photo is made
   smaller first (a 17 MB photo becomes about 0.9 MB, still readable). A percentage moves while it uploads, with Cancel
   beside it. The number, authority and expiry we read are shown back.
4. **Mobile and WhatsApp**, the company profile, the emirates, the Supplier Agreement, Submit.
5. **Services.** He lands on "Registration received. One step left: confirm your services below." Then: two sentences
   on what we understood his company does, and his services listed under his own sentences, none ticked for him. One
   tap confirms the certain ones. Then up to five short questions for whatever his documents left vague, then a check
   screen where anything can be taken out.
6. **Portal home.** What, if anything, is still needed from him.

## What changed on 12 Nov

Twenty-six pull requests were merged and put live (#1950 to #1976, less #1970, which is held). After the last one, the
live database matched the repository with no difference either way, all 78 server functions matched the repository, and
the link above was opened again on the live site at three phone sizes with nothing covering "Create my account".
No GitHub Actions run was used (ruling 1648): the session ran the checks, applied the database files and deployed.

| PR | What |
|---|---|
| #1951 | Two reads of one supplier's documents never overwrite each other; a late licence read is shown. |
| #1952 | A step a person waits on thinks as hard as fits that wait (amends ruling 1630). |
| #1953, #1954, #1958 | WhatsApp: the "one moment" line once, support cases, case summaries; a person is answered once. |
| #1955 | Quoting: brand hiding and money reading held by permanent test sets (971 and 207 rows). |
| #1956 | Operations: hourly duties on their own clock, mail to a person within a minute, demo cases purged, the Stripe live hold. |
| #1957, #1959, #1962, #1967, #1960 | Reading a supplier's profile, ruling 1647: the whole catalogue is considered; 47 new services; a profile is read first and matched second; the questions; a service done through a partner is matched knowingly. |
| #1961 | The portal home does one read fewer in a row. |
| #1963 | WhatsApp wording after the paid re-check; two speed shortcuts were proven unsafe and removed. |
| #1964, #1966, #1968 | The portal shell and the registration form after the browser walk (ruling 1645). |
| #1971 | The cookie notice is one row at the top on a phone and never covers "Create my account". |
| #1972 | After submitting, the supplier lands on the services step, and the card above says what is true. |
| #1973 | The matching step of the profile reading thinks at the effort that fits the wait. |
| #1969, #1974 | The registration test judges the new screens; one failed step now stops it saying "ready to invite". |
| #1975 | The services list is on screen about two seconds after it is ready (in testing against a stand-in server), where the page used to take about thirteen to notice. |
| #1976 | The services step is never redrawn by an older answer and never stays on "reading"; a list ticks the same rows whether it arrives live or after a reload, and nothing is ticked for him; his own phrases are readable on a phone and to a screen reader while he waits. |
| #1950, #1965 | The reports, and the repository's record of what the live database holds (checked: no difference either way). |

Each change was reviewed by an independent agent that ran the real code, and checked locally before merging. On every
branch that looked finished the review found at least one defect its author's tests had not: a licence file moved by a
background job, a loading ring the portal's own styling made invisible, a way to take a real company's listing by
typing its name, a registration call that would have failed on every company name, a WhatsApp answer sent before the
database's real answer was read, a ticked service saved as "through a partner", a page that jumped under the thumb at
Confirm.

## What was proven on the live site, and how

- **Free runs.** 12 Nov 10:20 UTC (after #1964 and #1966): five demo companies created an account, received the code
  by e-mail, created their company or claimed their invited listing, uploaded a licence, submitted and reached the
  workspace; the loading ring was photographed turning. 12 Nov about 11:10 UTC (after #1967): two demo companies, desktop
  and phone, no failed step; the licence was read and shown back in 8.9 and 6.2 seconds with the right number and
  authority; services ticked and confirmed; approved and verified.
- **The founder's two examples, paid, 12 Nov 12:16 UTC** (USD 0.024 for 10 AI calls). 59 steps passed, 3 failed.
  - *The decoration company (interior decoration, landscaping, pools through a partner).* 28 services listed under its
    own sentences, none ticked for it, each marked where it was not on the trade licence or needed a check. It was asked
    about the pools, quoting its own sentence about its pool partner, and "through a partner" was stored for the three
    pool services. Every answer was stored (15 services, 3 of them partner work); nothing it had not tapped was saved
    or used for matching; approved and verified. **Failed: speed.** The list was on screen 124 seconds after the upload,
    against a bar of 120.
  - *The manpower company ("we supply staff and similar services").* The reading proposed no trade from so vague a
    profile and asked instead: "What types of staff do you supply?" with 18 choices, among them general labour,
    professional staff on contract, and freelancers and independent contractors. Six answers, all stored; approved and
    verified; the whole registration took 3.4 minutes. One step was marked failed by our test, not by the product: it
    expected a trade among the proposals, which a vague profile rightly does not give. The test was corrected (#1969,
    #1974).
  - *What the real screenshots showed that earlier checks had not:* on a phone the supplier landed under a "Profile
    score" card of five buttons, with the step he must do two screens down, and a card saying "Nothing is needed from
    you" while his services waited. Both were fixed the same day (#1972), and so was a cookie notice that covered half
    of "Create my account" on a first visit (#1971).
- **After those fixes, one company only, paid, 12 Nov 14:12 UTC** (USD 0.016; ruling 1660: a paid test checks only what
  changed). The decoration company again. It landed on "Registration received. One step left: confirm your services
  below.", one row of tabs, and the services step directly under them. 26 services proposed, none ticked; the pools
  question asked and stored; nothing untapped saved; approved and verified. **Speed after #1973:** the two-sentence
  summary was on screen at 95 seconds, the list was ready at 117 seconds and on screen at 130 seconds, 10 seconds over
  the bar. About 13 of those seconds were the page noticing the list was ready. #1975 removed them: against a stand-in
  for the server the list was on screen a median of 0.7 to 1.7 seconds after it was stored (worst of nine runs, 2.9). That
  puts the whole wait at about the 120-second bar, not clearly under it, and it was not measured again with a paid run
  (ruling 1660).

## What is NOT proven, said plainly

- **A real iPhone.** Everything above was driven by a test browser set to phone sizes. Safari on a real iPhone can
  differ in four places we could not test: the keyboard rising when a field is tapped, a photo in Apple's HEIC format
  chosen from the Files app, an upload on a weak signal, and the keyboard over the "Something else" box on a question.
  The founder is registering a company of his own to test exactly this.
- **The full "ready to invite" test, by decision.** It was to be twelve demo companies registered twice with the paid
  readers on. The founder ruled on 12 Nov (ruling 1660) that a thing already proven is not paid for again, and the cap
  is not raised. So readiness rests on the evidence above: the flow by the free runs, his two examples by one paid run
  each, and each later change by the smallest check that shows it.
- **Reading time on a rich profile.** About two minutes. The first read alone took between 68 and about 90 seconds on
  the decoration profile. Making it faster means changing how the profile is read, which needs new measurement and
  could cost reading quality; reading well matters more than those seconds (ruling 1647). The supplier is told "This
  takes one to two minutes; you can carry on and come back", and sees the summary first.
- **WhatsApp reply speed.** About 27 seconds behind the "one moment" line when last measured, before today's wording
  fixes. Not measured since: it would cost about USD 0.70.
- **Whether each listed service is right on real suppliers' profiles.** The reading was measured on sixteen recorded
  hard profiles (97 of 111 services listed, 2 wrong trades of 65; a wrong service arrives unticked). On the live site
  it has been exercised by the paid runs above only.

## Money

Paid testing in this round: about USD 9.75 of the USD 10 cap (ruling 1608). All AI spend on 11 and 12 November,
including the company's own running: USD 10.40. Recorded AI spend: October USD 182; 1 to 12 November USD 147, of which
USD 100 on 2 and 3 November alone, on tests that re-proved the whole system. On days with no test the company runs for
USD 0.40 to 2.30 a day. The rule since ruling 1660 is in `.claude/memory/a-paid-test-checks-only-what-changed.md`.

## Known small things left

- On the "different number" WhatsApp path the page moves once when a correct code lands.
- The Insights tab moves once while it loads; a new supplier has nothing to press there.
- 874 services have no everyday name beyond their label, so some of a supplier's own words stay as his words instead
  of becoming a service we can match. A file of 3,501 names is written and held (PR #1970): its first version had about
  5 wrong names in 100, and a wrong name is hard to undo. It waits for a before-and-after measurement.
- Our hosting provider holds requests for 1.6 to 4 seconds in the first seconds after every fifth minute of the hour
  (`fix-round-2026-11-12/five-minute-mark-relay-hold.md`). The portal home can open slowly at those moments.

## Not perfect, outside supplier registration

On 12 Nov the founder summed up: everything perfect, the code organised to software engineering standards, no long
lines, everything in step on GitHub (ruling 1661). Each part was measured the same day. What is not true, or not yet:

- **Long lines.** Counted on the code as it stood after #1976, leaving out test files, code copied in from other
  projects and files a program writes: in the website code 2,164 of 39,157 lines are longer than 160 characters, and
  332 are longer than 300; in the server functions 5,393 of 101,660 are longer than 160, and 754 longer than 300. That
  is about 5 lines in every 100 in both. The largest website file is 947 lines and the largest server file 1,188. The
  code works, is tested and every change is reviewed, but an outside engineer will find dense long lines hard to read.
  (The founder was first given "5,519 of 133,284" for the server functions on 12 Nov. That count could not be
  reproduced by an independent check and is replaced by this one; the conclusion is the same.)
- **Twilio message templates.** One supplier notice template (`supplier_account_notice`) has failed since 5 October,
  and the template for the sign-in code is missing. Not fixed.
- **The customer side.** It was audited and the quoting fixes went live (#1955), but the customer journey was not walked
  again end to end after the day's changes.
- **Housekeeping not done:** 498 quote PDFs that belong to no quote are still stored; the monthly scheduled routine's
  setup step; the test of the voice transcription provider.

GitHub and the live system were in step when checked after #1976: the database with no difference either way, and 78
of 78 functions. Earlier the same day 10 functions had been one shared file behind the repository, with no difference
in behaviour; they were redeployed.

## Decided, and still to decide

- **Decided 12 Nov (ruling 1660):** the paid-test cap stays at USD 10. Proven once is proven; a paid call checks one
  changed thing on the smallest input.
- **Still the founder's to decide:** whether an automatic formatter is run across the whole code after Monday's first
  registrations settle, in one dedicated change, with a rule that stops long lines coming back. It costs no AI spend but
  touches almost every file, so it should not happen in the days around the invitations. The it_engineer seat
  recommends yes, after Monday.
- **Still the founder's to decide:** whether to route the portal home's first read around that five-minute hold (1.5 to
  2 days of work), and through which channel the note to the hosting provider's support should go.

## Monday

Text three to five suppliers first, in the morning. Their registrations are watched as they happen. Send the rest in
the afternoon. Demo companies cannot stand in for the first real ones.
