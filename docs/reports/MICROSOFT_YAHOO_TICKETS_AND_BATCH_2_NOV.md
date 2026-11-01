# Microsoft 365 ticket, Yahoo request and the 2 Nov 06:00Z batch, 2 Nov 2026

Seat: `it_engineer` with `sales_engineer`. Founder ledger 1445 and 1478. Read-only on production (`select` only, DNS reads); nothing
was sent, applied, merged or submitted. The two drafts below are for the founder or the CEO seat to submit; they were not.

## 1. What really goes at 06:00Z today (measured 1 Nov 23:30Z)

**Nothing will go, because the bounce brake trips at the 05:00Z beat, before any invitation is queued.**

| Fact | Measured value |
|---|---|
| Rows in the outbox, `supplier_invite`, `queued` | 18, all created 28 Oct 06:45Z, all `not_before` 4 Nov 06:00Z (4 rows) or 06:05Z (14 rows), `last_error` null |
| Provider class of the 18 | 18 Google (MX), 14 role mailboxes, 4 named |
| Sent so far | 52 (2 on 28 Oct, 20 on 29 Oct, 30 on 30 Oct), all Google; 7 bounced (5 of 19 named, 2 of 33 role) |
| Who set the 18 to 4 Nov | **Not provable from code or data.** No code path writes 4 Nov (`enqueue_supplier_invites` spreads inside the day; `send_outbox` holds write a `last_error`, and these have none). It matches founder instruction 1461 ("18 held invitations", handover from cloud sessions), so it reads as a manual hold with no audit row. The date also equals the first 10:00 Dubai after the Google verdict goes stale (27 Oct 22:50Z plus 7 days). |
| New batch the beat would queue | `enqueue_supplier_invites`: cap `least(invite_daily_cap 30, founder cap 40)` = 30, open class `{google}`; `fn_supplier_invite_candidates(30, {google})` returns 30 Google addresses (26 role, 4 named), spread 06:00Z to 13:00Z |
| The brake | `fn_invite_send_health(since 30 Oct 05:00Z)` = 30 sent, 2 bounced = **6.7%**. The rule is `sent >= 15 and rate > invite_max_bounce_rate (3%)`, so it fires. It sets `invite_enabled=false`, writes `invite_brake`, raises `invite_paused_bounce` to the founder, and queues 0. One bounce in 30 is already 3.3%, so any 30-address day with a single bounce trips it. |
| After the brake | `sales_engineer.invite_restart` may resume once, no sooner than 3 days after the brake, only if the real 3-day window would not fire again, at 10 a day until a day has sent. Earliest resume is Thursday 5 Nov. |

**lead_email_check on every address due (48: the 30 new and the 18 held).** Re-ran the shipped `judgeWithoutDns` and `judgeDns`
(`sales_engineer/lead_email_check.ts`) with live MX lookups: **48 of 48 verified, 0 rejected, 0 no MX, 0 typo domains**, and all 48
have Google MX. This agrees with the stored verdicts (checked 1 Nov 22:30Z to 23:35Z). The check cannot see a missing mailbox on a
live domain, and all 7 past bounces were on domains with a real MX.

**Expected bounces if the 30 went:** named 5/19 (26%) and role 2/33 (6%) give 26 x 6% + 4 x 26% = about 2.6 of 30 (about 9%, small
sample, wide error). That would again exceed 3%. For the 18 held: 14 x 6% + 4 x 26% = about 1.9 of 18 (about 10%).

**No code fix made for the brake.** It is working as written, and loosening it is a safety change for the CEO seat. Options for that
seat, not applied: (a) in the candidate order, send role mailboxes only until the 3-day bounce rate is measured clean; (b) raise the
minimum sample before the rate rule fires; (c) leave it. A fix to the batch size would not help; the rate rule has no size floor above 15.

## 2. Added by PR (this branch)

- Supplier sign-up page (`SupplierPortal.tsx`, code step): one line, in English on both language tables (suppliers are always English,
  ledger 993): "So our messages reach your inbox, add supplier@quotesdone.com to your contacts, or write to us at that address."
