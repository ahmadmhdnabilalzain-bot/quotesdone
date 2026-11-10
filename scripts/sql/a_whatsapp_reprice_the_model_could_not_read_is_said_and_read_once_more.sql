-- Seat: customer_support. Assigned: customer_support (supplier follow-up of #1909, item 2; founder ruling 1608).
--
-- MEASURED on origin/main: a supplier's WhatsApp "change my price to 72,556" is read by one gateway call
-- (wa_inbound/speculation.ts directiveRead). When that call failed, the reading was null, which supplier_directive.ts took
-- for "not a change": the message fell through to the ordinary answer, the price never moved, and nobody told him.
--
-- THE CODE CHANGE (wa_inbound/reprice_outage.ts): a failed reading is an outage. A message that states an amount is told
-- at once that nothing changed and how to change it in the portal, and is filed ONCE (dedupe wa_reprice:<MessageSid>) in
-- customer_support's reasoning queue under the surface wa_inbound.supplier_reprice. Its options are 'no_change' and
-- 'amount:<n>' for each amount HIS message states, nothing else.
--
-- THIS FILE: the replay's apply routine, which fn_reason_held_resolve finds by name (fn_reason_apply_<surface>).
--   * a choice that is not one of the held row's own options RAISES (fn_reason_held_resolve then keeps it reasoned
--     and it is asked again; never applied);
--   * 'amount:<n>' is applied through the one routine that re-prices (fn_supplier_apply_change, scoped in SQL to the
--     supplier whose confirmed number sent it), and only within 48 hours of his message: a price he gave two days
--     ago is not applied over whatever he has done since. He is told the routine's own result on WhatsApp;
--   * 'no_change' files the message as an ordinary unanswered turn (the queue holdUnwritten files, wa_inbound.
--     unwritten_reply), so the question it really was gets its answer.
-- NOT CHANGED: fn_supplier_apply_change, fn_reason_hold, fn_reason_held_resolve, the live (model up) re-price path.
-- prevented by: wa_inbound/reprice_outage.test.ts and this file's _probe.sql.
-- Pending until the release applies it: scripts/sql/pending/a_whatsapp_reprice_the_model_could_not_read_is_said_and_read_once_more.txt

create or replace function public.fn_reason_apply_wa_inbound__supplier_reprice(p_id bigint, p_result jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_ids text[];
  v_body text; v_phone text; v_sid text; v_res jsonb; v_msg text; v_d jsonb; v_q text; v_held bigint;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  select coalesce(array_agg(o->>'id'), '{}') into v_ids
    from jsonb_array_elements(coalesce(h.request->'decision'->'options', '[]'::jsonb)) o;
  if v_choice is null or not (v_choice = any (v_ids)) then
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  v_body := left(coalesce(h.subject->>'body', h.question), 1500);
  v_phone := h.subject->>'phone';
  v_sid := coalesce(h.subject->>'message_sid', v_phone || ':' || left(v_body, 40));

  if v_choice = 'no_change' then
    -- not a re-price after all: answered as the ordinary message it was (wa_inbound/model_says.ts holdUnwritten's shape)
    v_q := 'Reply on WhatsApp to this supplier message, in UAE English (suppliers are always answered in English). '
        || 'They were told we could not read it just now and would come back to them.' || chr(10) || chr(10) || 'MESSAGE:' || chr(10) || v_body;
    v_held := public.fn_reason_hold('customer_support', 'wa_inbound.unwritten_reply', v_body,
      jsonb_build_object('seat', 'customer_support', 'surface', 'wa_inbound.unwritten_reply', 'subject', jsonb_build_object('channel', 'whatsapp', 'phone', v_phone, 'message_sid', h.subject->>'message_sid'),
        'question', v_q, 'research', false,
        'context', jsonb_build_object('audience', 'supplier', 'language', 'en', 'turn_id', 'wa:' || v_sid),
        'reask', jsonb_build_object('message', v_body, 'facts', 'WHAT HAS HAPPENED ON THIS TURN (decided by our systems; convey it accurately, do not change or add to it):' || chr(10)
          || 'The message was read again: it does not ask to change a quotation price, so no price was changed.', 'audience', 'supplier', 'lang', 'en', 'channel', 'WhatsApp', 'problems', '[]'::jsonb)),
      '{}'::jsonb, jsonb_build_object('channel', 'whatsapp', 'phone', v_phone, 'message_sid', h.subject->>'message_sid')
                     || case when h.subject ? 'fixture' then jsonb_build_object('fixture', h.subject->'fixture') else '{}'::jsonb end,
      'reprice_reading_said_no_change', 'wa_unwritten:' || v_sid);
    return jsonb_build_object('applied', true, 'changed', false, 'answered_by', v_held);
  end if;

  if h.created_at < now() - interval '48 hours' then
    v_res := jsonb_build_object('ok', false, 'refusal', 'it could not be read within 48 hours of your message');
  else
    v_res := public.fn_supplier_apply_change(p_phone => v_phone, p_field => 'quote_price', p_value => substr(v_choice, 8),
                                             p_inbound => v_body, p_channel => 'whatsapp');
  end if;
  v_msg := case when coalesce((v_res->>'ok')::boolean, false)
    then 'We read your WhatsApp message again now that our reader is back. ' || coalesce(v_res->>'message', 'Your quotation price is updated.')
    else 'We read your WhatsApp message again now that our reader is back, but the price was NOT changed: ' || coalesce(v_res->>'refusal', 'it could not be applied')
         || '. You can change it yourself in the supplier portal: https://quotesdone.com/portal' end;
  v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'supplier_reprice_result', 'requested_by', 'customer_support', 'channel', 'whatsapp',
    'to_phone', regexp_replace(coalesce(v_phone, ''), '^whatsapp:', ''), 'to_role', 'supplier', 'lead_id', public.fn_wa_lead_id(v_phone),
    'lang', 'en', 'subject', 'Your quotation price change', 'body', v_msg, 'dedupe_key', 'wa_reprice_result:' || p_id)));
  return jsonb_build_object('applied', true, 'changed', coalesce((v_res->>'ok')::boolean, false) and not coalesce((v_res->>'unchanged')::boolean, false),
                            'result', v_res, 'told', v_d->0->>'status');
end $fn$;
revoke execute on function public.fn_reason_apply_wa_inbound__supplier_reprice(bigint, jsonb) from public, anon, authenticated;

select case
  when to_regprocedure('public.fn_reason_apply_wa_inbound__supplier_reprice(bigint,jsonb)') is null
    then 'PROBE FAILED: the apply routine is missing'
  when has_function_privilege('anon', 'public.fn_reason_apply_wa_inbound__supplier_reprice(bigint, jsonb)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_reason_apply_wa_inbound__supplier_reprice(bigint, jsonb)', 'execute')
    then 'PROBE FAILED: a client can run the re-price apply'
  else 'PROBE OK' end as verdict;
