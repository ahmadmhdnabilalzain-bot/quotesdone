-- PROBE: a harness chat turn carries its run tag and files no knowledge gap and no task (it_engineer, 27 Oct 2026).
-- Pure probe, no DDL of its own: run AFTER its .sql in the SAME query (node scripts/qsql.mjs on a file that
-- concatenates both); it always ends in raise exception CHK<<...>>, so nothing survives, including the .sql it was run
-- after. It reaches no one: it calls two retrieval/filing routines and writes three log rows, all inside the rolled-back
-- transaction; nothing is sent and no model is called. Its rehearsal window is qd_run:zzprobe, its questions are words no
-- corpus holds, and it reads one real number only (org_tasks max id) to count what it created.
-- PROBE OK only if:
--   C0  control: an UNTAGGED question is filed (one gap, one task), so a zero below is the guard and not a dead routine;
--   T1  the same question asked again under the run tag bumps no ask counter and raises no task priority;
--   T2  a new question under the run tag files no gap and opens no task (the widget / WhatsApp door);
--   T3  fn_sales_assist under the run tag files no gap, opens no task, reports gap_recorded false and test_traffic true,
--       and its sales_decision_log row carries the run tag;
--   T4  an UNTAGGED ZZ DEMO question files nothing on either routine;
--   T5  assistant_logs and support_reply_readability rows written under the run tag carry it; an untagged row does not;
--   T6  once the run's window is closed, a new row is not stamped (the ai_cost_log rule, unchanged);
--   T7  across all of it, exactly one org_tasks row was created: C0's.
do $probe$
declare
  v_fail  text := '';
  v       jsonb;
  v_task0 bigint;
  v_n     int;
  v_asks  int;
  v_prio  int;
  v_task  bigint;
  v_tag   text;
  q_old   constant text := 'zzprobe qxjvwk plorfin zentraquist';     -- C0 files it, T1 asks it again
  q_new   constant text := 'zzprobe vremlotic sandquorbel';          -- T2
  q_sales constant text := 'zzprobe drimbalux quenterfold';          -- T3
