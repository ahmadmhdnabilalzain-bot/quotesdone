-- THE LIVE SYSTEM GIVES OUT THE PUBLIC NUMBERS AND NEVER THE FOUNDER'S MOBILE.
--
-- Agent: ceo. 2 Nov 2026. Ruling ledger 1482: the public calling number is +971 56 791 8605 (the number on the Contact us page), WhatsApp is +1 218 316 6814.
-- The founder's personal mobile (his personal mobile) stays only where it is server-side (login_otp, voice_otp, app_secrets admin_mfa_phone /
-- founder_mobile) and in the already-signed archived agreement versions, which this file does not touch.
-- Companion of the_founders_mobile_leaves_the_current_legal_texts.sql (the signed and registry texts). Found by reading every small
-- table of production and every routine body on 2 Nov 2026; kb_chunks (8 GB) and the history tables (kb_revisions, assistant_logs,
-- wa_turn, wa_messages, notifications: what was already said or sent) are NOT rewritten, because history is evidence.
--
-- WHAT THIS CHANGES
--   1. Three routines that put the mobile in a reply to a customer or supplier: fn_wa_route (a complaint's closing line),
--      fn_text_did_not_survive_reply (the "your text arrived as question marks" reply), fn_support_knowledge_gap (the "I have no sourced
--      answer" reply). Each is the LIVE definition (the schema mirror text, md5-equal to pg_get_functiondef on 2 Nov 2026) with only the
--      contact sentence changed. CREATE OR REPLACE keeps the owner, SECURITY DEFINER flag, pinned search_path and the grants
--      (service_role only; no PUBLIC, anon or authenticated EXECUTE), which the verdict re-reads.
--   2. company_faq 620 and 622 (Arabic answers the site assistant and the support seats quote). Each update is guarded by the md5 of the row as
--      read, so a row edited since is left alone; trg_company_faq_text_change_clears_embedding clears the embedding so kb_embed re-embeds it.
--   3. The one social_reply_library row that gave the mobile (English and Arabic).
--   4. The company knowledge the seats read is re-rendered, as sync_company_facts.mjs --emit-sql does after a FAQ change.
-- WHAT THIS DOES NOT CHANGE: founder_public_phone (already +12183166814), founder_mobile, admin_mfa_phone, any signed text.
-- No begin/commit: the applier runs the file as one transaction. Ends with a verdict row (PROBE OK or PROBE FAILED).
--   node scripts/apply_sql.mjs scripts/sql/the_live_system_gives_out_the_public_numbers_and_never_the_founders_mobile.sql --apply --ddl --seat ceo

CREATE OR REPLACE FUNCTION public.fn_wa_route(p_phone text, p_body text, p_has_audio boolean DEFAULT false, p_needs_person boolean DEFAULT NULL::boolean, p_intent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  v_det  := public.fn_wa_answer(p_phone, coalesce(p_body, '(voice note)'), p_intent);
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
    v_reply := v_reply || ' If you would rather speak to someone directly, call '
            || '+971 56 791 8605 or message +1 218 316 6814 on WhatsApp.';
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
   -- 6 Oct: a voice note has its own chain (received audio stays on Gemini, matrix v2)
   where purpose = case when p_has_audio then 'whatsapp_voice_note' else 'whatsapp_conversation' end and active;

  return jsonb_build_object(
    'ok', true,
    'needs_model', v_needs,
    'why', v_why,
    'inference_held', v_held,
    -- 6 Oct: rung 1 of the chain, never a literal, so the table is the one place a model is named
    'model', case when v_needs then (select e ->> 'model' from jsonb_array_elements(v_chain) e
                                      where e ->> 'kind' = 'model' order by (e ->> 'rung')::int limit 1) else null end,
    'fallback_chain', case when v_needs then v_chain else null end,
    'on_model_failure',
      'Try each rung in order. Record model_wanted, model_used and fell_back on llm_calls for every '
   || 'attempt, so a fallback that becomes permanent is visible rather than quietly expensive. The '
   || 'final rung is the deterministic reply and it cannot fail.',
    'model_reason', case
      when not v_needs then 'No model needed. The database answered it.'
      -- 6 Oct: matrix v2 (founder_instruction 1108)
      when p_has_audio then 'google/gemini-3.8-flash hears the voice note (received audio stays on Gemini). On failure '
        || 'the deterministic reply.'
      else 'openai/gpt-6-luna first, by the founder''s matrix v2. On failure google/gemini-3.8-flash. On failure the '
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
    'intent_decided_by', case when p_intent is null then 'held: not yet reasoned' else 'reasoning' end,
    'fact_pack', v_pack,
    'model_brief', public.fn_wa_model_brief()
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_text_did_not_survive_reply(p_lang text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when lower(coalesce(p_lang, 'en')) = 'ar' then
      'وصلتني رسالتكم وقد تحوّلت حروفها إلى علامات استفهام، فتعذّرت عليّ قراءة سؤالكم. '
      || 'لا خطأ في سؤالكم، وإنما لم يصل النص سليمًا عبر الاتصال. يُرجى إعادة إرسال الرسالة. '
      || 'وإن تكرر ذلك، يمكنكم الاتصال أو المراسلة عبر واتساب:' || E'\n'
      || E'‎' || '+1 218 316 6814' || E'\n' || 'أو الاتصال الهاتفي على:' || E'\n' || E'‎' || '+971 56 791 8605' || E'\n'
      || '(من الاثنين إلى الجمعة، من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات)' || E'\n'
      || 'أو البريد الإلكتروني:' || E'\n' || 'management@quotesdone.com'
    else
      'Your message reached me with its characters replaced by question marks, so I cannot read '
      || 'what you asked. Nothing is wrong with your question — it did not survive the connection. '
      || 'Please send it again. If it keeps happening, call +971 56 791 8605 or WhatsApp +1 218 316 6814 '
      || '(Mon-Fri, 9am-6pm GST) or email management@quotesdone.com.'
  end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_support_knowledge_gap(p_question text, p_refusal text, p_surface text DEFAULT 'website_widget'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_norm text;
  v_gap  public.sales_knowledge_gap%rowtype;
  v_task bigint;
  v_asks int := 0;
  -- TEST TRAFFIC FILES NOTHING (27 Oct 2026): a request carrying a sandbox run tag, or a ZZ DEMO question. The caller
  -- still gets ok and its reply text, with no task number, so its own reply path does not change.
  v_test boolean := public.fn_e2e_run_tag_current() is not null or public.fn_seat_work_is_demo(p_question, null);
begin
  if coalesce(btrim(p_question), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty_question');
  end if;

  -- THE QUESTION ARRIVED WITH ITS SCRIPT STRIPPED, so there is nothing here to answer and
  -- nothing to file. org_tasks 578945 is what happens without this branch: a task that sat in
  -- the work queue for nine days titled in question marks, asked four times, with no reading of
  -- it possible by anyone.
  --
  -- BOTH KEYS CARRY BOTH LANGUAGES. site_assistant picks between reply_en and reply_ar with
  -- `/[؀-ۿ]/.test(message) || uiLang === 'ar'` — it reads the script of the message, and on this
  -- branch the script is exactly what was destroyed, so a stripped Arabic message is pure ASCII
  -- and that test says "English" for the one visitor who needs the Arabic. The language cannot be
  -- known here, so it is not guessed: whichever key the caller reads, the person gets both
  -- paragraphs. This is the fix for the defect the comment above would otherwise only describe.
  if public.fn_text_lost_its_script(p_question) then
    return jsonb_build_object(
      'ok', false, 'reason', 'text_lost_its_script',
      'reply_en', public.fn_text_did_not_survive_reply('en') || E'\n\n'
                  || public.fn_text_did_not_survive_reply('ar'),
      'reply_ar', public.fn_text_did_not_survive_reply('ar') || E'\n\n'
                  || public.fn_text_did_not_survive_reply('en'));
  end if;

  if not v_test then
    v_norm := left(lower(regexp_replace(btrim(p_question), '\s+', ' ', 'g')), 400);
    select * into v_gap from public.sales_knowledge_gap where question_norm = v_norm;

    if not found then
      insert into public.org_tasks (title, detail, status, tier, action_class, assigned_agent,
                                    priority, requires_evidence, needs_founder)
      values (
        left('Answer an unanswered support question: ' || btrim(p_question), 160),
        'Someone who was NOT signed in asked this on the ' || coalesce(nullif(btrim(p_surface), ''), 'website_widget')
          || ' and Customer Support could not source an answer from company knowledge.' || E'\n\n'
          || 'QUESTION: ' || btrim(p_question) || E'\n'
          || 'REFUSAL: ' || coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer') || E'\n\n'
          || 'THERE IS NO ESCALATION TO A HUMAN -- founder ruling, 9 Sep 2026. This task IS what '
          || 'happens instead, and it is the only thing that happens.' || E'\n\n'
          || 'DONE MEANS: the answer exists in a corpus fn_support_corpus_search reads (company_faq, '
          || 'support_knowledge, ops_knowledge) and this question returns it. Then set '
          || 'sales_knowledge_gap.status to knowledge_added.',
        'assigned', 'advisory', 'knowledge_gap', 'customer_support', 3, true, false)
      returning id into v_task;

      insert into public.sales_knowledge_gap (question_norm, question, refusal, nearest_corpus, task_id)
      values (v_norm, left(btrim(p_question), 2000),
              coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer'),
              'support_corpus', v_task);
      v_asks := 1;
    else
      v_task := v_gap.task_id;
      v_asks := v_gap.asks + 1;
      update public.sales_knowledge_gap
         set asks = asks + 1, last_asked_at = now(),
             refusal = coalesce(nullif(btrim(p_refusal), ''), refusal)
       where id = v_gap.id;
      -- Asked repeatedly is the definition of urgent, exactly as on the sales side.
      update public.org_tasks
         set priority = least(9, greatest(priority, 3 + v_gap.asks)), updated_at = now()
       where id = v_task and status not in ('done', 'cancelled');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true, 'task_id', v_task, 'asks', v_asks, 'test_traffic', v_test,
    'reply_en', 'I do not have a sourced answer to that yet, and I will not guess at it. I have '
      || 'recorded your question exactly as you asked it so it gets answered properly. If you need '
      || 'it now, call +971 56 791 8605 or WhatsApp +1 218 316 6814 (Mon-Fri, 9am-6pm GST) or email '
      || 'management@quotesdone.com.',
    'reply_ar', 'لا تتوفر لديّ إجابة موثّقة عن ذلك حتى الآن، ولا أودّ التخمين. سجّلتُ سؤالكم كما كتبتموه '
      || 'تمامًا ليُجاب عنه إجابة دقيقة. وإن احتجتم إلى الإجابة الآن، يمكنكم الاتصال أو المراسلة عبر '
      || 'واتساب:' || E'\n' || '+1 218 316 6814' || E'\n' || 'أو الاتصال الهاتفي على:' || E'\n' || '+971 56 791 8605' || E'\n' || 'أو البريد الإلكتروني:' || E'\n'
      || 'management@quotesdone.com');
end
$function$;

-- 2. company_faq 620 and 622
update public.company_faq set answer = $qd_faq$تتبع النزاعات مساراً محدداً: ترفع المشكلة، وتُراجع مع السجل الكامل، وتُحل عبر المنصة، بما في ذلك الاسترداد حيثما كان مناسباً، ويُسوّى مقابل المعاملة الأصلية. والهدف نتيجة عادلة للطرفين. وإذا رغبت في التحدث إلى شخص مباشرة، اتصل بنا على الرقم
+971 56 791 8605
أو راسلنا عبر واتساب على الرقم التالي.
+1 218 316 6814
من الاثنين إلى الجمعة، من 9 صباحاً حتى 6 مساءً بتوقيت الخليج، أو راسلنا على
management@quotesdone.com$qd_faq$, updated_at = now() where id = 620 and md5(answer) = '4657bad97023a49a24658d8e468c8257';
update public.company_faq set answer = $qd_faq$يسعدنا التحدث إليك. اتصل بنا على الرقم
+971 56 791 8605
أو راسلنا عبر واتساب على الرقم
+1 218 316 6814
من الاثنين إلى الجمعة، من 9 صباحاً حتى 6 مساءً بتوقيت الخليج. أو راسلنا بالبريد الإلكتروني على
management@quotesdone.com
كما يمكنك استخدام صفحة الاتصال على
/contact$qd_faq$, updated_at = now() where id = 622 and md5(answer) = '1d87c1da534601a8be0d135e3861c83e';

-- 3. social_reply_library
update public.social_reply_library set reply_en = $qd_soc$You can reach our team by phone on +971 56 791 8605 or on WhatsApp on +1 218 316 6814 (Sunday to Thursday, 9am to 6pm UAE time) or at management@quotesdone.com. If you would like a member of our team to continue this conversation here, just reply "agent".$qd_soc$, reply_ar = $qd_soc$يمكنكم التواصل مع فريقنا اتصالًا على:
+971 56 791 8605
أو عبر واتساب على:
+1 218 316 6814
(من الأحد إلى الخميس، من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات)
أو عبر البريد الإلكتروني:
management@quotesdone.com
وإن رغبتم في أن يتابع أحد أعضاء فريقنا هذه المحادثة هنا، فاكتبوا «موظف».$qd_soc$, updated_at = now() where md5(reply_en) = '1d8ddf8da48a12803afa31580b43fc70' and md5(reply_ar) = 'fb7e490ee6e36a236eecde11938ef6fc';

-- 4. re-render the company knowledge the seats read
do $s$ begin perform public.fn_company_org_directory_sync(); perform public.fn_company_self_knowledge_sync(); end $s$;

-- verdict
select case when
       (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fn_wa_route', 'fn_text_did_not_survive_reply', 'fn_support_knowledge_gap')
          and p.prosrc !~ '(50[ .-]?931[ .-]?9355|509319355)' and p.prosrc like '%+971 56 791 8605%' and p.prosrc like '%+1 218 316 6814%'
          and p.proconfig::text like '%search_path=public, pg_temp%'
          and not has_function_privilege('anon', p.oid, 'EXECUTE') and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
          and has_function_privilege('service_role', p.oid, 'EXECUTE')) = 3
   and (select count(*) from public.company_faq where id in (620, 622) and answer !~ '(50[ .-]?931[ .-]?9355|509319355)' and answer like '%+971 56 791 8605%' and answer like '%+1 218 316 6814%') = 2
   and (select count(*) from public.social_reply_library where reply_en ~ '(50[ .-]?931[ .-]?9355|509319355)' or reply_ar ~ '(50[ .-]?931[ .-]?9355|509319355)') = 0
   and (select count(*) from public.company_faq where answer ~ '(50[ .-]?931[ .-]?9355|509319355)' or question ~ '(50[ .-]?931[ .-]?9355|509319355)') = 0
  then 'PROBE OK' else 'PROBE FAILED: a routine, a FAQ row or a social reply still gives the founder''s mobile, a public number is missing, or a routine''s grants changed' end as verdict;
