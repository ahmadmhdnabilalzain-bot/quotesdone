-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721131409   name: supplier_doc_final_notice_email_and_whatsapp
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Final notice, one week before a gating document expires, on email AND WhatsApp.
--
-- The existing doc_reminder edge function emails at 14 days about six document types. This is the
-- deliberate LAST contact before the account is actually paused, and it is the only message that
-- states the consequence and the deadline. It covers only the two documents that can cause a
-- suspension (trade licence, insurance) - warning someone about an ISO lapse that will not pause
-- their account would train them to ignore the message that will.
--
-- WHATSAPP CAVEAT, stated rather than hidden: send_whatsapp only transmits business-initiated
-- messages through Twilio templates approved by Meta, resolved in tmplKey(). There is no approved
-- template for document expiry yet, so a queued WhatsApp row for this type is marked 'skipped' and
-- never delivered. The row is still queued here, and send_whatsapp is being taught the mapping, so
-- delivery begins the moment the template SID is registered in wa_template_sids - no code change.
-- Until then this is an EMAIL-ONLY notice, and the counters below report the two separately so the
-- gap stays visible instead of looking like a delivery success.

create or replace function public.fn_doc_final_notice(p_days integer default 7)
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  rec record; v_email int := 0; v_wa int := 0; v_skipped int := 0;
  v_horizon date := current_date + make_interval(days => p_days);
  v_phone text; v_to text; v_label text; v_exp date;
begin
  for rec in
    select id, company_name, claimed_by, email, phone, whatsapp,
           license_expiry, insurance_expiry
      from leads
     where approval_status = 'approved'
       and coalesce(banned,false) = false
       and coalesce(matching_blocked,false) = false
       and ((license_expiry   is not null and license_expiry   between current_date and v_horizon)
         or (insurance_expiry is not null and insurance_expiry between current_date and v_horizon))
  loop
    -- Whichever gating document expires first is the one we lead with.
    if rec.license_expiry is not null and rec.license_expiry between current_date and v_horizon
       and (rec.insurance_expiry is null or rec.license_expiry <= rec.insurance_expiry) then
      v_label := 'trade licence'; v_exp := rec.license_expiry;
    else
      v_label := 'insurance certificate'; v_exp := rec.insurance_expiry;
    end if;

    -- One final notice per document per expiry cycle. Without this the daily cron would send
    -- the same warning seven days running.
    if exists (select 1 from notifications
                where type = 'doc_final_notice' and lead_id = rec.id
                  and subject like '%' || v_label || '%'
                  and created_at > now() - interval '20 days') then
      v_skipped := v_skipped + 1; continue;
    end if;

    v_to := nullif(trim(coalesce(rec.claimed_by, rec.email)), '');
    if v_to is null or position('@' in v_to) = 0 then v_skipped := v_skipped + 1; continue; end if;

    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_final_notice', v_to, 'supplier', rec.id, 'email',
      'Final reminder: your ' || v_label || ' expires on ' || v_exp,
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your ' || v_label || ' on file with QuotesDone expires on ' || v_exp || '.' || chr(10) || chr(10) ||
      'If we do not have a valid copy by then, your account will be paused automatically and you will stop receiving customer requests until it is renewed. This is temporary and there is no fee to restore it.' || chr(10) || chr(10) ||
      'Two ways to fix it, either is fine:' || chr(10) ||
      '  1. Reply to this email with the renewed document attached. Our system reads it and updates your profile automatically.' || chr(10) ||
      '  2. Upload it in the Documents tab of your supplier portal: https://quotesdone.com/portal' || chr(10) || chr(10) ||
      'If you have already renewed, please send us the latest copy so our records match.',
      'queued');
    v_email := v_email + 1;

    -- WhatsApp: queued for the same supplier when we hold a number. Delivery depends on the
    -- approved template described in the header comment.
    v_phone := nullif(trim(coalesce(rec.whatsapp, rec.phone)), '');
    if v_phone is not null then
      insert into notifications(type,to_email,to_role,lead_id,channel,to_phone,subject,body,status)
      values ('supplier_doc_expiry', v_to, 'supplier', rec.id, 'whatsapp', v_phone,
        'Your ' || v_label || ' expires on ' || v_exp,
        'Your ' || v_label || ' expires on ' || v_exp || '. Renew it to keep receiving QuotesDone requests: https://quotesdone.com/portal',
        'queued');
      v_wa := v_wa + 1;
    end if;
  end loop;

  return json_build_object('emails_queued', v_email, 'whatsapp_queued', v_wa,
                           'skipped', v_skipped, 'days_ahead', p_days,
                           'whatsapp_deliverable', false,
                           'whatsapp_note', 'Queued but not deliverable until a supplier_doc_expiry template SID is registered in wa_template_sids.',
                           'ran_at', now());
end $function$;

comment on function public.fn_doc_final_notice(integer) is
  'Last warning before a supplier is paused for an expired trade licence or insurance. Queues email (deliverable now) and WhatsApp (deliverable once an approved Twilio template SID is registered).';

revoke all on function public.fn_doc_final_notice(integer) from public, anon, authenticated;
