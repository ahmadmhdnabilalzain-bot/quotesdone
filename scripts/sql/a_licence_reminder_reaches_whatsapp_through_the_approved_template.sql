-- A LICENCE REMINDER REACHES WHATSAPP THROUGH THE APPROVED TEMPLATE — owner: customer_support
--
-- Founder, 22 Sep 2026 (instruction 637): "check the WhatsApp templates — you have access; I don't
-- know what you're waiting from me."
--
-- MEASURED 22 Sep 2026 (Twilio ContentAndApprovals + the live routines, read-only):
--   * supplier_doc_expiry is APPROVED at Meta in both languages (en HXf3d8… UTILITY since 21 Jul,
--     ar HX03dc… approved but classed MARKETING; its UTILITY replacement HXbeac… is still 'received').
--   * fn_licence_expiry_sweep (the T-30/14/7/expired ask) never put a single WhatsApp message on the
--     queue. Its WhatsApp branch only COUNTED: it read outreach_channel_policy.whatsapp, which has
--     said 'blocked' since 7 Sep ("zero opted-in contacts"), and wrote a licence_renewal_ask row with
--     that reason. Its email went out with to_role NULL, so trg_wa_fanout (which only twins customer
--     and supplier mail) never twinned it, and send_whatsapp had no mapping for type licence_renewal.
--     That is the audit's "licence-expiry reminders cannot go by WhatsApp".
--   * fn_doc_final_notice (the T-7 final notice, run daily by the supplier_docs duty) queued its own
--     WhatsApp row AND its email fans out a WhatsApp twin — two WhatsApps per supplier with a
--     confirmed number — and it reported 'whatsapp_deliverable': false with a note that no template
--     SID was registered. The SID has been registered and approved since 21 Jul.
--   * wa_template_sids still registers control_mode_code (HXc472…), REJECTED 4 Aug for a WABA
--     permission Meta then lacked. No code sends it (send_whatsapp tmplKey, os_api: none).
--
-- WHAT WAS WRONG. Consent is enforced where it belongs — a03_notifications_whatsapp_goes_to_a_
-- confirmed_number skips any customer/supplier WhatsApp without a confirmed number, and trg_wa_fanout
-- only twins to one — so the sweep's extra policy gate blocked the confirmed suppliers too.
--
-- CHANGES.
--   1. fn_licence_expiry_sweep: the email is addressed to_role 'supplier', so the fan-out twins it to
--      the confirmed WhatsApp number (send_whatsapp maps licence_renewal → supplier_doc_expiry in the
--      same PR). The WhatsApp ask is recorded as sent with the twin's id, or as blocked with the real
--      reason (no confirmed number). The stale policy read is gone. Subjects lose the " - QuotesDone"
--      suffix because the subject is {{1}} of a template that already opens with the brand.
--   2. notification_copy 'licence_renewal' (EN + formal Gulf Arabic), so an Arabic-registered supplier
--      is asked in Arabic by the language trigger instead of the generic '*' copy.
--   3. fn_doc_final_notice: its own WhatsApp insert is removed; the fan-out twin is counted instead,
--      and the false 'whatsapp_deliverable' claim is replaced by what was queued.
--   4. control_mode_code is removed from app_secrets.wa_template_sids (the Twilio content stays).
--
-- NOT CHANGED. The templates themselves (Meta/Twilio side), send_whatsapp's caps and staleness bar,
-- outreach_channel_policy (other readers may rely on it; its reason text is stale and says so), the
-- scheduling of fn_licence_expiry_sweep (it has no cron today; the supplier_docs duty runs the T-7
-- final notice), and every trigger on public.notifications.
--
-- Verified by scripts/sql/a_licence_reminder_reaches_whatsapp_through_the_approved_template_probe.sql
-- and by scripts/checks/support_acceptance_group_licence_expiry.mjs (runs the real sweep, rolled back).

begin;

