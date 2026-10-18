-- PROBE: A CUSTOMER_SUPPORT QUESTION REACHES A PERSON IN FIFTEEN MINUTES (customer_support, 19 Oct 2026).
-- Pure probe, run in the SAME query after a_customer_support_question_reaches_a_person_in_fifteen_minutes.sql so the
-- whole thing aborts; never applied. Files three ZZ-probe held questions 20 minutes old (a reachable person, an
-- anonymous visitor, a fixture), runs the router, and checks: the reachable one is handed over and its action
-- escalated; the anonymous one is dismissed with a reason; the fixture is tagged for the purge and NOT deleted;
-- no other real row changed status.
do $probe$
declare v_real int; v_real2 int; a_id bigint; b_id bigint; c_id bigint; ra text; rb text; rc text; esc boolean;
        c_left int; v_err text;
begin
  begin
    select count(*) into v_real from public.agent_actions where status = 'pending' and agent <> 'customer_support';
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'probe.person', 'probe question one',
            '{"context":{"audience":"customer","customer_id":"00000000-0000-0000-0000-000000000000"}}', '{}', 'probe', 'held',
            now() - interval '20 minutes') returning id into a_id;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'site_assistant.person', 'probe question two', '{"context":{"audience":"visitor"}}',
            '{"path":"/"}', 'probe', 'expired', now() - interval '20 minutes') returning id into b_id;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('customer_support', 'site_assistant.person', 'ZZ DEMO probe three', '{"context":{"audience":"visitor"}}',
            '{"path":"/"}', 'probe', 'held', now() - interval '20 minutes') returning id into c_id;
    insert into public.agent_actions (agent, kind, status, risk, title, target_table, target_id)
    values ('customer_support', 'held_question', 'pending', 'low', 'probe', 'reasoning_held_question', a_id::text);

    perform public.fn_cs_held_question_route();

    select result ->> 'cs_route' into ra from public.reasoning_held_question where id = a_id;
    select result ->> 'cs_route' into rb from public.reasoning_held_question where id = b_id;
    select result ->> 'demo_purge' into rc from public.reasoning_held_question where id = c_id;
    select count(*) into c_left from public.reasoning_held_question where id = c_id;
    select escalated into esc from public.agent_actions where target_id = a_id::text and kind = 'held_question';
    select count(*) into v_real2 from public.agent_actions where status = 'pending' and agent <> 'customer_support';
    raise exception 'ZZPROBE rollback';
  exception when others then v_err := sqlerrm;
  end;
  if v_err <> 'ZZPROBE rollback' then raise exception 'CHK<<PROBE FAILED the router raised: %>>', v_err;
  elsif ra is distinct from 'handed_to_founder' or not coalesce(esc, false) then
    raise exception 'CHK<<PROBE FAILED reachable question: route %, escalated %>>', ra, esc;
  elsif rb is distinct from 'dismissed' then raise exception 'CHK<<PROBE FAILED anonymous visitor: %>>', rb;
  elsif rc is null or c_left <> 1 then raise exception 'CHK<<PROBE FAILED fixture tag % kept %>>', rc, c_left;
  elsif v_real2 <> v_real then raise exception 'CHK<<PROBE FAILED other seats changed: % -> %>>', v_real, v_real2;
  end if;
  raise exception 'CHK<<PROBE OK handed=%, anonymous=%, fixture kept and tagged>>', ra, rb;
end $probe$;
