-- PROBE: A SUPPLIER'S REPORT THAT THE CUSTOMER WENT SILENT STOPS A NON-RESPONSE REFUND. Seats: customer_support + sales_engineer.
-- Agent: customer_support builder (supplier wave-2 review fixes), 16 Nov 2026. Pure probe: no DDL, never applied; run after
-- a_supplier_report_that_the_customer_went_silent_stops_a_non_response_refund.sql on a LOCAL Postgres 16 (never on production).
-- It always raises, so every row is rolled back. The transactions are random ids with no customer or supplier behind them.
-- PROBE OK only if
--   1. on a transaction the supplier reported silent, the reading is not eligible, names the report (date and channel) among the
--      blocking reasons and returns supplier_reported_customer_silent;
--   2. on a transaction with the same watch and no report, neither the reason nor the key appears (the report alone moved it).
do $probe$
declare
  fails text := ''; tx uuid := gen_random_uuid(); tx2 uuid := gen_random_uuid(); j jsonb; j2 jsonb;
  v_att jsonb := '[{"channel":"email"},{"channel":"whatsapp"},{"channel":"phone"}]';
begin
  insert into public.supplier_response_watch (transaction_id, lead_id, attempts) values (tx, -1, v_att), (tx2, -1, v_att);
  insert into public.supplier_customer_silence (transaction_id, lead_id, reported_by, channel) values (tx, -1, 'zz-demo-silence@example.invalid', 'whatsapp');
  j := public.fn_refund_nonresponse_eligibility(tx);
  j2 := public.fn_refund_nonresponse_eligibility(tx2);
  if coalesce((j->>'eligible')::boolean, true) then fails := fails || ' 1:eligible'; end if;
  if j->>'supplier_reported_customer_silent' is null then fails := fails || ' 1:no_key'; end if;
  if (j->'blocking_reasons')::text !~ 'trying to reach the customer' or (j->'blocking_reasons')::text !~ 'whatsapp' then fails := fails || ' 1:no_reason(' || (j->'blocking_reasons')::text || ')'; end if;
  if j2->>'supplier_reported_customer_silent' is not null or (j2->'blocking_reasons')::text ~ 'trying to reach the customer' then fails := fails || ' 2:unreported_named'; end if;
  if jsonb_array_length(j->'blocking_reasons') <> jsonb_array_length(j2->'blocking_reasons') + 1 then fails := fails || ' 2:more_than_one_reason_moved'; end if;
  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: a supplier''s silence report blocks the non-response path with its date and channel; without it nothing changes>>';
end $probe$;
