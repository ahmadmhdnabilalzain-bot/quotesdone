-- A SUPPLIER WHO SAYS "STOP" IS NEVER MAILED AGAIN, NOT EVEN BY A REMINDER ALREADY QUEUED (28 Oct 2026, sales_engineer;
-- founder ledger 1401, the supplier-journey audit, scenario S6).
--
-- MEASURED on production, 28 Oct 2026, in a rolled-back probe after an invited ZZ DEMO lead's "stop" reply had been
-- recorded (email_suppressions, reason unsubscribe, source reply): public.fn_suppression_stops('unsubscribe',
-- 'supplier_invite_nudge') = false. The day-3/7/14 reminder of an unopened invitation (supplier_invite_nudge) is the
-- same cold outreach as the invitation, but it was missing from the opt-out list, here and in its TS twin OPT_OUT_TYPES
-- (_shared/suppression_policy.ts) that send_outbox applies. fn_supplier_invite_nudges_due skips a suppressed address
-- when it QUEUES, but the onboarding duty queues the nudge after midnight Dubai with not_before 09:00 Dubai, so a "stop"
-- that arrives in between did not stop the nudge at the outbox. fn_email_type_is_marketing already counted it as
-- marketing; only this list disagreed.
--
-- WHAT THIS CHANGES: fn_opt_out_types() also names supplier_invite_nudge (the TS list moves in the same PR, and
-- scripts/checks/every_duty_has_an_owner_and_a_clock.test.mjs fails if the two differ). fn_suppression_stops reads it,
-- so the seat clocks and the outbox now agree that an unsubscribe stops the nudge.
-- WHAT IT DOES NOT CHANGE: which words count as "stop" (that is _shared/unsubscribe_mailbox.ts, in the same PR), and
-- no notification, lead or suppression row is touched.
create or replace function public.fn_opt_out_types()
returns text[]
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select array['supplier_invite', 'supplier_invite_nudge', 'supplier_registration_reminder', 'supplier_rfq_widened_invite']::text[]
$fn$;
revoke execute on function public.fn_opt_out_types() from public, anon, authenticated;
