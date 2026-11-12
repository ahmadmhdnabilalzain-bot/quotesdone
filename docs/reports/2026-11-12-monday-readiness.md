# Where supplier registration stands for Monday 16 Nov 2026

Written 12 Nov 2026 by the it_engineer seat for the founder (rulings 1645, 1646, 1647). The final audit is in
`2026-11-12-final-audit.md`; the reports written while fixing are in `fix-round-2026-11-12/`.

## The link to text

`https://quotesdone.com/portal?join=1`

Opened on the live site on 12 Nov in an emulated iPhone 13 with a fresh profile: "Register as a supplier" in 1.8 s, the
Work email box in view at 16 px. `/portal` alone opens on "Sign in".

## What a supplier meets now, in order

1. **Create account.** E-mail, a code by e-mail, the code box. A moving ring on every submit.
2. **Company.** The legal name. A company that is already in our listing gets its own new row and the listing is flagged
   for the it_engineer seat to merge; nobody can take a listing by typing its name.
3. **Trade licence.** A photo from the phone or a PDF. Files of 3 MB or less go as they are; a larger photo is scaled to
   3,000 px (a 17 MB photo becomes about 0.9 MB). A percentage moves while it uploads, with Cancel beside it. The number,
   authority and expiry we read are shown back in a panel.
4. **Mobile and WhatsApp**, the company profile, the emirates, the Supplier Agreement, Submit.
5. **Services.** "Here is what we understood your company does": two sentences about his company, then his services
   under his own sentences. One tap confirms the certain ones. Then up to five question cards for what his documents left
   vague, then a check screen where anything can be taken out.
6. **Portal home.** "Registration received" and what, if anything, is needed from him.

## What was changed on 12 Nov, all live

| PR | What |
|---|---|
| #1951 | Two reads of one supplier's documents never overwrite each other; a late licence read is shown. |
| #1952 | A step a person waits on uses the highest thinking effort that fits that wait (amends ruling 1630). |
| #1953, #1954, #1958 | WhatsApp: the holding line once, support cases, case summaries; a person is answered once. |
| #1955 | Quoting: brand hiding and money reading held by permanent test sets (971 and 207 rows). |
| #1956 | Operations: hourly duties on their own clock, person mail within a minute, demo cases purged, the Stripe live hold. |
| #1957, #1959, #1962, #1967, #1960 | Supplier profiling, ruling 1647: the whole catalogue is read; 47 new services; a profile is read first and mapped second; question cards; a partner service is matched knowingly. |
| #1961 | The portal home does one read fewer in a row. |
| #1963 | WhatsApp wording after the paid re-check; the two speed cuts were proven unsafe and reverted. |
| #1964, #1966, #1968 | The portal shell and the registration form after the browser walk (ruling 1645). |
| #1969, #1974 | The registration certification judges the new screens; one failed step now stops "ready to invite". |
| #1971 | The cookie notice is one row at the top on a phone and never covers "Create my account". |
| #1972 | After submitting, the supplier lands on the services step, and the card above says what is true. |
| #1973 | The matching step of the profile reading thinks at the effort that fits the wait. |
| #1950, #1965 | The audit and fix-round reports; the repository says what production holds (0 drift either way). |

Twenty-three pull requests, no GitHub Actions run (ruling 1648). Each was reviewed by an independent agent that ran the real
code path, and gated locally. On every branch that looked finished the review found at least one defect its author's tests
had not: a licence file moved by a background sweep, a loading ring the portal's own stylesheet made invisible, a claim by
name that would have let a hand-made request take a real company's listing, a registration call that would have thrown on
every company name, a WhatsApp draft sent in place of the database's answer, a ticked service saved as "through a partner".

## What was proven on production, and how

- **Free production runs (models off, ZZ DEMO companies only, torn down after).** 12 Nov 10:20 UTC, run ef32843a, after
  #1964 and #1966: five demo companies created an account, received the code by e-mail (accepted by the mail provider 1.1 to
  3.1 s after the click), created their company or claimed their invited listing, uploaded a licence, submitted and reached
  the workspace; the loading ring was photographed turning on every journey. 12 Nov about 11:10 UTC, run 88b2a67b, after
  #1967, with the corrected script: two companies (desktop and phone), no failed step; the licence was read and shown back
  in 8.9 s and 6.2 s with the right number and authority; five services ticked and confirmed, the company approved and
  verified. With models off the profile reading and the question cards do not run: those rows are "NOT RUN", never "PASS".
- **The first run also showed our own instrument was stale.** The certification still looked for the licence text boxes
  #1966 had replaced and judged a correct screen wrong. Fixed in #1969, whose review then found that the script's final
  verdict ignored failed steps altogether. That is being closed before any paid run is read as a certificate.
