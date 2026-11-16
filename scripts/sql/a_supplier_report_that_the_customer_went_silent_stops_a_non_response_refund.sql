-- A SUPPLIER'S REPORT THAT THE CUSTOMER WENT SILENT STOPS A NON-RESPONSE REFUND. Seats: customer_support + sales_engineer
-- (the refund ladder's reading is the accountant's; only its evidence grows). Agent: customer_support builder (supplier wave-2 review
-- fixes), 16 Nov 2026. Review supplierw2, item 5.
--
-- Measured before (READ, LOCAL): a revealed supplier who says "the customer is not answering" (portal, e-mail or WhatsApp;
-- fn_supplier_customer_not_answering, a_supplier_company_has_members_asks_on_any_channel_and_can_leave.sql) is told his report is
-- kept as evidence if the customer later says he never made contact. fn_refund_nonresponse_eligibility read only
-- supplier_response_watch, so a customer could still be refunded for "the supplier never answered" against a supplier who had told
-- us, in writing, that he was the one chasing.
--
-- Now: the report is read. It adds one blocking reason (dated, with its channel: "a person must weigh both sides") and one output key,
-- supplier_reported_customer_silent, so the claim is not eligible for the automatic non-response path and goes to a person (the
-- post-reveal dispute). Nothing else in the routine changes.
--
-- Rebuilt from the PRODUCTION body of fn_refund_nonresponse_eligibility(uuid) (md5 of pg_get_functiondef
-- 66cb9119be9619f6a899bcbb14c24d92, SELECT 16 Nov 2026, re-read the same day before this edit). Re-read the md5 before applying; if
-- it moved, rebuild from the live body. Apply AFTER a_supplier_company_has_members_asks_on_any_channel_and_can_leave.sql (the
-- supplier_customer_silence table) and after the_weekly_sanctions_screen_checks_every_member_of_a_company.sql.
-- Probe: a_supplier_report_that_the_customer_went_silent_stops_a_non_response_refund_probe.sql (LOCAL only).
set local lock_timeout = '3s';
CREATE OR REPLACE FUNCTION public.fn_refund_nonresponse_eligibility(p_transaction_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  w public.supplier_response_watch; c public.pricing_config;
  v_wd int; v_att int; v_ch int; v_reasons text[] := '{}'; v_ends timestamptz; v_sil record;
begin
  select * into w from public.supplier_response_watch where transaction_id = p_transaction_id;
  select * into c from public.pricing_config limit 1;

  if w.id is null then
    return jsonb_build_object('eligible', false, 'basis', 'no_watch',
      'detail', 'Support has not recorded contacting this supplier at all, so there is no evidence of silence to decide on.');
  end if;

  -- WORKING days since the PAYMENT (13 Nov 2026, R6): Monday to Friday, skipping public.public_holidays
  -- (fn_is_working_day). This counted Friday and Saturday as the weekend, wrong since the UAE moved to Saturday and
  -- Sunday in 2022, and counted from the watch, not the payment. The window's end is fn_reveal_window's.
  select count(*) into v_wd
    from generate_series((public.fn_reveal_clock_start(p_transaction_id) at time zone 'Asia/Dubai')::date,
                         (now() at time zone 'Asia/Dubai')::date, interval '1 day') d
   where public.fn_is_working_day(d::date);
  v_wd := greatest(v_wd - 1, 0);   -- the day of the payment itself is not an elapsed day
  v_ends := (public.fn_reveal_window(p_transaction_id)->>'ends_at')::timestamptz;

  select count(*), count(distinct a->>'channel')
    into v_att, v_ch
    from jsonb_array_elements(w.attempts) a;

  if w.first_response_at is not null then
    v_reasons := v_reasons || ('the supplier replied on ' || w.first_response_at::text || ' via ' || coalesce(w.response_channel,'?'));
  end if;
  if v_ends is null or now() <= v_ends then
    v_reasons := v_reasons || (v_wd || ' working day(s) have passed of the ' || c.refund_window_working_days || ' the terms allow; the window ends '
                               || coalesce(to_char(v_ends at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI'), 'when the payment is recorded') || ' UAE time');
  end if;
  -- 16 Nov 2026 (review supplierw2): the supplier told us, after a day, that HE was trying to reach this customer and was not
  -- answered (supplier_customer_silence, fn_supplier_customer_not_answering). That is his side of the contact, so silence on HIS part
  -- is not shown; the claim goes to a person (post_reveal_dispute), never to an approval on non-response.
  select s.reported_at, s.channel into v_sil from public.supplier_customer_silence s where s.transaction_id = p_transaction_id;
  if v_sil.reported_at is not null then
    v_reasons := v_reasons || ('the supplier reported on ' || to_char(v_sil.reported_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI')
                               || ' UAE time (' || v_sil.channel || ') that he was trying to reach the customer and was not answered; a person must weigh both sides');
  end if;
  if v_att < c.supplier_nonresponse_min_attempts then
    v_reasons := v_reasons || ('support made ' || v_att || ' attempt(s), fewer than the ' || c.supplier_nonresponse_min_attempts || ' required');
  end if;
  if v_ch < c.supplier_nonresponse_min_channels then
    v_reasons := v_reasons || ('support used ' || v_ch || ' channel(s), fewer than the ' || c.supplier_nonresponse_min_channels || ' required');
  end if;

  return jsonb_build_object(
    'eligible', array_length(v_reasons,1) is null,
    'basis', 'measured',
    'transaction_id', p_transaction_id,
    'working_days_elapsed', v_wd,
    'working_days_required', c.refund_window_working_days,
    'window_ends_at', v_ends,
    'attempts', v_att, 'attempts_required', c.supplier_nonresponse_min_attempts,
    'channels', v_ch, 'channels_required', c.supplier_nonresponse_min_channels,
    'supplier_replied', w.first_response_at is not null,
    'supplier_reported_customer_silent', v_sil.reported_at,
    'first_response_at', w.first_response_at,
    'blocking_reasons', coalesce(to_jsonb(v_reasons), '[]'::jsonb),
    'evidence', w.attempts);
end $fn$;
revoke execute on function public.fn_refund_nonresponse_eligibility(uuid) from public, anon, authenticated;
grant execute on function public.fn_refund_nonresponse_eligibility(uuid) to service_role;
