---
name: an-invitation-open-is-measured-on-a-tracked-share
description: 3 Nov 2026. Founder asked to know who opens the invitation. A share (app_secrets.invite_open_tracking, seeded 20) gets an HTML twin with one first-party pixel; the rest stay plain text. Opens are a floor, never a read receipt.
metadata:
  type: project
---

**The ask (founder, 3 Nov 2026):** "I want us to know when someone opened our invitation email. If they read our email and
chose not to register, this is very valuable information for the team and the CEO."

**The ruling it changes:** founder_instruction 1301 (27 Oct), "safer to not send links" — the invitation is plain text, no
link. A pixel is an image URL inside an HTML part, so it is contained, not general:
- `app_secrets.invite_open_tracking` = 'off' or a whole percentage (seeded '20'). The arm is a fixed hash of the lead
  (`fn_invite_open_arm`), so tracked and untracked compare. 'off' = send_outbox makes no call and sends today's bytes.
- Tracked = multipart/alternative: the SAME text part, plus an HTML twin with ONE 1x1 image at
  `https://quotesdone.com/u/o/<token>.gif` (`src/app/u/o/[token]/route.ts`). Token = random 32 hex (gen_random_uuid),
  never the email or lead id. Placement seeds (GlockApps) are never tracked.
- Opens: `email_open_event` (salted hash of the address, never the raw IP), classified by `fn_email_open_classify`.

**Read the numbers honestly:** Outlook and most corporate mail block remote images from a new sender, so "opened" is a
floor; Apple Mail Privacy Protection and scanners load images without a person (known ones are machine_prefetch, not all).
The untracked arm has no opens by construction: compare arms on bounce / complaint / reply / unsubscribe / registered rates
and on inbox placement (a GlockApps run of the tracked variant needs the founder's OK: it costs a credit).

**Where it shows:** `fn_invite_open_summary` in `fn_marketing_report_figures` (measured.invitation_opens + a headline
sentence) and in `fn_ceo_seat_board` (seats.marketing.achievement.invitation_opens). Follow-up list:
`fn_invite_opened_not_registered(days)`. Privacy Policy 1.9 section 9 says so (unsigned: nobody re-accepts).
Files: `scripts/sql/an_invitation_open_is_measured_on_a_tracked_share_and_reaches_the_ceo.sql` (+ `_probe.sql`),
`scripts/sql/the_privacy_policy_1_9_says_we_measure_invitation_opens.sql`, `supabase/functions/send_outbox/open_tracking.ts`.
