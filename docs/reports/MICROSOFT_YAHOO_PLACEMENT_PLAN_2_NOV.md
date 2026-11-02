# Microsoft and Yahoo placement plan, 2 Nov 2026

Seat: `it_engineer`. Founder ledger 1445: Microsoft and Yahoo must stop being spam; find a solution, not an explanation.
This session changed nothing on production and sent nothing. Read-only sources: GlockApps connector, production
`select`s, public DNS, RDAP.

## The answer

**No setting, ticket, new IP or paid service was found that moves Microsoft or Yahoo quickly.** Every Microsoft and Yahoo
source points to one thing: mail people asked for, that they answer, from clean addresses. So the plan is:

1. Stop the three things hurting us: bad addresses, seed bursts and sending cold to Microsoft.
2. Reach Microsoft-hosted suppliers another way, so that our first email to them is one they asked for or a reply.
3. Open the classes that do not depend on Microsoft: Google now, and Etisalat through a small measured pilot.
4. Hold all 3 GlockApps credits until there is something new to measure.

**Honest outlook (my estimate; no source gives a timeline):** the 80% Microsoft bar will probably not be met by the end
of November and may not be met in 2026. See [What is achievable by when](#what-is-achievable-by-when).

## Ranked actions

Costs are list prices from secondary sources unless marked otherwise; check them before paying.

| # | Action | Expected effect and source | Cost | Who | How it is proved |
|---|---|---|---|---|---|
| 1 | **Clean the list before the next send.** 13.5% of real sends bounced (7 of 52, as briefed). Hold `supplier_invite` rows (18 were queued today) until each address passes a verification service; suppress the rest. Target under 2%, the warm-up plan's own bar. Also check why the same-day brake (3+ bounces at 5%+) did or did not fire. | Bad addresses put outbound mail ["at risk for further scrutiny"](https://learn.microsoft.com/defender-office-365/external-senders-mail-flow-troubleshooting). [Yahoo](https://senders.yahooinc.com/best-practices/) also says to remove invalid recipients. | Verification vendor per-address fee, **not priced here**; a payment | sales_engineer (code); **founder or CEO seat approves the spend** | No credit: bounce rate in `notifications` |
| 2 | **Stop cold email to Microsoft and Yahoo; make the first contact elsewhere.** Keep the gate shut for them. Ask those suppliers by phone or an opted-in channel to register or write to supplier@ first, and send a confirmed opt-in from the site. supplier@ then replies. | Microsoft [recommends double opt-in](https://learn.microsoft.com/defender-office-365/external-senders-mail-flow-troubleshooting); Yahoo says to [send only to users who requested mail](https://senders.yahooinc.com/best-practices/); [Google agrees](https://support.google.com/a/answer/81126). Weak but on point: a [2023 M365 case](https://techcommunity.microsoft.com/discussions/exchange_general/%e2%80%8eall-outgoing-mail-from-microsoft-365-tenant-to-outlook-and-yahoo-mark-as-spam-a/3994239) saw new mail junked while replies reached the inbox. Reaches 1,959 Microsoft companies without a filter verdict. | Staff or call time; no licence | CEO seat decides; sales_engineer builds. WhatsApp only with [opt-in](../../.claude/memory/whatsapp-supplier-invites-need-an-opt-in.md) | Credit 1, plus supplier@ replies per Microsoft-hosted address |
| 3 | **Real two-way mail with people who know the company on Microsoft and Yahoo.** Existing supplier@ correspondents, registered suppliers and business contacts, never the founder's own inboxes. Each thread is genuine and answered the same day. Target about 30 threads a week, half or more on Microsoft. | Microsoft support community: [no sender-side reset; steady volume, no unsolicited test traffic, time](https://techcommunity.microsoft.com/discussions/microsoft-365/google-workspace-sender-stuck-at-scl5-to-all-microsoft-hosted-recipients/4534669). Recipient-side junk rescue is only useful if a person does it. | Free | CEO seat picks who; supplier@ mailbox answers. **The list needs names only a person can give** | Credit 1 |
| 4 | **Stop spending seeds.** 423 of the 475 external campaign sends ever made (89%) were seeds that never engage. No test until the date below. | [Same thread](https://techcommunity.microsoft.com/discussions/microsoft-365/google-workspace-sender-stuck-at-scl5-to-all-microsoft-hosted-recipients/4534669). Seeds also [read pessimistically where engagement drives placement](https://bird.com/blog/email-seed-list); [Braze makes the same point](https://community.braze.com/discussions/channels/can-not-pass-outlook-com-spam-test/3677/replies/3729). | Free | it_engineer | Credits stay at 3 |
| 5 | **Etisalat pilot, the largest unlock within reach.** 6,331 of 17,401 pool addresses are on `emirates.net.ae`. They are held only because `other` follows Microsoft, and GlockApps has no Etisalat seed, so no test can ever open them. Make it its own class: verified addresses, about 10 a day, judged on bounces, replies and complaints. | Not a placement claim: an unmeasured class gets measured, on the real recipients. **Risk:** these are cold sends over the same tenant. | Free | **CEO seat decides** (it changes the `other` rule, ledger 1377 scope); it_engineer builds | Own metric: reply and NDR rate. No seed exists |
| 6 | **Keep Google open without weekly credits.** The only open class is `{google}`, on the 27 Oct test, which goes stale about 3 Nov 22:50Z at 7 days. Three credits would last three weeks. Propose a Google-only window of 21 days, with the bounce brake staying as the live guard. **This loosens a gate, so it is disclosed and goes to the CEO seat.** The 7 days is a session's choice in `invite_placement_bar`, not a founder number. | Google is measured clean: 25 of 25 seeds inbox, 0 spam. | Free | CEO seat decides; it_engineer applies | Credit 1 renews it before 17 Nov |
| 7 | **Turn on the feedback we are entitled to.** Yahoo [CFL](https://senders.yahooinc.com/complaint-feedback-loop): Sender Hub, verify `quotesdone.com` by DNS TXT, enrol the DKIM domain. Google Postmaster Tools (site verification already in DNS; may show nothing at this volume). | Diagnosis only: [CFL is DKIM-domain based](https://senders.yahooinc.com/faqs). Our 48 Yahoo/AOL companies will produce few reports. | Free | **Founder sign-in:** a Yahoo account and GoDaddy DNS | No credit: enrolment shows in Sender Hub |
| 8 | **Store the fields that decide.** Microsoft now says [SCL does not determine the verdict; read CAT, SFV, DIR](https://learn.microsoft.com/defender-office-365/anti-spam-spam-confidence-level-scl-about). Record those from GlockApps' header view. Run a message trace with the app's Exchange rights to [confirm we are not in the high-risk pool](https://learn.microsoft.com/defender-office-365/outbound-spam-sending-limits-troubleshoot#best-practices-for-bulk-senders) (not measured; the app's rights were read back on 27 Oct; message-trace access itself is untested). | Diagnosis. Rules out one tenant-level cause for free. | Free | it_engineer (code) | Trace output; Credit 1 |
| 9 | **File the sender tickets once, after 1 to 4, with evidence.** [Outlook.com Postmaster](https://substrate.office.com/ip-domain-management-snds/postmaster) sender support; [Yahoo Sender Support Request](https://senders.yahooinc.com/faqs). A recipient admin who knows us can [submit false positives](https://learn.microsoft.com/defender-office-365/step-by-step-guides/how-to-handle-false-positives-in-microsoft-defender-for-office-365#handle-spam-false-positives) in Defender. | Low odds. [Low-volume senders rarely get individual help](https://suped.com/email-deliverability/answers/where-can-i-find-the-microsoft-outlook-sender-support-form) (a user comment). [Yahoo has no whitelist](https://senders.yahooinc.com/faqs). In the closest [case](https://techcommunity.microsoft.com/discussions/microsoft-365/google-workspace-sender-stuck-at-scl5-to-all-microsoft-hosted-recipients/4534669), no outcome was ever posted. | Free | it_engineer drafts; forms may need **founder sign-in** | Credit after any reply |
| 10 | **Separate cold mail from the main domain.** Microsoft [advises a subdomain for bulk mail](https://learn.microsoft.com/defender-office-365/outbound-spam-protection-about#recommendations-for-customers-who-want-to-send-mass-mailings-through-microsoft-365). This protects the company's own mail rather than raising placement; the new name starts with no history. **It conflicts with the standing ruling that the campaign sends from supplier@quotesdone.com, so it needs a new ruling.** | Protection, not placement. | DNS only | **Founder ruling**, then it_engineer | Credit 2, only if chosen |
| 11 | **Google Workspace comparator, only if Credit 1 shows no movement.** One mailbox. See the route comparison. | Tells whether anything but the domain matters. A [July 2026 case](https://techcommunity.microsoft.com/discussions/microsoft-365/google-workspace-sender-stuck-at-scl5-to-all-microsoft-hosted-recipients/4534669) on a new domain was stuck at SCL 5 from Workspace too. | About [USD 7 to 8.40 per user a month](https://dupple.com/learn/google-workspace-pricing) plus VAT; a payment | **Founder payment and DNS**; it_engineer builds a lane | Credit 2 |

**Not recommended:** commercial warm-up networks, dedicated IPs, Azure Communication Services, BIMI, MTA-STS and TLS-RPT.
Reasons are below.

### Today, and what takes time

| Today or this week | Takes weeks |
|---|---|
| 1 hold and clean the queue; 4 stop tests; 6 and 5 CEO-seat decisions; 7 enrolment; 8 trace and fields | 2 the first-contact path; 3 two-way threads; 5 pilot results; 9 ticket replies; any change in Microsoft's verdict |

### Spending the 3 credits

Each `create_test` costs a credit even if nothing is sent, and a test is 112 cold seed messages.

| Credit | When | Condition | Question it answers |
|---|---|---|---|
| 1 | By **Mon 16 Nov**, paced 5 per run on the M365 lane | Bounce under 2% and 30+ real two-way threads. Slip it if not met, within action 6's window | Has Microsoft or Yahoo moved at all? Also renews Google, reads CAT/SFV and first measures `List-Unsubscribe-Post` at the recipient |
| 2 | About **30 Nov** | If Credit 1 moved: same lane again. If 0 of 18 again: the action 10 or 11 comparator | Is the trend real, or does the domain fail on every route? |
| 3 | Reserved for the **pass** | Only when Credit 2 is 50% or better | Formal ledger 1312 pass at 80% |

A top-up is new spend for the founder; the price was not looked up.

## What is achievable by when

My judgement, low confidence. Microsoft says a new IP [ramps in a couple of weeks or less](https://learn.microsoft.com/defender-office-365/external-senders-mail-flow-troubleshooting), but that assumes good domain reputation and low complaints, so it does not settle our case.

| Date | Google | Yahoo/AOL seeds | Microsoft seeds | Real-world |
|---|---|---|---|---|
| Now (measured 27 Oct) | 25/25 inbox | 0/17 | 0/18 | 52 cold sent, 1 reply |
| 16 Nov | holds | 0 to 20% | 0 to 20% | bounce under 2% |
| Mid December | holds | 20 to 60% | 20 to 50% | opted-in Microsoft suppliers get replies in the inbox |
| January 2027 | holds | 50%+ | 80% possible, not likely | |

Seeds never engage, so real opted-in mail should do better than these columns. Only reply rate and consenting recipients
can show that.

## Measured today

- **Domain age.** Registered 8 Jun 2026 (RDAP), so 147 days old.
- **Corrections to the brief:**
  - `invite_enabled` is **`true`**, and `supplier_invite` rows are moving: 2, 20 and 30 sent on 28, 29 and 30 Oct over the M365 lane, 18 queued. The gate answers `{google}`.
  - SPF also carries `include:spf.protection.outlook.com`.
  - Seeds sent are 423 (`invite_m365_seed`, 5 to 27 Oct).
  - GlockApps shows 5 tests; the first two were on 5 Oct, one of which received nothing.
- **Inbound to supplier@:** 6 messages, 27 to 30 Oct, 5 classed `no_auto_reply` and 1 `supplier_question`. A class label is not proof of a real reply; the "1 real reply" is as briefed.
- **Who we need to reach** (28 Oct read, one-per-company picker, 6,863):

| Class | Companies | Share |
|---|---:|---:|
| other (mostly Etisalat by MX in the wider pool) | 3,810 | 55.5% |
| Microsoft | 1,959 | 28.5% |
| Google | 1,046 | 15.2% |
| Yahoo/AOL | 48 | **0.7%** |

So **Yahoo is the smaller problem**: 48 companies in this set, 1,267 addresses in the wider pool. The same goes for
Proofpoint, with 134 addresses: its [sender path is thin](https://www.suped.com/learn/email-deliverability/how-can-i-contact-proofpoint-support-to-resolve-email-delivery-issues) and a recipient admin's [false-positive report](https://help.proofpoint.com/Proofpoint_Essentials/Administrator_Topics/110_logs/How_to_Report_False_Positive_and_False_Negative_messages) is the documented one, so neither earns a dedicated action.

### GlockApps history

| Test | Route | Copy | Microsoft inbox (provider rows) | Yahoo + AOL inbox | Gmail |
|---|---|---|---:|---:|---|
| 5 Oct | Resend (Amazon SES IP), `hello.` subdomain | earlier invitation | 2/16 | 1/17 | 17 Promotions, 1 spam of 18 |
| 19 Oct | M365 | offer list | 0/18 | 0/17 | Promotions |
| 27 Oct 09:33 | M365 | offer list, TNEF | 0/18 | 0/17 | Promotions |
| 27 Oct 22:50 | M365 | variant A, TNEF off, paced | 0/18 | 0/17 | **20/20 inbox** |

- **The fixes worked where reputation was not the blocker.** Copy, TNEF and pacing moved Gmail from Promotions to inbox within a day. Microsoft and Yahoo did not move at all.
- **BCL 0 throughout, content scores clean.** This is not read as bulk or as content.
- **Different IPs, same result.** SES, UAE Central and UAE North all landed in spam. The 5 Oct comparison is imperfect (other copy, IP on a blocklist that day).

## Comparing the routes

| Route | Measured or cited evidence | Verdict |
|---|---|---|
| **M365 mailbox (now)** | Ours: 0/18 three times. [Exchange Online is for user mail; bulk is unsupported and "best-effort"](https://learn.microsoft.com/defender-office-365/outbound-spam-protection-about#recommendations-for-customers-who-want-to-send-mass-mailings-through-microsoft-365). Limits are not the issue: [10,000 recipients a day, 30 a minute](https://learn.microsoft.com/defender-office-365/outbound-spam-sending-limits-troubleshoot#sending-limits-in-exchange-online). **Risk:** [Microsoft's anti-spam policy prohibits unsolicited bulk or commercial mail](https://support.microsoft.com/en-us/office/microsoft-anti-spam-policy), and an outbound restriction would hit the tenant's real users. | Keep, for low volume and reply-led mail only |
| **Google Workspace mailbox** | No test of ours. Vendor tests [conflict](https://puzzleinbox.com/blog/cold-email-microsoft-365-vs-google-workspace-2026), and the vendors sell inboxes. They favour same-provider sending, which we already have and which still scores 0. [Google also says not to mail people who did not sign up](https://support.google.com/a/answer/81126). | Comparator only (action 11) |
| **ESP on a shared IP** | Ours: 2/16 on 5 Oct, plus bad results elsewhere | No gain shown |
| **ESP on a dedicated IP** | [Usually too little below 50,000 a month; 100,000 is the floor](https://www.suped.com/learn/email-deliverability/what-are-the-minimum-and-maximum-sending-volumes-for-dedicated-ips) (vendor summary). We send under 1,500 a month, so an IP would have thin history of its own. It would unlock SNDS and JMRP, which is its one real benefit. | No |
| **Azure Communication Services** | [Retires 30 Sep 2028, maintenance mode](https://learn.microsoft.com/azure/communication-services/acs-retirement-and-breaking-changes-guide). | No |
| **High Volume Email** | [Internal send only](https://learn.microsoft.com/azure/communication-services/acs-retirement-and-breaking-changes-guide). | Cannot reach suppliers |

**Other paths checked:**
- **SNDS and JMRP:** not open to us. They [require IP ownership](https://techcommunity.microsoft.com/discussions/microsoft-365/google-workspace-sender-stuck-at-scl5-to-all-microsoft-hosted-recipients/4534669), and we are on Microsoft's shared IPs. GlockApps' own tip says the same.
- **Delisting:** does not apply. [`sender.office.com` removes banned IPs](https://learn.microsoft.com/defender-office-365/external-senders-mail-flow-troubleshooting), and we are junked, not blocked.
- **Tenant-level reputation:** no sender-facing report or control was found. The closest are message trace and the [TERRL report](https://learn.microsoft.com/office365/servicedescriptions/exchange-online-service-description/exchange-online-limits#receiving-and-sending-limits).
- **The GoDaddy-resold tenant:** it can [limit admin access and support](https://learn.microsoft.com/en-us/answers/questions/5430966/administration-limitations-for-m365-subscriptions). No source links it to placement, so leaving GoDaddy is not recommended for this problem. If a Microsoft admin ticket is ever needed, expect it to go through GoDaddy.
- **MTA-STS, TLS-RPT, BIMI:** no source reviewed credits them with placement, so skip them for this purpose.
- **Yahoo one-click and body link:** [required for bulk marketing mail](https://senders.yahooinc.com/best-practices/), but [no volume threshold is published](https://senders.yahooinc.com/faqs). The rule on Exchange adds the one-click header (not yet measured at a recipient). The visible body link conflicts with ruling 1301 (no links). At 30 a day this is left as it is.

## Warm-up services and tools

| Option | Cost | How it works | Terms and risk | Rank |
|---|---|---|---|---|
| **Real correspondents** (action 3) | Free | Real people, real replies | Within every provider's rules. Slow, limited by who will answer | **1, use** |
| **Reply-led mail from opted-in suppliers** (action 2) | Free | The product's own traffic | The same, and it compounds | **1, use** |
| [MailReach](https://www.warmforge.ai/blog/warmy-vs-mailreach) | USD 25 per mailbox a month | Connects to the mailbox; a shared pool automates sends, replies and spam rescue | **Automated engagement, not real interest; declined** | Do not use |
| [Warmforge](https://www.warmforge.ai/blog/warmy-vs-mailreach), [Warmup Inbox](https://www.mailreach.co/blog/warmup-inbox-pricing), [Warmy](https://warmy.io/pricing), [Instantly](https://www.helloinbox.email/blog/best-email-warmup-tools) | about USD 10, n/a, 49+, 37 a month | The same model | Same | Do not use |
| [warmbly/warmbly](https://github.com/warmbly/warmbly) (583 stars, Apache) | Hosting | Self-hosted cold email plus warm-up | Its warm-up has the same problem | Do not use |
| [FassihShah/WarmGrid](https://github.com/FassihShah/WarmGrid) (3 stars, MIT) | Hosting | Imports seed accounts that auto-reply and rescue from spam | **Simulated replies** | Excluded by the ethics boundary |
| [darkzOGx/darkzwarmer](https://github.com/darkzOGx/darkzwarmer) (13 stars, MIT) | Hosting | Generates inboxes that mail and auto-reply to each other | **Fake mailboxes** | Excluded by the ethics boundary |

**Plainly on terms and risk:**
- **Google:** warm-up tools were reportedly [cut from Gmail accounts in February 2023](https://www.growbots.com/blog/google-bans-cold-email-warmup/). This is a vendor's account; no Google statement was found.
- **Microsoft:** no warm-up-specific ban was found. Its [code of conduct](https://www.microsoft.com/content/dam/microsoft/mlsd/documents/servicesagreement/MSA_2025_en-us.pdf) bars spam, but engagement signals produced by a bot network are designed to look like interest that does not exist, so we treat them as against the purpose of the rules. **Yahoo:** nothing specific found.
- **Effect:** the evidence is vendor-only and conflicting. [Tests cited by GigRadar](https://gigradar.io/blog/email-warmup-tool) found no improvement, and a [Litemail test](https://litemail.ai/blog/google-workspace-cold-email-deliverability-test-2026) put six weeks of warm-up at 63.4% primary, against its own product's 94.2%. [InboxAlly claims providers detect it](https://docs.inboxally.com/warm-up-sending-strategy/the-dangers-of-using-an-automated-email-warmup-service/), but it sells a rival.
- **Risk to the domain:** pooled traffic ties us to other customers' behaviour, the vendor gets standing access to supplier@, and a pass earned that way would not hold when real suppliers do not engage. It could also turn the founder's 80% gate green on signals that are not real, against the rule on not fabricating to pass a gate.

## Limits of this report

- Practitioner sources are forums and vendors. Where a vendor sells the answer, that is noted.
- The Outlook.com postmaster pages now redirect to a thin page, so its sender-support form and response times could not be read. The form address needs confirming when action 9 is filed.
- Not measured: placement at real recipients, the class split of the 52 cold sends, high-risk pool status, whether `List-Unsubscribe-Post` arrives.
- Tenant-specific filtering at real UAE M365 suppliers is unknown; GlockApps has 2 Exchange seeds.
- Prices were not read from vendors' own checkout pages.