create or replace function public.fn_licence_expiry_sweep(p_dry_run boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r          record;
  v_band     text;
  v_days     int;
  v_planned  int := 0;
  v_email    int := 0;
  v_wa       int := 0;
  v_blocked  int := 0;
  v_rows     jsonb := '[]'::jsonb;
  v_subject  text;
  v_body     text;
  v_note     bigint;
  v_twin     bigint;
  v_twin_st  text;
  v_twin_err text;
  v_dest     text;
begin
  for r in
    select l.id, l.company_name, l.email, l.phone_e164, l.license_expiry, l.license_doc_path,
           (l.license_expiry - (now() at time zone 'Asia/Dubai')::date) as days_left
      from public.leads l
     where l.license_expiry is not null
       and l.license_expiry <= (now() at time zone 'Asia/Dubai')::date + 30
       and coalesce(l.banned, false) = false
     order by l.license_expiry
     limit 500
  loop
    v_days := r.days_left;
    v_band := case
      when v_days < 0   then 'expired'
      when v_days <= 7  then 't_minus_7'
      when v_days <= 14 then 't_minus_14'
      else                   't_minus_30' end;
    v_planned := v_planned + 1;
    v_twin := null; v_twin_st := null; v_twin_err := null;
    -- Where a WhatsApp twin would go: only a number the supplier confirmed, never the raw phone.
    v_dest := public.fn_whatsapp_destination('supplier', null, r.id, r.email);

    v_subject := case when v_days < 0
      then 'Your trade licence has expired'
      else 'Your trade licence expires in ' || v_days || ' days' end;

    v_body := 'Dear ' || coalesce(r.company_name, 'Supplier') || ',' || chr(10) || chr(10)
           || case when v_days < 0
                then 'The trade licence we hold for you expired on ' || to_char(r.license_expiry, 'DD Mon YYYY')
                  || '. Until we have a valid one we cannot include you in new requests.'
                else 'The trade licence we hold for you expires on ' || to_char(r.license_expiry, 'DD Mon YYYY')
                  || ', which is ' || v_days || ' days from now.' end
           || chr(10) || chr(10)
           || 'Please send us the renewed copy. A clear photograph is fine, a PDF is better. '
           || 'You can reply to this email with it attached, or upload it in the Documents tab of your '
           || 'supplier portal: https://quotesdone.com/portal' || chr(10) || chr(10)
           || 'Nothing else is needed and there is no charge.' || chr(10) || chr(10)
           || 'QuotesDone';

    -- EMAIL. Always attempted when we hold an address. Addressed to the supplier role so the
    -- language trigger and trg_wa_fanout both see who it is for.
    if coalesce(btrim(r.email), '') <> '' then
      if not p_dry_run then
        insert into public.licence_renewal_ask
          (lead_id, band, expiry_date, days_to_expiry, channel, sent)
        values (r.id, v_band, r.license_expiry, v_days, 'email', false)
        on conflict (lead_id, expiry_date, band, channel) do nothing;

        if found then
          insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel, lead_id)
          values ('licence_renewal', 'licence_expiry', r.email, 'supplier', v_subject, v_body, 'queued', 'email', r.id)
          returning id into v_note;

          update public.licence_renewal_ask
             set sent = true, notification_id = v_note
           where lead_id = r.id and expiry_date = r.license_expiry and band = v_band and channel = 'email';

          -- The fan-out has already run (AFTER INSERT); its twin is the WhatsApp ask.
          -- Its status is whatever the BEFORE triggers made of it (queued, or captured/skipped with a reason).
          select n.id, n.status, n.last_error into v_twin, v_twin_st, v_twin_err from public.notifications n
           where n.lead_id = r.id and n.type = 'licence_renewal' and n.channel = 'whatsapp'
             and n.created_at >= now()
           order by n.id desc limit 1;
        end if;
      end if;
      v_email := v_email + 1;
    end if;

    -- WHATSAPP. The twin of the email, to the confirmed number, on the approved supplier_doc_expiry
    -- template. No confirmed number is recorded as the reason, never hidden.
    if v_twin is not null then
      if v_twin_st = 'queued' then v_wa := v_wa + 1; else v_blocked := v_blocked + 1; end if;
      insert into public.licence_renewal_ask
        (lead_id, band, expiry_date, days_to_expiry, channel, sent, notification_id, blocked_reason)
      values (r.id, v_band, r.license_expiry, v_days, 'whatsapp', v_twin_st = 'queued', v_twin,
              case when v_twin_st <> 'queued' then left(coalesce(v_twin_err, 'twin ' || v_twin_st), 500) end)
      on conflict (lead_id, expiry_date, band, channel) do nothing;
    elsif p_dry_run and v_dest is not null and coalesce(btrim(r.email), '') <> '' then
      v_wa := v_wa + 1;
    elsif coalesce(btrim(r.phone_e164), '') <> '' or v_dest is not null then
      v_blocked := v_blocked + 1;
      if not p_dry_run then
        insert into public.licence_renewal_ask
          (lead_id, band, expiry_date, days_to_expiry, channel, sent, blocked_reason)
        values (r.id, v_band, r.license_expiry, v_days, 'whatsapp', false,
                case when v_dest is null
                     then 'no confirmed WhatsApp number on file (an unverified number is never used)'
                     else 'no email was queued this run, so there was nothing to twin' end)
        on conflict (lead_id, expiry_date, band, channel) do nothing;
      end if;
    end if;

    if jsonb_array_length(v_rows) < 10 then
      v_rows := v_rows || jsonb_build_object(
        'lead_id', r.id, 'company', r.company_name, 'expiry', r.license_expiry,
        'days_left', v_days, 'band', v_band,
        'email', case when coalesce(btrim(r.email),'')<>'' then 'queued' else 'no address held' end,
        'whatsapp', case when v_dest is not null then 'queued to the confirmed number' else 'no confirmed number' end);
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'dry_run', p_dry_run,
    'licences_within_30_days', v_planned,
    'email_asks', v_email,
    'whatsapp_asks_sent', v_wa,
    'whatsapp_asks_blocked', v_blocked,
    'whatsapp_status', 'open to confirmed numbers: the email is twinned by trg_wa_fanout and sent on the approved supplier_doc_expiry template',
    'sample', v_rows,
    'note', case when p_dry_run
      then 'Dry run. Nothing was queued and nothing was written. Call with p_dry_run => false to act.'
      else 'Asks queued. Each is closed only when a replacement document actually arrives, never when a message is sent.' end
  );
