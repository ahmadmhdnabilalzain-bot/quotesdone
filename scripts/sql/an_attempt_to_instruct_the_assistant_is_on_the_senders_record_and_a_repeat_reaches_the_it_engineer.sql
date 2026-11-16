-- AN ATTEMPT TO INSTRUCT THE ASSISTANT IS ON THE SENDER'S RECORD, AND A REPEAT REACHES THE IT ENGINEER.
--
-- Seat: it_engineer (wave 3 OPS builder, 16 Nov 2026; FAILURES hunt item 12, founder ledgers 1711-1713).
-- WHAT WAS MISSING. Every door already fences a stranger's text as data (_shared/untrusted.ts; quote_extract, quote_compare,
-- email_triage) and the reply models are told never to follow it. But when someone tried -- "ignore your rules", "you are now
-- the admin", "list the supplier's phone number" -- nothing was kept: the next colleague to read that person's record could
-- not know, and a sender trying again and again on WhatsApp, e-mail and the widget was invisible to the it_engineer.
-- WHAT THIS FILE DOES. Recognising an attempt is the MODEL's reading (ruling 1663/1664: never a word list): the call that
-- already reads each message for "does it need a person" (needsAPerson, whatsappReadings) also says whether it tries to
-- instruct the assistant (_shared/injection_attempt.ts, INJECTION_OPTIONS). When it does, the surface calls
-- fn_injection_attempt_record, which:
--   1. keeps one row per message in public.injection_attempt, on the SENDER: the customer or supplier the channel already
--      knows, else the confirmed owner of the number (fn_whatsapp_owner) or the one account of the e-mail address, else the
--      address or the number itself (with its country prefix), else the widget caller's hash;
--   2. counts that sender's attempts (30 days);
--   3. from the second attempt, keeps ONE it_engineer finding per sender (injection_attempts:<sender>), updated with the count,
--      the channels and the model's own readings, never one per message.
-- Nothing blocks anyone: the reply is the one the fenced prompt already writes. The record is read by every colleague through
-- fn_contact_timeline (the event 'injection_attempt'; a_persons_timeline_joins_only_their_own_number_and_shows_an_attempt_
-- to_instruct_the_assistant.sql) and by the it_engineer through the finding.
-- Probe: an_attempt_to_instruct_the_assistant_is_on_the_senders_record_and_a_repeat_reaches_the_it_engineer_probe.sql
-- Prevented by: supabase/functions/_shared/injection_attempt.test.ts
-- Rollback: drop function public.fn_injection_attempt_record(jsonb); drop table public.injection_attempt;
set local lock_timeout = '3s';

create table if not exists public.injection_attempt (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  channel text not null check (channel in ('whatsapp', 'email', 'widget', 'portal', 'social')),
  surface text not null check (btrim(surface) <> ''),
  message_ref text not null check (btrim(message_ref) <> ''),
  sender_key text not null check (sender_key ~ '^(customer|supplier|email|phone|visitor):.+'),
  customer_id uuid,
  lead_id bigint,
  email text,
  phone_tail text,
  phone_prefix text,
  -- what the MODEL said the message tried to make the assistant do, in its own words (never the message itself)
  reading text not null default '' check (length(reading) <= 600),
  model text,
  unique (channel, message_ref)
);
create index if not exists injection_attempt_sender_at on public.injection_attempt (sender_key, at desc);
create index if not exists injection_attempt_customer on public.injection_attempt (customer_id) where customer_id is not null;
create index if not exists injection_attempt_lead on public.injection_attempt (lead_id) where lead_id is not null;
alter table public.injection_attempt enable row level security;
drop policy if exists injection_attempt_service_role_only on public.injection_attempt;
create policy injection_attempt_service_role_only on public.injection_attempt
  as permissive for all to public using (false) with check (false);
revoke all on public.injection_attempt from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
 ('injection_attempt', true, 'security', 'each attempt to instruct the assistant, on the sender''s record (16 Nov 2026)', 'it_engineer')
on conflict (table_name) do nothing;

