-- A SUPPLIER IS SENT NO SCORECARD FOR A MONTH BEFORE HE WAS APPROVED, OR FOR A MONTH NO REQUEST REACHED HIM.
-- Seat: sales_engineer. 18 Nov 2026.
--
-- WHAT WAS MEASURED (production, read-only, 18 Nov 2026):
--   * Shine Carpets Washing L.L.C. (leads 2936) registered on 17 Nov 2026 08:38 UTC and was approved at 08:40. On 18 Nov 02:00 UTC
--     fn_sales_engineer_supplier_scorecard_tick e-mailed him "Your QuotesDone scorecard for October 2026" (notification 149942):
--     "There is not enough data yet for a scorecard: no request, quote or rating of yours in October 2026." He was not a supplier in
--     October. The tick picked every approved supplier with a portal account and no row for the month: it never asked WHEN he was
--     approved, nor whether anything happened to him in the month.
--
-- WHAT THIS CHANGES (fn_sales_engineer_supplier_scorecard_tick only; the card, the portal and the text are untouched):
--   1. a supplier approved AFTER the month ended (approved_at, else the first of registration_submitted_at, accepted_terms_at,
--      created_at, in Dubai time) gets no e-mail for that month;
--   2. a supplier to whom no request was sent in the month (card.activity.requests_sent = 0) gets no e-mail: there is nothing on it.
--   Both are recorded in supplier_scorecard with outcome 'skipped: <why>' (one row per supplier and month, so the daily tick does not
--   compute it again). The portal still shows any month's card, with "not enough data yet" when it has none (founder_instruction
--   1013 item 2 is kept there); only the e-mail of an empty or not-yet-his month stops.
--
-- Pending: scripts/sql/pending/a_supplier_is_sent_no_scorecard_for_a_month_before_he_was_approved_or_without_a_request.txt
-- Prevented by: scripts/checks/a_supplier_is_sent_no_scorecard_for_a_month_he_was_not_a_supplier.test.mjs

create or replace function public.fn_sales_engineer_supplier_scorecard_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_month date := (date_trunc('month', (now() at time zone 'Asia/Dubai')) - interval '1 month')::date;
  r record; v_card jsonb; m jsonb; v_ok jsonb; v jsonb; v_sent int := 0; v_held int := 0; v_skipped int := 0; v_skip text;
begin
  for r in select l.id, l.company_name, lower(btrim(l.claimed_by)) as mail,
                  (coalesce(l.approved_at, l.registration_submitted_at, l.accepted_terms_at, l.created_at) at time zone 'Asia/Dubai')::date as since
             from public.leads l
            where l.approval_status = 'approved' and nullif(btrim(l.claimed_by), '') is not null
              and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
              and (coalesce(l.is_demo, false) or public.fn_is_demo_email(l.claimed_by)) = v_fx
              and not exists (select 1 from public.supplier_scorecard s where s.lead_id = l.id and s.month = v_month)
            order by l.id limit 500 loop
    v_card := public.fn_supplier_scorecard(r.id, v_month);
    -- 18 Nov 2026: never a card for a month before he was a supplier, nor for a month in which no request reached him
    v_skip := case when r.since >= (v_month + interval '1 month')::date
                   then 'skipped: approved on ' || to_char(r.since, 'YYYY-MM-DD') || ', after ' || to_char(v_month, 'FMMonth YYYY') || ' ended'
                   when coalesce((v_card->'activity'->>'requests_sent')::int, 0) = 0
                   then 'skipped: no request was sent to him in ' || to_char(v_month, 'FMMonth YYYY') end;
    if v_skip is not null then
      insert into public.supplier_scorecard (lead_id, month, card, to_email, outcome) values (r.id, v_month, v_card, r.mail, v_skip);
      v_skipped := v_skipped + 1;
      continue;
    end if;
    m := public.fn_supplier_scorecard_text(v_card, r.company_name);
    v_ok := public.fn_email_sendable(r.mail);
    if not coalesce((v_ok->>'ok')::boolean, false) then
      insert into public.supplier_scorecard (lead_id, month, card, to_email, outcome)
      values (r.id, v_month, v_card, r.mail, 'not_sendable: ' || (v_ok->>'reason'));
      v_held := v_held + 1;
      continue;
    end if;
    v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_scorecard', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.mail, 'to_role', 'supplier', 'lead_id', r.id, 'lang', 'en',
      'dedupe_key', 'supplier_scorecard:' || r.id || ':' || to_char(v_month, 'YYYY-MM'),
      'subject', m->>'subject', 'body', m->>'body')));
    insert into public.supplier_scorecard (lead_id, month, card, to_email, outcome, handoff_id)
    values (r.id, v_month, v_card, r.mail, 'queued', (v->0->>'handoff_id')::bigint);
    v_sent := v_sent + 1;
  end loop;
  return jsonb_build_object('month', to_char(v_month, 'YYYY-MM'), 'sent', v_sent, 'not_sendable', v_held, 'skipped', v_skipped);
end $fn$;
revoke execute on function public.fn_sales_engineer_supplier_scorecard_tick() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supplier_scorecard_tick() to service_role;
