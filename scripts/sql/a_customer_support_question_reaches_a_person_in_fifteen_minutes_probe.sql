-- PROBE: A CUSTOMER_SUPPORT QUESTION REACHES A PERSON IN FIFTEEN MINUTES (customer_support, 19 Oct 2026).
-- Pure probe, run in the SAME query after a_customer_support_question_reaches_a_person_in_fifteen_minutes.sql so the
-- whole thing aborts; never applied. A probe customer with a VERIFIED email and an unverified twin; probe held
-- questions 20 minutes old. It checks, end to end:
--   the verified customer is acknowledged in Arabic ONCE (the router runs twice) and handed to the CEO; a KNOWN customer
--   with no confirmed contact gets nothing, stays open with customer_support and is the CEO's overdue item at 4 h; the CEO duty picks the handover up and files its reasoning as audience customer;
--   a returned answer the gate HOLDS leaves the item open and sends nothing; a passed answer is sent once, the question
--   applied and the item closed; an anonymous visitor is dismissed; a ZZ DEMO fixture is tagged, NOT deleted; no
--   founder-kind notification is written and no other seat's pending item changes.
do $probe$
declare v_real int; v_real2 int; v_cu uuid; v_cu2 uuid; a_id bigint; u_id bigint; b_id bigint; c_id bigint;
        ra text; ru text; rb text; rc text; c_left int; v_acks int; v_ack_lang text; v_u_msgs int; v_ceo bigint;
        v_rid bigint; v_aud text; v_held_verdict text; v_open text; v_after_hold int; v_sent text; v_reply int;
        v_held text; v_ho text; v_again text; v_fnd int; v_err text; v_u_cs int; v_u_ceo text;
