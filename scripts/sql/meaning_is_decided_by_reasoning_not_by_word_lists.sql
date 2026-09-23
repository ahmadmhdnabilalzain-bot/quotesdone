-- MEANING IS DECIDED BY REASONING, NOT BY WORD LISTS — the SQL side of the first migrated decision points.
-- Seat: it_engineer (shared platform); the decisions belong to customer_support (WhatsApp escalation),
-- ceo (the founder's commands) and sales_engineer (exact spec). 23 Sep 2026, founder_instruction 886-903:
-- "NO word matching anywhere: decisions by reasoning, never keyword/regex/ilike on meaning."
--
-- WHAT WAS WRONG, read from production 23 Sep 2026 (pg_get_functiondef):
--   * fn_wa_route decided "this is a complaint, it needs a person" with
--       v_trouble := p_body ~* '(complain|refund|dispute|angry|lawyer|legal|scam|cheat|fraud|شكوى|احتيال|نصب)'
--     so "is it legal to build a pool in my garden?" was escalated as a complaint and "you people took my
--     money and vanished" was not.
--   * fn_ceo_classify decided what the founder meant with position(ceo_command_rule.pattern in text), the
--     lowest rank winning: "check why the refund failed" was 'measure' (rank 50, 'check') and never 'fix';
--     "don't build anything yet" was 'build'.
--   * fn_rfq_required_check counted a required spec as "found" when any 4-letter token of any of its
--     option labels appeared anywhere in the inquiry text: a customer who wrote "no preference on the
--     frame" had answered frame_material; "clear" anywhere answered glass type.
--
-- WHAT THIS CHANGES.
--   * fn_wa_route takes the reasoned answer as p_needs_person (from _shared/think.ts in wa_inbound). It no
--     longer reads the body for meaning at all. When the reasoning is held (the model hold) p_needs_person
--     is null: nobody is escalated by a guess, and the message waits in customer_support's queue
--     (reasoning_held_question) until it can be read. The intent table (fn_wa_answer) is unchanged here
--     and is the next WhatsApp item in the registry (decision_points.json).
--   * fn_ceo_command_submit records the instruction as 'interpreting' with intent 'ambiguous' and decides
--     nothing; fn_ceo_command_interpret applies the intent think() chose (ceo_agent calls it at once, or
--     fn_reason_held_resolve does when the hold lifts). fn_ceo_classify is DROPPED: nothing may call it.
--     ceo_command_rule is left in place, unread, as the record of what the old table said.
--   * fn_rfq_required_check keeps reading the inquiry's KEYED answers (our own schema: the spec keys, the
--     concept map, the columns) and drops the free-text option scan. Whether the customer's words state a
--     required spec is decided in inquiry_intake by think() and written into the spec under its key, with
--     the customer's words as evidence.
--
-- WHAT IT DOES NOT DO. It does not change the model path, the founder-number rule, or who gets the number.
-- It does not migrate the other 70-odd decision points; decision_points.json is the ordered list.
--
-- Pending: scripts/sql/pending/meaning_is_decided_by_reasoning_not_by_word_lists.txt. Applies AFTER
-- every_seat_reasons_before_it_answers.sql (fn_reason_held_resolve calls fn_ceo_command_interpret).

