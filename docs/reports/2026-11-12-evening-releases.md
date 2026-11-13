# What went live on the evening of 12 Nov 2026, and what was proven

Written 13 Nov 2026, 00:40 UTC, by the it_engineer seat for the founder, and brought up to date at 02:00 UTC after
#1992 and #1993 went live. It follows
`2026-11-12-monday-readiness.md`, whose evening note says the first real phone test failed. This file is what was done
about that test and about everything else the founder found the same evening (ledger 1662 to 1672).

Words used here, as in the readiness report: a **demo company** is a made-up company we register ourselves to test
(its name starts "ZZ DEMO"; it is deleted afterwards and no real person is messaged). A **free run** has the paid AI
readers switched off. A **paid run** has them on.

The **local gate** is the check the session runs itself before a merge (`npm run gate`); no GitHub Actions run was used
(ruling 1648). It has 30 steps. Every gate named here was run in its offline form on the exact tree that was then
merged: the 17 steps that need no access to production all passed each time ("17 of 17" in the session's messages
means these). Once, for #1992, the website build step failed because a restart of the session's machine had
wiped its build folder; that one step was run again alone on the same tree and passed. The other 13 were not part of it: 12 read production, and one (the combined test run) is replaced by the
Deno test suite inside the 17 plus the node checks that name the files a change touched. After each release the
session ran the production check that matters most by hand: every deployed function compared with the repository
("parity", 79 of 79 at the end).

Other labels: **J1, J2, J6, J11** are the numbered test registrations of the certification (J1 a normal licence,
J2 the invitation link, J6 the public link, J11 a company profile in the licence slot). **PROBE OK** is the verdict
of a small database test that is run and rolled back after a database file is applied. The **ceo seat** is the AI
agent that takes what the other seats cannot decide. A **hash** of a text is a fingerprint that changes if one
letter of the text changes.

> **Correction, 13 Nov 2026, 04:40 UTC. One claim in this report was wrong.** It says "Download my data (PDF)" was
> walked signed-in on the live site twice and proven. The founder pressed it on his own iPhone at 07:49 Dubai time
> and got "Something went wrong". The PDF door had never worked in a real browser: the page sent a header the
> function's cross-site permission answer did not list, so every browser refused to send the request. Both walks
> drove the browser through a test tool that intercepts requests, which skips exactly that browser rule; the reviews
> and the session checked that the permission check answered, not what it allowed. Fixed by #1994 (live 04:32 UTC,
> main `286c72c2a`): proven this time from a plain browser with no interception, on both domains. What still stands
> from the rows below: the privacy fix to the export routine, the PDF's content and wording, the refusal after
> sign-out. The lesson is `.claude/memory/an-intercepted-browser-cannot-prove-what-a-real-browser-allows.md`.

## What the founder found, in his words, and where each stands

| Ledger | His words (shortened) | State at 02:00 UTC, 13 Nov |
|---|---|---|
| 1662 | "Couldnt register" (a valid licence refused as expired) | Live, #1978. His own re-registration read the licence in 9.1 s and was approved. |
| 1663, 1664, 1666 | The AI reads a licence, a profile and every chat; no "code first"; the bar is the model's own app | Standing rule. #1978, #1979, #1980, #1981 live. The audit is `2026-11-12-llm-first-audit.md`. |
| 1668 a | A company profile in the licence slot was not recognised | #1985 and #1992 live. Proven by a paid registration on the live site: "This looks like a company profile, not a trade licence…". Closed in the ledger. |
| 1668 b | Was registration really the sales engineer's? | Answered the same evening: it is recorded under that seat; the AI reads; the approval is a rule checklist. |
| 1668 c | "share my email with the customer" in Settings | Removed, #1984. Nothing ever read that switch; no e-mail was ever shared by it. |
| 1669, 1671 | "Download my data" gave raw JSON; it should be a PDF in our template | #1986, #1990 and #1993 live. A privacy leak in the old export was found and closed in the same change. Walked signed-in on the live site, twice. 1669 closed in the ledger. |
| 1670 | A real-estate company suggested as a "designer"; "phone not verified" after a WhatsApp code | Live, #1984. Closed in the ledger. |
| 1672 | No category picker, no typed company name; e-mail, mobile, terms with the IP address, then documents | Live, #1987. Proven by a paid run on both doors. |
| 1645 | "small or hidden text boxes … buttons not clickable … I'm looking for perfection" | #1989 live: 2 blockers, 13 should-fixes and 5 review items from a full walk of the supplier portal. Ten smaller items are listed in that PR for later. |

