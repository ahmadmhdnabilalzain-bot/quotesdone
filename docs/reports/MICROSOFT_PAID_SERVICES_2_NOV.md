# Paid services that claim to fix Microsoft and Yahoo placement, 2 Nov 2026

Seat: `it_engineer`. Founder ruling, 2 Nov: "it's impossible there isn't a service that will fix Microsoft." This is the third pass after
`MICROSOFT_YAHOO_PLACEMENT_PLAN_2_NOV.md` (official documents) and `MICROSOFT_YAHOO_WIDE_SEARCH_2_NOV.md` (forums and community threads).
Those two did not look at vendors; this one does. **Read-only.** Nothing was bought, signed up for, sent or submitted, and no
GlockApps credit was spent. Prices are from each vendor's own page unless marked.

Source labels: **[official]** Microsoft's or the vendor's own statement; **[measured]** numbers someone measured and showed method for;
**[vendor claim]** a seller describing its own product; **[anecdote]** one customer or reviewer; **[unverified]** I could not read the
page or the figure came only from a search snippet or a competitor.

The case: M365 lane from `supplier@quotesdone.com` on Microsoft's shared IPs; SPF, DKIM and DMARC pass; SCL 5, BCL 0; 0 of 18 Microsoft
seeds and 0 of 17 Yahoo/AOL seeds in the inbox on 19 Oct, 27 Oct (twice); Gmail 20 of 20 inbox on 27 Oct 22:50. Low volume, cold
B2B, UAE, new domain.

## Verdict

**I found no paid service with measured, independent evidence that it moves a new cold B2B domain from Junk to Inbox at Outlook.com,
Hotmail, Yahoo or AOL.** The evidence for every service below is a vendor claim, a testimonial, or a vendor-run test. That is a
bounded statement: it covers the vendor pages and search results I opened on 2 Nov, not every service in the world, and not
private case studies a vendor may hold.

Four findings change what is worth paying for:

1. **Microsoft's own page says it works with exactly one third party on sender trust: Validity.** [Official](https://substrate.office.com/ip-domain-management-snds/Postmaster/Troubleshooting):
   Validity's Sender Certification "allows Outlook.com to exercise greater assurance about mail from certified senders in good standing".
   But the eligibility we could read rules us out (see Validity below), and on allow lists the same page answers "No" (read through a page summary; confirm before quoting).
2. **The cheapest Microsoft-side tools, SNDS and JMRP, need an IP we are responsible for.** SNDS access is requested "for the IPs for
   which you are responsible" and expires after 10 months without re-attestation ([official](https://substrate.office.com/ip-domain-management-snds/snds)).
   We send from Microsoft's shared IPs. Only an own-IP lane would unlock them.
3. **Changing the IP has already been tried and did not help.** The placement plan's history shows SES (via Resend), UAE Central and UAE North
   IPs all landed in spam (5 Oct: Microsoft 2/16, Yahoo+AOL 1/17; the comparison is imperfect: other copy, IP on a blocklist that day).
   So an own-IP lane is a poor first purchase for placement. It is only worth it to unlock SNDS and JMRP.