-- ── 1. WhatsApp: the reasoned escalation replaces the regex ─────────────────────────────────────
-- A new parameter changes the signature, so the old one is dropped first (no overload may survive to be
-- called by name with the regex still in it). DROP + CREATE grants EXECUTE to PUBLIC, so the revoke and
-- the service_role grant below are what restore the ACL production has today (service_role only).
drop function if exists public.fn_wa_route(text, text, boolean);
create function public.fn_wa_route(p_phone text, p_body text, p_has_audio boolean default false,
  p_needs_person boolean default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  v_det    jsonb;
  v_pack   jsonb;
  v_conv   record;
  v_needs  boolean;
  v_why    text;
  v_held   boolean;
  v_latin  boolean;
  v_trouble boolean;
  v_asked  boolean;
  v_person boolean;
  v_reason text;
  v_chain  jsonb;
  v_intent text;
  v_reply  text;
begin
  select coalesce((select value = 'true' from public.app_secrets where key = 'paid_inference_enabled'), false)
    into v_held;
  v_held := not v_held;

  v_det  := public.fn_wa_answer(p_phone, coalesce(p_body, '(voice note)'));
  v_pack := public.fn_wa_fact_pack(p_phone);
  v_intent := v_det->>'intent';
  v_reply  := v_det->>'reply';
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;

  -- Script detection picks the reply language; it is a format test, not a reading of meaning.
  v_latin := coalesce(p_body, '') ~ '^[\s\x20-\x7E]*$';

  -- The two ways a message needs a person. The second is REASONED (think() in wa_inbound): a complaint,
  -- a dispute, a refund demand, an accusation or a legal threat, however it is worded. Null = not yet
  -- reasoned (the hold): nobody is escalated on a guess; the message waits in customer_support's queue.
  v_asked   := coalesce(v_intent = 'contact_human', false);
  v_trouble := coalesce(p_needs_person, false);

  -- One decision now, not two. Needing a person and getting his number are the same thing here.
  v_person := v_asked or v_trouble;
  v_reason := case
    when v_asked   then 'They asked for a person, or asked who runs the company.'
    when v_trouble then 'This is a complaint, a dispute or an accusation. It needs a person whether '
                     || 'they asked for one or not, and the founder is the only person there is.'
    when p_needs_person is null then 'Whether this needs a person has not been reasoned yet (the model hold); '
                     || 'it is waiting in customer_support''s queue and nobody was escalated on a guess.'
    else 'Nobody asked for a person and nothing here needs one. A number given out by a machine '
      || 'cannot be taken back.' end;

  -- A complaint gets the number appended, because the escalation and the contact are the same act.
  if v_trouble and not v_asked then
    v_reply := v_reply || ' If you would rather speak to someone directly, call or message '
            || '+971 50 931 9355, which is answered by the owner.';
  end if;

  v_needs := false; v_why := 'A deterministic answer matched and the message is simple, so this turn costs nothing.';
  if p_has_audio then
    v_needs := true; v_why := 'The message is a voice note and must be transcribed before it can be answered.';
  elsif not v_latin then
    v_needs := true; v_why := 'The message is not in Latin script and the fixed answers exist only in English.';
  elsif v_intent in ('small_talk','off_topic','greeting','contact_human') then
    v_needs := false;
    v_why := format('Matched %s, which is answered completely without a model.', v_intent);
  elsif coalesce((v_det->>'matched')::boolean, false) = false then
    v_needs := true; v_why := 'No fixed answer matched. Wording varies, so this is the normal case rather than an exception.';
  elsif coalesce(v_conv.message_count, 0) >= 2 then
    v_needs := true; v_why := 'This is a continuing conversation; a fixed answer would ignore what came before.';
  elsif length(coalesce(p_body,'')) > 160 then
    v_needs := true; v_why := 'The message is long enough to contain more than one question.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rung', rung, 'model', model, 'kind', kind, 'rationale', rationale) order by rung), '[]'::jsonb)
    into v_chain
    from public.model_fallback_chain
   where purpose = 'whatsapp_conversation' and active;

  return jsonb_build_object(
    'ok', true,
    'needs_model', v_needs,
    'why', v_why,
    'inference_held', v_held,
    'model', case when v_needs then 'google/gemini-3-flash' else null end,
    'fallback_chain', case when v_needs then v_chain else null end,
    'on_model_failure',
      'Try each rung in order. Record model_wanted, model_used and fell_back on llm_calls for every '
   || 'attempt, so a fallback that becomes permanent is visible rather than quietly expensive. The '
   || 'final rung is the deterministic reply and it cannot fail.',
    'model_reason', case
      when not v_needs then 'No model needed. The database answered it.'
      else 'google/gemini-3-flash first, by founder ruling. On failure claude-sonnet-5. On failure the '
        || 'deterministic reply. Every rung gets the same fact pack and the same boundaries.' end,

    -- One decision. Handing to a person and giving the number are the same act.
    'needs_a_person', v_person,
    'person_decided_by', case when v_asked then 'intent'
                              when p_needs_person is null then 'held: not yet reasoned'
                              else 'reasoning' end,
    'founder_number', case when v_person then (coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
                   '(no approved public contact is configured — tell the CEO)')) else null end,
    'person_reason', v_reason,
    'opened_by', case when v_asked then 'they asked'
                      when v_trouble then 'complaint or dispute'
                      else null end,

    'action', case
      when v_needs and v_held  then 'send_deterministic_and_log_shortfall'
      when v_needs             then 'walk_fallback_chain_with_fact_pack'
      else                          'send_deterministic' end,

    'transcription_gap', case when p_has_audio
      then 'Whether Gemini 3 Flash can take the Twilio media URL directly, or whether a speech model '
        || 'must be added to ai_model_register first, is NOT established and must be checked before '
        || 'audio is enabled.'
      else null end,

    'deterministic_reply', v_reply,
    'deterministic_intent', v_intent,
    'fact_pack', v_pack,
    'model_brief', public.fn_wa_model_brief()
  );
