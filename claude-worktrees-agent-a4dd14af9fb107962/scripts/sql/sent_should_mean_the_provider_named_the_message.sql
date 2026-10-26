-- "SENT" SHOULD MEAN THE PROVIDER NAMED THE MESSAGE.
--
-- public.notifications.status flips to 'sent' when Resend answers 2xx. That is an ACCEPTANCE, not a
-- delivery, and the row kept nothing that could be taken back to the provider afterwards -- no
-- message id, no timestamped receipt. So the only available answer to "did the accountant actually
-- send the founder his report?" was "a column in our own database says so", which is the same
-- confusion this estate has already been bitten by:
--
--   * a status column is not a delivery record
--   * 171 leads showed invite_status = invited while notifications held ZERO invitation rows
--   * CONNECTED is a claim, not a measurement
--
-- Resend returns an id on every accepted message. Storing it costs one column and turns an internal
-- claim into something checkable against the provider: GET /emails/<id> answers with the real
-- status, the recipient and whether an attachment rode along.
--
-- This matters most for exactly the mail the founder is about to test: the accountant's weekly
-- financial report, which now leaves with a PDF attached. "He says he sent it" and "Resend holds
-- message 4a1f... addressed to him with one attachment" are not the same sentence.

alter table public.notifications
  add column if not exists provider_message_id text;

comment on column public.notifications.provider_message_id is
  'The id Resend returned when it ACCEPTED this message, or null if it never got that far. status = '
  '''sent'' only ever meant "the provider answered 2xx"; this column is what makes that claim '
  'checkable afterwards -- GET https://api.resend.com/emails/<id> returns the provider''s own view '
  'of the message, its recipient and its attachments. Added 9 Sep 2026 alongside attachment '
  'carriage, so that "the accountant sent the founder his report" can be verified against Resend '
  'rather than against a column this company writes itself.';

create index if not exists notifications_provider_message_id_idx
  on public.notifications (provider_message_id)
  where provider_message_id is not null;

do $do$
declare v_col int; v_idx int;
begin
  select count(*) into v_col from information_schema.columns
   where table_schema='public' and table_name='notifications' and column_name='provider_message_id';
  if v_col <> 1 then raise exception 'provider_message_id was not added'; end if;

  select count(*) into v_idx from pg_indexes
   where schemaname='public' and tablename='notifications'
     and indexname='notifications_provider_message_id_idx';
  if v_idx <> 1 then raise exception 'the lookup index was not created'; end if;

  raise notice 'provider_message_id present and indexed';
end
$do$;