## The releases, in the order they went live

Each was reviewed by an agent that did not write it, checked by the local gate on the exact tree it was merged into,
merged by pull request, deployed by the session, and its database files applied and probed on the live database.

| PR | What | Database files applied |
|---|---|---|
| #1976, #1977 | Earlier the same evening (see the readiness report) | |
| #1978 | The model's reading of a licence is the reading; code no longer overrides it | |
| #1980 | A supplier's own typed words are understood by the model | |
| #1979 | The request chat understands the customer; Al Ain is matched as Abu Dhabi | |
| #1982 | An approved supplier keeps his standing while a new licence is read | `an_approved_supplier_whose_new_licence_is_never_read_goes_to_the_ceo_seat.sql` |
| #1981 | A quotation is read by the model and checked by code; an e-mailed quote is never submitted by itself | |
| #1984 | Roles suggested only from what the documents say; "Consultant" (no "designer"); "WhatsApp verified / phone not verified"; the e-mail switch removed | `the_consultant_role_is_called_consultant_not_designer.sql` |
| #1986 | "Download my data" as a PDF on our template; a copy holds only its owner's records | `a_copy_of_a_persons_data_holds_their_own_records_and_nobody_elses.sql`, `my_data_pdf_is_owned_by_customer_support.sql` |
| #1985 | A wrong document in the licence slot is named; a chamber certificate is never stored or approved as a licence | `a_chamber_of_commerce_or_a_residency_office_is_not_a_licensing_authority.sql`, `a_licence_file_is_filed_in_the_backup_only_once_it_is_read.sql` |
| #1989 | The supplier portal walk's defects | none |
| #1990 | The privacy probe catches two more kinds of leak; a burst of copy requests is counted one at a time | `a_burst_of_data_copy_requests_is_counted_one_at_a_time.sql` |
| #1988 | The manifest and two memory notes | none |
| #1987 | Sign-up asks the least; the company is named by its trade licence | `a_supplier_is_named_by_his_trade_licence_not_by_typing.sql`, `the_acceptance_certificate_follows_the_trade_licence.sql` |
| #1992 | A sure company profile, catalogue, quotation or ID in the licence slot is named, whatever licence details it quotes | none |
| #1993 | The data copy says only what is true: four defects found by walking it on the live site | none |

After the last one: main is `5ac05433f`, all 79 server functions match the repository, the website build is ready, and
every probe named above answers PROBE OK on the live database.

## What a supplier meets now, in order

1. His work e-mail, then the code from the e-mail.
2. "Opening your registration…", about a second. Nothing is typed: no company name, no category.
3. One form: his mobile, with the code by WhatsApp or by SMS.
4. The Supplier Agreement: his full name (first name and family name; a first name alone is refused in words), the
   tick, "Accept the agreement". The acceptance is recorded at once with the server's time, his IP address, the
   agreement's version and a hash of its text.
5. The trade licence. It is read in about 15 seconds and shown back: "Company (from your trade licence): …", with
   the number, authority and expiry. The signed certificate is then issued again in the licensed name.
6. The company profile, an optional trading name, optional catalogues, Submit.
7. The services step: what we read from his documents, to tick.

## What was proven on the live site, and how