end;
$function$;

revoke execute on function public.fn_licence_expiry_sweep(boolean) from public, anon, authenticated;

insert into public.notification_copy (type, subject_en, body_en, subject_ar, body_ar, note)
values ('licence_renewal',
  'Your trade licence is due for renewal',
  'Dear supplier,' || chr(10) || chr(10)
  || 'The trade licence we hold for your company is about to expire or has expired. Please send us the renewed copy; a clear photograph is fine, a PDF is better.' || chr(10) || chr(10)
  || 'You can reply to this email with it attached, or upload it in the Documents tab of your supplier portal: https://quotesdone.com/portal' || chr(10) || chr(10)
  || 'Nothing else is needed and there is no charge.' || chr(10) || chr(10) || 'QuotesDone',
  'حان موعد تجديد رخصتكم التجارية',
  'السادة الكرام،' || chr(10) || chr(10)
  || 'نودّ إفادتكم بأن الرخصة التجارية المسجّلة لدينا لشركتكم قاربت على الانتهاء أو انتهت بالفعل. يُرجى تزويدنا بنسخة الرخصة المجدّدة، وتكفي صورة واضحة لها، ويُفضَّل إرسالها بصيغة PDF.' || chr(10) || chr(10)
  || 'يمكنكم الرد على هذه الرسالة مع إرفاق النسخة، أو رفعها من تبويب المستندات في بوابة المورّدين: https://quotesdone.com/portal' || chr(10) || chr(10)
  || 'لا يلزم أي إجراء آخر، ولا تترتب على ذلك أي رسوم.' || chr(10) || chr(10) || 'فريق QuotesDone',
  'fn_licence_expiry_sweep ask; the Arabic subject is {{1}} of the approved supplier_doc_expiry Arabic template')
on conflict (type) do update
  set subject_en = excluded.subject_en, body_en = excluded.body_en,
      subject_ar = excluded.subject_ar, body_ar = excluded.body_ar, note = excluded.note, updated_at = now();

create or replace function public.fn_doc_final_notice(p_days integer default 7)
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  rec record; v_email int := 0; v_wa int := 0; v_skipped int := 0;
  v_horizon date := current_date + make_interval(days => p_days);
  v_to text; v_label text; v_exp date;
begin
  for rec in
    select id, company_name, claimed_by, email, license_expiry, insurance_expiry
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

    -- WhatsApp is the fan-out twin of that email (confirmed number only, approved
    -- supplier_doc_expiry template). A second row of our own would be a duplicate message.
    if exists (select 1 from notifications n
                where n.lead_id = rec.id and n.type = 'doc_final_notice' and n.channel = 'whatsapp'
                  and n.created_at >= now()) then
      v_wa := v_wa + 1;
    end if;
  end loop;

  return json_build_object('emails_queued', v_email, 'whatsapp_queued', v_wa,
                           'skipped', v_skipped, 'days_ahead', p_days,
                           'whatsapp_note', 'WhatsApp goes only as the fan-out twin to a confirmed number, on the approved supplier_doc_expiry template.',
                           'ran_at', now());
end $function$;

revoke execute on function public.fn_doc_final_notice(integer) from public, anon, authenticated;

update public.app_secrets
   set value = (value::jsonb - 'control_mode_code')::text
 where key = 'wa_template_sids' and value::jsonb ? 'control_mode_code';

commit;
