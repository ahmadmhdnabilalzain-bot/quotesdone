-- Assigned: sales_engineer
-- AN APPROVED SUPPLIER WHOSE NEW LICENCE IS NEVER READ GOES TO THE CEO SEAT (12 Nov 2026, sales_engineer; review of #1982, L3-1;
-- founder rulings 1663 and 1664, "Trade license reading ... there's no code first, 100%").
--
-- Since #1982 an APPROVED supplier who attaches a new licence keeps the reading we accepted (name, number, expiry, authority) while
-- the model reads the new file: the row names the new file with licence_read_state 'ours_failed', and he stays approved, matched and
-- badged on the old reading (_shared/licence_read_state.ts keepsAcceptedReading). The re-read sweep tries the file up to 8 times
-- (fn_supplier_licence_reread_claim, about 42 hours). After that nothing happened: the three-day hand-over to the ceo seat in
-- fn_sales_engineer_decides_held_registrations reads approval_status = 'pending' only. So an approved supplier who attached ANOTHER
-- company's licence, or a forged or expired one, while the provider was down stayed approved on the old reading for good, the new
-- file unread and nobody told (read from the live definitions, 12 Nov 2026).
--
-- Now: fn_sales_engineer_hands_unread_approved_licences_to_ceo puts each such supplier (approved, 'ours_failed', failing for three
-- days) to the ceo seat ONCE PER LICENCE FILE, kept exactly as the pending case keeps it: an agent_actions row of kind
-- 'held_registration_for_ceo' whose detail.clock names the file. Nothing is sent to the supplier and his standing is not changed:
-- the person reads the file and decides. The decider calls it on its daily run. p_lead_id limits it to one supplier (the probe).
-- fn_sales_engineer_decides_held_registrations is replaced from its LIVE definition (pg_get_functiondef, 12 Nov 2026) with only the
-- call and one key of its answer added; CREATE OR REPLACE keeps its ACL (postgres, service_role).
-- Probe: scripts/sql/an_approved_supplier_whose_new_licence_is_never_read_goes_to_the_ceo_seat_probe.sql
-- Prevented by: that probe, and scripts/checks/an_approved_supplier_whose_new_licence_is_never_read_is_handed_on.test.mjs

