# GlockApps 27 Oct 2026: the result, why Microsoft junked it, and the fix plan

Seat: `it_engineer`. Founder instruction 1312: supplier invitations stay held until a GlockApps test of the
invitation from supplier@quotesdone.com shows Outlook at 80% inbox or more. This report covers four things:
- the 27 Oct test result, and where it is recorded;
- the measured causes;
- what changed in code and in `app_secrets`;
- the re-test the automated GlockApps loop (`deliverability_test`, built by another agent) should run.

## 1. The result: FAIL, invitations stay held

GlockApps test `id:2026-10-27-09:33:53:634t`, supplied by the founder. 112 seeds left from supplier@quotesdone.com
through the Microsoft 365 lane between 09:46:19 and 11:02:02Z (`notifications`, `kind='invite_m365_seed'`, 112 rows,
all `sent`; measured).

| Provider | Inbox | Spam |
|---|---:|---:|
| Outlook US (8 seeds) | 0 | 8 |
| Outlook.fr | 0 | 1 |
| Outlook.de | 0 | 1 |
| Hotmail (6) | 0 | 6 |
| Exchange / Office 365 (2) | 0 | 2 |
| **All Microsoft (18)** | **0** | **18 (100%)** |

- Gmail put every seed in Promotions. Yahoo and AOL put every seed in spam.
- Overall: 39.6% inbox, 18.9% tabs, 36.9% spam, 4.6% missing.
- The ledger 1312 bar is Outlook at 80% inbox or more. Outlook scored 0%, so **invitations stay held**.

**Where it is recorded.** The applied file is
`scripts/sql/glockapps_27_oct_microsoft_0_of_18_inbox_is_recorded_and_the_invitations_stay_held.sql` (verdict
`PROBE OK`). It wrote two things:
- a per-provider note on the 27 Oct row of `invite_placement_check`;
- the dated note *"GlockApps 27 Oct: Microsoft 0/18 inbox — FAIL; invitations stay held"* on ledger row 1312, which
  stays `open`.

**Why a note and not new rows.** `invite_placement_check` is the daily two-mailbox seed:
- its primary key is `dubai_day`;
- CHECK constraints pin `gmail_to` to the founder's Gmail and `outlook_to` to management@quotesdone.com.

So it cannot hold one row per GlockApps provider without a schema change. That change belongs to the
`deliverability_test` loop being built by another agent. The row's own `verdict` (`inbox`, from the in-tenant seed)
was left alone, because `fn_invite_placement_gate` reads it.

**Read-back of both invite switches** (27 Oct 2026, ~14:37Z, after every write in this report):

| key | value |
|---|---|
| `invite_enabled` | `false` |
| `wa_supplier_invite_golive` | `false` |
| `supplier_outreach_golive` | `true` (unchanged) |
| `invite_m365_enabled` | `true` (unchanged; the lane is on, but nothing is queued) |
| queued `supplier_invite` rows | 0 |

## 2. Diagnosis: what EOP scored, and the evidence for each finding

EOP's verdict was **Spam**, not phishing. Microsoft Learn ("Frequently asked questions – Anti-spam protection",
Spam vs. high-confidence spam) gives the common triggers for a Spam verdict as *"promotional content patterns,
suspicious links, low sender reputation"*. Each one is checked below, along with every other signal in the brief.

### 2a. Ruled out, with evidence

