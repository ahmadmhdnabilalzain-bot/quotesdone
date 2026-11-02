---
name: a-deferred-row-aged-out-by-created-at
description: "2 Nov 2026: send_outbox's 72 h stale guard read created_at, so invitations the brake deferred were held for good the minute they fell due; a supplier_invite 'held' with no last_error is that guard. Fixed: age from max(created_at, not_before); a resume reopens the day's batch."
metadata:
  type: project
---
- **Symptom.** 18 Google-class invitations (ids 116650-116668, queued 28 Oct) released for 2 Nov 11:07 Dubai went to
  `held` at 11:16, no `last_error`, 0 attempts. send_outbox logged "18 held (supplier sending gate or stale)".
- **Cause.** `email_stale_hours` (72) measured from `created_at`; a row moved on by `not_before` was 120 h "old" after
  9 minutes of being due. `held` is terminal. Now `isStale` (send_outbox/channels.ts): invitation-lane types age from
  not_before, everything else from created_at, and every row is stale 14 days after creation. Every hold writes a
  `last_error`, the supplier_emails_enabled kill switch included, so "held, no reason" no longer means two things.
- The 18 are released only by `fn_sales_engineer_releases_the_invitations_held_stale_on_2_nov` (fixed ids), called by the tick's
  batch, and only while invite_enabled + supplier_outreach_golive are on and the 3-day bounce window is under 3% (ruling 1449).
- **Second cause.** The bounce brake fires inside the 09:00 batch; the tick then answered "already ran this Dubai day",
  so a same-day resume queued nothing. A resume later than the day's batch run now reopens it, waiting while the brake's
  own 3-day window is still over the limit. The brake is unchanged.
- Prevented by: `supabase/functions/send_outbox/channels.test.ts`, `scripts/checks/a_resumed_invitation_day_sends_the_same_day.test.mjs`.
- `provider_status` on M365 invitation sends is null on every row read (46 since 29 Oct): the proof of a send is the
  `m365:<qd-notif-...>` provider_message_id, not a provider status.

Related: [[a-status-column-is-not-a-delivery-record]], [[the-invitation-gate-reads-the-glockapps-verdict]]