create or replace function public.fn_sales_engineer_hands_unread_approved_licences_to_ceo(p_at timestamptz default now(), p_lead_id bigint default null)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_key text; v_n int := 0;
begin
  for r in select l.id, l.company_name, l.license_doc_path, l.licence_read_failed_since, l.trade_license_no, l.license_expiry
             from public.leads l
            where l.approval_status = 'approved' and not coalesce(l.banned, false)
              and l.licence_read_state = 'ours_failed' and l.license_doc_path is not null
              and l.licence_read_failed_since <= p_at - interval '3 days'
              and (p_lead_id is null or l.id = p_lead_id)
              -- our own fixtures are read again only by a fixture run (fn_supplier_licence_reread_claim), so outside one their files only
              -- ever "fail": a demo supplier is handed over only in a fixture run, a real one only outside it (review of #1982, LICENCE 4 a)
              and (coalesce(l.is_demo, false) or public.fn_is_demo_email(l.claimed_by) or coalesce(l.company_name, '') ~* '^\s*zz\s*demo')
                  = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
              -- once per licence file, decided in the WHERE so the 200 a run takes are all still to do (LICENCE 4 b)
              and not exists (select 1 from public.agent_actions a
                                where a.kind = 'held_registration_for_ceo' and a.target_id = l.id::text
                                  and a.detail ->> 'clock' = 'approved_licence_unread:' || l.license_doc_path)
            order by l.id limit 200 loop
    v_key := 'approved_licence_unread:' || r.license_doc_path;
    perform public.fn_ceo_task_open('Read the new trade licence of an approved supplier: ' || left(coalesce(r.company_name, '#' || r.id), 120),
      'Supplier ' || r.id || ' is APPROVED and attached a new trade licence file that our document reader has failed on since '
      || to_char(r.licence_read_failed_since at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai. He stays approved, matched and badged on '
      || 'the PREVIOUSLY ACCEPTED reading (licence ' || coalesce(r.trade_license_no, 'unread') || ', expiry ' || coalesce(r.license_expiry::text, 'unread')
      || '), which is not the new file''s. Read the new file by hand: if it is his renewed licence, record its fields; if it names another company, '
      || 'looks forged or has expired, hold him. He was not asked for anything.');
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'held_registration_for_ceo', 'auto_done', 'low',
            'Approved supplier''s new licence put to the ceo seat — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
            'No action required here. The ceo task decides it.',
            jsonb_build_object('supplier_id', r.id, 'clock', v_key, 'approved', true,
                               'why', 'an approved supplier''s new licence file was not read for 3 days; the fields on file are the previously accepted reading'),
            'leads', r.id::text);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

-- CREATE grants EXECUTE to PUBLIC: closed as the decider is (postgres and service_role only).
revoke all on function public.fn_sales_engineer_hands_unread_approved_licences_to_ceo(timestamptz, bigint) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_hands_unread_approved_licences_to_ceo(timestamptz, bigint) to service_role;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_decides_held_registrations(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v jsonb; v_to text; v_first timestamptz; v_asks int; v_days numeric; v_key text; v_what text; v_replied boolean; v_ever_approved boolean; v_why text; v_asked int := 0; v_closed int := 0; v_out jsonb; v_waiting int := 0; v_to_ceo int := 0; v_approved_to_ceo int := 0;
begin
  for r in select l.id, l.company_name, l.claimed_by, l.email, l.license_doc_path, l.licence_gate_reason reason, l.approved_at, l.phone, l.licence_read_failed_since from public.leads l
            where l.approval_status = 'pending' and not coalesce(l.banned, false)
              and l.licence_gate_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread', 'licence_authority_unread', 'licence_authority_not_uae', 'licence_authority_unconfirmed', 'licence_name_mismatch', 'licence_being_read')
            order by l.id limit 200 loop
    -- A file may have arrived by a path that missed the trigger. A re-run that changes nothing writes no log.
    v := public.fn_sales_engineer_verifies_supplier(r.id, 'mandatory_item_changed');
    if v ->> 'approval_status' is distinct from 'pending' or v ->> 'reason' is distinct from r.reason then continue; end if;
    v_to := lower(nullif(btrim(coalesce(r.claimed_by, r.email)), ''));
    v_key := r.reason || ':' || coalesce(r.license_doc_path, '');
    -- OUR READER FAILED, NOT THE FILE (10 Nov 2026, customer_support; _shared/licence_read_state.ts). The supplier is never
    -- asked for a clearer copy and the registration is never closed for it: supplier_api docs_reread reads the licence again.
    -- One that is still unread three days after our first failure is put to the ceo seat, once per licence.
    if r.reason = 'licence_being_read' then
      if coalesce(r.licence_read_failed_since, p_at) <= p_at - interval '3 days'
         and not exists (select 1 from public.agent_actions a where a.kind = 'held_registration_for_ceo' and a.target_id = r.id::text and a.detail ->> 'clock' = v_key) then
        perform public.fn_ceo_task_open('Decide a held supplier registration: ' || left(coalesce(r.company_name, '#' || r.id), 120),
          'Supplier ' || r.id || ' is held because our document reader has failed on its trade licence since ' || to_char(r.licence_read_failed_since at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai. The supplier was not asked for anything. Read the licence by hand, record the fields, then approve.');
        insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
        values ('sales_engineer', 'held_registration_for_ceo', 'auto_done', 'low', 'Held registration put to the ceo seat — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
                'No action required here. The ceo task decides it.', jsonb_build_object('supplier_id', r.id, 'clock', v_key, 'why', 'our document reader could not read the licence for 3 days'), 'leads', r.id::text);
        v_to_ceo := v_to_ceo + 1;
      else
        v_waiting := v_waiting + 1;
      end if;
      continue;
    end if;
    select min(a.created_at), count(*) into v_first, v_asks from public.agent_actions a
     where a.kind = 'held_registration_asked' and a.target_table = 'leads' and a.target_id = r.id::text and a.detail ->> 'clock' = v_key;
    v_days := coalesce(extract(epoch from p_at - v_first) / 86400, 0);
    -- A reply stops the close: a supplier who answered is never closed unheard. Mail by lead, WhatsApp by number.
    v_replied := v_asks > 0 and (exists (select 1 from public.inbound_messages m where m.lead_id = r.id and m.created_at > v_first)
      or exists (select 1 from public.wa_messages w where w.created_at > v_first and nullif(regexp_replace(coalesce(r.phone, ''), '[^0-9]', '', 'g'), '') = regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g')));
    v_ever_approved := r.approved_at is not null;
    if v_asks > 0 and (v_replied or (v_days >= 14 and (v_ever_approved or r.reason = 'licence_authority_unconfirmed'))) then
      v_why := case when v_replied then 'the supplier replied' when v_ever_approved then 'the supplier was approved before' else 'the authority is on no list we hold' end;
      if not exists (select 1 from public.agent_actions a where a.kind = 'held_registration_for_ceo' and a.target_id = r.id::text and a.detail ->> 'clock' = v_key) then
        perform public.fn_ceo_task_open('Decide a held supplier registration: ' || left(coalesce(r.company_name, '#' || r.id), 120),
          'Supplier ' || r.id || ' is held for ' || r.reason || ' and is not closed automatically because ' || v_why || '. Read the licence and any reply, then approve or ask again.');
        insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
        values ('sales_engineer', 'held_registration_for_ceo', 'auto_done', 'low', 'Held registration put to the ceo seat — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
                'No action required here. The ceo task decides it.', jsonb_build_object('supplier_id', r.id, 'clock', v_key, 'why', v_why), 'leads', r.id::text);
      end if;
    elsif v_asks > 0 and v_days >= 14 then
      update public.leads set approval_status = 'rejected', verified = false, approval_decided_by = 'ceo',
             rejection_reason = 'registration incomplete after 14 days: ' || r.reason where id = r.id;
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('ceo', 'held_registration_decision', 'auto_done', 'low', 'Held registration closed after 14 days — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
              'No action required. The supplier was asked three times and sent nothing new. Uploading a licence and saving reopens the registration.',
              jsonb_build_object('supplier_id', r.id, 'decision', 'closed', 'reason', r.reason, 'first_asked_at', v_first, 'asks', v_asks), 'leads', r.id::text);
      if v_to is not null then
        perform public.fn_sales_engineer_writes('registration_closed', 'supplier', v_to, r.id, null, null, null, 'Your QuotesDone supplier registration has closed',
          'We asked three times for a trade licence we could accept and have not received one, so your registration is now closed. Upload your current UAE trade licence in the Documents tab of https://quotesdone.com/portal and save your profile, and it opens again.',
          null, null, '{}'::text[], 'registration_closed:' || r.id || ':' || md5(v_key));
      end if;
      v_closed := v_closed + 1;
    elsif v_asks = 0 or (v_asks = 1 and v_days >= 3) or (v_asks = 2 and v_days >= 7) then
      v_what := case r.reason
        when 'licence_authority_not_uae' then 'The trade licence you uploaded was not issued by a UAE authority, and QuotesDone registers companies licensed in the UAE. Please upload your current UAE trade licence.'
        when 'licence_authority_unconfirmed' then 'We could not confirm the authority that issued your trade licence. Please reply to this e-mail naming the UAE authority or free zone that issued it, or upload a clearer copy of the whole page.'
        when 'licence_authority_unread' then 'We could not read the issuing authority on your trade licence. Please upload a clearer copy of the whole page.'
        when 'licence_expiry_unread' then 'We could not read the expiry date on your trade licence. Please upload a clearer copy of the whole page.'
        when 'licence_number_unread' then 'We could not read the licence number on your trade licence. Please upload a clearer copy of the whole page.'
        when 'licence_name_mismatch' then 'The company name on your trade licence is already registered with us by another account. Please upload the licence of your own company, or reply to this e-mail if this is your company.'
        else 'We could not read the company name on your trade licence. Please upload a clearer copy of the whole page.' end;
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'held_registration_asked', 'auto_done', 'low', 'Asked for what a held registration is missing — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
              'No action required. Asked again at day 3 and day 7; the ceo seat closes it at day 14.',
              jsonb_build_object('supplier_id', r.id, 'clock', v_key, 'reason', r.reason, 'ask', v_asks + 1, 'told', v_to is not null), 'leads', r.id::text);
      if v_to is not null then
        perform public.fn_sales_engineer_writes('registration_held', 'supplier', v_to, r.id, null, null, null, 'Your QuotesDone registration: one thing is needed',
          v_what || ' Upload it in the Documents tab of https://quotesdone.com/portal; we read it as soon as it arrives. If you have a question, reply to this e-mail. If we hear nothing 14 days after our first request, the registration may close, and you can reopen it at any time.',
          null, null, '{}'::text[], 'registration_held:' || r.id || ':' || md5(v_key) || ':' || (v_asks + 1));
      end if;
      v_asked := v_asked + 1;
    end if;
  end loop;
  -- An APPROVED supplier whose new licence our reader has failed on for three days (12 Nov 2026): see the header of this file.
  v_approved_to_ceo := public.fn_sales_engineer_hands_unread_approved_licences_to_ceo(p_at);
  v_out := jsonb_build_object('asked', v_asked, 'closed', v_closed, 'being_read', v_waiting, 'being_read_to_ceo', v_to_ceo,
                              'approved_unread_to_ceo', v_approved_to_ceo);
  perform public.fn_it_duty_ran('held_registrations', v_out);
  return v_out;
end $function$;