| Check | Result |
|---|---|
| Paid registration, normal licence (J1), after #1985 and #1989 | Every step passed: licence read in 25 s, all five fields right, services proposed, approved and verified. USD 0.0085. |
| Paid registration through the new sign-up, public door (J6) and invitation door (J2) | Every step passed on both: a first name alone refused in words; accepted with the full name in 1.4 s; licence read in 14 to 16 s; the company shown and stored as the licence names it; approved and verified; portal home in about 2 s. |
| Paid wrong-document registration (J11), after #1992 | A demo company profile in the licence slot is answered "This looks like a company profile, not a trade licence. Please attach your trade licence here. Your company profile goes in the Company profile box below." Nothing of it stored as a licence; not approved. USD 0.0016. |
| Signed-in walk of "Download my data (PDF)" on the live site, demo supplier and customer, phone size and desktop, no model calls | Ready in 1.6 to 6.2 s; on the phone nothing downloads by itself and "Open your PDF" opens in the same tab; letterhead, the person's own details, Dubai time; the 4th request in 10 minutes refused in words; every call refused after sign-out; no other party's data. It found four low-harm defects, fixed by #1993; a second walk after that fix confirmed all four on the live site ("We have no record of any e-mail we sent you, other than one-time codes."; one documents list; "WhatsApp updates: Yes, on the same number as your mobile"; after the refusal both buttons keep their own words, disabled). |
| Paid accuracy run of the reader: 63 synthetic documents, 80 model calls, AED 0.3061 | Sure non-licences named a wrong document: 6 of 6. Licence-like non-licences (a chamber certificate, an establishment card) never stored as a licence: 2 of 2. Licences refused as a wrong document: 0 of 50. Licence number, legal name and expiry: 100% on the licences read. |
| The privacy probe on the live export routine | PROBE OK; all 13 deliberately leaky variants written by the author and the reviewer make it fail. |
| `my_data_pdf` called without a signed-in session | Refused. |

## What is NOT proven or not right, said plainly

- **A company profile that also prints a licence validity date is held for a person, not named.** The first paid
  wrong-document run showed the softer sentence for a demo profile: the reader had answered "company profile" with
  full confidence, but the rule refused to name any document from which an authority was read, and a profile often
  quotes one. #1992 fixed that. On the reviewer's advice one case is deliberately still held: when the reader read
  BOTH an authority and an expiry date, a licence page is probably inside the file (an ID scanned in front of the
  licence, a profile pack with the licence on page 6), so a person looks and the supplier is never refused.
- **Five of the 50 accuracy licences were held for a person**, and the reader's stated reason each time was that the
  file prints that it is a synthetic fixture and not a real licence. That is a property of our test files. It is not
  evidence about real licences either way.
- **Two parts of the accuracy suite are out of date** and are not counted as evidence: its approval stage does not
  write the issuing authority onto its demo rows (so it reports "authority unread" for 40), and its trade stage is
  older than this week's reader. Approval on the live site is proven by the paid registrations above instead.
- **The first attempts of two paid checks died in the test harness, not the product:** the accuracy suite on a stale
  line (one call, about USD 0.001), and the certification's "first name alone" was three words, which the live form
  rightly accepted. Both are fixed (#1988 and the closing bookkeeping change).
- **A held licence has no screen for accepting it.** When the reader cannot confirm a file is a licence, a task opens
  for the ceo seat at once, but accepting the licence is a database write. On Monday that needs a session on hand.
- **Real iPhone Safari** was not driven by us for the PDF download or the new sign-up: the founder's own phone is the
  proof. The signed-in walk above used the iPhone descriptor on Chromium, which is not Safari.
- **The founder's own company profile is still filed in Dropbox as "Trade licence"** from his test. His registration
  was not touched; removing that one file is his call.

## Money

The spend counter for this round read USD 10.262 at 01:56 UTC against the cap of USD 11 (ruling 1667); it counts every
model call on the platform since 11 Nov 18:00 UTC, not only tests. Tonight's paid checks: the accuracy run USD 0.083,
J1 USD 0.0085, the three sign-up journeys USD 0.0142, the diagnosis and confirmation of the company-profile case
USD 0.0024, the wrong-document registration USD 0.0016, and about USD 0.004 for the accuracy suite's failed first start
and the one-licence run that proved its fix.

## Left for after Monday, named so they are not lost

- An "accept this licence" action for a held file, in the admin area.
- The Dropbox label of a held file (filed as "Trade licence" after 15 minutes), and the supplier folder's category
  ("uncategorized": the trade-to-category mapping is the founder's to decide).
- The wording a held supplier sees after Submit ("we are still reading your trade licence").
- Professional, industrial and tourism licences named in the reader's instructions.
- An Arabic-only licence: the generic line after a reload, and the Documents tab door.
- The accuracy suite's approval and trade stages (a company profile that quotes licence details is now in its corpus).
- Certificates and project references in the data copy's documents list (the copy says where they are instead).
- The machine-readable JSON file still offered beside the PDF: the founder's call whether it stays.
- The PDF footer prints two WhatsApp numbers for QuotesDone while the portal's help line shows none.
- The ten smaller items of the portal walk listed in #1989.
