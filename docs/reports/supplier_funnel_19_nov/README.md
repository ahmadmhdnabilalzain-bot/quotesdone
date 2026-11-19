# Supplier funnel, 28 Oct – 19 Nov 2026

The CEO seat's analyst measured this on 19 Nov 2026 with production SELECTs and catalog reads only.
It covers ledgers 1440, 1436, 1184, 1230 and 1373. What was built and applied the same day is
listed at the end.

## 1. The funnel

The campaign started on 28 Oct. It sends through the Microsoft 365 lane from supplier@quotesdone.com.

| Step | Count | Source |
|---|---|---|
| Marked invited (`invited_at` on or after 28 Oct) | 187 | leads |
| Actually sent | **150** | notifications, type supplier_invite, status sent |
| Delivered (not hard-bounced) | **134** (16 bounced, 10.7%) | invite_status bounced / provider_status undelivered |
| Opened (20% tracking sample, live since 4 Nov) | 12 of 18 tracked, about 67% | email_open_event, likely_human |
| Replied as a person | **4** (3.0% of delivered) | inbound_messages, supplier_question |
| Clicked | 2 | invite_clicked_at (the invitation has no link, per ruling 1301) |
| Started sign-up (email code) | 2 | email_verifications, all on the first attempt |
| Submitted a licence | 2 | registration_submitted_at |
| Approved | **2** | approved_at |

Triple Six Real Estate registered on its own (ruling 1729), so the goal counter reads 3. The older
July–August cohort had 171 invited, 10 bounced and 0 registered.

**The biggest drop is from delivered to replied: 97% of delivered suppliers never reply, even though about 67% open.** The
invitation says plainly that buyers have not started yet, so it offers a supplier nothing today.

## 2. What is our defect, and what is the market

**Sign-up itself has no defect.**
- Every one of the 5 codes issued was used on the first attempt.
- 3 licences were submitted, read and approved.
- 0 licences were rejected and 0 registrations were abandoned.

**Our defects.** Each line ends with the fix and where it now stands.

1. **The address check was too weak.** "Verified" meant only syntax plus MX for the `true` class.
   First invitations bounced like this:

   | Class | Bounced | Rate |
   |---|---|---|
   | `verified` | 1 of 74 | 1.4% |
   | maps/social | 0 of 3 | 0% |
   | `true` | 6 of 38 | 16% |
   | unchecked directory (`uaecsd`) | 8 of 32 | 25% |

   Fixed by `invitations_go_only_to_addresses_that_were_checked.sql`, applied 19 Nov.
2. **The brake tripped on too small a sample.** Brake 51 (18 Nov) fired on 2 bounces in 6 mails and
   held sending until 25 Nov. It now waits for a minimum sample: a 2-of-6 cell no longer trips.
   Probation still trips at 2 hard bounces in 20–22 sends, and 3 hard bounces in one Dubai day stop
   sending at once.
3. **37 leads were stranded.** They were queued with only cancelled notifications, and could never
   be invited. They are released: 3 are eligible again and 34 stay excluded by the evidence rule. A
   new trigger frees a lead only when a campaign stop cancels its invitation.
4. **The funnel table counted the 40 nudges as sends** (190/174 instead of 150/134). It now counts
   first invitations only.
5. **The pool figure was wrong.** The schedule note said "17,383 eligible". The real Google-hosted
   ready pool is about 291 checked addresses (234 verified, 53 maps, 4 social).
6. **A US number in UAE supplier mail.** The final-touch e-mail showed +1 218. It was removed from
   the e-mail on 19 Nov. The WhatsApp opt-in reply and ai_reply.ts still show it, and that is the
   next change.
7. **Microsoft deliverability.** Microsoft inboxes received 0 of 21 on the GlockApps test of 10 Nov,
   and only Google receives us (24/24). This is our sender's reputation, not the market. It is held
   for the founder's local session (ledger 1733).

## 3. Sending capacity and the target

- 28 send days remain, and 297–397 registrations are still needed.
- The measured rate is 2 registrations per 150 sends, 1.33% (95% interval 0.37–4.7%).
- At that rate the target needs 22,300–29,800 sends, about 800–1,060 a day.
- At the 50-a-day ceiling (ruling 1231) we would send about 1,400, which gives about 19
  registrations. The ready pool runs out after about 14 send days.

**E-mail alone cannot reach 300–400 by 31 Dec.** With every fix, it gives roughly 15–25 more
registrations this year. Only chambers of commerce and trade associations writing to their own
members, led by the founder, can close the gap, or else the target date has to move. That decision
was put to the founder on 19 Nov.

## 4. WhatsApp (ledger 1373)

WhatsApp invitations are blocked for four reasons:
- 0 opt-ins: the opt-in table is empty, and ruling 1341 counts only the "Set up my page" button or a
  yes to a consent question.
- The `supplier_invite` MARKETING template was never submitted.
- `wa_supplier_invite_golive` is false.
- WhatsApp never runs ahead of e-mail.

The sender is healthy (HIGH, ONLINE, 100K a day). Under the opt-in rule, WhatsApp is a follow-up
channel for suppliers who already engaged, not a way to find new ones.

## 5. Other channels (ledger 1184)

| Channel | State |
|---|---|
| LinkedIn | Manual only, because the User Agreement forbids automation. 1,126 company-page URLs, 49 personal profiles. |
| Supplier referral | Ready, but `supplier_referral_code` has 0 rows. |
| Chambers, founder network, Google Business profile, click-to-chat | Marked safe; 0 trials each. |
| Ads, hired caller, AI voice, bulk SMS, bought lists | Refused (1456, 1709, TDRA, 1185, PDPL). |

## 6. What was built and applied on 19 Nov 2026

- `a_cancelled_invitation_frees_its_lead_and_its_index_slot.sql`: applied 13:59 UTC, PROBE OK.
- `invitations_go_only_to_addresses_that_were_checked.sql`: applied 14:17 UTC, PROBE OK. The CEO
  decision was restart_on_checked_addresses:
  - invite_enabled true, cap 20 a day
  - projection 1 bounce in 77 checked sends
  - 2,354 eligible with evidence and 0 without
  - Google ready pool 291
- `send_outbox` was deployed with the US number removed from the final-touch e-mail.

Both files passed an independent adversarial review against the live routines, with three fixes
applied before merge (PR #2066).