begin
  begin
    select count(*) into v_real from public.agent_actions
     where status = 'pending' and agent not in ('customer_support', 'ceo', 'sales_engineer');
    select count(*) into v_fnd from public.notifications where kind in (select kind from public.founder_mail_policy);
    insert into public.customers (email, email_verified) values ('probe-1462@probe.test', true) returning id into v_cu;
    insert into public.customers (email, email_verified) values ('probe-1462-unverified@probe.test', false) returning id into v_cu2;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'probe.person', 'متى يصل عرض السعر؟',
            jsonb_build_object('context', jsonb_build_object('audience', 'customer', 'customer_id', v_cu)), '{}', 'probe', 'held',
            now() - interval '20 minutes') returning id into a_id;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'probe.person', 'when does my quote arrive?',
            jsonb_build_object('context', jsonb_build_object('audience', 'customer', 'customer_id', v_cu2, 'email', 'typed@probe.test')),
            '{}', 'probe', 'held', now() - interval '20 minutes') returning id into u_id;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'site_assistant.person', 'probe question two', '{"context":{"audience":"visitor"}}',
            '{"path":"/"}', 'probe', 'expired', now() - interval '20 minutes') returning id into b_id;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'site_assistant.person', 'ZZ DEMO probe three', '{"context":{"audience":"visitor"}}',
            '{"path":"/"}', 'probe', 'held', now() - interval '20 minutes') returning id into c_id;

    perform public.fn_cs_held_question_route();
    update public.reasoning_held_question set result = result - 'cs_route' where id = a_id;   -- force a retry
    perform public.fn_cs_held_question_route();
    select result ->> 'cs_route' into ra from public.reasoning_held_question where id = a_id;
    select result ->> 'cs_route' into ru from public.reasoning_held_question where id = u_id;
    select result ->> 'cs_route' into rb from public.reasoning_held_question where id = b_id;
    select result ->> 'demo_purge' into rc from public.reasoning_held_question where id = c_id;
    select count(*) into c_left from public.reasoning_held_question where id = c_id;
    select count(*), max(lang) into v_acks, v_ack_lang from public.notifications
     where kind = 'support_question_ack' and to_email = 'probe-1462@probe.test';
    select count(*) into v_u_msgs from public.notifications where to_email in ('probe-1462-unverified@probe.test', 'typed@probe.test');
    select count(*) into v_u_cs from public.agent_actions
     where agent = 'customer_support' and kind = 'support_no_confirmed_contact' and status = 'pending' and target_id = u_id::text;
    update public.reasoning_held_question set created_at = now() - interval '5 hours' where id = u_id;   -- 4 hours pass
    perform public.fn_cs_held_question_route();
    select risk into v_u_ceo from public.agent_actions
     where agent = 'ceo' and kind = 'support_question_handover' and status = 'pending' and target_id = u_id::text;
    select min(id) into v_ceo from public.agent_actions where agent = 'ceo' and kind = 'support_question_handover' and target_id = a_id::text;

    perform public.fn_ceo_support_handover_duty();                                     -- picks it up
    select (detail ->> 'reasoning_id')::bigint into v_rid from public.agent_actions where id = v_ceo;
    select request -> 'context' ->> 'audience' into v_aud from public.reasoning_held_question where id = v_rid;
    update public.reasoning_held_question                                              -- the model answers
       set status = 'reasoned', result = '{"answer":"probe reply 050 123 4567","decision":{"choice":"reply","fields":{}}}'
     where id = v_rid;
    v_held_verdict := public.fn_ceo_support_reply_record(v_ceo, '["it shows contact details"]'::jsonb);   -- the gate holds it
    select status into v_open from public.agent_actions where id = v_ceo;
    select count(*) into v_after_hold from public.notifications where kind = 'support_question_reply' and to_email = 'probe-1462@probe.test';
    update public.reasoning_held_question set result = '{"answer":"probe reply","decision":{"choice":"reply","fields":{}}}' where id = v_rid;
    v_sent := public.fn_ceo_support_reply_record(v_ceo, '[]'::jsonb);                  -- the gate passes it
    v_again := public.fn_ceo_support_reply_record(v_ceo, '[]'::jsonb);                 -- a retry
    select count(*) into v_reply from public.notifications where kind = 'support_question_reply' and to_email = 'probe-1462@probe.test';
    select status into v_held from public.reasoning_held_question where id = a_id;
    select status into v_ho from public.agent_actions where id = v_ceo;

    select count(*) into v_real2 from public.agent_actions
     where status = 'pending' and agent not in ('customer_support', 'ceo', 'sales_engineer');
    v_fnd := (select count(*) from public.notifications where kind in (select kind from public.founder_mail_policy)) - v_fnd;
    raise exception 'ZZPROBE rollback';
  exception when others then v_err := sqlerrm;
  end;
  if v_err <> 'ZZPROBE rollback' then raise exception 'CHK<<PROBE FAILED a routine raised: %>>', v_err;
  elsif ra is distinct from 'handed_to_ceo' or v_ceo is null then raise exception 'CHK<<PROBE FAILED not handed to the CEO: %>>', ra;
  elsif v_acks <> 1 or v_ack_lang is distinct from 'ar' then raise exception 'CHK<<PROBE FAILED acks % in %>>', v_acks, v_ack_lang;
  elsif ru is distinct from 'no_confirmed_contact' or v_u_msgs <> 0 or v_u_cs <> 1 or v_u_ceo is distinct from 'high' then
    raise exception 'CHK<<PROBE FAILED known person, unconfirmed contact: route %, messages %, cs items %, ceo overdue %>>', ru, v_u_msgs, v_u_cs, v_u_ceo;
  elsif v_rid is null or v_aud is distinct from 'customer' then raise exception 'CHK<<PROBE FAILED pickup: reasoning %, audience %>>', v_rid, v_aud;
  elsif v_held_verdict <> 'held' or v_open <> 'pending' or v_after_hold <> 0 then
    raise exception 'CHK<<PROBE FAILED a held reply: %, item %, sent %>>', v_held_verdict, v_open, v_after_hold;
  elsif v_sent <> 'sent' or v_reply <> 1 or v_held <> 'applied' or v_ho <> 'done' or v_again = 'sent' then
    raise exception 'CHK<<PROBE FAILED a passed reply: %, replies %, question %, item %, retry %>>', v_sent, v_reply, v_held, v_ho, v_again;
  elsif rb is distinct from 'dismissed' then raise exception 'CHK<<PROBE FAILED anonymous visitor: %>>', rb;
  elsif rc is null or c_left <> 1 then raise exception 'CHK<<PROBE FAILED fixture tag % kept %>>', rc, c_left;
  elsif v_real2 <> v_real then raise exception 'CHK<<PROBE FAILED other seats changed: % -> %>>', v_real, v_real2;
  elsif v_fnd <> 0 then raise exception 'CHK<<PROBE FAILED % founder-kind notifications written>>', v_fnd;
  end if;
  raise exception 'CHK<<PROBE OK one Arabic ack, known-unconfirmed kept open and overdue to the CEO at 4 h, picked up as customer, held reply kept open, passed reply sent once and closed>>';
end $probe$;
