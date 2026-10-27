-- A LICENCE IS ASKED FOR AT 30 AND 7 DAYS AND PAUSED ON ITS EXPIRY DAY (founder ruling 1209, 13 Oct 2026).
-- Assigned: sales_engineer (document validity is the sales engineer's since 9 Sep; the duty is
-- sales_engineer.licence_expiry_watch, #938). Deterministic: templated English, no model.
--
-- WHAT ALREADY DID MOST OF IT, and is reused rather than duplicated: the daily duty
-- sales_engineer.licence_expiry_watch -> fn_it_engineer_licence_expiry_watch -> fn_licence_expiry_sweep (email to
-- every supplier inside 30 days, twinned on WhatsApp by trg_wa_fanout to a CONFIRMED number only, on the approved
-- supplier_doc_expiry template; one row per lead, expiry, band and channel in licence_renewal_ask) and
-- fn_reconcile_doc_blocks (pauses an approved supplier whose licence is past its date and tells them; restores when
-- the date on file is valid again). What ruling 1209 changes, measured against those bodies as live today:
--   1. THE THRESHOLDS were 30, 14 and 7 days plus an 'expired' ask. Now 30 and 7 only: one email (and its WhatsApp
--      twin) per threshold. A supplier first seen at 20 days gets the 30-day ask, at 7 days the 7-day ask.
--   2. THE PAUSE came the day AFTER expiry (license_expiry < current_date, and current_date is the UTC day). Now ON the
--      expiry day, the Dubai day. The sweep no longer sends its own 'expired' ask: the pause notice is the expiry-day
--      message, so the supplier hears once at each threshold.
--   3. THE RESTORE waits for a date AFTER today. A renewed licence moves the date only when it is approved: a new
--      licence whose expiry is unread is held, never approved (rulings 1176/1177,
--      a_new_licence_whose_expiry_is_unread_is_held_never_approved_probe.sql), and a held supplier is not matchable
--      whatever matching_blocked says (fn_is_matchable needs 'approved').
--   4. it_engineer's invariant inside the watch (no approved supplier past its date is matchable) reads the same day.
-- Every routine here is CREATE OR REPLACE of a live one, so its ACL is kept (no revoke: the grants are unchanged).
--
-- prevented by: scripts/checks/a_licence_is_asked_for_at_30_and_7_days_and_paused_on_its_expiry_day.test.mjs
-- probe: scripts/sql/a_licence_is_asked_for_at_30_and_7_days_and_paused_on_its_expiry_day_probe.sql

create or replace function public.fn_licence_expiry_sweep(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
       -- 1 to 30 days ahead. The expiry day itself is fn_reconcile_doc_blocks's: it pauses matching and tells the
       -- supplier that day, so a second "expired" ask here would be a second message for one threshold.
       and l.license_expiry >  (now() at time zone 'Asia/Dubai')::date
       and l.license_expiry <= (now() at time zone 'Asia/Dubai')::date + 30
       and coalesce(l.banned, false) = false
     order by l.license_expiry
     limit 500
  loop
    v_days := r.days_left;
    -- TWO THRESHOLDS, 30 and 7 days (ruling 1209). One ask per threshold per channel: the unique key
    -- (lead_id, expiry_date, band, channel) makes a re-run a no-op and a renewed licence a fresh pair.
    v_band := case when v_days <= 7 then 't_minus_7' else 't_minus_30' end;
    v_planned := v_planned + 1;
    v_twin := null; v_twin_st := null; v_twin_err := null;
    -- Where a WhatsApp twin would go: only a number the supplier confirmed, never the raw phone.
    v_dest := public.fn_whatsapp_destination('supplier', null, r.id, r.email);

    v_subject := 'Your trade licence expires in ' || v_days || case when v_days = 1 then ' day' else ' days' end;

    v_body := 'Dear ' || coalesce(r.company_name, 'Supplier') || ',' || chr(10) || chr(10)
           || 'The trade licence we hold for you expires on ' || to_char(r.license_expiry, 'DD Mon YYYY')
           || ', which is ' || v_days || case when v_days = 1 then ' day' else ' days' end || ' from now. On that day we pause new '
           || 'customer requests to you until we have approved the renewed licence.'
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
$function$
;

create or replace function public.fn_reconcile_doc_blocks(p_grace_days integer DEFAULT 0)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lic_susp int := 0; v_ins_susp int := 0; v_restored int := 0;
  -- THE EXPIRY DAY IS THE PAUSE DAY (ruling 1209): a document is paused ON its expiry date, the Dubai calendar day
  -- (current_date is the database's UTC day, four hours behind Dubai each midnight). It is restored only when the
  -- date on file is AFTER today, i.e. a renewed document was approved (rulings 1176/1177: a new licence whose
  -- expiry is unread is held, never approved, so the date does not move until it is).
  v_cut date := (now() at time zone 'Asia/Dubai')::date - p_grace_days;
  rec record;
begin
  -- ---- SUSPEND: trade licence expired -------------------------------------------------
  -- Only touches rows that are unblocked or already blocked for a document reason, so a
  -- manual block set by the team is never overwritten or silently cleared.
  for rec in
    select id, company_name, claimed_by, email, phone, whatsapp, license_expiry
      from leads
     where approval_status = 'approved' and coalesce(banned,false) = false
       and license_expiry is not null and license_expiry <= v_cut
       and (coalesce(matching_blocked,false) = false
            or matching_block_reason in ('licence_expired','insurance_expired'))
       and coalesce(matching_block_reason,'') is distinct from 'licence_expired'
  loop
    update leads set matching_blocked = true, matching_block_reason = 'licence_expired'
     where id = rec.id;
    v_lic_susp := v_lic_susp + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_suspended', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is paused - trade licence expired',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your trade licence expired on ' || rec.license_expiry || ', so your account has been temporarily paused and you will not receive new customer requests until it is renewed.' || chr(10) || chr(10) ||
      'To restore your account: reply to this email with the renewed licence attached, or upload it in the Documents tab of your supplier portal. Your account is restored automatically as soon as we have a valid copy - nothing else is needed and no fee applies.',
      'queued');
  end loop;

  -- ---- SUSPEND: insurance expired -----------------------------------------------------
  for rec in
    select id, company_name, claimed_by, email, insurance_expiry
      from leads
     where approval_status = 'approved' and coalesce(banned,false) = false
       and insurance_expiry is not null and insurance_expiry <= v_cut
       and (coalesce(matching_blocked,false) = false
            or matching_block_reason in ('licence_expired','insurance_expired'))
       and coalesce(matching_block_reason,'') is distinct from 'insurance_expired'
       -- a licence block is the more serious of the two, so do not downgrade its reason
       and coalesce(matching_block_reason,'') is distinct from 'licence_expired'
  loop
    update leads set matching_blocked = true, matching_block_reason = 'insurance_expired'
     where id = rec.id;
    v_ins_susp := v_ins_susp + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_suspended', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is paused - insurance expired',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your insurance certificate expired on ' || rec.insurance_expiry || ', so your account has been temporarily paused and you will not receive new customer requests until it is renewed.' || chr(10) || chr(10) ||
      'To restore your account: reply to this email with the renewed certificate attached, or upload it in the Documents tab of your supplier portal. Your account is restored automatically as soon as we have a valid copy.',
      'queued');
  end loop;

  -- ---- RESTORE: the blocking document is valid again -----------------------------------
  -- Only clears blocks this job set. A manual block stays put.
  for rec in
    select id, company_name, claimed_by, email, matching_block_reason
      from leads
     where matching_block_reason in ('licence_expired','insurance_expired')
       and ((matching_block_reason = 'licence_expired'
             and (license_expiry is null or license_expiry > v_cut))
         or (matching_block_reason = 'insurance_expired'
             and (insurance_expiry is null or insurance_expiry > v_cut)))
  loop
    update leads set matching_blocked = false, matching_block_reason = null where id = rec.id;
    v_restored := v_restored + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_restored', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is active again',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Thank you - your documents are up to date and your account is active again. You will start receiving matching customer requests immediately.',
      'queued');
  end loop;

  return json_build_object('licence_suspended', v_lic_susp, 'insurance_suspended', v_ins_susp,
                           'restored', v_restored, 'grace_days', p_grace_days, 'ran_at', now());