| Signal | Evidence (measured 27 Oct 2026) | Verdict |
|---|---|---|
| SPF | `quotesdone.com TXT v=spf1 include:secureserver.net include:spf.protection.outlook.com ~all`. Gmail's Authentication-Results on today's seed: `spf=pass … smtp.mailfrom=supplier@quotesdone.com`. Return-Path and From are the same domain. | aligned, pass |
| DKIM | `selector1._domainkey.quotesdone.com CNAME selector1-quotesdone-com._domainkey.netorgft20811795.n-v1.dkim.mail.microsoft` (selector2 likewise). Gmail: `dkim=pass header.i=@quotesdone.com header.s=selector1`. The signature is quotesdone.com, **not** onmicrosoft.com. | aligned, pass |
| DMARC | `_dmarc.quotesdone.com TXT v=DMARC1; p=quarantine; rua=mailto:management@quotesdone.com`. Gmail: `dmarc=pass (p=QUARANTINE sp=QUARANTINE)`. A passing message is not affected by `p=quarantine` vs `p=none`. | pass; not a cause |
| MX | `0 quotesdone-com.mail.protection.outlook.com` | correct |
| Domain blocklists | `quotesdone.com.dbl.spamhaus.org`, `.multi.surbl.org` and `.multi.uribl.com` each answered **NXDOMAIN** from the list's own servers. Those lists answer a refusal code (127.255.255.x / 127.0.0.1), not NXDOMAIN, when they refuse a public resolver, so NXDOMAIN is a real "not listed". | not listed |
| Sending IP | `87.54.107.40.zen.spamhaus.org` NXDOMAIN. GlockApps also reported no IP listing. | not listed |
| "HELO to IP (40.107.54.87): Fail" | PTR `87.54.107.40.in-addr.arpa → mail-uaenorthazon11021087.outbound.protection.outlook.com`, which resolves forward to `40.107.54.87` (forward-confirmed). 40.107.0.0/16 is in `spf.protection.outlook.com`. The HELO name is chosen by Exchange Online Protection's outbound server, which is Microsoft's host, not ours. | **confirmed Microsoft's, not ours to fix** |
| Link domain, link count, shorteners, tracking redirects | The body carries no URL (the lane's copy rule `no link anywhere in the email` holds rows that break it). The only URL is in the `List-Unsubscribe` header (`https://quotesdone.com/u/unsubscribe?...`, our own domain, not a redirect). No tracking pixel, since there is no HTML. | none |
| HTML-only or image-heavy | The MIME is a single `text/plain; charset=utf-8` part with no HTML (`m365Mime`). | no |
| Cross-domain Reply-To (a phishing signal measured on 6 Oct) | The lane drops Reply-To while the reply reader is proven. The proof rows (`agent_runs`, `resend_inbound`, `counts.m365_inbox=1`, status `ok`) ran every 15 minutes from 07:30 to 11:00Z, so every seed went with **no** Reply-To. | absent |
| `List-Unsubscribe` + `List-Unsubscribe-Post` | Both present as real MIME headers (one-click URL plus a mailto). The body also ends with the reply-"stop" line. | present, as Yahoo/Gmail want |
| `Precedence: bulk` or similar bulk headers | None written by `m365Mime`. | absent |
| From display name | `Ahmad Alzain at QuotesDone <supplier@quotesdone.com>`, a named person at a real domain | fine |
| Physical address | The signature says `QuotesDone Technologies · Dubai, UAE`, with no street, by the founder's 27 Oct ruling. CAN-SPAM's street-address rule is US law, which is out of scope for the company. | not changed |

### 2b. Causes, ranked by the weight of evidence

1. **Sender reputation: a mailbox whose only history is bursts to strangers (primary cause).**
   - supplier@ has sent **317 messages ever**, every one a placement seed:
     - 81 on 5 Oct, 110 on 19 Oct and 112 on 27 Oct, all to GlockApps seed lists;
     - 2 a day to the two internal mailboxes.
   - It has never held a two-way conversation, and none of its mail has ever been replied to.
   - The decisive comparison is between the two GlockApps tests over this same lane:
     - 19 Oct (`2026-10-19-02:51:47:497t`, recorded in the `m365_lane.ts` header comment): Outlook, Yahoo and AOL were
       100% spam (EOP SCL 5). That plain-text mail carried a portal link in its body and the earlier wording.
     - 27 Oct: Microsoft was again 18 of 18 spam. By then the link was gone and the text had been rewritten (#1614).
   - So a substantial content change moved Microsoft by zero. That is what a reputation-driven verdict looks like.
   - Yahoo and AOL, which weigh sender history most, were also 100% spam both times.
2. **The send pattern: bursts of 20.**
   - All 112 seeds were queued at once (09:41Z, no `not_before`).
   - `send_outbox` runs every 15 minutes (`agent_runs`: 09:46:14, 10:01:18, 10:16:28 …) and sent 20 per run back to
     back, about 4 seconds apart. Per minute: 09:46 → 20; 10:01 → 20; 10:16 → 20; 10:31/32 → 3+17; 10:46/47 → 14+6;
     11:01/02 → 8+4.
   - Microsoft Learn ("Troubleshoot outbound sending limits", best practices for bulk senders): *"Spread bulk sends
     over time rather than sending all at once"*. The same page notes *"Exchange Online isn't designed for bulk
     mailing scenarios"*.
3. **Promotional content (contributing; also the Gmail Promotions cause).**
   - The 27 Oct text was a marketing layout:
     - a "What you get:" list of four dashed bullets;
     - "Free registration for our first 1,000 suppliers" and "No commission on work you win";
     - "To join, register at quotesdone.com".
   - "Promotional content patterns" is Microsoft's first named Spam trigger.
   - Gmail filed both the GlockApps seeds and the founder's own copy (`invite_placement_check` 27 Oct, labels
     `CATEGORY_PROMOTIONS`) under Promotions.
   - The bare `quotesdone.com` in the body is not a link, but clients turn it into one, and URL filters extract it.
4. **Base64 text part (minor, plausible, unmeasured).**
   - `m365Mime` wrote the text part as `Content-Transfer-Encoding: base64`.
   - Nearly-all-ASCII text in base64 is what bulk tools emit; a person's client writes 7bit or quoted-printable.
     SpamAssassin's `MIME_BASE64_TEXT` is the public example of this being scored.
   - Microsoft does not publish its own rule, so this is ranked last.

**Not measured, and what would settle it.**
- The GlockApps report's raw headers for the Microsoft seeds would show three things:
  - the `X-Microsoft-Antispam: BCL:` value. A BCL at or above 7 means "bulk"; 4–7 means "mixed complaints" (Microsoft
    Learn, Bulk complaint level);
  - `CAT:` (SPM vs BULK) in `X-Forefront-Antispam-Report`;
  - whether the message was routed through the high-risk outbound pool. An Exchange admin can see that in Message
    trace (`OutboundIpPoolName`).
- None of these were available to this session. The `deliverability_test` loop should store the Microsoft seeds'
  `X-Forefront-Antispam-Report` and `X-Microsoft-Antispam` headers with each result, so the next test answers the
  BCL-vs-SPM question directly.

## 3. Fix plan, ranked by expected impact

| # | Fix | Status |
|---|---|---|
| a | **Week 1 of the warm-up: real two-way conversation only** (reputation, cause 1) | planned; dates below. Needs the founder's yes to the internal test email (1314): not recorded yet |
| b | **Copy variant A**: plain text, no offer, no link or domain, short, ends in one question that invites a reply (cause 3) | **applied** to `app_secrets` and the lane code (this PR) |
| c | **Headers**: the text part is quoted-printable instead of base64 (cause 4). List-Unsubscribe and -Post stay, no Precedence header, no Reply-To while the reader is proven (all verified above) | in code (this PR) |
| d | **Pacing**: at most 5 lane sends per `send_outbox` run, the rest re-queued 10 minutes on (cause 2) | in code (this PR) |
| e | **Re-test** through the `deliverability_test` loop after week 1, then before week 3 | schedule below |

### a. Week 1: conversation only (warm-up plan 1313)

Microsoft's verdict follows the mailbox's history, so week 1 gives supplier@ a history of mail that people answer.

- **Who it writes to:**
  - The founder's **Dorata mailbox** (`doratajewelries.com MX 0 doratajewelries-com.mail.protection.outlook.com`,
    measured). This is a separate Microsoft 365 tenant, so it is real external Microsoft traffic, and the most useful
    partner for the Outlook score.
  - His **Gmail**.
  - **management@quotesdone.com.** This is in-tenant and builds little external reputation, but it is the agreed day-1
    message.
