-- PROBE for the_ceo_queue_is_worked_closed_or_flagged_overdue.sql. Aborted transaction, ends in CHK<<...>>.
-- Run after the .sql in the same query. Fixture rows only (ZZ DEMO); every write rolls back.
--   a  question applied                                                   -> done
--   b  zzprobe_exp:9:1 failed, zzprobe_exp:9:2 applied later (same item)    -> dismissed
--   d  zzprobe_exp:8:1 failed, only the OTHER item (9) applied later        -> pending + flagged (never dismissed)
--   e  zzprobe_k:2026-07-01:x failed, zzprobe_k:2026-10-01:x only 'reasoned' -> pending + flagged (only 'applied' supersedes)
--   s  support_question_handover, 9 days old                                -> untouched (#1462 owns it)
--   an earlier day's open overdue task -> closed (superseded); today's task opened; then, once no listed item is
--   pending, a second run closes today's task. No notification.
-- Also reports, read-only, how many live CEO held questions have no superseding question for their own item.
do $probe$
declare h jsonb := '{}'; a_id bigint; b_id bigint; d_id bigint; e_id bigint; s_id bigint; old_t bigint; live jsonb; v_id bigint;
  sa text; sb text; sd text; sd_esc boolean; se text; se_esc boolean; ss text; ss_esc boolean;
  old_state text; today_state1 text; today_state2 text; v_err text; v_fnd int; n_unsuperseded int; v_today text;
begin
  select count(*) into n_unsuperseded
    from public.agent_actions a join public.reasoning_held_question q on q.id::text = a.target_id
   where a.agent = 'ceo' and a.status = 'pending' and a.kind = 'held_question'
     and q.status <> 'applied'
     and not exists (select 1 from public.reasoning_held_question n
                      where n.surface = q.surface and n.id > q.id and n.status = 'applied' and n.dedupe_key <> q.dedupe_key
                        and public.fn_ceo_queue_dedupe_stem(n.dedupe_key) = public.fn_ceo_queue_dedupe_stem(q.dedupe_key));
  v_today := 'CEO queue overdue ' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  begin
    v_fnd := (select count(*) from public.notifications);
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, dedupe_key, created_at)
    select 'ceo', 'ceo.zz_probe', 'ZZ DEMO probe ' || k, '{}', '{}', 'probe', st, k, now() - interval '9 days'
      from (values ('zzprobe_app:1', 'applied'), ('zzprobe_exp:9:1', 'failed'), ('zzprobe_exp:8:1', 'failed'),
                   ('zzprobe_k:2026-07-01:x', 'failed')) v(k, st);
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, dedupe_key, created_at)
    select 'ceo', 'ceo.zz_probe', 'ZZ DEMO probe ' || k, '{}', '{}', 'probe', st, k, now() - interval '8 days'
      from (values ('zzprobe_exp:9:2', 'applied'), ('zzprobe_k:2026-10-01:x', 'reasoned')) v(k, st);
    for v_id in select id from public.reasoning_held_question where dedupe_key in ('zzprobe_app:1', 'zzprobe_exp:9:1', 'zzprobe_exp:8:1', 'zzprobe_k:2026-07-01:x') loop
      insert into public.agent_actions (agent, kind, status, risk, title, target_table, target_id, created_at)
      values ('ceo', 'held_question', 'pending', 'low', 'ZZ DEMO probe', 'reasoning_held_question', v_id::text, now() - interval '9 days');
    end loop;
    select a.id into a_id from public.agent_actions a join public.reasoning_held_question q on q.id::text = a.target_id where q.dedupe_key = 'zzprobe_app:1' and a.agent = 'ceo';
    select a.id into b_id from public.agent_actions a join public.reasoning_held_question q on q.id::text = a.target_id where q.dedupe_key = 'zzprobe_exp:9:1' and a.agent = 'ceo';
    select a.id into d_id from public.agent_actions a join public.reasoning_held_question q on q.id::text = a.target_id where q.dedupe_key = 'zzprobe_exp:8:1' and a.agent = 'ceo';
    select a.id into e_id from public.agent_actions a join public.reasoning_held_question q on q.id::text = a.target_id where q.dedupe_key = 'zzprobe_k:2026-07-01:x' and a.agent = 'ceo';
    insert into public.agent_actions (agent, kind, status, risk, title, created_at)
    values ('ceo', 'support_question_handover', 'pending', 'medium', 'ZZ DEMO probe', now() - interval '9 days') returning id into s_id;
    delete from public.ceo_task where title = v_today;   -- rolled back: lets the probe see today's task opened fresh
    old_t := public.fn_ceo_task_open('CEO queue overdue 2000-01-01', '#' || d_id || ' held_question: ZZ DEMO probe');

    live := public.fn_ceo_queue_work();

    select status into sa from public.agent_actions where id = a_id;
    select status into sb from public.agent_actions where id = b_id;
    select status, escalated into sd, sd_esc from public.agent_actions where id = d_id;
    select status, escalated into se, se_esc from public.agent_actions where id = e_id;
    select status, escalated into ss, ss_esc from public.agent_actions where id = s_id;
    select state into old_state from public.ceo_task where task_id = old_t;
    select state into today_state1 from public.ceo_task where title = v_today;

    -- every listed item settles: the next run closes today's task
    -- live handoffs close only through their originator, so the second run is shown on a list of the fixtures alone
    update public.ceo_task set detail = 'probe' || E'\n#' || d_id || ' x' || E'\n#' || e_id || ' x' where title = v_today;
    update public.agent_actions set status = 'done' where id in (d_id, e_id);
    perform public.fn_ceo_queue_work();
    select state into today_state2 from public.ceo_task where title = v_today;
    v_fnd := (select count(*) from public.notifications) - v_fnd;
    raise exception 'ZZPROBE rollback';
  exception when others then v_err := sqlerrm;
  end;
  if v_err <> 'ZZPROBE rollback' then raise exception 'CHK<<PROBE FAILED the worker raised: %>>', v_err;
  elsif sa is distinct from 'done' then raise exception 'CHK<<PROBE FAILED applied question: %>>', sa;
  elsif sb is distinct from 'dismissed' then raise exception 'CHK<<PROBE FAILED same-item superseded question: %>>', sb;
  elsif sd is distinct from 'pending' or not coalesce(sd_esc, false) then
    raise exception 'CHK<<PROBE FAILED an unrelated item was dismissed or not flagged: %, %>>', sd, sd_esc;
  elsif se is distinct from 'pending' or not coalesce(se_esc, false) then
    raise exception 'CHK<<PROBE FAILED a reasoned-only later question superseded: %, %>>', se, se_esc;
  elsif ss is distinct from 'pending' or coalesce(ss_esc, false) then
    raise exception 'CHK<<PROBE FAILED support handover touched: %, %>>', ss, ss_esc;
  elsif old_state is distinct from 'done' then raise exception 'CHK<<PROBE FAILED earlier day task not closed: %>>', old_state;
  elsif today_state1 is distinct from 'open' then raise exception 'CHK<<PROBE FAILED today task not opened: %>>', today_state1;
  elsif today_state2 is distinct from 'done' then raise exception 'CHK<<PROBE FAILED today task not closed once its items settled: %>>', today_state2;
  elsif v_fnd <> 0 then raise exception 'CHK<<PROBE FAILED % notifications written>>', v_fnd;
  end if;
  raise exception 'CHK<<PROBE OK same-item dismissed, unrelated and reasoned-only kept+flagged, handover untouched, tasks opened and closed, no notification; live unsuperseded=%; live run incl. fixtures: %>>', n_unsuperseded, live;
end $probe$;
