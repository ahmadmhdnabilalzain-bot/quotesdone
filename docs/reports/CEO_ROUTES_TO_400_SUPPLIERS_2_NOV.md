# Routes to 300-400 registered suppliers by 31 Dec 2026 (2 Nov 2026)

**Seat:** `ceo`. Read-only. Nothing was sent, bought, switched or applied. Founder rulings used: no ads (1456), suppliers always
English, WhatsApp opt-in only (1184, 1341), top-3, never name suppliers publicly, Apify paused to Feb 2027, no lawyer, UAE/GCC law only.
This extends `CEO_SUPPLIER_CHANNELS_2_NOV.md` (PR #1743) and `MICROSOFT_YAHOO_WIDE_SEARCH_2_NOV.md` (PR #1755). It does not repeat them.

Labels: **[measured]** read from production on 2 Nov; **[sourced]** from a page named here; **[assumption]** mine, no data behind it.
No conversion rate below is measured except the email one, and that has n = 1.

## Verdict

**300 to 400 is not reachable on the evidence we have. The number I would commit to is about 80 registrations by 31 Dec, with a
plausible range of 15 to 220.** The range is wide because only one conversion is measured (1 start in 45 delivered emails, 0 finished).
The central case needs every route below to start and the first phone pilot to work. The high case (about 220) is still under 300.
To reach 300 from the pool we can actually contact, about 14% of everyone reached would have to register. Measured: 0 of 45.

The first measured week fixes the number. A decision rule is at the end.

## Measured pool (production, 2 Nov)

Real leads: not demo, not merged, not closed, not banned.

| Reading | Count |
|---|---:|
| Leads with an email | 20,272 (the founder's 17,401 is a different cut; I could not match it) |
| With any phone / UAE mobile (+9715) / UAE landline | 4,971 / 2,861 / 2,105 |
| A mobile and an email | 2,861 (every mobile lead also has an email) |
| `whatsapp` field filled | 1,266 |
| LinkedIn URL / Instagram / website | 1,177 / 2,416 / 11,321 |
| Consumer-mailbox email (gmail, yahoo, hotmail, outlook, live, aol, icloud) | 4,167 |
| Invited / clicked / claimed / submitted / approved | 241 / 1 / 1 / 0 / 0 |
| WhatsApp opt-ins / consent asks / marketing consents | 0 / 0 / 0 |
| Email checks: verified / rejected / retry | 628 / 145 / 3 (776 checked of 20,272) |
| Buyer inquiries, ever / last 30 days | 3 / 0 |

**Where the phones are.** The three biggest segments have no phone at all: general 3,442, building materials 2,757, contractor 2,613
leads, 0 phones in each. Phones sit in ten trades. Mobiles / phones: painting 343/558, security 284/475, landscaping 227/357,
signage 219/356, flooring 214/304, upholstery 192/243, wallpaper 146/208, gypsum 143/232, fitout 138/271, safety 131/368.
Those ten hold 2,037 of 2,861 mobiles and 3,372 of 4,971 phones. Phone and WhatsApp routes therefore reach finishing and
fit-out trades only. MEP, building-materials and contractor leads are email-only.

## Routes, ranked

"Needed rate" is registrations required for 300 from that route alone divided by what it can reach. "Registrations" are by 31 Dec,
low / central / high, **all assumptions** except where a bound is measured. Routes overlap, so the sum double-counts and is capped below.

| # | Route | Reachable | Needed rate for 300 | Registrations (low / central / high) | Cash, AED | Who | Risk |
|---|---|---|---|---|---|---|---|
| 1 | Phone calls to known numbers | 4,971 numbers; at 60 dials a day for about 30 calling days, 1,800 dials; at 40% answered, about 720 conversations [assumption: 60, 40%] | 42% of conversations | 14 / 36 / 72 (2%, 5%, 10% of conversations [assumption]) | One caller for 2 months, about 7,000 [assumption, unquoted]; telephony unquoted | A human caller. No seat can place a call today | See legal below; the B2B scope is unconfirmed |
| 2 | Trade events | Big 5 says 50,000 to 65,000 visitors and 2,600 exhibitors [sourced, listings]; our trades are only part | not computable | 0 / 10 / 30 (30 to 150 conversations at 0 to 20% [assumption]) | 1,000 to 3,000 for badges, print, transport [assumption] | A person on foot. Founder or hire | None specific. A show-floor chat with consent is the cleanest opt-in we can get |
| 3 | Email, existing lane (Google class only) | 772 checked + 1,951 unchecked in the open class; the schedule allows 2,050 sends to 31 Dec [from #1743] | 15% of sends | 0 / 10 / 30. Ceiling 39 starts at the measured 1 in 45; completion of a start is unmeasured (0 of 1) | Verification vendor for 14,202 unchecked leads: quote first | Running (`sales_engineer` sends) | Bounce 7 of 52 over the limit; Microsoft and Yahoo junk (see #1755) |
| 4 | Chambers and trade associations | Dubai Chamber had 292,486 active members at end 2025, all trades [sourced: Gulf News, Gates Dubai]. Share in our trades not found. No public member directory found | unknown | 0 / 5 / 25 | Membership or sponsorship fee: not found, quote first | Founder opens the relationship | Chamber will not hand a list; PDPL |
| 5 | Referrals from registered suppliers | 0 registered today, so 0 now. Reachable = registered count at 1 Dec times referrals each | n/a | 0 / 5 / 15 (0, 0.2, 0.5 new registrations per early supplier, on 25 to 30 early ones [assumption]) | 0 to a small reward (ruling needed) | `it_engineer` builds the code, per #1743; `sales_engineer` asks | Low |
| 6 | LinkedIn organic, by a person | 1,177 leads carry a LinkedIn URL; company page has 66 posts, none in 30 days [from #1743] | 25% of URLs | 0 / 5 / 15 | 0 cash; about 2 hours a day of a person | A person. Automated messaging is forbidden | Account restriction if automated |
| 7 | WhatsApp templates to known numbers | **0 today** (0 opt-ins). Ceiling 2,861 mobiles after consent, 1,266 if only the `whatsapp` field | n/a | 0 / 5 / 15, and these are mostly the same people routes 1, 2, 3 produce | 0.18 per marketing message [vendor figure, Meta rate card unconfirmed]: at most about 515 for 2,861 | `sales_engineer` (templates are ours) | Meta: opt-in required; a cold send risks the sender quality rating and the one number support uses |
| 8 | Free directory and marketplace presence | Not measured | unknown | 0 / 3 / 10 | 0 | `marketing` (profiles), `it_engineer` (structured data) | Low |
| 9 | Inbound from the site | No visit data in the database; Vercel analytics not read | unknown | 0 / 2 / 5 | 0 | `it_engineer` | None |
| 10 | SEO supplier landing pages | Not measured | unknown | 0 / 1 / 5 by 31 Dec. New pages usually need longer than 8 weeks to rank [assumption] | 0 | `it_engineer` builds, `marketing` writes | None |
| 11 | Buying-side demand as the pull | **3 inquiries ever, 0 in 30 days** | n/a | 0. There is no demand to show a supplier | 0 | n/a | Do not claim waiting buyers: none are waiting |

**Total:** 14 / 82 / 222. Subtract overlap (one supplier met by a call, a show and an email counts once) and the figure to plan on is
**about 80, range 15 to 220**.

**Why #11 matters beyond the count.** `fn_match_capability` matches only suppliers who confirmed their scope, and the buyer side
is empty. The sharpest invitation we could send, "a buyer in your trade is waiting", is currently untrue. Say it only when it is
true. Ruling 1456 removes ads, so buyer demand has to come from unpaid routes too; none is measured.

## Dates checked by search

| Event | Date | Place | Fit |
|---|---|---|---|
| Gulfood Manufacturing | 3 to 5 Nov | Dubai World Trade Centre | Food manufacturing. Poor fit |
| Dubai Design Week (Downtown Design 4 to 8 Nov) | 3 to 8 Nov | Dubai Design District | Interior design, fit-out, upholstery, wallpaper, flooring. Starts tomorrow, too late to prepare |
| The Big 5 Global, with Middle East Stone inside it | 23 to 26 Nov | Dubai World Trade Centre | Best fit: building materials, MEP, finishing trades |
| Sign & Graphic Imaging ME | 7 to 9 Dec | Dubai World Trade Centre | Signage: 445 signage leads, 219 mobiles |

Not relied on: GITEX Global (not our buyers); its dates appeared as both 4 to 8 Dec and 8 to 11 Dec across sources, so I could not
fix them. The Hotel Show was 28 to 30 Sep, already past. I did not find other UAE construction or trade shows for Nov and Dec 2026,
and I did not search the other chambers (Sharjah, Abu Dhabi, Ajman, Ras Al Khaimah). Sources: the [Big 5 organiser](https://www.big5global.com/?p=64246),
[DWTC calendar via WAM](https://www.wam.ae/en/article/c1t9tuc-dwtc-announces-diverse-events-calendar-across-two),
[Dubai Design Week](https://www.dubaistandard.com/?p=39370), [Gulfood Manufacturing](https://www.foodtechbiz.com/events-list/gulfood-manufacturing-3-to-5-november-2026-at-dubai-world-trade-centre).

## Legal and platform checks

- **WhatsApp (Meta).** Already settled in #1743 and ruling 1341: a template goes only to a number that opted in to us. I did not find
  Meta's own wording on quality rating and messaging limits in this pass. The per-message price for the UAE marketing category is
  higher than most markets per Meta's pricing page; the AED figure is from vendor guides and they disagree, so check the rate card
  before budgeting. The template `supplier_invite` is not submitted yet.
- **Phone.** Cabinet Resolution 56 of 2024, effective 27 Aug 2024 per [Morgan Lewis](https://www.morganlewis.com/zh-cn/blogs/sourcingatmorganlewis/2024/07/telemarketing-in-an-evolving-legal-landscape-uae-adopts-regulations-on-telemarketing-activities)
  and [Clyde & Co](https://www.clydeco.com/en/insights/2024/07/uae-tightens-telemarketing-regulations-what-you-ne). Commentary says
  telemarketers need prior approval from the competent authority, must keep call records, must use local numbers from licensed
  providers, and must not call numbers on the Do Not Call Registry ([Tamimi](https://www.tamimi.com/news/new-uae-telemarketing-regulations-what-you-need-to-know/)).
  Fines sit in Resolution 57 of 2024; Clyde reports AED 50,000 for a first violation against registered consumers. The resolution's own
  text frames its scope around consumers, but **I could not read the official text (HTTP 403) and found no source that says business-to-business
  calls are in or out.** Unconfirmed. The pilot must not start until the authority's answer on approval is in hand. This is the main
  schedule risk for route 1.
- **PDPL.** Federal Decree-Law 45 of 2021, in force from 2 Jan 2022 per several secondary sources. Whether the Executive Regulations are in force
  is contradicted across sources and I found no primary citation. Unconfirmed. Practical reading for us: record where each contact came from
  and honour every stop. Marketing to a business email is already being done; this does not change it.
- **LinkedIn.** Automated messaging is forbidden (#1743). Every route 6 action is a person.

## Cost, one line

Cash I can name: callers about 7,000 and events about 1,000 to 3,000 [both assumptions, quote before spending], WhatsApp at most about 515.
Unquoted: telephony, email verification, chamber fee. Plausible cash total **about 10,000 AED plus the unquoted items**. Nothing is spent.

## What can start this week (3 to 8 Nov)

1. **Email, `sales_engineer` and `it_engineer`:** the placement verdict dates from 27 Oct and lapses after 7 days, so invitations hold from
   about 3 Nov unless GlockApps is retested. A retest costs one credit and needs a person to send; the CEO decides that credit.
2. **WhatsApp, `sales_engineer`:** submit the `supplier_invite` template to Meta. Cost 0. Sends nothing.
3. **Phone, CEO then founder:** ask the authority whether telemarketing approval and the Do Not Call list bind a call to a company;
   start the Twilio regulatory bundle for a company UAE number (founder documents). Nothing is dialled.
4. **Referral, `it_engineer`:** build the referral code, per #1743. No registered supplier exists yet, so it waits for the first.
5. **SEO and directories, `it_engineer` and `marketing`:** landing pages for the ten trades that carry phones, claim free profiles.
6. **Events, CEO:** prepare a QR to the sign-up page and the consent question for Big 5 on 23 to 26 Nov. Dubai Design Week is too soon.
7. **Chambers, founder:** one introduction to the Dubai Chamber business-development team. The CEO drafts the ask.

## Decision rule (CEO seat)

Run the first pilots, then decide on **16 Nov** using measured numbers only:
- 50 calls (once cleared): if registrations per conversation are under 2%, stop calls and re-plan; if 5% or more, add a second caller.
- Email: if starts per delivered stay near 1 in 45 and no start finishes, hold at the cap and spend nothing more on it.
- Referral and WhatsApp wait for the first 10 registered suppliers.
- Restate the 31 Dec number from measured conversion. If the measured central figure is under 100, say so to the founder plainly.

## What needs the founder

- Documents for the Twilio UAE regulatory bundle and a company number that is not his mobile.
- The Dubai Chamber introduction, and a ruling on a referral reward.
- One person for callers, events and LinkedIn, or approval of the cost once quoted. No seat can stand at a show or dial.
- A Microsoft 365 support ticket needs an admin sign-in (from #1755).

## Not measured

Site visit counts, conversion at every stage after a start, the share of Dubai Chamber members in our trades, other chambers' reach, and whether
telemarketing rules bind calls to companies.
