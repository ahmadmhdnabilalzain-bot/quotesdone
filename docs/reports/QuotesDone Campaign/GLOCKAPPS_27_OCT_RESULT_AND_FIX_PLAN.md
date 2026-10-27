# GlockApps 27 Oct 2026: the result, why Microsoft junked it, and the fix plan

Seat: `it_engineer`. Founder instruction 1312: supplier invitations stay held until a GlockApps test of the
invitation from supplier@quotesdone.com shows Outlook at 80% inbox or more. This report covers four things:
- the 27 Oct result, and where it is recorded;
- the measured causes;
- what changed in code and in `app_secrets`;
- the compressed warm-up and the single remaining re-test.

## 1. The result: FAIL, invitations stay held

The GlockApps test is `id:2026-10-27-09:33:53:634t` (project 163001). The founder supplied the result, and it was
re-read through the GlockApps API on 27 Oct, read-only, with no credit spent. The test has not formally "finished";
that is normal while slow providers report.

The send: 112 seeds left from supplier@quotesdone.com through the Microsoft 365 lane between 09:46:19 and 11:02:02Z
(`notifications`, `kind='invite_m365_seed'`: 112 rows, all `sent`). GlockApps tracks 111; the 112th is its own
monitoring address.

| Provider | Inbox | Spam |
|---|---:|---:|
| Outlook (8) | 0 | 8 |
| Outlook.fr | 0 | 1 |
| Outlook.de | 0 | 1 |
| Hotmail (6) | 0 | 6 |
| Exchange / Office 365 (2) | 0 | 2 |
| **All Microsoft (18)** | **0** | **18 (100%)** |

Other providers:
- **All Gmail** (20 consumer seeds) went to **Promotions**.
- **100% spam:** Yahoo (9), AOL (8), att.net (2), Yandex (2).
- **100% inbox:** Google Workspace (5), Apple, Proton, Web.de, GMX, T-online, Freenet, Laposte, Libero/Virgilio, Mail.ru,
  Amazon WorkMail and the other smaller EU providers.
- **Not delivered:** Interia.pl (3) and Onet.pl (2).

Totals: 44 inbox, 21 tabs, 41 spam, 5 not delivered. That is 39.6% inbox, 18.9% tabs, 36.9% spam and 4.6% missing.

**The ledger 1312 bar is Outlook at 80% inbox or more. Outlook scored 0%, so invitations stay held.**

**Where it is recorded.** The applied file is
`scripts/sql/glockapps_27_oct_microsoft_0_of_18_inbox_is_recorded_and_the_invitations_stay_held.sql` (verdict
`PROBE OK`). It wrote two things:
- a per-provider note on the 27 Oct `invite_placement_check` row;
- the dated note *"GlockApps 27 Oct: Microsoft 0/18 inbox — FAIL; invitations stay held"* on ledger row 1312, which
  stays `open`.

`invite_placement_check` is the daily two-mailbox seed table: its primary key is `dubai_day`, and CHECK constraints pin
its two recipients. So it takes a note, not one row per provider. Per-provider rows belong to the `deliverability_test`
loop that another agent is building. The row's own `verdict`, which `fn_invite_placement_gate` reads, is untouched.

**Read-back of both invite switches** (27 Oct, after every write in this report):

| key | value |
|---|---|
| `invite_enabled` | `false` |
| `wa_supplier_invite_golive` | `false` |
| `supplier_outreach_golive` | `true` (unchanged) |
| `invite_m365_enabled` | `true` (unchanged) |
| queued `supplier_invite` rows | 0 |

## 2. Diagnosis

### 2a. What the filters said (GlockApps API, 27 Oct)

- **Microsoft:** Exchange/EOP stamped **SCL 5** ("Suspected Spam") on **19** seeds, and Forefront stamped SCL 5 on 3 more.
  EOP's verdict was Spam, not phishing.
- **The content filters see nothing wrong:**
  - SpamAssassin scored **0.4**; Barracuda scored **0**.
  - Content analysis: 0 links, 0 images, nothing broken.
