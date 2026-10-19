-- A FIXTURE ASKING FOR A PERSON NEVER PAGES THE FOUNDER (19 Oct 2026, customer_support; QA channels run).
-- A ZZ DEMO "Talk to a person" from the reserved block +971500000081 reached fn_notify_founder: founder_alert 103774 was
-- e-mailed to the founder and 103775 sent on WhatsApp. zzzz_notifications_demo_capture could not catch it, because a founder
-- alert names its subject only in its text (no lead, inquiry or quote id). Fixed where the alert is raised: a fixture number
-- still gets its handoff to customer_support (the rehearsal measures it), but fn_notify_founder is not called.
-- CREATE OR REPLACE keeps the existing grants; body otherwise identical to the live routine (read 19 Oct 2026).
CREATE OR REPLACE FUNCTION public.fn_wa_human_request(p_phone text, p_hold boolean, p_event text, p_detail text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'); v_h bigint; v_ok boolean := true; v_err text;
  v_founder boolean;
begin
  if length(v_digits) < 9 then return jsonb_build_object('ok', false, 'reason', 'no usable number'); end if;
  -- A. The founder trying "Talk to a person" from his own number is not a person waiting (handoff 58191, 22 Sep).
  v_founder := coalesce(public.fn_identify_contact(v_digits) ->> 'audience', '') = 'founder';
  if p_hold and not v_founder then
    insert into public.wa_conversation (phone_e164, party_kind, message_count, thread_state, handed_to)
    values (v_digits, 'unknown', 0, 'handed_to_human', 'customer_support')
    on conflict (phone_e164) do update set thread_state = 'handed_to_human', handed_to = 'customer_support', last_seen_at = now();
  end if;
  select id into v_h from public.agent_actions
   where kind = 'handoff' and status = 'pending' and detail ->> 'type' = 'support.human_requested' and detail ->> 'phone_digits' = v_digits
   order by id desc limit 1;
  if v_h is null and not v_founder then
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.human_requested', 'wa_conversation',
      v_digits || ':' || to_char(now() at time zone 'UTC', 'YYYYMMDDHH24MISS'),
      jsonb_build_object('phone_digits', v_digits, 'held', p_hold, 'event', p_event,
                         'waiting_for', 'a person to answer +' || v_digits || ' on WhatsApp'));
  end if;
  -- B. A reserved fixture number (+971 50 000 00xx, the ZZ DEMO harness) never pages the founder: the QA channels run of
  --    19 Oct 2026 sent him founder_alert 103774 (e-mail) and 103775 (WhatsApp) for +971500000081. The handoff above is kept.
  if public.fn_is_demo_phone(p_phone) then
    return jsonb_build_object('ok', true, 'handoff_id', v_h, 'held', p_hold, 'founder_own_number', v_founder, 'notified', true, 'fixture', true);
  end if;
  begin
    perform public.fn_notify_founder(p_event => p_event, p_detail => p_detail, p_level => 'high', p_kind => 'whatsapp_human_request',
                                     p_dedupe_key => 'wa_human:' || v_digits || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD'),
                                     p_owner_agent => 'customer_support');
  exception when others then v_ok := false; v_err := left(sqlerrm, 300);
  end;
  return jsonb_build_object('ok', true, 'handoff_id', v_h, 'held', p_hold, 'founder_own_number', v_founder, 'notified', v_ok, 'notify_error', v_err);
end $function$;

do $$ begin
  if position('fn_is_demo_phone(p_phone)' in pg_get_functiondef('public.fn_wa_human_request(text,boolean,text,text)'::regprocedure)) = 0 then
    raise exception 'fn_wa_human_request does not refuse a fixture number before paging the founder';
  end if;
end $$;