begin
  insert into public.rehearsal_window (run_tag, opened_by, note)
  values ('qd_run:zzprobe', 'a_harness_chat_turn_carries_its_run_tag_and_files_no_gap_or_task_probe.sql', 'ZZ DEMO probe');
  select coalesce(max(id), 0) into v_task0 from public.org_tasks;

  -- C0: untagged, the door files.
  perform set_config('app.e2e_run_tag', '', true);
  v := public.fn_support_knowledge_gap(q_old, 'probe', 'zz_probe');
  v_task := (v->>'task_id')::bigint;
  select g.asks, t.priority into v_asks, v_prio
    from public.sales_knowledge_gap g left join public.org_tasks t on t.id = g.task_id where g.question_norm = q_old;
  if v_task is null or v_asks is distinct from 1 then
    v_fail := v_fail || ' C0 an untagged question was not filed (task ' || coalesce(v_task::text, 'null') || ', asks ' || coalesce(v_asks::text, 'null') || ');';
  end if;
  if coalesce((v->>'test_traffic')::boolean, true) then v_fail := v_fail || ' C0 untagged traffic was called test traffic;'; end if;

  -- T1: the same question under the run tag.
  perform set_config('app.e2e_run_tag', 'zzprobe', true);
  if public.fn_e2e_run_tag_current() is distinct from 'zzprobe' then v_fail := v_fail || ' T0 the run tag is not current;'; end if;
  v := public.fn_support_knowledge_gap(q_old, 'probe', 'zz_probe');
  if (v->>'test_traffic')::boolean is not true or (v->>'ok')::boolean is not true or v->>'task_id' is not null then
    v_fail := v_fail || ' T1 reply ' || left(v::text, 120) || ';';
  end if;
  if (select asks from public.sales_knowledge_gap where question_norm = q_old) is distinct from v_asks then
    v_fail := v_fail || ' T1 the ask counter was bumped by test traffic;'; end if;
  if (select priority from public.org_tasks where id = v_task) is distinct from v_prio then
    v_fail := v_fail || ' T1 the task priority was raised by test traffic;'; end if;
  v := public.fn_sales_assist(q_old, null::vector);
  if (select asks from public.sales_knowledge_gap where question_norm = q_old) is distinct from v_asks then
    v_fail := v_fail || ' T1 fn_sales_assist bumped the ask counter under the run tag;'; end if;

  -- T2: a new question under the run tag.
  v := public.fn_support_knowledge_gap(q_new, 'probe', 'zz_probe');
  if exists (select 1 from public.sales_knowledge_gap where question_norm = q_new) then v_fail := v_fail || ' T2 a gap was filed;'; end if;

  -- T3: the portal's retrieval under the run tag.
  v := public.fn_sales_assist(q_sales, null::vector);
  if (v->>'answered')::boolean is distinct from false then v_fail := v_fail || ' T3 the nonsense question was answered (probe premise broken);'; end if;
  if (v->>'gap_recorded')::boolean is not false or (v->>'test_traffic')::boolean is not true or v->>'task_id' is not null then
    v_fail := v_fail || ' T3 reply gap_recorded=' || coalesce(v->>'gap_recorded', 'null') || ' test_traffic=' || coalesce(v->>'test_traffic', 'null') || ';';
  end if;
  if exists (select 1 from public.sales_knowledge_gap where question_norm = q_sales) then v_fail := v_fail || ' T3 a gap was filed;'; end if;
  select e2e_run_tag into v_tag from public.sales_decision_log where query = q_sales order by id desc limit 1;
  if v_tag is distinct from 'zzprobe' then v_fail := v_fail || ' T3 the decision row carries ' || coalesce(v_tag, 'no tag') || ';'; end if;

  -- T4: untagged, but the question says ZZ DEMO.
  perform set_config('app.e2e_run_tag', '', true);
  v := public.fn_sales_assist('ZZ DEMO ' || q_sales, null::vector);
  if (v->>'test_traffic')::boolean is not true then v_fail := v_fail || ' T4 a ZZ DEMO portal question is not test traffic;'; end if;
  v := public.fn_support_knowledge_gap('ZZ DEMO ' || q_new, 'probe', 'zz_probe');
  if exists (select 1 from public.sales_knowledge_gap where question in ('ZZ DEMO ' || q_sales, 'ZZ DEMO ' || q_new)) then
    v_fail := v_fail || ' T4 a ZZ DEMO question was filed;'; end if;

  -- T5: the stamp, tagged and untagged.
  perform set_config('app.e2e_run_tag', 'zzprobe', true);
  insert into public.assistant_logs (message, reply, seat, answered, audience, path)
  values ('ZZ DEMO probe turn', 'ZZ DEMO probe reply', 'customer_support', true, 'visitor', 'zz_probe')
  returning e2e_run_tag into v_tag;
  if v_tag is distinct from 'zzprobe' then v_fail := v_fail || ' T5 a tagged assistant_logs row carries ' || coalesce(v_tag, 'no tag') || ';'; end if;
  perform public.fn_support_reply_readability_log('widget', 'en', 'reasoned', false, 90, 90, '{}'::text[], 'ZZ DEMO probe zzprobe', true);
  select e2e_run_tag into v_tag from public.support_reply_readability where reason = 'ZZ DEMO probe zzprobe' order by id desc limit 1;
  if v_tag is distinct from 'zzprobe' then v_fail := v_fail || ' T5 a tagged readability row carries ' || coalesce(v_tag, 'no tag') || ';'; end if;
  perform set_config('app.e2e_run_tag', '', true);
  insert into public.assistant_logs (message, reply, seat, answered, audience, path)
  values ('ZZ DEMO probe turn untagged', null, 'customer_support', false, 'visitor', 'zz_probe')
  returning e2e_run_tag into v_tag;
  if v_tag is not null then v_fail := v_fail || ' T5 an untagged row was stamped ' || v_tag || ';'; end if;

  -- T6: the window closed, the tag is no longer kept.
  update public.rehearsal_window set models_allowed = false where run_tag = 'qd_run:zzprobe';
  perform set_config('app.e2e_run_tag', 'zzprobe', true);
  insert into public.assistant_logs (message, seat, answered, audience, path)
  values ('ZZ DEMO probe turn after the window', 'customer_support', false, 'visitor', 'zz_probe')
  returning e2e_run_tag into v_tag;
  if v_tag is not null then v_fail := v_fail || ' T6 a row after the window closed was stamped;'; end if;

  -- T7: one task in all, C0's.
  select count(*) into v_n from public.org_tasks where id > v_task0;
  if v_n <> 1 then v_fail := v_fail || ' T7 ' || v_n || ' org_tasks were created, expected 1 (the control);'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK control_task=' || v_task || ' tasks_created=' || v_n
                                   else 'PROBE FAILED:' || v_fail end;
end $probe$;