- **GlockApps' own flag `GAPPS_WARM_UP`:** inbox was under 50% at the 20-minute check. GlockApps reads that as *"the
  sending IP or domain has not built enough reputation for its current volume"*.
- **Authentication:** SPF, DKIM and DMARC all pass. Sender IP 40.107.54.87, rDNS
  `mail-uaenorthazon11021087.outbound.protection.outlook.com`.

### 2b. What actually reached a recipient (the received headers)

The GlockApps API exposes no headers. So the received copy of the lane's mail was read, read-only, from the founder's
Gmail: the 27 Oct 04:31Z morning seed, the same lane and the same `m365Mime`. Exchange did **not** deliver what the lane
submitted.

| What we submitted (Graph `sendMail`, MIME) | What arrived at Gmail |
|---|---|
| one `text/plain` part | **`multipart/mixed`** with the text part **plus `application/ms-tnef; name="winmail.dat"`** (`Content-Disposition: attachment`). About 32 KB for an 80-word note |
| `List-Unsubscribe` and `List-Unsubscribe-Post` | `List-Unsubscribe` arrived. **`List-Unsubscribe-Post` was dropped**: it is not in the headers and not in Google's ARC `h=` list, which names `list-unsubscribe`. So RFC 8058 one-click is gone |
| text part `base64` | text part re-encoded by Exchange (`Content-ID`, `base64`), so our transfer encoding does not reach the wire |
| — | our own outbound EOP scored it clean: `X-Forefront-Antispam-Report: … SCL:1; SFV:NSPM; CAT:NONE; DIR:OUT`, `BCL:0` |

