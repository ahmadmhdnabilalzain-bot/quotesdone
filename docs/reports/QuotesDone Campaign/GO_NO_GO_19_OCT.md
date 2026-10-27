# Supplier invitation campaign: go/no-go for Monday 19 Oct 2026

The marketing seat measured this read-only on production (htdblwldjkcgjvmqkbeh) at **03:22 Dubai (23:22 UTC, 18 Oct)**. Nothing was changed.

## Verdict: NO-GO as measured. It turns GO only if the two flags are switched on before 08:30 Dubai.

Two items fail, and both have the same cause. `supplier_outreach_golive` and `invite_enabled` are both `false`. While either one is false:
- `fn_invite_placement_day_closed` returns "supplier_outreach_golive is false", so the 04:30 UTC seed never gets queued.
- `enqueue_supplier_invites` stops at its first gate and writes nothing to the outbox.

Everything else passes. There are some warnings on content quality below.

| # | Item | Result |
|---|------|--------|
| 1 | Cap | PASS |
| 2 | Batch (20 eligible, lead 143027) | PASS (with warnings) |
| 3 | Template (English, links, tracking) | PASS (with warnings) |
| 4 | Unsubscribe (link and header) | PASS |
| 5 | Sender domain SPF / DKIM / DMARC | PASS (note: DMARC p=none) |
| 6 | Sending path (Resend lane; M365 is off) | PASS |
| 7 | Bounce and complaint webhooks | PASS |
| 8 | Placement seed at 04:30 UTC, gate reads Gmail and Outlook | **FAIL** |
| 9 | Flags (listed, not flipped) | **FAIL** (blocking: both are false) |

---

## 1. Cap: PASS
- `app_secrets.invite_daily_cap` = **20** (last updated 3 Aug).
- `fn_invite_founder_cap('2026-10-19')` = **20**. It returns 20 until 25 Oct, 30 from 26 Oct, 40 from 2 Nov, then 50.
- The cap that applies is `least(20, 20)` = 20. The `invite_warmup` base_cap is 20 and the ceiling is 50, which the founder cap lowers to 20.
- The day is open. Monday is not the UAE weekend, and `fn_supplier_invites_hold_reason` = null, so there is no holiday.
- `daily_send_cap` (outbox-wide) = 400. There is plenty of headroom.

## 2. Batch: PASS, with warnings
- Eligible pool (`fn_supplier_invite_eligible`): **17,401** leads.
- `fn_supplier_invite_candidates(20)` returns **20 rows**. Every one of them has:
  - `fn_supplier_invite_eligible` = true
  - `is_demo` = false
  - `fn_is_demo_email` = false
  - `fn_email_sendable` = `{ok:true, reason:"sendable"}`, which means not suppressed and not blocked
  - `invite_status` = null (never invited)
  - lang = `en`
- The eligibility rule also requires a measured MX record, no role-inbox, platform or careers addresses, no sanctions or screening hits, and no earlier `supplier_invite` in the outbox.
- Lead IDs: 1309, 1960, 15082, 14304, 15249, 4638, 25284, 15886, 290, 29757, 1880, 30063, 1641, 1648, 1693, 1717, 17458, 1890, 17552, 2164.
- **Lead 143027** (Assurance Corps Co., source `marketing_sourcing`) is handled correctly as a real company:
  - `is_demo` = false, and the lead is on `fn_demo_purge_kept_leads()`, so it is never purged.
  - Its email is sendable.
  - It is **not in today's batch** and is currently ineligible. The only reason is that `assurancecorps.com` has no measured MX row in `email_domain_mx`, which is the cold-invite MX rule. It has 0 notifications.
- WARN, list quality:
  - Lead 29757, "GOZL VETERINARY MEDICINES TRADING", is tagged `invite_trades = {building_materials}`. It would get the Building & Construction Materials variant.
  - Offshore and marine firms are probably in the same trade bucket: 15249 Oceaneering, 15886 SBM Offshore, 25284 OMT, 17458 Combifloat and 17552 Sonic Gauge.
- WARN, salutation: lead 14304's `company_name` is a product list. The letter would open "Dear Adhesives & Glues | Air Tools | Bolts & Nuts | Building Materials,".
- WARN, possible duplicate company: 1309 (qconworld.com) and 14304 (qcon-me.com) may both be QCON. The one-company rule keys on domain and name, so it lets both through.

## 3. Template: PASS, with warnings
- Subject (base): "Invitation: become a founding supplier on QuotesDone (free, no commission)". Today all 20 rows use marketing's plan variant: "Invitation: Building & Construction Materials supplier on QuotesDone (free, no commission)".
- Preheader is set.
- Each rendered body is about 2.0–2.1k characters. There are 0 unfilled `{{…}}` placeholders and no Arabic script, so every body is English.
- Link format: `https://quotesdone.com/en/portal?t=<claim_token>&utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&utm_content=lead-<id>`. All 20 rows carry the UTM tracking.
- HTTP check with a zero token, so no real lead was touched: **200**, after one redirect `/en/portal` → `/portal`. The UTM parameters survive the redirect. The homepage returns 200.
- WARN: the plan variant hard-codes the trade sentence "fewer than 10 Building & Construction Materials suppliers…". Mis-tagged leads (section 2) get the wrong pitch.

