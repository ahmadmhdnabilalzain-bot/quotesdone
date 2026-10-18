-- PROBE: A CUSTOMER_SUPPORT QUESTION REACHES A PERSON IN FIFTEEN MINUTES (customer_support, 19 Oct 2026).
-- Pure probe, run in the SAME query after a_customer_support_question_reaches_a_person_in_fifteen_minutes.sql so the
-- whole thing aborts; never applied. Files three probe held questions 20 minutes old (a reachable Arabic-speaking
-- customer, an anonymous visitor, a ZZ DEMO fixture) and checks, end to end:
--   the reachable one is acknowledged in Arabic and handed to the CEO; the CEO duty picks it up (files its reasoning);
--   once that reasoning returns, the duty replies to the person, marks the question answered and closes the handover;
--   the anonymous one is dismissed; the fixture is tagged for the purge and NOT deleted;
--   no founder-kind notification is written, and no other seat's pending item changes.
do $probe$
declare v_real int; v_real2 int; a_id bigint; b_id bigint; c_id bigint; ra text; rb text; rc text; c_left int;
        v_ack text; v_ceo bigint; v_rid bigint; v_reply int; v_held text; v_ho text; v_fnd int; v_err text;
begin
  begin
    select count(*) into v_real from public.agent_actions
     where status = 'pending' and agent not in ('customer_support', 'ceo', 'sales_engineer');
    select count(*) into v_fnd from public.notifications where kind in (select kind from public.founder_mail_policy);
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'probe.person', 'متى يصل عرض السعر؟',
            '{"context":{"audience":"customer","email":"probe-1462@probe.test"}}', '{}', 'probe', 'held',
            now() - interval '20 minutes') returning id into a_id;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'site_assistant.person', 'probe question two', '{"context":{"audience":"visitor"}}',
            '{"path":"/"}', 'probe', 'expired', now() - interval '20 minutes') returning id into b_id;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'site_assistant.person', 'ZZ DEMO probe three', '{"context":{"audience":"visitor"}}',
            '{"path":"/"}', 'probe', 'held', now() - interval '20 minutes') returning id into c_id;

    perform public.fn_cs_held_question_route();
    select result ->> 'cs_route' into ra from public.reasoning_held_question where id = a_id;
    select result ->> 'cs_route' into rb from public.reasoning_held_question where id = b_id;
    select result ->> 'demo_purge' into rc from public.reasoning_held_question where id = c_id;
    select count(*) into c_left from public.reasoning_held_question where id = c_id;
    select lang into v_ack from public.notifications where kind = 'support_question_ack' and to_email = 'probe-1462@probe.test';
    select id into v_ceo from public.agent_actions where agent = 'ceo' and kind = 'support_question_handover' and target_id = a_id::text;

    perform public.fn_ceo_support_handover_duty();                       -- picks it up
    select (detail ->> 'reasoning_id')::bigint into v_rid from public.agent_actions where id = v_ceo;
    update public.reasoning_held_question                                -- the model answers
       set status = 'reasoned', result = '{"answer":"probe reply","decision":{"choice":"reply","fields":{}}}'
     where id = v_rid;
    perform public.fn_ceo_support_handover_duty();                       -- replies and closes
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
  elsif v_ack is distinct from 'ar' then raise exception 'CHK<<PROBE FAILED acknowledgement language: %>>', v_ack;
  elsif v_rid is null then raise exception 'CHK<<PROBE FAILED the CEO duty did not pick the handover up>>';
  elsif v_reply <> 1 or v_held <> 'applied' or v_ho <> 'done' then
    raise exception 'CHK<<PROBE FAILED after the reasoning: replies %, question %, handover %>>', v_reply, v_held, v_ho;
  elsif rb is distinct from 'dismissed' then raise exception 'CHK<<PROBE FAILED anonymous visitor: %>>', rb;
  elsif rc is null or c_left <> 1 then raise exception 'CHK<<PROBE FAILED fixture tag % kept %>>', rc, c_left;
  elsif v_real2 <> v_real then raise exception 'CHK<<PROBE FAILED other seats changed: % -> %>>', v_real, v_real2;
  elsif v_fnd <> 0 then raise exception 'CHK<<PROBE FAILED % founder-kind notifications written>>', v_fnd;
  end if;
  raise exception 'CHK<<PROBE OK ack=%, handed, picked up, replied, closed; anonymous=%, fixture kept and tagged>>', v_ack, rb;
end $probe$;