**Why the `winmail.dat`.** Microsoft Learn ("TNEF conversion options"; "How to specify the email message format … to
prevent Winmail.dat attachments") says the default remote domain's `TNEFEnabled` is `$null`, "Follow user settings".
Exchange then decides per message, and here it chose TNEF. The fix is a tenant setting:
- Exchange admin center: **Mail flow → Remote domains → Default → Use rich-text format: Never**;
- or `Set-RemoteDomain -Identity Default -TNEFEnabled $false`.

**Who can make it.** That needs an Exchange administrator sign-in. This session's Microsoft 365 app holds Graph
application permissions only, and Graph cannot set remote domains, so the founder (or whoever holds the M365 admin
sign-in) has to make the change.

**Effect, measured vs unmeasured.** It is not measured that the attachment caused the SCL 5. But a cold one-to-one
note carrying an unexplained binary `winmail.dat` attachment is exactly the kind of thing a filter weighs. It is also
what Gmail's and Yahoo's receivers see, and it is the likeliest reason `List-Unsubscribe-Post` is lost in the rebuild.

### 2c. Ruled out, with evidence

| Signal | Evidence (measured 27 Oct 2026) | Verdict |
|---|---|---|
| SPF | `quotesdone.com TXT v=spf1 include:secureserver.net include:spf.protection.outlook.com ~all`. It takes **4 DNS lookups** (secureserver.net → spf-0.secureserver.net → spf.protection.outlook.com, plus the top-level outlook include), under the RFC 7208 limit of 10, and the syntax is valid. Gmail: `spf=pass smtp.mailfrom=supplier@quotesdone.com`. GlockApps' `SPF_RECORD_ERROR` names an **empty** domain, record and error, so it is a probe artefact | pass, aligned |
| DKIM | `selector1._domainkey.quotesdone.com CNAME selector1-quotesdone-com._domainkey.netorgft20811795.n-v1.dkim.mail.microsoft`. Gmail: `dkim=pass header.i=@quotesdone.com header.s=selector1`, so the signature is quotesdone.com, not onmicrosoft.com | pass, aligned |
| DMARC | `_dmarc.quotesdone.com v=DMARC1; p=quarantine; rua=mailto:management@quotesdone.com`. Gmail: `dmarc=pass`. A passing message is not affected by `p=quarantine` vs `p=none` | not a cause |
| MX | `0 quotesdone-com.mail.protection.outlook.com` | correct |
| Domain blocklists | Spamhaus DBL, SURBL and URIBL each answered **NXDOMAIN** from their own servers. A refused public-resolver query answers 127.255.255.x / 127.0.0.1, not NXDOMAIN | not listed |
| Sending IP | Spamhaus ZEN: NXDOMAIN; GlockApps: no IP listing | not listed |
| "HELO to IP (40.107.54.87): Fail" | PTR → `mail-uaenorthazon11021087.outbound.protection.outlook.com` → A `40.107.54.87` (forward-confirmed). 40.107.0.0/16 is inside `spf.protection.outlook.com`. The HELO name is chosen by Exchange Online's outbound server | **confirmed Microsoft's host, not ours to fix** |
| Links, shorteners, tracking | 0 links (GlockApps and the lane's copy rule agree). The only URL is our own `List-Unsubscribe` | none |
| HTML-only, image-heavy | Plain text, 0 images | no |
| Cross-domain Reply-To | Dropped while the reply reader is proven. The reader proved itself every 15 minutes from 07:30 to 11:00Z, so no seed carried one | absent |
| `Precedence: bulk` and the like | None, on the submitted or on the received copy | absent |
| From display name | It arrived as `Ahmad Alzain <supplier@quotesdone.com>` (Exchange uses the mailbox's own name) | fine |
| Physical address | `QuotesDone Technologies · Dubai, UAE`, with no street, by the founder's 27 Oct ruling | unchanged |

### 2d. Causes, ranked by the weight of evidence

1. **Sender reputation and volume (primary cause).**
   - supplier@ has sent 317 messages ever, all placement seeds: 81 on 5 Oct, 110 on 19 Oct and 112 on 27 Oct, plus 2 a
     day to the two internal mailboxes. It has never held a conversation, and nothing it sent has been replied to.
   - The content filters score the mail clean (SpamAssassin 0.4, Barracuda 0, outbound EOP SCL 1).
   - EOP inbound scored SCL 5 at every Microsoft seed, and GlockApps raised `GAPPS_WARM_UP`.
   - Providers that weigh sender history most (Microsoft, Yahoo/AOL) junked 100%, while Google Workspace, Apple, Proton
     and most EU providers inboxed 100%.
   - The 19 Oct test over the same lane was also 100% Microsoft spam, despite a substantial content change since.
2. **The burst.** All 112 seeds were queued at once (09:41Z). `send_outbox` runs every 15 minutes and sent 20 per run,
   about 4 seconds apart (09:46 → 20; 10:01 → 20; 10:16 → 20; 10:31/32 → 20; 10:46/47 → 20; 11:01/02 → 12). Microsoft
   Learn, bulk-sender best practice: *"Spread bulk sends over time rather than sending all at once"*.
3. **The `winmail.dat` attachment on every external copy, and the lost one-click unsubscribe header** (2b). These are
   measured on the received copy. Their weight in the SCL is unmeasured, but they are cheap to remove and affect every
   provider.
4. **Promotional layout (secondary; mainly Gmail Promotions).** The old text was an offer list ("What you get", "Free
   registration…", "No commission"). The content filters did not object to it, so this is not the Microsoft cause.
   Gmail's Promotions tab, however, follows tone and engagement.

## 3. Fix plan, ranked by expected impact

| # | Fix | Status |
|---|---|---|
| a | **Warm-up: engaged person-to-person mail before the re-test** (cause 1) | compressed plan in §4; starts the day this PR deploys |
| b | **Turn TNEF off for external mail**: Exchange admin center → Mail flow → Remote domains → Default → rich-text **Never** (cause 3) | **needs the founder's M365 admin sign-in**; 1 minute; must be done **before day 0** |
| c | **Pacing: at most 5 lane sends per `send_outbox` run**, the rest re-queued 10 minutes on (cause 2) | in code (this PR) |
| d | **Copy variant A**, "one question, no offer": plain, personal, ends in a question that invites a reply (cause 4) | **applied** to `app_secrets` and the lane code (this PR) |
| e | Headers: `List-Unsubscribe` and `List-Unsubscribe-Post` are submitted, with no Precedence header. The text part is now submitted quoted-printable, **but Exchange re-encodes the part, so expect no wire effect**; it is kept only because it is harmless and tested | in code (this PR). Whether `-Post` survives once TNEF is off must be checked on the day-0 copies |
| f | **Re-test with the last GlockApps credit**, around day 3 | §4 |

### c. Pacing (code)

- `M365_PER_RUN = 5` (`m365_lane.ts`). Once a run has sent 5 through the lane, each further lane row goes back to
  `queued` with `not_before = now + 10 min`. It is never dropped and never diverted to Resend.
- At one run per 15 minutes that is 20 an hour, so a 112-seed test takes about 6 hours instead of 76 minutes.
- The cap applies to seeds too, so the re-test measures the same pattern real invitations will have.
- The seed path (`seedMarker`, `withPlacementRef`, `M365_SEED_KIND`) is untouched, so nothing conflicts with the
  `deliverability_test` agent.

### d. Invitation copy: three variants, A chosen and applied

The founder delegated the choice on 27 Oct ("approved. dont ask me"). All three variants:
- are English only;
- never use the word "AI";
- carry no link, no date, no licence or permit number and no street;
- keep the `QuotesDone Technologies · Dubai, UAE` signature and end with the reply-"stop" line;
- pass `m365CopyLint`.

**Variant A, "one question, no offer" (CHOSEN, APPLIED).** Ranked first because:
- it carries no offer phrase;
- it is honest about the pre-launch state;
- its only call to action is a reply, which is the engagement signal Gmail and Microsoft both reward.

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

**Variant B, "short, one benefit, ask for trades" (ranked second).** It keeps "no commission", which is an offer phrase.

> Subject: `{Trade} quote requests for {Company}`
>
> Hi {Company} team,
>
> I'm Ahmad, founder of QuotesDone in Dubai. Companies in the UAE post their requests for quotation with us, and each one goes only to suppliers in that exact trade. Suppliers choose which requests to quote on and pay no commission on work they win.
>
> Which trades does your company cover? If you reply with them, we will set up your company page for you.
>
> (signature, stop line)

**Variant C, "two sentences" (ranked third).** It implies buyers are already sending requests, which is not yet true,
and its context-free opening reads like a template.

> Subject: `{Trade} work in the UAE`
>
> Hi {Company} team,
>
> Do you take on {trade} work for companies in the UAE? I'm Ahmad, founder of QuotesDone in Dubai, and I'm collecting {trade} suppliers to send our buyers' requests for quotation to.
>
> (signature, stop line)

**What was applied, exactly.**
- `scripts/sql/the_supplier_invitation_asks_one_question_and_makes_no_offer.sql` (applied 27 Oct, `PROBE OK`, read
  back identical):
  - `invite_subject` = `A question about your work in the UAE`;
  - `invite_body` = variant A with `{{company}}` and the no-trade wording.
- **The email itself is built in code.** `send_outbox/m365_lane.ts` `m365InvitationText` / `m365Subject`, used by both
  the Microsoft 365 lane and the Resend fallback through `campaignMail`, now writes variant A.
- That code reaches production only when this PR is merged and `send_outbox` is deployed. **Until then the deployed lane
  sends the old text in bursts.**
- `scripts/checks/the_supplier_invitation_carries_no_link.test.mjs` now fails if the stored body and the lane's text
  drift apart.

**Rollback (previous values).** Re-applying the update block of
`scripts/sql/the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql` restores
the previous keys, and reverting this PR's `m365_lane.ts` copy hunk restores the previous code. Previous
`invite_subject`: `Quote requests in the UAE`. Previous `invite_body`:

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

## 4. Compressed warm-up and the one re-test (founder, 27 Oct: "do the warm up immediately after the fix. we cant wait for a week")

**Day 0 is the day this PR's `send_outbox` is deployed.** Before day 0, two things must be true:
1. TNEF is off (3b).
2. One copy is checked in the founder's Gmail: **no `winmail.dat`**, and `List-Unsubscribe-Post` present.

| Day | Who supplier@ writes to | Volume | What the other side does |
|---|---|---|---|
| **0** | The founder's own 5 mailboxes (the coordinator has queued the invitation copies) | 5 | He opens each one, moves it out of Junk or Promotions ("Not junk" / "Move to Primary"), adds supplier@ to contacts, and **replies** with a line or two. supplier@ answers each reply, so every one becomes a thread |
| **1** | People who know Ahmad personally or through business, chosen for **Outlook.com / Hotmail / Live / Office 365 and Yahoo / AOL** addresses first (that is where the score is). Includes his Dorata mailbox (`doratajewelries.com` is its own Microsoft 365 tenant, measured: real external Microsoft traffic). A short personal note from supplier@, not the invitation template, that asks something they will answer | about 10 | open, reply, rescue from Junk if needed |
| **2** | the same circle plus new contacts | about 15 | the same; supplier@ answers every reply the same day |
| **3** | the same | about 20 | the same. **Re-test that afternoon** (below), only if the replies came in |

Rules for every day:
- **Never a real supplier, never a cold address.** Invitations stay held (`invite_enabled=false`).
- Messages go through the paced lane: at most 5 per 15 minutes.
- Any copy that lands in Junk is rescued by its reader. A rescued message is worth more than a new one.

**The re-test (day 3, the single remaining credit; balance read 27 Oct: 1 test available).**
- It runs through `deliverability_test` with the live variant-A invitation over the M365 lane, paced 5 per run (about 6
  hours for 112 seeds).
- It stores per-provider placement, plus the Microsoft seeds' `X-Forefront-Antispam-Report` / `X-Microsoft-Antispam`
  (SCL, BCL, CAT), so a second failure says whether it was reputation (SCL with BCL 0) or bulk (BCL).
- Pass: Outlook (outlook.com + hotmail + Office 365 seeds together) **≥ 80% inbox**, as ledger 1312 requires.
- Hold the re-test if day 0–3 produced fewer than about 30 two-way threads. A credit spent too early is lost.

**The honest risk of compressing it.**
- Nothing measured says Microsoft rebuilds a new mailbox's reputation in three days. GlockApps' own guidance for this
  flag is "increase gradually over several weeks", and Microsoft's is to spread volume over time.
- The 112-seed test is itself a cold send to mailboxes that never engage. On day 3 it would still be the majority of
  everything supplier@ has ever sent to strangers.
- On this evidence, **a day-3 pass at Microsoft is possible but not likely.**
- Two of the four fixes do not depend on time and could move the result on their own: TNEF off and pacing. Copy mainly
  moves Gmail.

**What would make the re-test fail again:**
1. TNEF still on: the `winmail.dat` attachment is still on every copy.
2. This PR not deployed: the old text, and bursts of 20.
3. Too little engagement: the founder's copies left in Junk, replies not sent or not answered, recipients mostly at
   Gmail rather than Outlook / Hotmail / Yahoo.
4. The seeds sent unpaced (queued with a lane that ignores `M365_PER_RUN`).
5. Simply too little history. Microsoft's verdict on a mailbox with three days of conversation may still be SCL 5.
   Then the honest plan is two to three more weeks of the same, as in the original plan.

**A failed re-test leaves zero credits.** A top-up is new spend, so it goes to the founder.

**Paid warm-up services (named for the founder's decision; nothing was signed up for).**
- They connect to the mailbox and exchange automated conversations with a network of inboxes: opening, replying, and
  rescuing from spam.
- Two of the established ones, at public list prices as last known; **not re-checked today, because this sandbox cannot
  reach vendor sites**:
  - **Warmup Inbox**, from about USD 15–19 a month per inbox;
  - **Mailwarm**, from about USD 69 a month per inbox.
- What they can and cannot do:
  - They raise daily engaged volume from the 10–20 a person-to-person circle can give to 30–50, much of it at
    Outlook / Hotmail / Gmail.
  - The vendors themselves still quote two to four weeks, so they would not make day 3.
  - They need standing access to supplier@ (IMAP/SMTP or OAuth consent), which is a security decision for the
    founder.
  - Automated engagement is something Microsoft does not endorse.
- **This is new spend, so it is the founder's decision.**
