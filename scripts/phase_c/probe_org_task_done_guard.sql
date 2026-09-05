-- ABORTED-TRANSACTION PROBE for a10_org_task_done_needs_a_determination (5 Sep 2026). Commits nothing:
-- the final RAISE rolls every write back and carries the counts out in its message.
--   node scripts/phase_c/q_tmp.mjs scripts/phase_c/probe_org_task_done_guard.sql
do $$
declare
  v_open   bigint;
  v_refuse text := '(not refused)';
  v_task   bigint;
  v_inc    bigint;
  t        record;
  v_traces int; v_runs int;
  v_pb     record;
  v_spine  jsonb;
  s        record;
  v_spine_refuse text := '(not refused)';
begin
  -- 1. a bare status flip on an open task is REFUSED, in words
  select id into v_open from public.org_tasks where status = 'assigned' order by id limit 1;
  begin
    update public.org_tasks set status = 'done' where id = v_open;
  exception when others then
    v_refuse := sqlstate || ' ' || left(sqlerrm, 160);
  end;

  -- 2. a resolved incident closes its task WITH the determination (fixture, rolled back)
  insert into public.org_tasks (dept_key, title, detail, status, tier, action_class, needs_founder, assigned_agent)
  values ('product_eng', 'ZZ DEMO — Incident probe (QuotesDone fixture, not a real incident)',
          'probe of the fact-close path; this row never commits', 'assigned', 'advisory', 'incident', false, 'qa_manager')
  returning id into v_task;
  insert into public.os_incidents (title, kind, severity, status, detail, opened_by, org_task_id, owner)
  values ('ZZ DEMO — Incident probe (QuotesDone fixture, not a real incident)', 'probe', 'low', 'open',
          '{"fixture": true}'::jsonb, 'probe', v_task, 'cto')
  returning id into v_inc;
  update public.os_incidents set status = 'resolved', resolved_at = now(), resolved_by = 'probe_resolver',
         resolution = 'the probe resolved it; nothing real happened' where id = v_inc;
  select status, decided_by, length(result->>'deliverable') dl, result->>'employee' emp,
         result->'review'->>'outcome' rv, result->>'decision_trace_id' tr into t
    from public.org_tasks where id = v_task;
  select count(*) into v_traces from public.decision_trace where entity_type = 'org_task' and entity_id = v_task::text and decision_type = 'fact_close';
  select count(*) into v_runs from public.agent_runs where counts->>'org_task_id' = v_task::text and status = 'ok';

  -- 3. the spine's own close passes the guard (a real actionable playbook, a synthetic match)
  select k.record_id, k.title into v_pb from public.ops_knowledge k
   where k.runtime_eligible and k.supersession_state = 'current'
     and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')
   order by k.record_id limit 1;
  insert into public.org_tasks (dept_key, title, detail, status, tier, action_class, needs_founder, assigned_agent)
  values ('product_eng', 'ZZ DEMO — spine probe (QuotesDone fixture)', 'probe of the spine close; never commits',
          'assigned', 'advisory', 'analysis', false, 'qa_manager')
  returning id into v_task;
  v_spine := public.fn_org_task_deterministic_done(v_task, null, jsonb_build_object(
     'deliverable', repeat('Determination text for the probe of the spine close through the guard. ', 6),
     'outcome', 'probe outcome', 'similarity', 0.91, 'terms_matched', 3, 'terms_total', 5,
     'playbook_record_id', v_pb.record_id, 'playbook_title', v_pb.title, 'employee', 'qa_manager'));
  select status, decided_by, length(result->>'deliverable') dl into s from public.org_tasks where id = v_task;

  -- 4. and a spine-shaped close with the deliverable stripped is refused too
  begin
    update public.org_tasks set result = result - 'deliverable', status = 'assigned' where id = v_task;
    update public.org_tasks set status = 'done' where id = v_task;
  exception when others then
    v_spine_refuse := sqlstate || ' ' || left(sqlerrm, 120);
  end;

  raise exception 'PROBE %', jsonb_pretty(jsonb_build_object(
    'bare_flip_on_open_task', v_refuse,
    'incident_close', jsonb_build_object('task_status', t.status, 'decided_by', t.decided_by,
        'deliverable_chars', t.dl, 'employee', t.emp, 'review_outcome', t.rv,
        'decision_trace_id', t.tr, 'fact_close_traces', v_traces, 'agent_runs_ok', v_runs),
    'spine_close', jsonb_build_object('rpc', v_spine - 'root_cause', 'task_status', s.status,
        'decided_by', s.decided_by, 'deliverable_chars', s.dl),
    'spine_shape_without_deliverable', v_spine_refuse,
    'trigger_present', (select count(*) from pg_trigger where tgname = 'a10_org_task_done_needs_a_determination')));
end $$;