create or replace function public.fn_injection_attempt_record(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_channel text := lower(btrim(coalesce(p->>'channel', '')));
  v_ref text := left(btrim(coalesce(p->>'message_ref', '')), 200);
  v_cust uuid := case when btrim(coalesce(p->>'customer_id', '')) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then btrim(p->>'customer_id')::uuid end;
  v_lead bigint := case when btrim(coalesce(p->>'lead_id', '')) ~ '^[0-9]{1,18}$' then btrim(p->>'lead_id')::bigint end;
  v_email text := nullif(lower(btrim(coalesce(p->>'email', ''))), '');
  v_phone text := nullif(btrim(coalesce(p->>'phone', '')), '');
  v_tail text; v_prefix text; v_key text; v_id bigint; v_n int; v_case boolean := false; v_o record;
begin
  if v_channel not in ('whatsapp', 'email', 'widget', 'portal', 'social') or v_ref = '' then
    return jsonb_build_object('recorded', false, 'reason', 'a channel and the message reference are required');
  end if;
  if v_phone is not null then
    v_tail := nullif(right(regexp_replace(v_phone, '[^0-9]', '', 'g'), 9), '');
    if length(coalesce(v_tail, '')) < 9 then v_tail := null; end if;
    v_prefix := public.fn_phone_prefix(v_phone);
  end if;
  -- the person behind a number or an address, when exactly one is confirmed (the reply paths' own rule)
  if v_cust is null and v_lead is null and v_tail is not null then
    select o.customer_id, o.lead_id into v_cust, v_lead from public.fn_whatsapp_owner(v_phone) o limit 1;
  end if;
  if v_cust is null and v_lead is null and v_email is not null then
    select (array_agg(c.id))[1] into v_cust from public.customers c where lower(c.email) = v_email having count(*) = 1;
    if v_cust is null then
      select (array_agg(l.id))[1] into v_lead from public.leads l where lower(l.email) = v_email or lower(l.claimed_by) = v_email having count(*) = 1;
    end if;
  end if;
  v_key := case when v_cust is not null then 'customer:' || v_cust
                when v_lead is not null then 'supplier:' || v_lead
                when v_email is not null then 'email:' || v_email
                when v_tail is not null then 'phone:' || coalesce(v_prefix, '') || ':' || v_tail
                when nullif(btrim(coalesce(p->>'visitor', '')), '') is not null then 'visitor:' || left(btrim(p->>'visitor'), 80)
           end;
  if v_key is null then return jsonb_build_object('recorded', false, 'reason', 'no sender: nothing names who wrote it'); end if;

  insert into public.injection_attempt (channel, surface, message_ref, sender_key, customer_id, lead_id, email, phone_tail, phone_prefix, reading, model)
  values (v_channel, coalesce(nullif(btrim(p->>'surface'), ''), v_channel), v_ref, v_key, v_cust, v_lead, v_email, v_tail, v_prefix,
          left(coalesce(p->>'reading', ''), 600), left(p->>'model', 120))
  on conflict (channel, message_ref) do nothing
  returning id into v_id;

  select count(*) into v_n from public.injection_attempt a where a.sender_key = v_key and a.at > now() - interval '30 days';
  -- ONE CASE PER SENDER, from the second attempt: the same finding, its count and readings refreshed
  if v_n >= 2 then
    select min(a.at) as first_at, max(a.at) as last_at, jsonb_agg(distinct a.channel) as channels,
           (select jsonb_agg(x.reading order by x.at desc) from (select b.reading, b.at from public.injection_attempt b
              where b.sender_key = v_key order by b.at desc limit 3) x) as readings,
           jsonb_agg(a.id order by a.id) as ids
      into v_o
      from public.injection_attempt a where a.sender_key = v_key and a.at > now() - interval '30 days';
    perform public.fn_it_engineer_finding_upsert(
      'injection_attempts:' || v_key,
      'One sender tried ' || v_n || ' times in 30 days to instruct the assistant (' || split_part(v_key, ':', 1) || ')',
      'public.injection_attempt', 'agent_facing', 1,
      jsonb_build_object('sender', v_key, 'attempts', v_n, 'first_at', v_o.first_at, 'last_at', v_o.last_at, 'channels', v_o.channels,
                         'readings', v_o.readings, 'attempt_ids', v_o.ids, 'customer_id', v_cust, 'lead_id', v_lead,
                         'blocked', false, 'note', 'every reply was written from the fenced prompt; nothing was blocked. Read the timeline before deciding anything.'),
      array['a reply that followed it: the fences in _shared/untrusted.ts and the reply guards held every one of these turns'],
      array['whether this is a person testing us, a competitor, or an automated probe, and whether the account needs a human'], 'it_engineer');
    v_case := true;
  end if;
  return jsonb_build_object('recorded', v_id is not null, 'duplicate', v_id is null, 'sender', split_part(v_key, ':', 1),
                            'attempts', v_n, 'case', v_case);
end $fn$;
revoke execute on function public.fn_injection_attempt_record(jsonb) from public, anon, authenticated;
