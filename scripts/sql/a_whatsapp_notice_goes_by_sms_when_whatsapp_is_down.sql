-- A WHATSAPP NOTICE GOES BY SMS WHEN WHATSAPP IS DOWN (customer_support, 24 Sep 2026, founder ledger 994).
-- "Nothing may depend on WhatsApp alone." While the IT engineer's integration watch holds
-- duty:integration:twilio_whatsapp_sender open (Twilio 63005 since 24 Sep, ticket 29665983), or when one
-- WhatsApp send fails, send_whatsapp (_shared/whatsapp_failover.ts) turns the WhatsApp row into ONE SMS
-- twin that send_sms drains. This file is the idempotent half: the twin is written here, under a row lock
-- and a unique index, so two overlapping runs or a re-scan can never queue a second SMS for one notice.

alter table public.notifications add column if not exists failover_of bigint;
comment on column public.notifications.failover_of is
  'SMS twin of the WhatsApp notification with this id (fn_wa_sms_twin). At most one twin per notice: notifications_one_sms_twin.';
create unique index if not exists notifications_one_sms_twin on public.notifications (failover_of) where failover_of is not null;

create or replace function public.fn_wa_sms_twin(p_notification_id bigint, p_body text, p_reason text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  w public.notifications%rowtype;
  v_twin bigint;
  v_mark text := 'sms failover: ' || left(coalesce(p_reason, 'WhatsApp unavailable'), 300);
begin
  select * into w from public.notifications where id = p_notification_id for update;
  if not found or w.channel <> 'whatsapp' then
    return jsonb_build_object('ok', false, 'outcome', 'not_a_whatsapp_notice');
  end if;
  if coalesce(w.to_phone, '') = '' or coalesce(btrim(p_body), '') = '' then
    return jsonb_build_object('ok', false, 'outcome', 'nothing_to_send');
  end if;
  select id into v_twin from public.notifications where failover_of = w.id;
  if v_twin is null then
    insert into public.notifications (channel, status, type, kind, to_phone, to_email, to_role, lead_id, inquiry_id,
                                      quote_id, subject, body, lang, requested_by, severity, failover_of)
    values ('sms', 'queued', w.type, w.kind, w.to_phone, w.to_email, w.to_role, w.lead_id, w.inquiry_id,
            w.quote_id, w.subject, left(p_body, 600), w.lang, w.requested_by, w.severity, w.id)
    on conflict (failover_of) where failover_of is not null do nothing
    returning id into v_twin;
    if v_twin is null then select id into v_twin from public.notifications where failover_of = w.id; end if;
  end if;
  -- A row not yet sent leaves the WhatsApp queue; a row that already failed keeps 'failed' (the truth) and
  -- carries the mark, which is also what stops send_whatsapp's failed-row scan asking again.
  update public.notifications
     set status = case when status in ('queued', 'sending') then 'skipped' else status end,
         last_error = left(case when status in ('queued', 'sending') then v_mark
                                else coalesce(last_error || '; ', '') || v_mark end, 500)
   where id = w.id and coalesce(last_error, '') not like '%sms failover:%';
  return jsonb_build_object('ok', true, 'outcome', 'sms_twin', 'sms_id', v_twin);
end $fn$;

revoke execute on function public.fn_wa_sms_twin(bigint, text, text) from public, anon, authenticated;

-- PROBE (cleans up after itself; returns a verdict row). The WhatsApp row uses the reserved fixture mobile, so
-- zzzz_notifications_demo_capture captures it and its twin: nothing here can reach a real person.
create temp table _wa_sms_twin_probe (verdict text) on commit drop;
do $probe$
declare v_wa bigint; v_twins int; v_left int;
begin
  insert into public.notifications (channel, status, type, to_phone, to_role, subject, body, lang, requested_by)
  values ('whatsapp', 'queued', 'new_quote', '+971500000099', 'customer', 'ZZ DEMO probe', 'ZZ DEMO probe body', 'en', 'customer_support')
  returning id into v_wa;
  perform public.fn_wa_sms_twin(v_wa, 'ZZ DEMO probe sms', 'probe');
  perform public.fn_wa_sms_twin(v_wa, 'ZZ DEMO probe sms', 'probe');   -- a second call must not add a twin
  select count(*) into v_twins from public.notifications where failover_of = v_wa;
  delete from public.notifications where failover_of = v_wa or id = v_wa;
  select count(*) into v_left from public.notifications where failover_of = v_wa or id = v_wa;
  insert into _wa_sms_twin_probe values (case when v_twins = 1 and v_left = 0 then 'PROBE OK'
    else 'PROBE FAILED: ' || v_twins || ' SMS twin(s) for one notice, ' || v_left || ' probe row(s) left' end);
end $probe$;
select verdict from _wa_sms_twin_probe;
