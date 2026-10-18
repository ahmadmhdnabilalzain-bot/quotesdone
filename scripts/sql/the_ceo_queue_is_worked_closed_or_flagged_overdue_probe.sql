-- PROBE for the_ceo_queue_is_worked_closed_or_flagged_overdue.sql. Aborted transaction, ends in CHK<<...>>.
-- Run after the .sql in the same query. Fixture rows only (ZZ DEMO); every write rolls back.
do $probe$
declare a_id bigint; b_id bigint; h_app bigint; h_old bigint; old_id bigint;
  sa text; sb text; esc boolean; v_err text; v_fnd int;
begin
  begin
    v_fnd := (select count(*) from public.notifications);
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('ceo', 'ceo.target_forecast', 'ZZ DEMO probe applied', '{}', '{}', 'probe', 'applied', now() - interval '9 days')
    returning id into h_app;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('ceo', 'ceo.knowledge_refresh', 'ZZ DEMO probe failed', '{}', '{}', 'probe', 'failed', now() - interval '9 days')
    returning id into h_old;
    insert into public.agent_actions (agent, kind, status, risk, title, target_table, target_id, created_at)
    values ('ceo', 'held_question', 'pending', 'low', 'ZZ DEMO probe', 'reasoning_held_question', h_app::text, now() - interval '9 days')
    returning id into a_id;
    insert into public.agent_actions (agent, kind, status, risk, title, target_table, target_id, created_at)
    values ('ceo', 'held_question', 'pending', 'low', 'ZZ DEMO probe', 'reasoning_held_question', h_old::text, now() - interval '9 days')
    returning id into b_id;
    insert into public.agent_actions (agent, kind, status, risk, title, created_at)
    values ('ceo', 'zz_probe_item', 'pending', 'low', 'ZZ DEMO probe', now() - interval '9 days') returning id into old_id;

    perform public.fn_ceo_queue_work();

    select status into sa from public.agent_actions where id = a_id;
    select status into sb from public.agent_actions where id = b_id;
    select escalated into esc from public.agent_actions where id = old_id;
    v_fnd := (select count(*) from public.notifications) - v_fnd;
    raise exception 'ZZPROBE rollback';
  exception when others then v_err := sqlerrm;
  end;
  if v_err <> 'ZZPROBE rollback' then raise exception 'CHK<<PROBE FAILED the worker raised: %>>', v_err;
  elsif sa is distinct from 'done' then raise exception 'CHK<<PROBE FAILED applied question: %>>', sa;
  elsif sb is distinct from 'dismissed' then raise exception 'CHK<<PROBE FAILED stale internal question: %>>', sb;
  elsif not coalesce(esc, false) then raise exception 'CHK<<PROBE FAILED old item not flagged overdue>>';
  elsif v_fnd <> 0 then raise exception 'CHK<<PROBE FAILED % notifications written>>', v_fnd;
  end if;
  raise exception 'CHK<<PROBE OK done=%, dismissed=%, overdue flagged, no notification>>', sa, sb;
end $probe$;
