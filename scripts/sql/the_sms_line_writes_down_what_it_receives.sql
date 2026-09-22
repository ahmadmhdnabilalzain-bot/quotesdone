-- THE SMS LINE WRITES DOWN WHAT IT RECEIVES (customer_support, 22 Sep 2026, finding INT-03)
--
-- MEASURED on the Twilio account, 22 Sep 2026: the number's SmsUrl was
-- https://demo.twilio.com/welcome/sms/reply — Twilio's factory default, the one every new number
-- ships with. WhatsApp on that same number has had wa_inbound since July. SMS had nothing: every
-- text anyone has ever sent us was answered by Twilio's demo responder and left no row, no log and
-- no finding anywhere in this estate. Nobody could tell you whether a single one had arrived,
-- because "zero" and "not recorded" look identical (the estate's own lens: zero cannot tell a dead
-- guard from an idle system).
--
-- This is the table the new sms_inbound edge function writes. It is a LOG, not a conversation:
-- sms_inbound authenticates the webhook, records the message and answers with an empty <Response/>.
-- It deliberately does not reply — customer_support is the only sender, and it sends from send_sms.
--
-- SHAPED LIKE wa_messages, because the same seat reads both and a second shape is a second thing to
-- learn. `verified` is the one addition: wa_inbound buries its signature verdict in meta and that
-- made twelve days of refusals invisible, so here the verdict is a column you can group by.
--
-- ALL CONVERSATIONS ARE KEPT FOR SALES (founder's standing rule): nothing purges this table.

create table if not exists public.sms_messages (
  id          bigint generated always as identity primary key,
  sms_from    text not null,
  sms_to      text not null,
  body        text not null default '',
  message_sid text,
  -- Did the X-Twilio-Signature check pass? false means the message reached the webhook but could
  -- not be proved to come from our Twilio account, and the caller got a 403. The row is still
  -- written: a refusal nobody records is a refusal nobody fixes.
  verified    boolean not null default false,
  meta        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

comment on table public.sms_messages is
  'Every SMS that reaches the Twilio number, genuine or refused, written by the sms_inbound edge function. Created 22 Sep 2026: until then the number''s SmsUrl pointed at Twilio''s demo responder and inbound SMS was recorded nowhere. Not purged (all conversations are kept for sales).';

-- Twilio retries a webhook it thinks failed, and a retry carries the same MessageSid. One row per
-- message, so a retry cannot inflate the count the seat reads.
create unique index if not exists sms_messages_message_sid_uk
  on public.sms_messages (message_sid) where message_sid is not null;
create index if not exists sms_messages_from_created_idx
  on public.sms_messages (sms_from, created_at desc);

alter table public.sms_messages enable row level security;
-- RLS on with NO policy is indistinguishable from somebody meaning to write one and forgetting, so
-- the deliberate service-role-only posture is stated in the schema. service_role bypasses RLS, so
-- the seats keep full access. Same shape as every other table in this estate (pg_policies guard so
-- a re-apply is a no-op).
do $$ begin
  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'sms_messages'
                    and policyname = 'sms_messages_service_role_only') then
    create policy sms_messages_service_role_only on public.sms_messages
      as permissive for all to public using (false) with check (false);
  end if;
end $$;
revoke all on public.sms_messages from anon, authenticated;

-- EVERY FUNCTION THAT SURVIVES NAMES ITS OWNER (founder, 8 Sep 2026). A new function with no row
-- here is the orphan state that rule exists to end, and scripts/checks/every_deployed_function_has_an_owner.mjs
-- reads this table.
insert into public.function_owner (function_slug, owner, note) values
  ('sms_inbound', 'customer_support',
   'The SMS webhook on the Twilio number. Authenticates the X-Twilio-Signature, records the message in sms_messages and answers with an empty <Response/>; it never replies, because customer_support sends from send_sms.')
on conflict (function_slug) do update
  set owner = excluded.owner, note = excluded.note;
