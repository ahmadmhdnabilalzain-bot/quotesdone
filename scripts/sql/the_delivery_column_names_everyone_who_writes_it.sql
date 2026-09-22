-- THE DELIVERY COLUMN NAMES EVERYONE WHO WRITES IT (22 Sep 2026, it_engineer).
--
-- notifications.provider_status was added by every_whatsapp_says_whether_it_arrived.sql for Twilio,
-- and its comment has said since then: "Written only by fn_twilio_status_arrived." That stopped being
-- true the moment supabase/functions/resend_webhook began recording email outcomes on the same
-- column (this PR). A comment that names one writer while two write is how the next reader concludes
-- an email status is a bug and deletes it.
--
-- Nothing but comments changes here: no DDL, no data, no routine, no grant. The column keeps its
-- CHECK notifications_provider_status_known, which is exactly why the email events are recorded in
-- Twilio's vocabulary (delivery_delayed -> sending, delivered -> delivered, bounced -> undelivered,
-- complained -> delivered with provider_error_code 'complained'); the mapping lives in
-- supabase/functions/resend_webhook/delivery_status.ts and is pinned by delivery_status.test.ts.
--
-- MEASURED 22 Sep 2026: 148 notifications with a provider_message_id on channel 'email', 0 of them
-- with a provider_status — the email half of this column had never been written at all.
--
--   node scripts/apply_sql.mjs scripts/sql/the_delivery_column_names_everyone_who_writes_it.sql --apply --ddl

comment on column public.notifications.provider_status is
  'The provider''s last reported status for this notification, and it never moves backwards. '
  'WhatsApp/SMS: Twilio''s own word, written by fn_twilio_status_arrived (wa_status callback and its '
  'backstop poll). Email: Resend''s outcome in the same vocabulary, written by the resend_webhook '
  'edge function on a signature-verified event, matched by provider_message_id — delivery_delayed '
  'as sending, delivered as delivered, bounced as undelivered, complained as delivered with '
  'provider_error_code ''complained''. Nothing else writes this column.';

comment on column public.notifications.provider_error_code is
  'Why the provider''s last status is what it is: a Twilio error code for WhatsApp/SMS, or for email '
  '''bounce:<type>'' (Resend''s own bounce type) or ''complained''. Written by the same two writers as '
  'provider_status.';
