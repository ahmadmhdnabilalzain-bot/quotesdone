# Supplier channels and what the target needs (2 Nov 2026)

**Seat:** `ceo`. Founder ledger 1436, 1438, 1448, 1449, 1455, 1456 (no ads, no boosted content). Measured read-only on production 2 Nov 00:50 Dubai. Nothing was sent, switched or spent.
The live register is `public.ceo_supplier_channel`, measured daily by `fn_ceo_supplier_channel_measure`.

## The target, at the machinery's honest maximum

| Reading | Value |
|---|---|
| Sent, delivered, replied, started, submitted, approved (real, to date) | 52, 45, 1, 1, 0, 0 |
| Sends the dated schedule allows to 31 Dec | 2,050, on 42 sending days (excludes the 2-3 Dec holiday) |
| Starts at the measured rate (1 of 45 delivered; n = 1) | **about 39 at most**, and no start has yet become a registration |
| Sends the low target of 300 needs at that rate | about 15,600, or **372 a day**. Ledger 1455: the cap is the CEO's, on measured health, 10 a week at most, so even clean readings end near 100 a day by 31 Dec |
| Mail the placement gate allows today | Google class only: Microsoft, Yahoo/AOL and others read below the bar |
| Checked leads in the open class | **772**. At 50 a day that is about 16 sending days. Google class unchecked adds 1,951 |
| Verdict age | The GlockApps verdict dates from 27 Oct and is good for 7 days. Unless retested, all invitations hold from about 3 Nov |

**Verdict:** this machinery reaches tens of registrations, not 300. That comes from what was measured, on very small numbers, and the first real submissions will correct it. The ceiling cannot close the gap on its own, because the open pool is smaller than the schedule's room and bounces are over the limit.

Bounced of sent, all time, by lead check: unchecked 5 of 18; checked 2 of 34. Both are over the 3% limit, and 7 of 52 in 7 days (13.5%) is what the CEO's first run will act on once its switch is on: halve the cap, send checked addresses only, close the mailbox (over twice the limit), and direct `it_engineer` to clean the list.

## Channels

| Channel | State | Why | Access needed from the founder |
|---|---|---|---|
| Email, `supplier@quotesdone.com` | **On, measured** | 52 sent in 7 days through the Microsoft 365 lane | One email-verification vendor key for the 14,202 unchecked leads. Cost quoted first |
| WhatsApp, opted-in suppliers | **Built, blocked** | 0 opt-ins, template `supplier_invite` not submitted, no sender reading until this PR deploys | None. The Twilio key's sender read is proved by the first reading |
| Company page posts | Built, quiet | 66 published in total, 0 created in 30 days. Reach only: contacts nobody | None |
| Supplier referral | **Not built** | A registered supplier invites others in its trade. 0 registered today, so nothing can run yet. It takes an ask at approval, a code recorded at registration, a count per referrer | None |
| Extra sending mailboxes | **Does not exist** | The lane reads one mailbox setting; no rotation is built | M365 admin sign-in; DNS host sign-in if a new subdomain is used |
| Phone | **Does not exist** | No outbound routine; `voice_otp` hangs up | A company UAE number that is not his mobile, with Twilio regulatory approval |
| LinkedIn | List only | Automated messaging is forbidden, so a person must send | A person with admin of the company page |
| Bulk SMS | Not built | Ledger 1185 | Ruling only |

## The rules checked

- **WhatsApp.** The [WhatsApp Business Messaging Policy](https://whatsappbusiness.com/policy/) allows a message only to someone who gave their number and agreed to our messages, requires every stop to be honoured, and lets Meta limit or restrict a business on negative feedback. So the 2,863 published mobiles are not a pool. An invitation is safe only to an opt-in, which is what `fn_wa_supplier_invite_queue` enforces. Ledger 1373's "if safe" is met by that filter and no other way. The fuel is the consent question, asked of suppliers already talking to us: a tracked directive to `sales_engineer`. That pool will be small.
- **Phone.** UAE Cabinet Resolution 56 of 2024, as summarised by [Legal 500](https://www.legal500.com/developments/thought-leadership/new-telemarketing-rules-and-regulations-in-the-uae/) and [Conventus Law](https://conventuslaw.com/report/new-telemarketing-regulations-introduced-in-uae/): marketing calls 09:00-18:00, consent, the Do Not Call Registry, limits on repeat calls. The official text returned 403, so **whether it binds business-to-business calls, and any registration duty, is not confirmed**. Nothing is built, so nothing rests on it yet.

## Not measured

Microsoft 365 mailbox and Twilio or Meta token scopes; how the Google class pool converts beyond one start.