## 4. Unsubscribe: PASS
- The header is built in `send_outbox/payload.ts`:
  - `List-Unsubscribe: <signed https link>, <mailto:…?subject=unsubscribe>`
  - `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (RFC 8058)
- `unsubscribe_signing_key` is present, and `unsubscribe_public_base` = `https://quotesdone.com/u/unsubscribe`.
- A live bogus-token check over GET and POST returns **400** with the page "unsubscribe link is invalid or has expired…" and the mailbox fallback. That shows the proxy is up and rejects unsigned links.
- The valid-link path has been proven end to end: a suppression with `reason='unsubscribe', source='link'` was written on 13 Oct 02:16 UTC from the test send. It was not re-run today, because a valid click is a production write.

## 5. Sender domain: PASS
- The effective invitation From is `QuotesDone <invite@hello.quotesdone.com>`: `invite_lane_enabled=true`, and `fn_invite_placement_sender()` agrees.
- Resend API: `hello.quotesdone.com` has status **verified** and sending enabled (us-east-1).
- DKIM: the `resend._domainkey.hello.quotesdone.com` TXT key is published, with d=hello.quotesdone.com, so it is aligned.
- SPF: the return-path `send.hello.quotesdone.com` has `v=spf1 include:amazonses.com ~all` and an MX to amazonses. Relaxed alignment to quotesdone.com holds.
- DMARC: `_dmarc.hello.quotesdone.com` = `v=DMARC1; p=none; rua=mailto:management@quotesdone.com`. The parent `quotesdone.com` has p=quarantine.
- Note: the subdomain policy is p=none (monitor only). That is acceptable for warm-up and is not a blocker.

## 6. Sending path: PASS
- `email_enabled=true`, `supplier_emails_enabled=true`.
- `invite_m365_enabled=false` (mailbox supplier@quotesdone.com). **The M365 lane is not in use.** Invitations go through Resend on the hello.quotesdone.com lane.
- Outbox over the last 7 days: every email row is `sent`. The one exception is a single `suppressed` row, which is expected behaviour. There are 0 failed rows.
- Two manual seeds of the invitation went out on 18 Oct and the provider reported `delivered`:
  - 18:16 UTC to the Gmail seed
  - 18:46 UTC to management@quotesdone.com

## 7. Bounces and complaints: PASS
- Resend webhooks are listed as **enabled**:
  - `…/functions/v1/resend_webhook` for `email.bounced`, `email.complained`, `email.delivered` and `email.delivery_delayed`
  - `…/resend_inbound` for `email.received`
- Live evidence: the nightly `delivery_feedback_canary` to `bounced+…@resend.dev` was recorded `undelivered / bounce:permanent` within about 1 second of sending on every night from 13 to 17 Oct. Bounce events arrive.
- A complaint has not been exercised live. Its handler path is the same function.
- Brakes are in place:
  - same-day brake
  - `invite_max_bounce_rate` 0.03
  - complaint pause at ≥1 complaint (invite_warmup)

## 8. Placement seed: FAIL
- Design: `fn_invite_placement_due` queues the seed from **04:30 UTC** (deadline 06:00 UTC minus 90 minutes). The latest it can queue is **07:30 UTC**, and the read cutoff is **08:00 UTC** (12:00 Dubai). Recipients are the Gmail seed and management@quotesdone.com, which is the Outlook/M365 seed.
- **Cause 1:** `fn_invite_placement_day_closed(now)` returns "supplier_outreach_golive is false". With the flags as they are, **the seed will not be queued at 04:30 UTC**.
- **Cause 2:** `invite_placement_check` has **0 rows ever**. The automated seed, the Gmail and Graph read-back, and the gate verdict have never run end to end on production. Whether the gate reads Gmail and Outlook is therefore **unproven**.
  - The Gmail seed credential `gmail_seed_refresh_token` was refreshed on 18 Oct 17:56 UTC, but no read has ever been recorded.
  - The gate currently returns `wait` for today.
- Effect if the flags go on in time: the batch waits (tick → `wait`) until the seed is read. It sends only if both copies are found in a folder (inbox, spam or elsewhere). If a copy is not read, not sent or not found by 08:00 UTC, it holds with `fail:…`. The sending window runs 10:00–17:00 Dubai, so the batch would realistically start between noon and 17:00.

## 9. Flags: FAIL (blocking). Listed only, none flipped.
| key | value | updated |
|---|---|---|
| `invite_enabled` | **false** | 2026-08-12 19:57 UTC |
| `supplier_outreach_golive` | **false** | 2026-09-06 14:17 UTC |
| `invite_lane_enabled` | true | 2026-09-28 |
| `invite_m365_enabled` | false | 2026-10-05 |
| `marketing_golive` | false | 2026-06-24 |

From 13–16 Oct, `agent_runs` and `invite_schedule` show the same hold every weekday: "planned 20 of 17,401 at cap 20, HELD — supplier_outreach_golive is false".

---

### What turns this into GO
Switch on both `supplier_outreach_golive` and `invite_enabled`, **ideally before 04:30 UTC (08:30 Dubai), and never later than 07:30 UTC (11:30 Dubai)**. That is the founder's decision. Then check:
- An `invite_placement_check` row for 2026-10-19 appears, and both seeds reach `sent`.
- The verdict settles before 08:00 UTC.
- The `sales_engineer` tick logs "N invitation(s) queued at a cap of 20".

Optionally, fix the trade tag on lead 29757 and the name on lead 14304 before the batch is written.
