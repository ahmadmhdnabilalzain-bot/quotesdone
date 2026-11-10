-- Seat: customer_support (the one sender to suppliers). Assigned: customer_support (supplier follow-up of #1909, item 4;
-- founder ruling 1608).
--
-- MEASURED on origin/main (live bodies read 10 Nov 2026): the loss notice job_awarded_other
-- (fn_sales_engineer_tells_losing_suppliers) and the licence-renewal ask (fn_licence_expiry_sweep) were addressed to
-- leads.email, the listing's address, scraped or typed by whoever invited the company. The address a registered
-- supplier signs in with, proves by a code and reads, is leads.claimed_by. Production: 1 lead's claimed_by differs from
-- its email today. Every other supplier notice already wrote coalesce(claimed_by, email) by hand (fn_cancel_inquiry,
-- fn_inquiry_add_missing_specs, fn_inquiry_change_from_customer, fn_sales_engineer_tells_matched_suppliers,
-- fn_reconcile_doc_blocks, fn_doc_final_notice, fn_edit_inquiry, fn_supplier_notice). The edge side had the same
-- mistake twice in customer_api/lib/matching.ts (job_awarded_other and new_inquiry): fixed there with
-- _shared/supplier_address.ts, the TypeScript twin of the helper below.
--
-- WHAT THIS CHANGES: one helper, fn_supplier_address(claimed_by, email): the sign-in address, else the listed one,
-- trimmed and lower-cased; and the two routines above read it. Their bodies are production's, byte for byte, but for
-- that one expression.
-- NOT CHANGED: the routines that already chose claimed_by first (they may move to the helper when next touched).
-- prevented by: scripts/checks/a_supplier_is_written_at_the_address_it_signs_in_with.test.mjs and this file's _probe.sql.
-- Pending until the release applies it: scripts/sql/pending/a_supplier_is_written_at_the_address_it_signs_in_with.txt

create or replace function public.fn_supplier_address(p_claimed_by text, p_email text)
 returns text
 language sql
 immutable
 set search_path to 'pg_catalog', 'pg_temp'
as $fn$
  select nullif(lower(btrim(coalesce(nullif(btrim(p_claimed_by), ''), p_email, ''))), '')
$fn$;
revoke execute on function public.fn_supplier_address(text, text) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_tells_losing_suppliers(p_inquiry uuid, p_winner bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare i public.inquiries; c public.customers; v_fx boolean; l record; v_job text; v_why text; v_d jsonb; v_told int := 0; v_not int := 0;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('told', 0, 'reason', 'no such request'); end if;
  select * into c from public.customers where id = i.customer_id;
  v_fx := coalesce(public.fn_seat_clock_customer_is_fixture(c), false);
  v_job := 'the ' || coalesce(public.fn_trade_label(i.category, 'en'), 'job') || coalesce(' job in ' || nullif(btrim(i.emirate), ''), ' job')
           || ' (request ' || coalesce(i.rfq_no::text, '-') || ')';
  for l in select le.id, coalesce(public.fn_supplier_address(le.claimed_by, le.email), '') as to_email
             from (select distinct q.supplier_id from public.quotes q where q.inquiry_id = p_inquiry and q.supplier_id is distinct from p_winner) x
             join public.leads le on le.id = x.supplier_id
            where not coalesce(le.banned, false) and not public.fn_is_sanctioned_lead(le.id) loop
    v_why := public.fn_seat_clock_refusal(v_fx, l.to_email, 'job_awarded_other');
    if v_why is not null then v_not := v_not + 1; continue; end if;
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'job_awarded_other', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', l.to_email, 'to_role', 'supplier',
      'lead_id', l.id, 'inquiry_id', p_inquiry, 'lang', 'en', 'subject', 'Update on a job you quoted — QuotesDone',
      'body', 'Thank you for taking the time to quote on ' || v_job || '. On this occasion the customer has chosen to proceed with another supplier. We genuinely appreciate the effort you put into your quote, and it was great having you compete for the work. New matching opportunities come through QuotesDone regularly — please keep an eye on your supplier inbox, and we wish you the very best of luck on the next one.',
      'dedupe_key', 'job_awarded_other:' || p_inquiry || ':' || l.id)));
    if coalesce(v_d->0->>'status', '') in ('done', 'demo_captured', 'pending', 'claimed') then v_told := v_told + 1; else v_not := v_not + 1; end if;
  end loop;
  return jsonb_build_object('told', v_told, 'not_told', v_not);
end $function$;

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
    -- the address the supplier signs in with (fn_supplier_address), not the listing's scraped one
    select l.id, l.company_name, public.fn_supplier_address(l.claimed_by, l.email) as email, l.phone_e164, l.license_expiry, l.license_doc_path,
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
$function$;

select case
  when public.fn_supplier_address(' Owner@ZZ-Demo.example.invalid ', 'listing@zz-demo.example.invalid') is distinct from 'owner@zz-demo.example.invalid'
    or public.fn_supplier_address('', 'Listing@zz-demo.example.invalid') is distinct from 'listing@zz-demo.example.invalid'
    or public.fn_supplier_address(null, null) is not null
    then 'PROBE FAILED: fn_supplier_address does not pick the sign-in address first'
  when position('fn_supplier_address(le.claimed_by, le.email)' in pg_get_functiondef('public.fn_sales_engineer_tells_losing_suppliers(uuid, bigint)'::regprocedure)) = 0
    or position('fn_supplier_address(l.claimed_by, l.email)' in pg_get_functiondef('public.fn_licence_expiry_sweep(boolean)'::regprocedure)) = 0
    then 'PROBE FAILED: a routine still writes to the listed address'
  when has_function_privilege('anon', 'public.fn_supplier_address(text, text)', 'execute') then 'PROBE FAILED: anon can run fn_supplier_address'
  else 'PROBE OK' end as verdict;