- First reply to an invited supplier (`email_triage/account_facts.ts`): `ADD_CONTACT_FACT` is added to the unregistered-supplier facts and
  the unverified-sender facts, asking once, in English, to add supplier@ to contacts or write there first.
- Display name on the supplier lane: `"Ahmad Alzain, QuotesDone" <supplier@quotesdone.com>` (`M365_FROM_NAME`, quoted because of the comma),
  replacing "Ahmad Alzain at QuotesDone". **Low-strength evidence:** only vendor posts say a bare role address is flagged; nothing from
  Microsoft or Yahoo; no measurement of our own. Do not spend a GlockApps credit on it alone.
- Checks: `m365_lane.test.ts` and `account_facts.test.ts`, 43 pass.

## 3. Inbox rate of today's batch, by provider mix

Today's mix is 100% Google (30 of 30; the gate leaves Microsoft, Yahoo and "other" closed). Seeds measured 20 of 20 inbox on 27 Oct 22:50Z.
Seeds do not engage and are Gmail mailboxes, while these are Google Workspace business domains, so I discount them. My estimate of the
share of sent mail that lands in a primary inbox: **about 75 to 90%** (delivered 91% after about 9% bounces, times roughly 85 to 95%
inbox among delivered). It is an estimate, not a measurement. If the batch had a Microsoft or Yahoo share it would be near zero for
those: 0 of 18 Microsoft and 0 of 17 Yahoo/AOL seeds on every M365-lane test. Across the whole 6,863-company pool (Microsoft 28.5%,
Google 15.2%, Yahoo/AOL 0.7%, other 55.5% unmeasured) the blended inbox rate is not measurable today.

**If Microsoft and Yahoo cannot change by morning (they cannot):** no ticket or form in either company's documentation has a published
turnaround under 24 to 72 hours, and neither has a sender-side switch for a tenant on shared IPs. Today's batch is Google only and stays so.

## 4a. Draft: Microsoft 365 admin center support request (not submitted)

Route: Microsoft 365 admin center, Support, "Help and support", service Exchange Online, issue "mail goes to Junk / outbound spam".
The tenant may be GoDaddy-resold; if the admin center shows no support option, the same text goes to GoDaddy as the reseller.
Outlook.com Postmaster (`substrate.office.com/ip-domain-management-snds/postmaster`) gets the same facts as a second request.

> **Subject:** Authenticated mail from our tenant is delivered to Junk (SCL 5) at Outlook.com, Hotmail and Exchange Online recipients
>
> Our domain quotesdone.com (registered 8 Jun 2026) sends low-volume, plain-text, one-to-one business invitations from the mailbox
> supplier@quotesdone.com, about 20 to 30 a day on weekdays, from this tenant through Exchange Online. Every message passes SPF, DKIM and DMARC.
> Our own message trace shows delivery, and the receiving side files the message in Junk.
>
> **What we measured.** On three inbox-placement tests of this mailbox (19 Oct, 27 Oct 09:33Z, 27 Oct 22:50Z) 0 of 18 Microsoft
> seed mailboxes received it in the inbox, every time; Gmail and Google Workspace seeds received 20 of 20 in the inbox on the last test. The
> junk verdict shows SCL 5 with BCL 0, so we are not judged as bulk. Delivery took 2 to 9 seconds.
>
> **What we already changed.** Removed all links and images, shortened the text to one question, paused TNEF, paced sends to 5 per run,
> added one-click List-Unsubscribe headers and a reply-"stop" line, added a bounce brake at 3% and suppressed every bounced address.
>
> **Message IDs (Internet Message-ID, sent through this tenant):**
> - `<qd-notif-114414.1793142116254@quotesdone.com>` to `<qd-notif-114474.1793146591356@quotesdone.com>` (30 test messages, 27 Oct 23:01Z to 28 Oct 00:16Z, to Outlook.com, Hotmail, Yahoo and AOL test mailboxes)
> - Outlook.com examples: `<qd-notif-114444.1793144798622@quotesdone.com>` (27 Oct 23:46:38Z), `<qd-notif-114451.1793145694944@quotesdone.com>` (28 Oct 00:01:35Z)
> - Real business mail, Google-hosted recipients (for comparison, delivered to inbox): `<qd-notif-117569.1793340128035@quotesdone.com>` (30 Oct 06:02Z)
>
> **We are asking for:** (1) confirmation of the filter verdict for these message IDs (CAT, SFV, DIR) and the reason; (2) whether the
> tenant or domain is in the high-risk delivery pool or any outbound reputation hold; (3) the supported way for a new low-volume sender
> to reach Outlook.com and Exchange Online inboxes; (4) if the filter is wrong, a false-positive review of quotesdone.com.
>
> Contact: Ahmad Alzain, QuotesDone Technologies, Dubai. Reply to management@quotesdone.com.

