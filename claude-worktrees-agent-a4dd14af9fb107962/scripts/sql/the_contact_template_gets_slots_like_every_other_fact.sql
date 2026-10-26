-- THE CONTACT TEMPLATE GETS SLOTS, LIKE EVERY OTHER COMPANY FACT
--
-- Founder, 7 September 2026: "+971509319355 is my number / Ahmad Alzain is my name / the agent will
-- use twilio number though."
--
-- fn_wa_answer already fills {{reveal_rate}}, {{free_count}} and {{reg_fee}} from configuration. The
-- contact_human template was the exception: it had the number typed into the sentence, spaced as
-- "+971 50 931 9355", and it never named him. The number could not change without editing a row,
-- and the spec's wording -- "You can contact Ahmad Alzain, founder of QuotesDone, on
-- {{founder_public_phone}}" -- needs a name a bare number cannot supply.
--
-- The slots read the settings that say PUBLICATION in their names. founder_mobile holds the same
-- digits and is deliberately not the source: it is a private contact record, and two values matching
-- today is not permission to publish either of them.
--
-- WHEN THE SETTING IS ABSENT the slot renders a sentence that admits it. An empty string would give
-- a customer "You can contact  on  ", and the spec asks for a blocker reported to the CEO rather
-- than a placeholder shown to a person.