- **What happens each day:**
  - 3–5 messages a day, each one answered from the other side.
  - Any copy that lands in Junk is moved to the inbox and marked "Not junk".
- **Gate:** day 1 is the internal test email, which still needs the founder's yes (instruction 1314; that yes is not
  recorded in the ledger as of this report).
- **Days:** working days only (Saturday and Sunday off). `company_calendar` has no public holiday from 28 Oct to 20 Nov
  (measured):

| Week 1 day | Date |
|---|---|
| 1 | Wed 28 Oct (or the first working day after his yes) |
| 2 | Thu 29 Oct |
| 3 | Fri 30 Oct |
| 4 | Mon 2 Nov |
| 5 | Tue 3 Nov |

### b. Invitation copy: three variants, A chosen and applied

The founder delegated the choice on 27 Oct ("approved. dont ask me", relayed by the coordinator). All three variants:
- are English only;
- never use the word "AI" (`profile-copy-rules`);
- carry no link, no date, no licence or permit number and no street;
- keep the `QuotesDone Technologies · Dubai, UAE` signature and end with the reply-"stop" line;
- pass every rule in `m365CopyLint`.

**Variant A, "one question, no offer" (CHOSEN, APPLIED).** Ranked first because:
- it removes every promotional pattern that was in the junked text;
- it is honest about the pre-launch state;
- its only call to action is a reply, which is the strongest positive signal a new mailbox can earn.

