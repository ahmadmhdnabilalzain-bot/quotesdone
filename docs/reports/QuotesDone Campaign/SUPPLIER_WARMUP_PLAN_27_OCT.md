# supplier@quotesdone.com warm-up plan, 27 Oct 2026

Seat: `it_engineer`. Founder instruction 1313 ("Start the 2–3 week warm-up plan for supplier@"),
recorded with 1312 (the batch stays held until GlockApps shows Outlook at 80% inbox or more) and
1314 (ask before the internal test email from management@ to supplier@).

## State at the start (measured 27 Oct 2026, 09:52 Dubai)

| what | value | source |
|---|---|---|
| `invite_enabled` | `false`, set at 09:52:42 Dubai by `fn_invite_campaign_pause('it_engineer', …)`, 0 queued rows cancelled | `app_secrets`, `agent_runs` |
| `supplier_outreach_golive` | `true` (the founder's go is unchanged) | `app_secrets` |
| sending lane | M365, `invite_m365_mailbox = supplier@quotesdone.com` | `app_secrets` |
| `invite_warmup` window | `window_start_hour = 10`, `window_end_hour = 10`, so the window has zero width and the 09:01 tick said "window closes at 10:00" | `app_secrets`, `agent_runs` |
| real invitations ever sent | 0 `supplier_invite` rows in `notifications`. 171 leads carry `invited_at`, which is the status-column trap in `a-status-column-is-not-a-delivery-record.md` | `notifications`, `leads` |
| 27 Oct morning seed | Gmail landed in the inbox, under the **Promotions** tab. Outlook landed in the inbox (Focused), but the mail stayed inside our own tenant and carried no DKIM signature, so it says nothing about external Outlook or Hotmail | `invite_placement_check` 2026-10-27 |

So the batch is held twice over: by the switch and by the zero-width window.

## Gates before anything is sent from supplier@ to anyone outside the company

1. **GlockApps, Outlook at 80% inbox or more** (instruction 1312). Run one GlockApps Inbox Insight
   test of the live invitation over the M365 lane (`kind = 'invite_m365_seed'`, as on 5 Oct).
   Report inbox, spam and promotions for each provider. If Outlook (outlook.com, hotmail.com and
   the Office 365 seeds together) is below 80% inbox, the batch stays held and the cause is fixed
   first.
2. **The founder's yes to the internal test email** from management@ to supplier@ (instruction 1314).
   Nothing in Week 1 sends before that yes.

## COMPRESSED, 27 Oct 2026 afternoon: this replaces Week 1 below

The founder, 27 Oct: *"do the warm up immediately after the fix. we cant wait for a week"*. GlockApps
`id:2026-10-27-09:33:53:634t` measured Microsoft at **0 of 18 inbox** (EOP SCL 5 on every Microsoft seed;
SpamAssassin 0.4; `GAPPS_WARM_UP` raised), so gate 1 failed. The evidence and the fixes are in
`GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md`.

**Before day 0:**
1. PR #1648 is merged and `send_outbox` deployed (variant-A copy, 5 lane sends per run).
2. The founder sets **Exchange admin center → Mail flow → Remote domains → Default → rich-text format: Never**. Today
   every external copy arrives with a `winmail.dat` attachment and without `List-Unsubscribe-Post`.
3. One copy in his Gmail is checked for both.

| Day | supplier@ writes to | Volume | The other side |
|---|---|---|---|
| 0 (deploy day) | the founder's 5 mailboxes (copies queued by the coordinator) | 5 | opens, "Not junk" / "Move to Primary", adds the contact, **replies**; supplier@ answers |
| 1 | people who know Ahmad, Outlook / Hotmail / Office 365 and Yahoo / AOL addresses first, his Dorata mailbox included; short personal notes that ask something | ~10 | open, reply, rescue from Junk |
| 2 | the same circle, widened | ~15 | the same |
| 3 | the same | ~20 | the same; **GlockApps re-test that afternoon** with the last credit, through `deliverability_test`, paced, only if about 30 two-way threads exist |

- Never a real supplier and never a cold address: `invite_enabled` stays `false` until the re-test passes (Outlook
  ≥ 80% inbox).
- The honest risk: nothing measured says three days is enough for Microsoft. If day 3 fails, the original weeks below
  apply.
- A failed re-test leaves no credit, and a top-up is the founder's spend.

## The plan (working days only; the UAE weekend and `company_calendar` holidays do not count)

| week | days | what supplier@ sends | daily volume | moves on when |
|---|---|---|---|---|
| 1, conversation | 1–5 | Real two-way mail with mailboxes that reply: management@, the founder's Gmail, his Dorata mailbox. The first one is the internal test email, **only after his yes** | 3–5 messages, each answered | 5 days with no junk placement on the daily seed |
| 2, first invitations | 6–10 | Cold supplier invitations (English, no link: ruling 1301) | 10/day on days 6–7, 15/day on days 8–10 | bounce under 2%, 0 complaints, daily seed in the inbox |
| 3, ramp | 11–15 | Invitations | 20 → 25 → 30 → 35 → 40 | same as above |
| after | 16+ | Invitations | to the 50 ceiling of `invite_warmup` | the `fn_invite_ramp` health rules decide |

Ruling 1231's dated caps (20/day, 30 from 26 Oct, 40 from 2 Nov, 50 from 9 Nov) are upper bounds.
The batch has been held since 20 Oct, so the plan restarts low and stays under them throughout.

## Stop rules (already live, not new)

- `fn_invite_same_day_brake`: 3 or more bounces at a rate of 5% or more, or 1 complaint, pauses the
  campaign the same day.
- `invite_warmup.backoff_bounce_rate = 0.03` lowers the next day's cap.
- The daily seed check keeps reading both seed inboxes every sending day.
- A second GlockApps test runs at the start of Week 3, before volume passes 20/day.

## To resume

Resume only after gate 1 passes:

1. Set `invite_warmup.window_end_hour` back to 17.
2. Set `invite_enabled = 'true'` by hand. `fn_invite_campaign_pause` says this resume is a
   deliberate act.
3. Read back both values, and the next `supplier_invite` row's `m365:` message id.
