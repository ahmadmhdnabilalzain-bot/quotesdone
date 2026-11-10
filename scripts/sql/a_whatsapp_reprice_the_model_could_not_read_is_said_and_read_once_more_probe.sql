-- PROBE (never applied; it always raises CHK<<...>> so every row it writes rolls back). Run after, or in the same rolled-back
-- transaction as, a_whatsapp_reprice_the_model_could_not_read_is_said_and_read_once_more.sql. Seat: customer_support.
-- A held re-price for a fixture number (+971 50 000 00xx, no supplier owns it): a choice outside its options raises; an
-- amount is put to fn_supplier_apply_change (which refuses an unknown number) and nothing is re-priced; 'no_change' is
-- answered as an ordinary turn (fn_reason_hold files nothing for a fixture subject, which is what it must do).
do $$
declare v_id bigint; v_quotes_before text; v_quotes_after text; v_out jsonb; v_raised boolean := false; v_no jsonb;
begin
  select md5(string_agg(id::text || ':' || coalesce(quote_amount::text, '') || ':' || coalesce(price_ex_vat::text, ''), ',' order by id)) into v_quotes_before from public.quotes;
  insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, dedupe_key)
  values ('customer_support', 'wa_inbound.supplier_reprice', 'change my price to 72,556',
          jsonb_build_object('decision', jsonb_build_object('name', 'supplier_reprice', 'options', jsonb_build_array(
            jsonb_build_object('id', 'no_change', 'meaning', 'x'), jsonb_build_object('id', 'amount:72556', 'meaning', 'y')))),
          jsonb_build_object('channel', 'whatsapp', 'phone', 'whatsapp:+971500000042', 'message_sid', 'SMzzprobe', 'body', 'change my price to 72,556', 'fixture', true),
          'probe', 'zz_probe_reprice:' || gen_random_uuid())
  returning id into v_id;
  begin
    perform public.fn_reason_apply_wa_inbound__supplier_reprice(v_id, '{"decision":{"choice":"amount:1"}}'::jsonb);
  exception when others then v_raised := sqlerrm like 'CHOICE_NOT_AN_OPTION%';
  end;
  v_out := public.fn_reason_apply_wa_inbound__supplier_reprice(v_id, '{"decision":{"choice":"amount:72556"}}'::jsonb);
  v_no := public.fn_reason_apply_wa_inbound__supplier_reprice(v_id, '{"decision":{"choice":"no_change"}}'::jsonb);
  select md5(string_agg(id::text || ':' || coalesce(quote_amount::text, '') || ':' || coalesce(price_ex_vat::text, ''), ',' order by id)) into v_quotes_after from public.quotes;
  if not v_raised then raise exception 'CHK<<PROBE FAILED: an amount outside the options was not refused>>'; end if;
  if coalesce((v_out->>'changed')::boolean, true) or coalesce((v_out->'result'->>'ok')::boolean, true) then
    raise exception 'CHK<<PROBE FAILED: an unknown number re-priced something: %>>', v_out; end if;
  if v_quotes_before is distinct from v_quotes_after then raise exception 'CHK<<PROBE FAILED: a quotation price moved>>'; end if;
  if coalesce((v_no->>'changed')::boolean, true) then raise exception 'CHK<<PROBE FAILED: no_change changed something>>'; end if;
  if v_no->>'answered_by' is not null then raise exception 'CHK<<PROBE FAILED: a fixture turn was filed for a model>>'; end if;
  raise exception 'CHK<<PROBE OK: off-option refused; amount refused for an unknown number (%); no_change answered as a turn (held %, none for a fixture); quotes unchanged>>',
    v_out->'result'->>'refusal', coalesce(v_no->>'answered_by', 'none');
end $$;