CREATE OR REPLACE FUNCTION public.fn_wa_answer(p_from text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_body     text := lower(btrim(coalesce(p_body, '')));
  i          record;
  v_intent   record := null;
  v_pat      text;
  v_reply    text;
  v_lead     record;
  v_lead_id  bigint;
  v_ident_k  text := 'unknown';
  v_ident_id text := null;
  v_id       bigint;
  v_missing  text;
  v_cfg      record;
  v_log      bigint;
begin
  if v_body = '' then
    return jsonb_build_object('ok', false, 'reason', 'Empty message.');
  end if;

  select standard_reveal_rate, supplier_free_count, supplier_reg_fee into v_cfg
    from public.pricing_config order by id limit 1;

  -- WHO IS ASKING. Identity gates every 'own_records' answer, so one supplier can never be told
  -- another supplier's business by sending a lucky message.
  v_lead_id := public.fn_wa_lead_id(p_from);
  if v_lead_id is not null then
    select * into v_lead from public.leads where id = v_lead_id;
    v_ident_k := 'lead'; v_ident_id := v_lead_id::text;
  end if;

  -- MATCH. First intent whose pattern appears in the body wins, in sort order, so a specific
  -- intent can be placed ahead of a general one.
  for i in select * from public.wa_reply_intent where active order by sort, intent_key loop
    foreach v_pat in array i.match_patterns loop
      -- WORD BOUNDARIES, NOT SUBSTRINGS. A plain substring test matched the greeting pattern 'hi'
      -- inside the word 'something', so 'i want to buy something' was answered with hello. Patterns that
      -- begin and end on a word character are matched on word boundaries; punctuation patterns such as
      -- '#' keep the substring test, because a boundary around a symbol never matches.
      -- Whole-token matching WITHOUT regex escapes. The transport between this file and the database
      -- strips backslashes, so a regex word boundary arrives as a literal letter and the statement
      -- will not even parse. Padding both sides with spaces and normalising punctuation to spaces
      -- gives the same result with no escape to lose.
      if (case
            when v_pat ~ '[a-z0-9]'
              then position(' ' || v_pat || ' '
                            in ' ' || regexp_replace(v_body, '[^a-z0-9 ]', ' ', 'g') || ' ') > 0
            else position(v_pat in v_body) > 0
          end)
         and (not i.requires_number or v_body ~ '[0-9]{2,}') then
        v_intent := i;
        exit;
      end if;
    end loop;
    exit when v_intent is not null;
  end loop;

  -- NO MATCH. An honest refusal that names what it would need. Never a guess, and never a claim
  -- that some service is unavailable.
  if v_intent is null then
    v_reply := public.fn_wa_unmatched_reply();
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, false, v_reply,
            'No enumerated intent matched. This row is the backlog: a real question with no resolver.')
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', false, 'reply', v_reply, 'log_id', v_log);
  end if;

  -- IDENTITY REQUIRED BUT UNKNOWN.
  if v_intent.requires_identity and v_lead_id is null then
    v_reply := 'I do not recognise this number yet, so I cannot look up your records. Reply with the '
            || 'email address you registered with, or REGISTER to start a new registration.';
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply,
            'Intent matched but the sender is not a known party.')
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', true, 'intent', v_intent.intent_key, 'reply', v_reply, 'log_id', v_log);
  end if;

  v_reply := v_intent.answer_template;

  -- COMPANY SLOTS, the same for everyone.
  v_reply := replace(v_reply, '{{reveal_rate}}', coalesce(round(v_cfg.standard_reveal_rate * 100, 1)::text || '%', '3%'));
  v_reply := replace(v_reply, '{{free_count}}',  coalesce(v_cfg.supplier_free_count::text, '1000'));
  v_reply := replace(v_reply, '{{reg_fee}}',     coalesce(round(v_cfg.supplier_reg_fee)::text, '1000'));

  -- THE APPROVED PUBLIC CONTACT, filled the same way. It is read from the settings that say
  -- publication in their names -- never from founder_mobile, which is a private contact record that
  -- happens to hold the same digits. Two values matching is not permission to publish either.
  --
  -- When the setting is absent the slot renders a sentence that ADMITS it rather than an empty
  -- string. "You can contact  on  " is worse than saying the contact is not configured, and the
  -- build spec asks for a blocker reported to the CEO rather than a placeholder shown to a customer.
  v_reply := replace(v_reply, '{{founder_public_phone}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
             '(no approved public contact is configured yet)'));
  v_reply := replace(v_reply, '{{founder_public_name}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_name'),
             'the owner'));

  -- OWN-RECORD SLOTS, read from this sender's row only.
  if v_lead_id is not null then
    v_reply := replace(v_reply, '{{company_name}}', coalesce(v_lead.company_name, 'your company'));
    v_reply := replace(v_reply, '{{reg_status}}',   coalesce(v_lead.registration_status, 'not started'));
    v_reply := replace(v_reply, '{{approval_status}}', coalesce(v_lead.approval_status, 'not yet reviewed'));

    -- The founder's mandatory six, not the ten the scoring view happens to list.
    select string_agg(m, ', ') into v_missing from (
      select 'a UAE mobile number' as m where coalesce(btrim(v_lead.phone_e164), '') = ''
      union all select 'an email address' where coalesce(btrim(v_lead.email), '') = ''
      union all select 'your trade licence' where coalesce(btrim(v_lead.license_doc_path), '') = ''
      union all select 'your company profile' where coalesce(btrim(v_lead.company_profile_doc_path), '') = ''
      union all select 'a signed copy of our terms' where coalesce(btrim(v_lead.signed_terms_path), '') = ''
    ) x;
    v_reply := replace(v_reply, '{{missing_list}}', coalesce(v_missing, 'nothing, your file is complete'));
    v_reply := replace(v_reply, '{{missing_line}}',
      case when v_missing is null then 'Your file is complete.'
           else 'We still need: ' || v_missing || '.' end);

    v_reply := replace(v_reply, '{{quote_count}}', '0');
    v_reply := replace(v_reply, '{{quote_detail}}',
      'No quotes yet. Once a buyer posts a request in your category you will be invited to quote.');
    v_reply := replace(v_reply, '{{awarded_count}}', '0');
    v_reply := replace(v_reply, '{{awarded_detail}}',
      'No jobs awarded yet. You will get a message here the moment one is.');
  end if;

  -- BY-ID LOOKUP. A number in the body is resolved against the real records, and returned ONLY to a
  -- party who appears on that record. An id is not a password.
  if v_intent.scope = 'by_id' then
    -- The first run of two or more digits. Stripping every digit from the whole sentence turns
    -- 'i have 2 questions about job 55' into 255, which is a different job belonging to someone else.
    v_id := nullif((regexp_match(v_body, '([0-9]{2,})'))[1], '')::bigint;
    if v_id is null then
      v_reply := 'Send me the number and I will look it up. For example: quote 1234, or job 5678.';
    else
      v_reply := replace(v_reply, '{{id_answer}}',
        'I could not find a record numbered ' || v_id || ' that you are a party to. Check the number, '
        || 'or reply HUMAN and the team will look into it.');
    end if;
  end if;

  insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply)
  values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply)
  returning id into v_log;

  return jsonb_build_object(
    'ok', true, 'matched', true, 'intent', v_intent.intent_key,
    'identity_kind', v_ident_k, 'identity_id', v_ident_id,
    'reply', v_reply, 'log_id', v_log, 'answered_by', 'deterministic'
  );
end;
$function$;

-- The template itself, in the spec's wording, with both slots.
update public.wa_reply_intent
   set answer_template = 'Of course. You can contact {{founder_public_name}}, founder of QuotesDone, on {{founder_public_phone}}. I have noted that you asked for a person.'
 where intent_key = 'contact_human';
