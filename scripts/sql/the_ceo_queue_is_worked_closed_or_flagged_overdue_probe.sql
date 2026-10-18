-- PROBE for the_ceo_queue_is_worked_closed_or_flagged_overdue.sql. Aborted transaction, ends in CHK<<...>>.
-- Run after the .sql in the same query. Fixture rows only (ZZ DEMO); every write rolls back.
--   a  question applied                                   -> done
--   b  question failed, a LATER question on its surface applied -> dismissed (superseded)
--   c  question failed, nothing later applied             -> stays pending, flagged overdue (never dismissed)
--   s  support_question_handover, 9 days old             -> untouched (#1462 owns it)
--   and one ceo_task for the day, no notification.
-- Also reports, read-only, how many live CEO held questions have NO later applied question on their surface (the ones
-- a dismissal could lose; the worker leaves them pending).
do $probe$
declare h_b bigint; h_app bigint; h_c bigint; a_id bigint; b_id bigint; c_id bigint; s_id bigint; live jsonb;
  sa text; sb text; sc text; sc_esc boolean; ss text; ss_esc boolean; n_task int; v_err text; v_fnd int; n_unsuperseded int;
begin
  select count(*) into n_unsuperseded
    from public.agent_actions a join public.reasoning_held_question h on h.id::text = a.target_id
   where a.agent = 'ceo' and a.status = 'pending' and a.kind = 'held_question'
     and h.status not in ('applied', 'answered', 'closed')
     and not exists (select 1 from public.reasoning_held_question n
                      where n.surface = h.surface and n.id > h.id and n.status in ('applied', 'answered', 'closed'));
  begin
    v_fnd := (select count(*) from public.notifications);
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('ceo', 'ceo.zz_probe_superseded', 'ZZ DEMO probe failed', '{}', '{}', 'probe', 'failed', now() - interval '9 days') returning id into h_b;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('ceo', 'ceo.zz_probe_superseded', 'ZZ DEMO probe applied', '{}', '{}', 'probe', 'applied', now() - interval '8 days') returning id into h_app;
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, created_at)
    values ('ceo', 'ceo.zz_probe_lonely', 'ZZ DEMO probe failed alone', '{}', '{}', 'probe', 'failed', now() - interval '9 days') returning id into h_c;
    insert into public.agent_actions (agent, kind, status, risk, title, target_table, target_id, created_at)
    values ('ceo', 'held_question', 'pending', 'low', 'ZZ DEMO probe', 'reasoning_held_question', h_app::text, now() - interval '8 days') returning id into a_id;
    insert into public.agent_actions (agent, kind, status, risk, title, target_table, target_id, created_at)
    values ('ceo', 'held_question', 'pending', 'low', 'ZZ DEMO probe', 'reasoning_held_question', h_b::text, now() - interval '9 days') returning id into b_id;
    insert into public.agent_actions (agent, kind, status, risk, title, target_table, target_id, created_at)
    values ('ceo', 'held_question', 'pending', 'low', 'ZZ DEMO probe', 'reasoning_held_question', h_c::text, now() - interval '9 days') returning id into c_id;
    insert into public.agent_actions (agent, kind, status, risk, title, target_table, target_id, created_at)
    values ('ceo', 'support_question_handover', 'pending', 'medium', 'ZZ DEMO probe', 'reasoning_held_question', h_app::text, now() - interval '9 days') returning id into s_id;

    live := public.fn_ceo_queue_work();

    select status into sa from public.agent_actions where id = a_id;
    select status into sb from public.agent_actions where id = b_id;
    select status, escalated into sc, sc_esc from public.agent_actions where id = c_id;
    select status, escalated into ss, ss_esc from public.agent_actions where id = s_id;
    select count(*) into n_task from public.ceo_task where title like 'CEO queue overdue %' and created_at > now() - interval '1 minute';
    v_fnd := (select count(*) from public.notifications) - v_fnd;
    raise exception 'ZZPROBE rollback';
  exception when others then v_err := sqlerrm;
  end;
  if v_err <> 'ZZPROBE rollback' then raise exception 'CHK<<PROBE FAILED the worker raised: %>>', v_err;
  elsif sa is distinct from 'done' then raise exception 'CHK<<PROBE FAILED applied question: %>>', sa;
  elsif sb is distinct from 'dismissed' then raise exception 'CHK<<PROBE FAILED superseded question: %>>', sb;
  elsif sc is distinct from 'pending' or not coalesce(sc_esc, false) then
    raise exception 'CHK<<PROBE FAILED unsuperseded question must stay pending and flagged: %, %>>', sc, sc_esc;
  elsif ss is distinct from 'pending' or coalesce(ss_esc, false) then
    raise exception 'CHK<<PROBE FAILED support handover touched: %, %>>', ss, ss_esc;
  elsif n_task < 1 then raise exception 'CHK<<PROBE FAILED no ceo_task opened for the overdue list>>';
  elsif v_fnd <> 0 then raise exception 'CHK<<PROBE FAILED % notifications written>>', v_fnd;
  end if;
  raise exception 'CHK<<PROBE OK applied=done, superseded=dismissed, unsuperseded=pending+flagged, support handover untouched, ceo_task opened, no notification; live unsuperseded=%; live run incl. fixtures: %>>', n_unsuperseded, live;
end $probe$;