4. **Warm-up networks are the only product class that sells the thing the founder is asking for** (fix the domain's reputation at Microsoft).
   They are also the class that manipulates the filter and the one with the weakest evidence. Details below.

## Service by service

| Service | What it does | Price (vendor page) | Microsoft consumer-inbox claim and evidence strength | Cold B2B fit | Terms and risk |
|---|---|---|---|---|---|
| **Validity Sender Certification** (formerly Return Path) | Paid allowlist: Outlook.com gets a list of "responsible senders" from Validity | **Not published** on [validity.com](https://www.validity.com/everest/sender-certification/). A third-party review estimates [USD 5,000 to 15,000 a year](https://mailflowauthority.com/monitoring-analytics/validity-everest-review) **[unverified]**; another says price follows annual volume ([Suped](https://www.suped.com/learn/email-deliverability/is-return-path-certification-worth-it-for-email-deliverability), which sells competing software) | Microsoft confirms the partnership **[official]**; the effect cited is the "unknown sender" label and links/images on by default, not Junk-versus-Inbox. Validity's own marketing page names no provider and shows no result. Suped calls the Microsoft effect "receiver-specific" and Yahoo's "variable" | **No.** Per Suped's summary of Validity's rules: dedicated IPs used exclusively for 60+ days, at least 100 messages per IP to each of Microsoft and Yahoo in 30 days, "templated commercial or transactional mail for owned brands", corporate and 1:1 mail excluded, "clean permission". Validity's own requirements PDF was unreadable to me **[unverified]**. Shared IPs, a new domain and cold outreach all fail | Allowed, but we cannot qualify |
| **Sender Score** (Validity) | A reputation score, not a service that changes filters | Free tool **[unverified: not opened]** | None found | n/a | Measurement only |
| **SNDS and JMRP** (Microsoft, free) | Reputation data and junk-complaint feed per IP | Free | Diagnosis, not a fix | Needs an own IP | Requires IP responsibility, re-attested every 10 months **[official]**. JMRP's own page was not readable; Microsoft's troubleshooting page only says to update JMRP when IPs change **[partly verified]** |
| **Outlook.com sender support** (Microsoft, free) | Troubleshooting and a blocked-sender route | Free | [Official](https://substrate.office.com/ip-domain-management-snds/postmaster): "not intended to provide extensive support" | Weak | Free; already in the placement plan as action 9 |
| **Microsoft 365 admin support** | Tenant-side help: trace, high-risk pool, outbound limits | **Included** with a business subscription; technical support 24 hours a day, 7 days a week ([official](https://learn.microsoft.com/en-us/microsoft-365/admin/get-help-support)) | A Microsoft moderator already told a poster in the same situation there is usually no sender-side switch (wide-search report). Consumer junk filtering is a different system from the tenant | Tenant checks only | Free. Paid tiers: Azure "Professional Direct" is listed at USD 1,000 a month and is Azure-only; Unified is a custom quote **[unverified: search snippet only]**. I found nothing saying either covers Outlook.com junk filtering |
| **Folderly** | Warm-up network plus audits, monitoring and optional human consulting | [USD 96 per mailbox a month, yearly](https://folderly.com/pricing); Inbox Insights (placement tests): free 2 tests a month, USD 79 a month for 100, USD 799 a year; Pulse (monitoring): free | Page makes **no** Outlook claim and no guarantee; shows customer headlines such as "98% deliverability". A reviewer's four-week test reports about 96% primary inbox **[anecdote, reviewer sells a competing tool, unverified]** | Built for cold senders | Warm-up: see the warm-up note below |
| **MailReach** | Warm-up network of "Google Workspace and Office 365 inboxes", spam tests | [USD 19.50 per mailbox a month on monthly billing as the page reads](https://www.mailreach.co/pricing) (other sources say USD 25, **[unverified]**); spam tests priced by credit | Claims Outlook warm-up; one testimonial "35% to 92% within a week or 2" **[anecdote]**; "spam restoration is possible in 90% of cases" is a claim, not a guarantee | Built for cold senders | Warm-up note |
| **Warmbox** | Warm-up from a "private inboxes network" | [Solo USD 15 to 19 a month (1 inbox, 50 a day), Start-up USD 69 to 79, Growth USD 139 to 159](https://www.warmbox.ai/pricing) (page does not label which is yearly) | "Outlook Warm-up for Microsoft inbox"; results "usually take 15-30 days"; no numbers for Microsoft **[vendor claim]** | Built for cold senders | Warm-up note |
| **lemlist / lemwarm** | Warm-up bundled into the cold platform | [Email plan USD 69 a month, USD 55 yearly](https://www.lemlist.com/pricing); lemwarm included, no separate price | No Microsoft-specific claim | Built for cold senders | Warm-up note |
| **Warmy** | Warm-up from a claimed "1M+ mailbox network", 500K+ seed list that "opens, replies and moves out of spam" | [From USD 49 a month](https://www.warmy.io/pricing/) | B2B plan says primary inbox at Microsoft 365; B2C says Outlook. Page itself gives no method, no sourcing of mailboxes and no independent verification, and no guarantee **[vendor claim]** | Built for cold senders | Warm-up note |
| **InboxAlly** | A "seed network" that performs "seven distinct engagement actions" to lift mail out of spam | [USD 149, 645 or 1,190 a month](https://www.inboxally.com/pricing); 10-day free trial | Lists "Gmail, Yahoo, Outlook & more"; no Microsoft figure; says "2-4 weeks" for most domains, "4-8 weeks" for damaged or new ones; page does not say whether the seeds are real people **[vendor claim]** | Built for cold senders | Warm-up note |
| **Instantly** | Cold platform; Lightspeed plan includes SISR "dedicated/private server and IP blocks" | [Growth USD 47 a month; Lightspeed USD 358 a month, USD 286.30 yearly](https://instantly.ai/pricing); the page's own prices are internally inconsistent | No Outlook claim; "30% higher inbox placement" is unattributed **[vendor claim]** | Yes, built for it | Cold mail permitted by product design; IP lane already shown not to help us (finding 3) |
| **Smartlead** | Cold platform; SmartServers dedicated IP; SmartDelivery placement tests; resells Outlook mailboxes | [Base USD 39, Pro 94, Unlimited Smart 174, Prime 379 a month; SmartServers USD 39 per server a month (Pro); SmartDelivery USD 49 / 174 / 599](https://www.smartlead.ai/pricing). Outlook mailboxes USD 4.50 to 9 per mailbox a month | No Microsoft claim. The resold Outlook mailboxes are, as far as I can tell, ordinary M365 mailboxes on Microsoft's shared IPs, i.e. our lane **[unverified]** | Yes | Same as Instantly |
| **Postmark** | Transactional and marketing ESP | [USD 15 a month for 10,000](https://postmarkapp.com/pricing); dedicated IP only at 300,000 a month or more, Pro plan, USD 50 and up | The best independent-looking number is Mailtrap's own test: Outlook 100%, Hotmail 80% on the free tier ([Mailtrap](https://mailtrap.io/blog/transactional-email-services/), **[measured by a competitor, seed count not stated, transactional template]**) | **No.** [Terms](https://postmarkapp.com/terms-of-service): lists "must be permission-based", purchased or rented lists prohibited, complaint rate under 0.1% | Cold outreach breaches the terms |
| **Amazon SES** | ESP; dedicated IPs; Virtual Deliverability Manager | [USD 0.10 per 1,000; dedicated IP USD 24.95 a month standard, or managed USD 15 an account plus per-email fee; VDM from USD 0.07 per 1,000](https://aws.amazon.com/ses/pricing/); Enterprise gets one annual expert deliverability assessment | Page mentions no Microsoft product. Mailtrap's test: Outlook 100%, Hotmail 100% **[competitor-run, transactional]** | **No.** [AWS policy](https://aws.amazon.com/aup/) bars sending "unsolicited mass email" | Account suspension risk. Our own 5 Oct SES route scored 2/16 |
| **Mailgun** | ESP; dedicated IP; Optimize (inbox placement) | [Foundation USD 35 a month after a free month, Scale USD 90; dedicated IP USD 59 a month](https://www.mailgun.com/pricing/); Optimize and Deliverability Services (a TAM) are unpriced, quote only | No Microsoft claim. Mailtrap's test: Outlook 66.67%, Hotmail 40% **[competitor-run]** | Sources conflict on enforcement; the primary AUP was not read **[unverified]** | Treat as not allowed until the AUP is read |
| **SendGrid** | ESP | Plan and dedicated-IP prices **not on the page I could read** | Mailtrap's test: Outlook 0%, Hotmail 0% **[competitor-run]**. EmailToolTester's August 2026 test reports Postmark 93.8% and SendGrid 82% averaged over all providers, via secondary posts **[unverified]** | Secondary sources say affirmative opt-in required **[unverified]** | Not worth reading further |
| **Postbox Services** (consultancy) | Deliverability audit, retainers | [Audit from USD 500](https://postboxservices.com/services/email-deliverability/) (their FAQ: USD 500 to 5,000); retainers USD 99, 299, from 599 a month | FAQ covers "Outlook junk while Gmail is fine" and names SNDS, JMRP and SmartScreen. No result shown, no guarantee **[vendor claim]** | Yes, advisory | No terms issue |
| **InboxArmy** | Audits and remediation | Page: "Basic audits may start around USD 2K to 5K"; [Mailtrap lists audits from USD 3,000](https://mailtrap.io/blog/email-deliverability-agencies/) | Page does not name Microsoft or Outlook; claims no Microsoft relationship; no guarantee | Yes, advisory | No terms issue |
| **Inbox Monster** | Enterprise placement, reputation and spamtrap suite | [Deliverability suite from USD 15,000 a year](https://inboxmonster.com/pricing) | Page names no Microsoft product. "Up to 30% improvement in 30 days" appears only in Mailtrap's summary **[unverified]** | Enterprise scale | Out of proportion to our volume |
| **GlockApps consulting** | Hour-long consulting call | Pricing page lists consulting but **no price** ([page](https://glockapps.com/pricing/)); an old secondary figure of USD 300 and a partner (MailSoar) are **[unverified]** | None | Advisory | Our credits are the same vendor's |
| **Word to the Wise** (Laura Atkins) | Consulting, strategy, training | **No published rates**; [quote request](https://wordtothewise.com/) | No Microsoft statement and no guarantee on the page | Advisory | Highest practitioner standing of the group, but I have no price or evidence of Microsoft results |
| **Al Iverson (Spam Resource)**, **Mailmodo audit**, **Spam Experts / Mail Assure** | Not found: no rates for Iverson, nothing for Mailmodo. Mail Assure filters mail for the recipient or the sending MSP; I found no evidence it changes Outlook.com's verdict on our mail | **[unverified]** | None | n/a | Skipped |

### The warm-up note (applies to Folderly, MailReach, Warmbox, lemwarm, Warmy, InboxAlly)

Plainly: **these products manipulate the filter's engagement signals.** Vendor-controlled mailboxes receive your mail, then open it, reply,
and move it out of Junk, so that Microsoft's systems see engagement that no real recipient produced. That is the product. I found:

- **No Microsoft statement, for or against.** A search for one returned only vendor blogs. The authoritative pages are Microsoft's anti-spam
  policy and the Services Agreement, which bar spam ("unwanted or unsolicited bulk" mail) and reserve the right to stop service and block
  delivery. I found no source that names engagement networks.
- **No independent measurement** of Outlook or Hotmail results for any of them. Comparisons are written by competitors or by affiliates.
  One vendor's own docs warn that automated warm-up is risky, which is a competitor's claim and unverified.
- **A tenant risk specific to us.** `quotesdone.com` is also the company's real mail domain (MX at Microsoft). Microsoft
  says [one customer's spam can degrade the service, and it disables accounts above undisclosed limits](https://learn.microsoft.com/en-us/defender-office-365/outbound-spam-protection-about),
  and that bulk mail through Microsoft 365 "isn't a supported use of the service". Pushing automated traffic through the
  production tenant adds to that risk. **Do not run any warm-up network on `quotesdone.com` or its tenant.**
- If Microsoft discounts or penalises pool traffic, the domain can end up worse than it started. I could not find a documented case
  either way. That is a risk to state, not a measurement.

## Ranking: what is worth paying to try

| # | Option | Cost | Why this place | Evidence | Gate |
|---|---|---|---|---|---|
| 1 | **Free measurement layer.** Folderly Inbox Insights free tier (2 tests a month, [page](https://folderly.com/pricing)), Folderly Pulse (free), GlockApps' own free tier (2 credits, [page](https://glockapps.com/pricing/)) | USD 0 | A second seed network cross-checks GlockApps, whose seeds [read pessimistically where engagement drives placement](https://bird.com/blog/email-seed-list) (per the placement plan). Not a fix | Vendor tools | Needs an account: **founder or CEO seat** |
| 2 | **One-mailbox warm-up trial, one month, on a throwaway domain.** Warmbox Solo (USD 15 to 19) or MailReach (USD 19.50 to 25) on monthly billing, plus a domain (about USD 10 to 15, not priced here) | About USD 30 to 45 all in | The only product that sells what the founder asked for, at a price that does not matter. Tests the vendor's claim directly against the 0 of 18 baseline. Both vendors say 15 to 30 days, so read at day 28 | Vendor claim and anecdote | Account, payment and a domain: **founder**. Never on `quotesdone.com` or its tenant |
| 3 | **Postbox Services audit from USD 500** | USD 500 and up | The only paid human review with a price on its page and a Microsoft-specific FAQ (SNDS, JMRP, SmartScreen). Buy only if Credit A below says content, not the domain, is the problem | Vendor claim | Credit A result |
| 4 | **An own-IP lane** (SES standard dedicated USD 24.95 a month, Mailgun USD 59, Smartlead server USD 39) | USD 25 to 95 a month | Its only real value is unlocking SNDS and JMRP. As a placement lever it is the lowest-odds item (finding 3). SES and Postmark terms forbid our use | None | Not before items 2 and 3 |
| 5 | Folderly (USD 96 a mailbox a month), InboxAlly (USD 149 and up), Warmy (USD 49 and up), lemlist (USD 55 to 69) | USD 49 to 1,190 a month | Same mechanism as item 2 at higher prices; Folderly needs a yearly commitment | Vendor claim | Only if item 2 moves the seeds |
| 6 | Instantly Lightspeed (USD 358), Smartlead bundles | USD 39 to 379 a month | Cold-friendly platforms but no Microsoft evidence; the IP lane is already shown not to help | None | No |
| 7 | InboxArmy (USD 2,000 and up), Inbox Monster (USD 15,000 a year), Microsoft paid support (USD 1,000 a month, Azure-only) | USD 2,000 and up | Out of proportion and no Microsoft-specific evidence | None | No |
| 8 | Validity Sender Certification | Unpublished | We fail every eligibility line we could read | Official partnership, no result | **Not buyable** |

Free and already queued, not repeated here: the Outlook.com sender support request and the M365 admin-center request (placement plan
action 9). Both cost nothing and should go before any purchase.

## Cheap measurement plan with the 3 existing GlockApps credits

Each credit is one seed burst of 112 messages. The baseline already exists and costs nothing: **Microsoft 0/18 and Yahoo+AOL 0/17
on 19 Oct, 27 Oct 09:33 and 27 Oct 22:50 (Gmail 20 of 20 inbox on the last)**. Success is fixed in advance: Microsoft at least 9 of 18
in the inbox. Any movement from 0 is reported even if it misses the bar. This fits inside the placement plan's credit table (Credit 1 by 16 Nov,
Credit 2 about 30 Nov, Credit 3 reserved for the formal pass) and does not add a credit.

| Credit | Test | Reading |
|---|---|---|
| **A** (the plan's Credit 1 slot) | **Control: a plain one-to-one message with no offer, no list and no link**, from `supplier@` on the M365 lane, same pacing. Changes content only | Control also 0 of 18: the domain or tenant is the cause, content is not; do not buy copy services or the audit; go to B. Control lands at 9 or more: cold-offer signals are the cause; buy item 3 (the audit) and rewrite |
| **B** (the plan's Credit 2 slot, about 30 Nov) | **After day 28 of the item-2 trial:** the baseline offer copy, sent from the **throwaway domain** that was warmed. Free Folderly tests (item 1) on a second, **un-warmed** throwaway domain act as the control | Warmed domain at 9 or more and un-warmed at 0 to 2: the vendor claim holds for a fresh domain; decide whether to repeat it on the real domain through a subdomain (founder ruling, placement plan action 10). Both at 0: warm-up does nothing for Microsoft here; stop spending |
| **C** (reserved) | The formal ledger 1312 pass, unchanged | Only when B is 50% or better |

Cost: about USD 30 to 45 for the trial, USD 0 for A, USD 500 only if A points at content. Limits that stay true after the plan: the trial
proves the vendor works for a fresh domain, not for `quotesdone.com`; seeds never engage and read pessimistically; and Credit A tests
content on the existing lane, not a new lane.

## Which vendors promise a guarantee

**None of the vendor pages I read offers a money-back or inbox-placement guarantee.** The nearest are: MailReach's "spam restoration is
possible in 90% of cases" (a claim, not a guarantee), InboxAlly's "2-4 weeks" and "4-8 weeks" timelines, Warmbox's "15-30 days", and Inbox
Monster's "up to 30% in 30 days" (reported by Mailtrap, not on Inbox Monster's own page). I did not open refund or terms pages for every
vendor, so a guarantee in a contract is **[unverified]**. Treat any vendor that does promise Microsoft placement as a warning sign: Microsoft's
troubleshooting page answers "No" on allow lists, and the only trusted-sender route it names (Validity) is not a placement promise either.

## Not done, and why

- No account, trial, payment, quote request or contact form was used (read-only rule). Prices that need a quote (Validity, Word to the Wise,
  Mailgun Optimize, Microsoft Unified, GlockApps consulting) are unknown.
- Validity's requirements PDF and its community article could not be read; its terms are quoted second-hand from Suped, which sells
  competing software.
- SendGrid's price and policy pages, Mailgun's policy and JMRP's own page were not readable; those cells are marked.
- I did not re-open Microsoft's anti-spam policy page; its wording comes from the Services Agreement summary in search results and from
  the placement plan's citation.