end;
$function$;
revoke execute on function public.fn_wa_route(text, text, boolean, boolean) from public, anon, authenticated;
grant execute on function public.fn_wa_route(text, text, boolean, boolean) to service_role;
comment on function public.fn_wa_route(text, text, boolean, boolean) is
  'The WhatsApp route. Whether a message needs a person is REASONED by the caller (think(), wa_inbound) and passed as p_needs_person; null means held, and nobody is escalated on a guess. scripts/sql/meaning_is_decided_by_reasoning_not_by_word_lists.sql';

-- ── 2. The founder's commands: understood by reasoning, recorded before they are understood ─────
create or replace function public.fn_ceo_command_interpret(p_command_id bigint, p_intent text, p_why text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c public.ceo_command; v_work boolean;
begin
  select * into c from public.ceo_command where command_id = p_command_id for update;
  if not found then raise exception 'no command %', p_command_id using errcode = 'P0002'; end if;
  select i.needs_work into v_work from public.ceo_command_intent i where i.intent_id = p_intent;
  if v_work is null then raise exception 'unknown intent %', p_intent using errcode = '22023'; end if;
  -- Idempotent: a command already understood is not re-routed (a replay after a live answer is a no-op).
  if c.state <> 'interpreting' then
    return jsonb_build_object('command_id', p_command_id, 'intent', c.intent_id, 'state', c.state, 'changed', false);
  end if;
  update public.ceo_command set intent_id = p_intent, state = 'accepted',
         outcome = coalesce(outcome, left('understood as ' || p_intent || coalesce(': ' || nullif(btrim(p_why), ''), ''), 1000))
   where command_id = p_command_id;
  -- An instruction that asks for work becomes work. One that states a rule or asks a question is
  -- accepted and answered without manufacturing a task nobody wanted.
  if v_work then
    insert into public.ceo_task (command_id, title, detail) values (p_command_id, left(btrim(c.body), 200), c.body);
    update public.ceo_command set state = 'routed'        where command_id = p_command_id;
    update public.ceo_command set state = 'tasks_created' where command_id = p_command_id;
  end if;
  select * into c from public.ceo_command where command_id = p_command_id;
  return jsonb_build_object('command_id', p_command_id, 'intent', c.intent_id, 'state', c.state, 'changed', true);
end $fn$;
revoke execute on function public.fn_ceo_command_interpret(bigint, text, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_command_interpret(bigint, text, text) to service_role;

-- Same signature as production: CREATE OR REPLACE keeps its ACL (service_role only).
create or replace function public.fn_ceo_command_submit(p_channel text, p_from text, p_body text)
 returns table(command_id bigint, intent_id text, state text, matched text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_id bigint;
begin
  if coalesce(btrim(p_body), '') = '' then
    raise exception 'an empty instruction is not an instruction' using errcode = '22023';
  end if;
  -- Recorded first, understood second. 'interpreting' is the state ceo_command_state already defines as
  -- "the CEO is working out what was asked"; fn_ceo_command_interpret moves it on with the reasoned intent.
  insert into public.ceo_command (channel, from_identity, body, intent_id, matched_rule, state)
  values (p_channel, p_from, p_body, 'ambiguous', null, 'received')
  returning ceo_command.command_id into v_id;
  update public.ceo_command set state = 'interpreting' where ceo_command.command_id = v_id;
  return query
    select c.command_id, c.intent_id, c.state, null::text
      from public.ceo_command c where c.command_id = v_id;
end
$function$;
revoke execute on function public.fn_ceo_command_submit(text, text, text) from public, anon, authenticated;

drop function if exists public.fn_ceo_classify(text);

-- ── 3. Exact spec: keyed answers only; the free-text option scan is gone ────────────────────────
create or replace function public.fn_rfq_required_check(i inquiries)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  spec_fields jsonb; f jsonb; bag jsonb := '{}'::jsonb;
  k text; v text; bk text; tok text;
  reqn int := 0; have text[] := '{}';
  miss jsonb := '[]'::jsonb; advisory jsonb := '[]'::jsonb; found boolean;
begin
  select cs.fields into spec_fields
    from public.category_specs cs
   where lower(cs.category) = lower(coalesce(i.category,''))
   limit 1;

  if spec_fields is null or jsonb_typeof(spec_fields) <> 'array' then
    return jsonb_build_object('applicable', false, 'reason', 'no category_specs row',
      'category', i.category, 'required_ok', true, 'required_total', 0,
      'present','[]'::jsonb, 'missing','[]'::jsonb, 'advisory_missing','[]'::jsonb, 'checked_at', now());
  end if;

  if i.spec is not null and jsonb_typeof(i.spec) = 'object' then
    for k, v in
      select e.key, case when jsonb_typeof(e.value) in ('object','array')
                         then e.value::text else coalesce(e.value #>> '{}','') end
        from jsonb_each(i.spec) e
    loop
      bag := bag || jsonb_build_object(lower(k), v);
    end loop;

    for k, v in
      select e2.key, case when jsonb_typeof(e2.value) in ('object','array')
                          then e2.value::text else coalesce(e2.value #>> '{}','') end
        from jsonb_each(i.spec) e1
        join lateral jsonb_each(case when jsonb_typeof(e1.value)='object'
                                     then e1.value else '{}'::jsonb end) e2 on true
    loop
      if not public._rfq_answered(bag->>lower(k)) then
        bag := bag || jsonb_build_object(lower(k), v);
      end if;
    end loop;
  end if;

  bag := bag
    || case when coalesce(i.emirate,'') <> '' then
            jsonb_build_object('emirate', i.emirate,
              'location', coalesce(nullif(bag->>'location',''), i.emirate)) else '{}'::jsonb end
    || case when coalesce(i.scope_type,'') <> '' then
            jsonb_build_object('scope', coalesce(nullif(bag->>'scope',''), i.scope_type)) else '{}'::jsonb end
    || case when coalesce(i.budget,'') <> '' then jsonb_build_object('budget', i.budget) else '{}'::jsonb end
    || case when coalesce(array_length(i.trades,1),0) > 0 then
            jsonb_build_object('trades', array_to_string(i.trades,', ')) else '{}'::jsonb end
    || case when coalesce(i.drawing_file_path,'') <> '' or i.boq is not null then
            jsonb_build_object('drawing','provided') else '{}'::jsonb end;

  for f in select value from jsonb_array_elements(spec_fields)
            where coalesce((value->>'required')::boolean, false)
  loop
    k := nullif(btrim(lower(coalesce(f->>'key',''))), '');

    -- Keyless required field: unaddressable, so ADVISORY ONLY (never blocks dispatch).
    if k is null then
      advisory := advisory || jsonb_build_object(
        'question', f->>'question', 'reason', 'category_specs field has no key - cannot be gated');
      continue;
    end if;

    reqn := reqn + 1; found := false;

    if public._rfq_answered(bag->>k) then found := true; end if;

    -- A KEY of ours that names the same field under another spelling (the concept map, or the key's own
    -- parts): our schema against our schema, a format reconciliation — not a reading of the customer's words.
    if not found then
      for bk in select key from jsonb_each_text(bag) loop
        if public._rfq_answered(bag->>bk) then
          if public._rfq_concept(k) is not null
             and public._rfq_concept(k) = public._rfq_concept(bk) then
            found := true;
          else
            foreach tok in array coalesce(string_to_array(k,'_'), '{}'::text[]) loop
              if length(coalesce(tok,'')) >= 4
                 and (bk = tok or bk like '%'||tok||'%' or tok like '%'||bk||'%') then
                found := true;
              end if;
            end loop;
          end if;
        end if;
        exit when found;
      end loop;
    end if;

    -- NO free-text scan. Whether the customer's own words state this field is reasoned in inquiry_intake
    -- (think(), surface 'inquiry_intake.exact_spec') and arrives here as a keyed answer, or not at all.

    if found then
      have := array_append(have, k);
    else
      miss := miss || jsonb_build_object('key', k, 'question', f->>'question', 'type', f->>'type');
    end if;
  end loop;

  return jsonb_build_object(
    'applicable', true, 'category', i.category,
    'required_total', reqn,
    'required_ok', (jsonb_array_length(miss) = 0),
    'present', to_jsonb(have),
    'missing', miss,
    'advisory_missing', advisory,
    'checked_at', now());
end $function$;
revoke execute on function public.fn_rfq_required_check(inquiries) from public, anon, authenticated;