- **The live link**, as above.
- **The paid check of the founder's two examples, 12 Nov 12:16 to 12:23 UTC** (run e9cea0c7; the readers on; two ZZ DEMO
  companies; USD 0.024 for 10 model calls; torn down clean, no message left for any person). 59 steps passed, 3 failed.
  - *The decoration company (interior decoration, landscaping, pools through a partner), desktop.* The licence was read
    and shown back. Its profile produced 28 services under its own sentences, none ticked for it, with "Not on your trade
    licence", "Please check" and "Your words" badges. The partner card was asked, quoting its own sentence about "Blue
    Lagoon Pools, under our supervision", and "through a partner" was stored for the three pool services. Every answer was
    stored (15 services, 3 of them partner work); nothing it had not tapped was saved or matched; approved and verified.
    **Failed: speed.** The list was on screen 124 s after the upload against a 120 s bar (the first read took 68 s, the
    slowest matching call 56 s).
  - *The manpower company ("we supply staff and similar services"), phone.* The reading proposed no trade from so vague
    a profile and asked instead: "What types of staff do you supply?" with 18 choices, among them general labour,
    professional staff on contract, and freelancers and independent contractors. Six answers, all stored; approved and
    verified; registration took 3.4 minutes. One step was marked failed by the script, not the product: it expected a
    trade among the proposals, which a vague profile rightly does not give. The script is being corrected (PR #1969).
  - *What the real screenshots showed that the walks had not:* on a phone the supplier lands on the Services tab under a
    "Profile score" card of five buttons, so the step he must do starts two screens down; and the card above says "Nothing
    is needed from you" while his services wait to be confirmed. Both are being fixed. The two-sentence summary of his company
    is drawn as soon as the first read is stored (68 s on the decoration profile); the script had not been looking for
    that interim view and timed the summary at the full list, which is corrected in PR #1969 and to be measured again.

- **After the last fixes, one company only (ruling 1660: a paid test checks only what changed), 12 Nov 14:12 UTC**, the
  decoration company again, USD 0.016. The supplier landed on "Registration received. One step left: confirm your
  services below.", one row of tabs, and the services step with its summary directly under them; the profile score is
  below. 26 services proposed, none ticked; the partner card asked and stored; nothing untapped saved; approved and
  verified. **Speed after #1973:** the summary was on screen at 95 s, the list was stored at 117 s and on screen at 130 s,
  10 s over the 120 s bar. About 13 s of that is the page noticing the list is ready, which is being cut at no cost
  (branch `sales_engineer-the-list-is-shown-the-moment-it-is-stored`). The first read itself varies between 68 and about
  90 s; making it faster means changing how the profile is read, which needs a new recording and measurement money, and
  reading well matters more than those seconds (ruling 1647). The supplier is told "This takes one to two minutes; you
  can carry on and come back", and sees the summary first.
- **The first screen, live, as a first-time phone visitor at 360x640, 390x664 and 390x844** (free): "Register as a
  supplier" in 1.0 to 1.6 s, the cookie notice a 61 px row at the top, "Create my account" fully visible and uncovered.

## What is NOT proven, said plainly

- **A real iPhone.** Everything above was driven in headless Chromium at phone sizes. Safari on an iPhone can differ in
  four places we could not test: the keyboard rising when a field is focused, a HEIC photo chosen from the Files app, an
  upload on a weak line (the send buffer), and the keyboard over the "Something else" field on a question card.
- **The full certification, by decision.** The "ready to invite" bar was twelve demo companies registered twice with the
  paid readers on. The founder ruled on 12 Nov (ledger 1660) that a thing already proven is not paid for again and the
  cap is not raised. So it is met by accumulated evidence instead: the flow by the free runs, the two founder examples
  by one paid run each, and each later change by the smallest check that shows it. Total model spend of this round:
  about USD 9.75 of the USD 10 cap.
- **WhatsApp reply speed.** The ordinary reply measured about 27 s behind the holding line before today's wording fixes;
  it has not been measured since, and the cuts that would have made it faster were wrong and are out.
- **Service-level correctness on real profiles.** The reading was measured on sixteen recorded hard profiles (97 of 111
  services listed, 2 wrong trades of 65, wrong services arrive unticked). On production it has been exercised only by
  the paid check above.

## Known small things left

- On the "different number" WhatsApp path the page moves once when a correct code lands.
- The Insights tab shifts once while it loads; a new supplier has nothing to press there.
- 874 services have no plain-word name beyond their label. A file of 3,501 names is written and held (PR #1970) until
  its effect on matching is measured: its first version had about 5 wrong names in 100, and a wrong name is hard to undo.
- Supabase holds edge-function calls for 1.6 to 4 s in the first seconds after each five-minute mark
  (`fix-round-2026-11-12/five-minute-mark-relay-hold.md`). The portal home can open slowly at those moments.

## Decisions that are the founder's

1. **Paid testing: decided 12 Nov (ledger 1660).** The cap stays at USD 10. Proven once is proven; a paid call checks one
   changed thing on the smallest input. Not measured for want of budget, and left so: WhatsApp reply speed (about
   USD 0.70) and the alias file's effect (about USD 0.20, PR #1970).
2. **Reroute the portal home's first read around the five-minute hold** (1.5 to 2 days of work), and through which
   channel the note to Supabase support should go.
## What we ask of the founder before Monday

Register one test company on your own iPhone from the link above, in Safari, on mobile data, with a photo of a licence
taken by the phone. Ten minutes. Tell us anything that is small, hidden, slow, jumps, or does not respond.