end $function$
;

create or replace function public.fn_it_engineer_licence_expiry_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_asks jsonb; v_before int; v_after int; v_fix json; v_ids jsonb;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  v_asks := public.fn_licence_expiry_sweep(false);

  -- THE INVARIANT, measured here and not trusted to the routine that sets it: an approved supplier whose licence
  -- or insurance is past its date is not matchable (fn_is_matchable reads matching_blocked).
  select count(*) into v_before from public.leads l
   where l.approval_status = 'approved' and not coalesce(l.banned, false) and not coalesce(l.matching_blocked, false)
     and (l.license_expiry <= v_today or l.insurance_expiry <= v_today);
  if v_before > 0 then v_fix := public.fn_reconcile_doc_blocks(0); end if;   -- pauses them AND tells each supplier
  select count(*), coalesce(jsonb_agg(l.id order by l.id), '[]'::jsonb) into v_after, v_ids from public.leads l
   where l.approval_status = 'approved' and not coalesce(l.banned, false) and not coalesce(l.matching_blocked, false)
     and (l.license_expiry <= v_today or l.insurance_expiry <= v_today);

  if v_after > 0 then
    perform public.fn_it_engineer_finding_upsert('licence_expiry:matchable_after_expiry',
      v_after || ' approved supplier(s) with an expired licence or insurance are still matchable after the pause ran',
      'public.leads / fn_reconcile_doc_blocks', 'customer_facing', v_after, jsonb_build_object('lead_ids', v_ids, 'owner_seat', 'sales_engineer'),
      '{}'::text[], array['why fn_reconcile_doc_blocks skipped them (a manual block reason it will not overwrite?)'], 'it_engineer');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'no expired supplier is matchable (licence_expiry_watch)'
     where issue_key = 'licence_expiry:matchable_after_expiry' and closed_at is null;
  end if;
  return jsonb_build_object('renewal_asks', v_asks - 'sample', 'expired_matchable_before', v_before,
                            'paused', v_fix, 'expired_matchable_after', v_after);
end $function$
;

update public.seat_duty
   set what = 'Renewal asks at 30 and 7 days before licence expiry (email, and WhatsApp to a confirmed number), one per threshold; on the expiry day the supplier is paused and told, until a renewed licence is approved; IT re-measures the invariant. Ruling 1209.',
       owner_file = 'scripts/sql/a_licence_is_asked_for_at_30_and_7_days_and_paused_on_its_expiry_day.sql'
 where duty = 'sales_engineer.licence_expiry_watch';

-- verdict (reads only: this file defines routines, so it must not raise)
select case when position('t_minus_14' in pg_get_functiondef('public.fn_licence_expiry_sweep(boolean)'::regprocedure)) = 0
             and position('license_expiry <= v_cut' in pg_get_functiondef('public.fn_reconcile_doc_blocks(integer)'::regprocedure)) > 0
             and exists (select 1 from public.seat_duty where duty = 'sales_engineer.licence_expiry_watch' and owner_seat = 'sales_engineer')
            then 'PROBE OK: thresholds 30 and 7, pause on the expiry day, duty sales_engineer.licence_expiry_watch'
            else 'PROBE FAILED: the sweep, the pause or the duty is not as ruled' end as verdict;