> Subject (trade known): `A question about your {trade} work`
> Subject (company only): `A question for {Company}` · (neither): `A question about your work in the UAE`
>
> Hi {Company} team,
>
> I'm Ahmad, founder of QuotesDone in Dubai. QuotesDone is a platform where companies in the UAE post requests for quotation, and each request goes only to suppliers who work in that exact trade.
>
> We are putting together our list of {trade} suppliers now, before buyers start sending requests. Would your company like to receive {trade} requests when they come in?
>
> Best regards,
> Ahmad Alzain
> Founder, QuotesDone
> QuotesDone Technologies · Dubai, UAE
>
> If this isn't relevant, reply "stop" and we won't contact you again.

With no trade known, the question reads "…receive the requests that match your trade when they come in?". With no
company, the greeting is "Hello,". About 80 words.

**Variant B, "short, one benefit, ask for trades" (not applied, ranked second).** It keeps "no commission", which is
an offer phrase, so it carries some of the promotional pattern that A drops.

> Subject: `{Trade} quote requests for {Company}`
>
> Hi {Company} team,
>
> I'm Ahmad, founder of QuotesDone in Dubai. Companies in the UAE post their requests for quotation with us, and each one goes only to suppliers in that exact trade. Suppliers choose which requests to quote on and pay no commission on work they win.
>
> Which trades does your company cover? If you reply with them, we will set up your company page for you.
>
> (signature, stop line)

**Variant C, "two sentences" (not applied, ranked third).** It is the shortest, but "to send our buyers' requests to"
implies buyers are already sending requests, which is not yet true (pre-launch). An opening question with no context
also reads like a cold-pitch template.

> Subject: `{Trade} work in the UAE`
>
> Hi {Company} team,
>
> Do you take on {trade} work for companies in the UAE? I'm Ahmad, founder of QuotesDone in Dubai, and I'm collecting {trade} suppliers to send our buyers' requests for quotation to.
>
> (signature, stop line)

**What was applied, exactly.**
- `scripts/sql/the_supplier_invitation_asks_one_question_and_makes_no_offer.sql`, applied 27 Oct, verdict `PROBE OK`:
  - `invite_subject` = `A question about your work in the UAE`;
  - `invite_body` = variant A with the `{{company}}` placeholder and the no-trade wording.
- Read back from production after the apply: identical.
- **The email itself is built in code, not from those keys.** `send_outbox/m365_lane.ts` `m365InvitationText` /
  `m365Subject`, used by both the Microsoft 365 lane and the Resend fallback through `campaignMail`, now writes
  variant A.
- That code reaches production when this PR is merged and `send_outbox` is deployed. Until then the deployed lane
  would still send the old text. **The re-test must not run before that deploy.**
- `scripts/checks/the_supplier_invitation_carries_no_link.test.mjs` now fails if the stored body and the lane's text
  drift apart. It reads the last MANIFEST file that writes `invite_body`.

