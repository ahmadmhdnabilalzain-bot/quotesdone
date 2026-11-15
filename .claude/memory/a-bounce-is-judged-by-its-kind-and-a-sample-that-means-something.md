---
name: a-bounce-is-judged-by-its-kind-and-a-sample-that-means-something
description: "15 Nov 2026, rulings 1696/1705: the supplier-invitation brake judges hard/policy/soft/complaint per provider class and list segment on the Wilson 95% lower bound over 14 days; the CEO restarts within a limit held as data; the ramp steps up on the same judgement; replies owed an answer go back to the model; the CEO, not the founder, accepts the marketing month and holds marketing_golive"
metadata:
  type: project
  modified: 2026-11-15
---

**What happened.** On 13 Nov 05:00 the batch's brake read 2 bounces of 32 over 3 days (6.3% > 5%) and switched invitations
off. It was a second stop inside 30 days, so it went to the CEO, whose ceiling was 0: nobody could restart. The ramp had
been stuck at a cap of 3 for days, because it grew only on 20 sends in 48 hours and 3 a day never reach 20. Measured the same
day: since the CEO's reachable_only lever (2 Nov) the company sends only checked mailboxes, which bounced 5 of 91 all time;
unchecked ones 8 of 38. One 3-day number mixed both (the lesson of 12 Aug, again).

**What is in place** (branch sales_engineer-the-supplier-funnel-runs-itself, four files pending, applied in this order):
1. `the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql`:
   `fn_invite_bounce_kind` (from `notifications.provider_error_code`), `fn_invite_bounce_judgement` (per provider class x
   segment, 14 days and today, Wilson lower bound; limits in `app_secrets.invite_bounce_judge`: hard 3%, policy 3% per class,
   complaint 0.3% on one event, soft never), `fn_invite_judge_and_brake` (the only place a judgement becomes a brake),
   `invite_brake_decision` (every brake/hold/restart/refusal with its reason), `growth_limit_change` +
   `fn_ceo_restarts_invites` (limit `ceo_invite_restarts_per_30d` = 2, a change waits a day), duty `ceo.invite_brake_review`.
2. `the_invitation_ramps_on_measured_health_and_tests_its_copy.sql`: the ramp on the judgement (+50%, at least +2, to 50);
   the copy test (`invite_variant`, words in `send_outbox/m365_lane.ts` INVITE_VARIANTS, the variant on `notifications.kind`).
3. `every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql`.
4. `the_ceo_approves_the_marketing_month_publishes_articles_and_holds_the_marketing_switch.sql`.

**How to apply:**
- Never brake on a rate without its sample: read the lower bound, by kind and by the segment actually being sent.
- A reply to a person is the model's (ruling 1339): a duty that owes an answer puts the mail back to email_triage, it never
  writes one. The final touch to a parked lead is campaign mail and may be code text; WhatsApp only as a click-to-chat link.
- The founder's emergency stop (`marketing_publishing_enabled`) is never written by the CEO.
- `scripts/checks/the_invitations_leave_on_their_own_subdomain.test.mjs` reads the newest `fn_invite_ramp` only in the
  lowercase `$fn$` spelling, so it still judges an August file; definitions copied from `pg_get_functiondef` (uppercase,
  `$function$`) are invisible to it, as the 3 Nov ramp already was.
