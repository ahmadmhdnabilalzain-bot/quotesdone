# Microsoft and Yahoo junk placement: the wide search, 2 Nov 2026

Seat: `it_engineer`. Founder ledger 1445. This is the second pass after
`MICROSOFT_YAHOO_PLACEMENT_PLAN_2_NOV.md` (branch `it_engineer/microsoft-yahoo-placement-plan`), which relied mostly on
official documents. This pass read community threads, GitHub issues, vendor and practitioner write-ups, and re-read two Microsoft
pages. Nothing was changed, sent or bought. GlockApps was only read (`list_tests`, `get_results`), no credit spent.

## Verdict

**The wide search found no fast fix and no new lever that works on its own.** Of the twelve Microsoft Q&A, tech-community and
GitHub threads I opened about authenticated mail landing in Junk at Microsoft, none posted a confirmed fix that applies to us.
Two small items are new and cheap (actions 1 and 2), one is a measurement gap worth closing (action 3), and two earlier
assumptions need a correction (end of this report).

Source labels: **[official]** a vendor's or Microsoft's own statement; **[measured]** numbers someone measured and showed;
**[anecdote]** one person's report; **[vendor]** a seller of the thing being discussed.

## What the threads show

| Case | What happened | Outcome | Label |
|---|---|---|---|
| [New domain, SPF/DKIM/DMARC pass, SCL 5, `dest:J` (Jan 2026)](https://learn.microsoft.com/en-us/answers/questions/5694073/outlook-microsoft-365-marking-fully-authenticated) | Same symptom as ours. A Microsoft external moderator said there is usually no sender-side switch and told the poster to open a Microsoft 365 admin center support request | No fix posted | anecdote, with an official reply |
| [Google Workspace sender, new domain, junk at Outlook.com and Exchange Online (Jul 2026)](https://techcommunity.microsoft.com/discussions/microsoft-365/google-workspace-sender-stuck-at-scl5-to-all-microsoft-hosted-recipients/4534669) | SPF `-all`, DMARC quarantine, delist portal clean, Postmaster request filed, JMRP refused (needs IP ownership) | Poster never returned. Replies: no reset, read CAT/SFV, tenant admins submit false positives, avoid test traffic | anecdote |
| [Clean long-standing domain, BCL 0, DMARC reject, SCL 5 (Aug 2025)](https://learn.microsoft.com/en-us/answers/questions/5531207/request-for-rca-why-are-my-legitimate-emails-class) | Moderator listed content, low engagement, gradual ramp; poster disputed it | Forum said it cannot do an RCA; pointed to Unified Support. No fix | anecdote |
| [Cloud-created mailboxes junk at Outlook.com, on-prem-created ones do not (May 2024)](https://learn.microsoft.com/en-gb/answers/questions/1665475/email-from-an-o365-mailbox-goes-to-junk-folder-in) | Same tenant, same path. The `olcsupport.office.com` request came back "can't see any issue" | Unresolved | anecdote |
| [New Microsoft 365 tenant to hotmail and outlook.com (Apr 2023)](https://learn.microsoft.com/en-us/answers/questions/5229430/microsoft-office-365-emails-going-to-hotmail-junk?forum=msoffice-all) | Gmail and other tenants fine, Hotmail and Outlook.com junk | Moderator suggested the recipients add the sender to Safe Senders. No fix | anecdote |
| [Company mail SCL 5, SFV:SPM at all Office 365 recipients (Sep 2022)](https://learn.microsoft.com/en-us/answers/questions/5165710/urgent-all-of-our-company-emails-are-being-marked) | GlockApps showed links and images in the signature triggered it | Workaround only: plain-text signature. We are already plain text with no link | anecdote |
| [mailcow issue 2851, clean servers junked by Outlook (2019 to 2026)](https://github.com/mailcow/mailcow-dockerized/issues/2851) | Many users, SNDS and JMRP enrolled. One relayed Outlook-bound mail through SendGrid. Delisting took 24 to 48 hours after proof of IP ownership | No general fix. A maintainer reported fewer cases in 2023; one user said junk placement stopped being an issue by Nov 2024, no cause given | anecdote |
| [Mitigation request answered "Not qualified for mitigation" (Aug 2026)](https://learn.microsoft.com/en-us/answers/questions/5968767/not-qualified-for-mitigation) | A blocked sender, not a junked one | No reply from the poster | anecdote |
| Four other Q&A threads ([4630901](https://learn.microsoft.com/en-us/answers/questions/4630901/why-email-from-microsoft-365-to-outlook-going-as-j), [5593828](https://learn.microsoft.com/en-us/answers/questions/5593828/emails-from-our-domain-are-consistently-delivered), [5034882](https://learn.microsoft.com/en-us/answers/questions/5034882/outgoing-office-365-business-email-flagged-as-spam), [1410712](https://learn.microsoft.com/en-gb/answers/questions/1410712/microsoft-office-365-sends-all-our-marketing-email)) | Same symptom | Only one claims a fix: DKIM and a single SPF record, for a sender whose identity Outlook could not verify. Ours verifies | anecdote |

Not found: any Reddit, Hacker News, ServerFault, Spiceworks or Mailop thread that I could open with a timed resolution. The
search tool returned none of those sites for these queries, so their silence is not evidence.

## Ranked actions not in the earlier plan

| # | Action | Evidence strength | Cost | Time | How to test | Who |
|---|---|---|---|---|---|---|
| 1 | **Ask opted-in Microsoft-hosted suppliers to write to supplier@ first (one real message from their own account), and also to add supplier@ to their contacts.** "Write first" is raised and contacts lowered by the second pass below. | Contacts: Microsoft says [mail from safe senders is never sent to Junk, and contacts can be trusted](https://support.microsoft.com/en-us/office/block-or-allow-junk-email-settings-48c9f6f7-2309-4f95-9a4d-de987e880e46) **[official]**, but that page covers Outlook on the web for Exchange and does not name Outlook.com, and a 2020 HN experiment found Safe Senders ignored at Outlook.com **[anecdote]**; "write first" worked in that same experiment | Free | Per recipient, immediate | One consenting Microsoft-hosted supplier adds the address; read the folder of the next message | sales_engineer (copy and page text) |
| 2 | **File one Microsoft 365 admin center support request** for the tenant, with message-trace IDs and the seeds' header fields. It is the only route a Microsoft staff reply recommended ([thread](https://learn.microsoft.com/en-us/answers/questions/5694073/outlook-microsoft-365-marking-fully-authenticated)). The tenant may be GoDaddy-resold, so the ticket may go through GoDaddy. | Weak. Staff recommendation **[official]**; no case I read reports an outcome | Free | Unknown; no published figure | A written reply, or a change in the next seed run | Founder or admin sign-in; it_engineer drafts |
| 3 | **Close the seed-versus-real gap with a small human panel**: 10 to 15 consenting people with real Outlook.com, Hotmail and Yahoo accounts receive ordinary supplier@ mail and report the folder and `X-Forefront-Antispam-Report` (CAT, SFV, DIR). They are asked to change nothing: no rescue, no reply on request. This is measurement, not engagement. | Moderate that seeds can mislead (see next section). None that a panel would read differently: that is the unknown | Free | One week | Compare panel folders with the 0 of 18 and 0 of 17 seeds | CEO seat picks people; it_engineer reads headers |
| 4 | **Send from a named person's display name** rather than the bare role `supplier@`. | Weak. Only vendor posts say role addresses are flagged; I found nothing from Microsoft or Yahoo, and no Outlook-specific data | Free | Immediate | Costs a GlockApps credit; not worth one alone | sales_engineer |

**Considered and not ranked:**
- Relaying Outlook-bound mail through SES or SendGrid. One mailcow user did it; the evidence is [anecdote]; our own 5 Oct run via SES reached 2 of 16 Microsoft seeds and 1 of 17 Yahoo/AOL seeds, so it is not a fix.
- A fresh domain or rotating domains. Rotating domains to dodge blocks is rejected; a single subdomain is already in the earlier plan.
- Any warm-up network, seed rings or auto-reply tools: rejected as the earlier plan found.
- A newly-registered-domain penalty: I found no Microsoft or Yahoo statement that domain age is a filter input. Domain age is 147 days (8 Jun 2026, per the earlier RDAP read).

## Header fields: what the values mean

Read from [Microsoft's header table](https://learn.microsoft.com/en-us/defender-office-365/message-headers-eop-mdo) **[official]**:
- `SFV:SPM` is "marked as spam by spam filtering"; `SFV:NSPM` is not spam; `SFV:SKB` is matched on a block list. `CAT:SPM` is spam, `CAT:HSPM` high-confidence spam, `CAT:BULK` bulk.
- `SRV:BULK` appears only when the BCL threshold is crossed. Our BCL 0 means we are not being judged as bulk.
- `SCL` in cloud organizations **does not determine the verdict**; use `CAT` and `DIR`. So "SCL 5" is not by itself proof of how the message was judged ([SCL page](https://learn.microsoft.com/en-us/defender-office-365/anti-spam-spam-confidence-level-scl-about), updated 3 Aug 2026).
- GlockApps `get_results` rows for the 27 Oct 22:50 test carry only SPF, DKIM and DMARC per seed. The CAT and SFV values are not in what the connector returns, so they must come from the shared report link or a received message.

## Tenant reputation pools

[Microsoft's pool page](https://learn.microsoft.com/en-us/defender-office-365/outbound-spam-high-risk-delivery-pool-about) **[official]**: mail judged as spam on the way out goes through the high-risk delivery pool; mail whose source domain has no A and no MX record always does; forwarded or relayed mail uses a relay pool unless the sender is in an accepted domain or SPF passes. Public DNS today (nslookup, 2 Nov): `quotesdone.com` has MX `quotesdone-com.mail.protection.outlook.com`, an A record, DMARC `p=quarantine` and a DKIM CNAME for `selector1`. So the no-MX rule does not apply. Whether the tenant is in the high-risk pool is **not measured**; message trace `OutboundIpPoolName` answers it (already in the earlier plan, action 8). The GlockApps sender IP 40.107.55.82 with rDNS `mail-uaenorthazon11022082.outbound.protection.outlook.com` is the normal outbound host name, not a relay-pool one, but that is my reading and not a Microsoft statement.

## Sender forms and response times

- The old `sendersupport.olc.protection.outlook.com/pm/` address now returns a 308 redirect to `substrate.office.com/ip-domain-management-snds/postmaster`, the same page the earlier plan cited. I did not open the form.
- Reported first replies in 24 to 72 hours and mitigation in 24 to 48 hours: [Suped](https://www.suped.com/learn/email-deliverability/how-long-does-snds-support-take-to-respond) says plainly these come from field reports and are not an SLA **[vendor, anecdote]**.
- Outlook.com mitigation is an IP concept. On Microsoft's shared IPs the likely answer is "not qualified"; one such answer is [reported here](https://learn.microsoft.com/en-us/answers/questions/5968767/not-qualified-for-mitigation) **[anecdote]**.
- Yahoo: [its FAQ](https://senders.yahooinc.com/faqs/) **[official]** says a new sender should file a Sender Support Request, Yahoo "will modify your reputation as needed", there is no whitelist program, mail is not usually moved to spam for poor reputation alone, and no timeframe is given. A user on a Microsoft forum reported a Yahoo submission went unanswered ([thread](https://techcommunity.microsoft.com/discussions/microsoft-365/messg-spam-from-my-office-email-to-yahoo/3393387/replies/3418027), shown only in a search excerpt, **[anecdote]**).

## Do seed results predict real placement?

The evidence says seeds are a direction, not a prediction, and more so at Microsoft:
- Al Iverson (practitioner, 2022): seeds show a provider's treatment of mail from senders recipients do not engage with, so they apply to "almost all subscribers, not every subscriber"; they miss personal filter settings and cannot explain why two people on one list differ ([post](https://www.spamresource.com/2022/08/seedlist-testing-its-useful-even-at.html)) **[practitioner opinion]**.
- [Allegrow](https://www.allegrow.co/knowledge-base/email-seed-list): seeds do not open, reply, click or complain; "a seed test showing 90% inbox" does not mean 90% of real recipients; B2B prospects sit on Microsoft 365 business domains **[vendor]**. A second Allegrow-linked claim, that consumer seeds cannot reproduce Microsoft 365 tenant rules, came from a search excerpt that I did not open on that page, so I do not rely on it.
- A MediaPost piece compared seeds with a roughly two-million-mailbox panel and reports seeds tracked panels except at engagement extremes. The page returned HTTP 403, so I saw only the search excerpt; I do not use it.
- Our own pattern: 100% inbox at Gmail, Google Workspace, Apple, GMX, Web.de, Mail.ru and 0% at Outlook, Hotmail, Yahoo, AOL, att.net, Yandex, with delivery in 2 to 9 seconds and SPF and DKIM pass on every seed row. The providers that junk us are the ones commonly described as weighting sender history. That is a reading, not a proof.
- Both Exchange (Office365) seeds of the 27 Oct 22:50 test went to spam. The n is 2. The 2026 Google Workspace case above reports Exchange Online recipients junking as well, but that is a different sender.
- Nothing I found measures how well seed junk predicts real junk at Microsoft 365 tenants. **That is unknown**, which is why action 3.

## UAE: Microsoft-hosted versus consumer

**No UAE or `.ae` measurement exists in what I found.** Search returned global proxies only: one tracker gives Microsoft 365 45.33% and Google Workspace 43.91% of detected domains; a 2026 SPF study gives Microsoft 365 19.6% and Google 13.6% of SPF-enabled domains; neither is UAE data and they measure different things (search excerpts, not opened). The best number is our own: of 6,863 one-per-company picks, 28.5% Microsoft, 15.2% Google, 0.7% Yahoo/AOL, 55.5% other (mostly Etisalat by MX), from the earlier plan's 28 Oct read. Consumer Outlook mailboxes are not separated in that count. If that split matters, a free DNS-only pass over the pool (tenant `autodiscover` and MX) would give it.

## What this search contradicts or corrects in the earlier plan

1. **"Reaches 1,959 Microsoft companies without a filter verdict" (action 2) is too optimistic.** The cases above, and the plan's own case, show Exchange Online recipients junking authenticated mail from a no-history domain. A first email, even a confirmation, may be junked at a business tenant the same way. The opt-in step should therefore happen on the website, with an instruction to add supplier@ to contacts (action 1 here), not rely on an email arriving.
2. **"Time and steady volume" is not a documented path.** No thread I read reports a resolved case with a duration; Microsoft staff give none. The plan's dates (16 Nov, mid December) are still the estimate they were.
3. **Not contradicted:** no sender-side reset (confirmed three times), SNDS and JMRP closed to us (confirmed), delisting does not apply (confirmed), ESP-on-shared-IP gives no gain (nothing found to the contrary), plain text with no link is already the recommended shape.

## Second pass: the forums read directly (2 Nov, later)

The first pass could not reach these sites through the search tool. This pass used the built-in browser (read only, nothing submitted).

| Site | Read? | What I read |
|---|---|---|
| Hacker News | Yes, via the Algolia API in the browser, 7 queries over stories and comments | [Tell HN, Apr 2023, 50 points](https://news.ycombinator.com/item?id=35691618); [Troubleshooting Email Delivery to Microsoft Users, Apr 2026, 85 points](https://news.ycombinator.com/item?id=47738962); [comment 22849274](https://news.ycombinator.com/item?id=22849274); [comment 27993397](https://news.ycombinator.com/item?id=27993397) |
| Mailop | Yes, through the [mail-archive.com mirror](https://www.mail-archive.com/mailop@mailop.org/msg13046.html). I did not open mailop.org itself; an HN commenter says its archive is member-only | 2018 to 2026 threads: the 2021 Microsoft Consumer Email Deliverability Issue (msgs 13046 to 13073), 20331 (Dec 2023), 26020 (Feb 2026), 16108 |
| ServerFault | Yes, via the Stack Exchange API (4 queries; the site's own search returned 0 for one long query) | [1178700, Apr 2025](https://serverfault.com/questions/1178700): Office 365 files all our mail as Junk; no answers. Also 684584, 970899, 1081732 |
| Spiceworks | Yes, site search. One query gave 4 results, none about this; two others returned nothing parseable | Nothing usable |
| Reddit (r/sysadmin, r/Office365, r/coldemail) | **No.** The browser pane and WebFetch both refuse reddit.com and old.reddit.com | None |
| Exa, Tavily, Brightdata skills | Exa skill loaded but this session exposes no Exa tools; Tavily and Brightdata not tried | None |

**What is new**
- **No timed, measured resolution exists in any of it.** Every account is an anecdote. The HN and mailop cases are mostly self-hosted IPs, which differ from ours (our IP is Microsoft's own); I use them only for what they say about Microsoft's behaviour.
- **Safe Senders may not work at Outlook.com [anecdote].** A 2020 HN experiment (comment 22849274) on a clean 20-year-old domain: Gmail inbox, Yahoo inbox after one "Not spam", Outlook.com junk every time, even after repeated "Not junk" and adding the domain to Safe Senders. The only thing that changed it was **sending a message from the outlook.com account to the domain first**; mail from the domain then reached the inbox. A 2018 mailop post reports a whitelisted domain still landing in junk ([msg 07250/07251](https://www.mail-archive.com/mailop@mailop.org/msg07251.html)). One user, small sample.
- **Microsoft's own wording, relayed [anecdote]:** support replied that mail was filtered "based on the recommendations of the SmartScreen Filter", primarily "mail content and recipient interaction" ([mailop msg 13046](https://www.mail-archive.com/mailop@mailop.org/msg13046.html), [13070](https://www.mail-archive.com/mailop@mailop.org/msg13070.html)); the junked headers showed PCL 2, SCL 0, BCL 0. A junk verdict with low SCL and BCL 0 is therefore not unusual, which fits Microsoft's own note that SCL does not decide.
- **Low volume [opinion]:** a long-time mailop poster wrote that sending too few messages to Microsoft also lands in Junk, with no remedy except paid certification, which he had not tried ([msg 13073](https://www.mail-archive.com/mailop@mailop.org/msg13073.html)). A Microsoft employee on the list answers "keep replying and ask them to escalate" ([msg 13047](https://www.mail-archive.com/mailop@mailop.org/msg13047.html)).
- **Changing the sending path helped some self-hosters [anecdote]:** routing Microsoft-bound mail through Gmail, or through the VPS vendor's SMTP proxy, stopped the junking ([HN 35691618](https://news.ycombinator.com/item?id=35691618), [HN 47776651](https://news.ycombinator.com/item?id=47776651)). It does not transfer to us: our path already is Microsoft's own, and the 5 Oct SES run reached 2 of 16 Microsoft seeds.
- **Subdomain is contested [anecdote]:** one commenter says it keeps transactional mail safe; another says Google Postmaster shows root and subdomain cross-polluting; a third says recovery after damage took weeks ([HN 47738962](https://news.ycombinator.com/item?id=47738962)). Supports the earlier plan's "protection, not placement".
- **Seed tests:** nothing in these forums measures how well seeds predict real placement. Still unknown.

## Limits

- Reddit could not be read at all; its absence is a gap, not a finding.
- Most thread authors never returned, so "no fix" means "no reported fix".
- Vendor numbers on Outlook inbox rates (Litemail, MailDeck, LeadsMonky and others) conflict and are not used.
- I did not open the Outlook.com sender form, a Yahoo form, or run a message trace.
