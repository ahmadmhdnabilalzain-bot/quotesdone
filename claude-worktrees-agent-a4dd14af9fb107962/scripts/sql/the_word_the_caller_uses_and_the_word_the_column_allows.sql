-- THE WORD THE CALLER USES AND THE WORD THE COLUMN ALLOWS
--
-- fn_wa_record_turn compares p_direction to 'in' in three places and stores it raw, and wa_turn's
-- CHECK allows only 'in' and 'out'. Nothing normalised between them. The edge function wiring the
-- WhatsApp brain in reached for 'INBOUND' -- the obvious word -- and every turn was refused by the
-- CHECK, inside a try/catch, so the agent would have had no memory at all and nothing would have
-- said why.
--
-- The CHECK is what made this visible; without it the row would have been stored and
-- window_opened_at would have stayed null, so the 24-hour service window would never open and the
-- agent would fall silent a day later for a reason nothing recorded. That is the worse failure.
--
-- Direction is normalised once, at the top, where the caller's vocabulary meets the column's:
-- in/inbound/incoming and out/outbound/outgoing, any case. Anything else is REFUSED with a stated
-- reason and nothing is written -- a silent guess about which way a message travelled would open a
-- service window that never happened.
CREATE OR REPLACE FUNCTION public.fn_wa_record_turn(p_phone text, p_direction text, p_body text DEFAULT NULL::text, p_media_url text DEFAULT NULL::text, p_media_kind text DEFAULT NULL::text, p_transcript text DEFAULT NULL::text, p_intent text DEFAULT NULL::text, p_answered_by text DEFAULT NULL::text, p_fact_pack jsonb DEFAULT NULL::jsonb, p_model text DEFAULT NULL::text, p_cost_aed numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  v_conv   record;
  v_lead   bigint;
  v_cust   uuid;
  v_kind   text := 'unknown';
  v_pid    text;
  v_turn   bigint;
  v_dir    text;
begin
  -- THE DIRECTION IS NORMALISED HERE, WHERE THE CALLER'S VOCABULARY MEETS THE COLUMN'S.
  -- Every branch below compares p_direction to 'in', and wa_turn's CHECK allows only 'in' and
  -- 'out'. A caller writing 'INBOUND' -- the obvious word, and the one the edge function reached
  -- for -- hit the CHECK and the whole turn was lost. Worse would have been no CHECK: the row
  -- would have been stored and the 24-hour service window would never have opened, so the agent
  -- would have gone quiet a day later for a reason nothing recorded.
  v_dir := case lower(btrim(coalesce(p_direction, '')))
             when 'in' then 'in' when 'inbound' then 'in' when 'incoming' then 'in'
             when 'out' then 'out' when 'outbound' then 'out' when 'outgoing' then 'out'
             else null end;
  if v_dir is null then
    return jsonb_build_object('ok', false, 'reason',
      format('direction %L is neither inbound nor outbound; nothing was recorded', p_direction));
  end if;
  if v_digits = '' then
    return jsonb_build_object('ok', false, 'reason', 'No usable phone number on the message.');
  end if;

  v_lead := public.fn_wa_lead_id(p_phone);
  if v_lead is not null then
    v_kind := 'lead'; v_pid := v_lead::text;
  else
    select id into v_cust from public.customers
     where regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') = v_digits limit 1;
    if v_cust is not null then v_kind := 'customer'; v_pid := v_cust::text; end if;
  end if;

  insert into public.wa_conversation (phone_e164, party_kind, party_id, message_count,
                                      window_opened_at, window_expires_at)
  values (v_digits, v_kind, v_pid, 0,
          case when v_dir = 'in' then now() else null end,
          case when v_dir = 'in' then now() + interval '24 hours' else null end)
  on conflict (phone_e164) do update set
      last_seen_at   = now(),
      party_kind     = coalesce(excluded.party_kind, wa_conversation.party_kind),
      party_id       = coalesce(excluded.party_id,   wa_conversation.party_id),
      -- An INBOUND message opens or re-opens the 24-hour service window. An outbound one never does,
      -- which is the whole point of the rule: we cannot extend our own permission to keep talking.
      window_opened_at  = case when v_dir = 'in' then now() else wa_conversation.window_opened_at end,
      window_expires_at = case when v_dir = 'in' then now() + interval '24 hours'
                               else wa_conversation.window_expires_at end
  returning * into v_conv;

  update public.wa_conversation
     set message_count = message_count + 1,
         last_intent   = coalesce(p_intent, last_intent)
   where id = v_conv.id
  returning * into v_conv;

  insert into public.wa_turn (conversation_id, direction, body, media_url, media_kind, transcript,
                              transcript_source, intent_key, answered_by, fact_pack, model_id, cost_aed)
  values (v_conv.id, v_dir, p_body, p_media_url, p_media_kind, p_transcript,
          case when p_transcript is not null then 'model' else 'none' end,
          p_intent, p_answered_by, p_fact_pack, p_model, p_cost_aed)
  returning id into v_turn;

  return jsonb_build_object(
    'ok', true, 'conversation_id', v_conv.id, 'turn_id', v_turn,
    'party_kind', v_conv.party_kind, 'party_id', v_conv.party_id,
    'message_count', v_conv.message_count,
    'window_expires_at', v_conv.window_expires_at,
    'window_open', (v_conv.window_expires_at is not null and v_conv.window_expires_at > now())
  );
end;
$function$;