**Rollback (previous values).** Re-applying the update block of
`scripts/sql/the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql` restores
the previous keys, and reverting this PR's `m365_lane.ts` hunk restores the previous code. Previous `invite_subject`:
`Quote requests in the UAE`. Previous `invite_body`:

```
Hi {{company}} team,

I'm Ahmad, founder of QuotesDone. QuotesDone connects companies in the UAE with qualified suppliers: buyers post a request for quotation, and each request reaches only the suppliers registered for that exact trade.

We are now onboarding suppliers ahead of our buyer launch.

What you get:
– Requests that match your trade, delivered directly to you.
– You choose which ones to quote on.
– No commission on work you win.
– Free registration for our first 1,000 suppliers.

To join, register at quotesdone.com, or simply reply with the trades you cover and our team will set up your company page for you.

Best regards,
Ahmad Alzain
Founder, QuotesDone
QuotesDone Technologies · Dubai, UAE

If this isn't relevant, reply "stop" and we won't contact you again.
```

### c. Headers: quoted-printable text part (code)

- `m365Mime` now writes the text part as `Content-Transfer-Encoding: quoted-printable` through `qpEncode` (RFC 2045
  §6.7):
  - ASCII stays readable on the wire;
  - `=` and the UTF-8 characters `·` and `–` become `=XX`;
  - a trailing space or tab is encoded;
  - lines are at most 76 characters.
- The outer base64 is untouched: it is Graph `sendMail`'s own input format, not a MIME part.
- Unchanged, because they are verified correct: `List-Unsubscribe` + `List-Unsubscribe-Post`, no `Precedence`, the
  Message-ID at `@quotesdone.com`, no Reply-To while the reader is proven.
- The seed path (`seedMarker`, `withPlacementRef`, `M365_SEED_KIND`) is untouched, so nothing conflicts with the
  `deliverability_test` agent.

### d. Pacing (code)

- `M365_PER_RUN = 5`. Once a `send_outbox` run has sent 5 through the lane, each further lane row in that run goes back
  to `queued` with `not_before = now + 10 min` and the note "paced: …". It is never dropped and never diverted to
  Resend.
- At one run per 15 minutes that is 20 an hour:
  - week 2's 10–15 invitations a day finish within the hour;
  - a 112-seed GlockApps test takes about 6 hours instead of 76 minutes.
- The cap applies to seeds as well, so the re-test measures the same pattern real invitations will have.

### e. Re-test: date and method

| When | What | Passes when |
|---|---|---|
| **Wed 4 Nov 2026, from 10:00 Dubai** (the working day after week 1 ends; it moves day for day if week 1 starts late) | One GlockApps test through `deliverability_test`: the live invitation (variant A, deployed), M365 lane, paced 5 per run. Store per-provider inbox/spam/tabs, plus the Microsoft seeds' `X-Forefront-Antispam-Report` and `X-Microsoft-Antispam` headers | Outlook (outlook.com + hotmail.com + Office 365 seeds together) **≥ 80% inbox** (ledger 1312) |
| If 4 Nov fails | 5 more working days of conversation mail, then re-test **Wed 11 Nov** | same |
| Start of week 3 (before volume passes 20/day) | The second GlockApps test the warm-up plan already requires | same |

Preconditions for the 4 Nov run:
1. This PR is merged and `send_outbox` is deployed. Check with `verify_deploy_parity`, then call the lane on a seed and
   read the MIME's `Content-Transfer-Encoding: quoted-printable`.
2. Week 1's five conversation days have run.
3. A GlockApps credit remains. 3 were bought (ledger 1120); count them in the dashboard rather than assuming.

Resumption itself is unchanged and stays a deliberate act. Only after a pass:
- `invite_warmup.window_end_hour` goes back to 17;
- `invite_enabled` is set to `'true'` by hand.

### What remains a risk after all of this

Copy, encoding and pacing remove the measurable content and pattern signals. They do not create reputation. If 4 Nov
still shows Microsoft below 80%, the evidence above points to the mailbox's history. In that case the next lever is
more weeks of genuine two-way mail, not further copy edits. Microsoft's own guidance for bulk sending is a dedicated
sender on a separate subdomain; that is a commercial choice the founder has already made the other way (ledger 1115:
send from a real mailbox).