Attach: the three GlockApps report links (test IDs `2026-10-19-02:51:47:497t`, `2026-10-27-09:33:53:634t`, `2026-10-27-22:50:26:837t`), one message
trace export for the IDs above, and one raw header set from an Outlook.com seed (CAT, SFV, DIR, SCL, BCL). The header set is not in
the connector's output; it must come from the shared report page.

Expectation: no case I read reports an outcome; a Microsoft moderator's reply to the same symptom was to open exactly this request.

## 4b. Draft: Yahoo Sender Support Request (not submitted)

Route: Yahoo Sender Hub (`senders.yahooinc.com`), Sender Support Request. Needs a Yahoo account and DNS TXT verification of
quotesdone.com (founder sign-in). Enrol the same domain in the Complaint Feedback Loop in the same visit.

> **Subject:** New sender quotesdone.com: authenticated one-to-one business mail delivered to the Spam folder at Yahoo and AOL
>
> Our domain quotesdone.com sends low-volume, plain-text, one-to-one business invitations (about 20 to 30 a day, weekdays) from
> supplier@quotesdone.com. Every message passes SPF, DKIM (d=quotesdone.com) and DMARC. The recipients are UAE companies
> Each message carries a List-Unsubscribe header with one-click POST and a reply-"stop" line; stops are honoured at once and every
> bounce is suppressed. Our bounce brake pauses sending at 3%; complaints so far: 0.
>
> **Measured:** 0 of 17 Yahoo and AOL seed mailboxes received the message in the inbox on each of three placement tests (19 Oct,
> 27 Oct 09:33Z, 27 Oct 22:50Z, GlockApps test IDs `2026-10-19-02:51:47:497t`, `2026-10-27-09:33:53:634t`, `2026-10-27-22:50:26:837t`); delivery took 2 to 9 seconds.
>
> **Message IDs (Message-ID header):** `<qd-notif-114417.1793142115120@quotesdone.com>` (27 Oct 23:01:55Z), `<qd-notif-114436.1793144797040@quotesdone.com>` (27 Oct 23:46:37Z), `<qd-notif-114437.1793145695512@quotesdone.com>` (28 Oct 00:01:35Z), `<qd-notif-114418.1793142981180@quotesdone.com>` (AOL, 27 Oct 23:16:21Z), `<qd-notif-114438.1793143889903@quotesdone.com>` (AOL, 27 Oct 23:31:30Z).
>
> **We are asking for:** a review of the reputation of quotesdone.com as a new sender, and the reason these messages were filed to Spam.
> We will register for the Complaint Feedback Loop.
>
> Contact: Ahmad Alzain, QuotesDone Technologies, Dubai, management@quotesdone.com.

Expectation: Yahoo's FAQ says it "will modify your reputation as needed", gives no timeframe and runs no whitelist; a user report of an unanswered
submission exists. Yahoo/AOL is 0.7% of the companies we need to reach (48), so this is the lower-value request.

## 5. Blocked

- Microsoft and Yahoo cannot change by this morning: nothing in either company's documentation moves a verdict in hours.
- The 05:00Z brake decision (above) is the CEO seat's. Nothing here changes it.
- The tickets need the founder's sign-in or a Microsoft admin session; I did not sign in anywhere.
- Header fields (CAT, SFV, DIR) are not in the GlockApps connector output.
