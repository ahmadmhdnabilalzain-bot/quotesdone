-- A SECOND CLOSING PATH BESIDE THE SPINE, AND THE GUARD THAT REFUSES IT (MASTER_PLAN §4.3), 5 Sep 2026.
--
-- MEASURED on production 5 Sep 2026 18:35 UTC, before this file:
--   * org_tasks done 996; 367 closed through the spine (result.lane = 'org_task', decided_by
--     'workflow_dispatch', a deliverable, a review, a decision_trace, a review_queue row).
--   * 143 done rows carry NO decider or NO deliverable. Grouped by the writer that closed them:
--       31  action_class 'incident'    result NULL          — fn_os_incident_close_task, the AFTER UPDATE
--                                                              trigger on os_incidents: `set status='done'`
--                                                              and nothing else (2–5 Sep; the 8 the packet
--                                                              named are among them)
--       24  action_class 'investigate' result.auto_closed   — fn_edge_health_scan's recovery branch:
--                                                              status='done' + {auto_closed, last_beat_at}
--       63  mode executed_by_invoker, no deliverable          — fn_action_invoke_collect before its six-key
--                                                              extractor (10–12 Aug; that fix already holds)
--       12  mode 'executed' (cos_execute, retired 3 Sep)      — 25 Jul–11 Aug
--       12  'analysis', decided_by fn_event_dispatch, NULL    — one batch on 2 Sep, no writer in pg_proc
--                                                              matches it (closed by hand or by a routine
--                                                              since replaced)
--       1   classified_in_six_slices                          — 12 Aug
--     So the SECOND PATH that is still live is two routines: fn_os_incident_close_task and
--     fn_edge_health_scan. Both close a task as a side effect of a RESOLVED INCIDENT — a fact recorded
--     on os_incidents with a resolver and a resolution — and neither carried that fact onto the task.
--
-- THE DESIGN: a resolved incident is not a playbook application, so it does not go through
-- fn_apply_playbook; it is a FACT CLOSE, and it records what the spine records:
--   fn_org_task_close_as_fact(task, decided_by, deliverable, basis)
--     - result.deliverable (the resolution, who resolved it, when), result.mode 'fact_close',
--       used_llm false, decided_by = the resolver, attempts + 1
--     - fn_task_review runs and its verdict is STORED (result.review); it does not gate the close,
--       because the thing reviewed is a recorded fact, not a determination — the incident row is the
--       evidence and the review chain's rows are the audit of who was told
--     - a sealed decision_trace (decision_type 'fact_close') and an agent_runs row for the employee
--       accountable for the incident (its owner when that is an active org_agent, else the task's
--       assignee), so v_department_health credits the department whose staff carried it
--   Both closers now call it. The 143 historic rows are left as they are: the population is split by
--   this file's apply time, never back-filled.
--
-- THE GUARD: a10_org_task_done_needs_a_determination, BEFORE INSERT OR UPDATE OF status on org_tasks.
--   A transition INTO 'done' with no deliverable or no decided_by is REFUSED with a readable reason
--   naming the two doors (the spine's fn_org_task_deterministic_done, or fn_org_task_close_as_fact).
--   It raises rather than returning NULL: a refusal that is not an error is how the last silent path
--   stayed silent. fn_action_invoke_collect already records a refused close on the action_execution
--   row ('org_task_close':'refused', the SQLERRM), so an invoker whose body carried no deliverable
--   leaves a readable trace instead of a bare done. Fires after a00_ (founder routing) and a05_ (fill
--   ownership, insert only) by name order; trg_org_task_root_cause still runs after it.
--
-- PROVED with an aborted-transaction probe (scripts/phase_c/probe_org_task_done_guard.sql): a bare
-- `update org_tasks set status='done'` on an open task is refused with the reason; a resolved
-- os_incidents row closes its task with a deliverable, a decider, a decision_trace and a review; the
-- spine's own close passes.
--
--   node scripts/apply_sql.mjs scripts/sql/a_second_closing_path_beside_the_spine.sql --apply --ddl

begin;

create or replace function public.fn_org_task_close_as_fact(p_task_id bigint, p_decided_by text, p_deliverable text, p_basis jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  t          record;
  v_deliv    text;
  v_employee text;
  v_review   jsonb;
  v_trace    uuid;
begin
  select o.id, o.dept_key, o.title, o.action_class, o.tier, o.status, o.assigned_agent, o.result
    into t from public.org_tasks o where o.id = p_task_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such org_task ' || p_task_id);
  end if;
  if t.status = 'done' then
    return jsonb_build_object('ok', false, 'reason', 'org_task ' || p_task_id || ' is already done');
  end if;
  if coalesce(btrim(p_decided_by), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'a fact close must name who resolved it (p_decided_by)');
  end if;
  v_deliv := btrim(coalesce(p_deliverable, ''));
  if length(v_deliv) < 40 then
    return jsonb_build_object('ok', false, 'reason', 'a fact close needs the resolution in words (>= 40 characters), not a status flip');
  end if;

  -- the employee accountable for the fact: the incident owner when it is an active colleague, else the
  -- task's assignee, else the department (which fn_org_agent_resolve maps to its head)
  select a.agent_key into v_employee
    from public.org_agents a
   where a.active and a.agent_key = coalesce(p_basis->>'owner', '');
  v_employee := coalesce(v_employee, nullif(t.assigned_agent, ''), t.dept_key);

  update public.org_tasks
     set result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                    'deliverable', left(v_deliv, 20000),
                    'summary',     left(v_deliv, 300),
                    'mode',        'fact_close',
                    'used_llm',    false,
                    'lane',        'fact',
                    'employee',    v_employee,
                    'basis',       coalesce(p_basis, '{}'::jsonb),
                    'at',          now()),
         decided_by  = p_decided_by,
         last_run_at = now(),
         attempts    = coalesce(attempts, 0) + 1,
         updated_at  = now()
   where id = p_task_id;

  v_review := public.fn_task_review(p_task_id);

  insert into public.decision_trace(
      correlation_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      gen_random_uuid(), 'org_task', p_task_id::text, 'fact_close',
      v_employee, p_decided_by, array['org_task_lane','fact_close']::text[],
      '[]'::jsonb,
      jsonb_build_array(jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                                           'title', t.title, 'action_class', t.action_class,
                                           'basis', coalesce(p_basis, '{}'::jsonb), 'review', v_review)),
      '[]'::jsonb,
      jsonb_build_array('the task closes because the fact it was raised for has been recorded as resolved by a named resolver'),
      jsonb_build_object('level', 'low', 'note', 'closes a task on a recorded fact; moves no money, sends nothing, approves nobody'),
      1.0,
      jsonb_build_object('mode', 'fact', 'tier', t.tier, 'paid_provider', 'not used'),
      jsonb_build_object('determination', left(v_deliv, 8000), 'basis', 'recorded resolution; no model call'),
      'closed', v_employee, t.dept_key, 'org_task',
      '{}'::jsonb, jsonb_build_object('os_incidents', 'live at close time'), '{}'::text[], '{}'::text[], '[]'::jsonb,
      'none: the close restates a recorded fact', 'not_escalated',
      'close the org_task on the recorded resolution', 'the mirroring employee_task run, if any, closes with it',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values (v_employee, now(), now(), 'ok',
          jsonb_build_object('org_task_id', p_task_id, 'lane', 'fact', 'decision_trace_id', v_trace,
                             'decided_by', p_decided_by, 'review_outcome', v_review->>'outcome'),
          left('org_task ' || p_task_id || ' closed on a recorded fact by ' || p_decided_by || ': ' || v_deliv, 500));

  update public.org_tasks
     set status  = 'done',
         updated_at = now(),
         result  = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                     'review', v_review, 'decision_trace_id', v_trace, 'disposition', 'fact_close')
   where id = p_task_id;

  return jsonb_build_object('ok', true, 'org_task_id', p_task_id, 'employee', v_employee,
                            'decision_trace_id', v_trace, 'review_outcome', v_review->>'outcome');
end
$function$;

create or replace function public.fn_os_incident_close_task()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_task record;
begin
  if new.status in ('resolved','closed') and coalesce(old.status,'') not in ('resolved','closed') then
    -- close the corrective task the incident opened — with the resolution ON the task (5 Sep 2026):
    -- a bare status flip is refused by a10_org_task_done_needs_a_determination now
    if new.org_task_id is not null then
      select o.id, o.status into v_task from public.org_tasks o where o.id = new.org_task_id;
      if found and v_task.status <> 'done' then
        perform public.fn_org_task_close_as_fact(new.org_task_id,
          coalesce(nullif(new.resolved_by, ''), 'os_incidents#' || new.id),
          'Incident #' || new.id || ' (' || coalesce(new.kind, 'incident') || ', severity ' || coalesce(new.severity, '?')
            || ') "' || coalesce(new.title, '') || '" was ' || new.status || ' by '
            || coalesce(nullif(new.resolved_by, ''), 'an unnamed resolver') || ' at '
            || coalesce(coalesce(new.resolved_at, now())::text, '?') || '. Resolution: '
            || coalesce(nullif(new.resolution, ''), nullif(new.detail->>'resolution', ''), '(none recorded on the incident)')
            || '. Opened ' || coalesce(new.opened_at::text, '?') || ' by ' || coalesce(new.opened_by, '?')
            || '; owner ' || coalesce(new.owner, '(none)') || '.',
          jsonb_build_object('os_incident_id', new.id, 'kind', new.kind, 'severity', new.severity,
                             'owner', new.owner, 'resolved_by', new.resolved_by, 'resolved_at', new.resolved_at,
                             'source', 'fn_os_incident_close_task'));
      end if;
    end if;
    -- capture the lesson so the resolution is remembered, not re-learned
    begin
      insert into public.institutional_memory
        (kind, subject_type, subject_id, headline, detail, outcome, learned_by, confidence, evidence_ref, occurred_at)
      values ('incident', 'os_incident', new.id::text,
              left('Incident resolved: '||coalesce(new.title, '#'||new.id::text), 200),
              left(coalesce(new.detail->>'resolution', new.detail->>'description',
                            'Resolved on '||to_char(now(),'DD Mon YYYY')), 2000),
              'resolved', coalesce(new.owner, 'system'), 0.7, 'os_incident#'||new.id, now());
    exception when others then null; end;
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_edge_health_scan()
 RETURNS TABLE(fn_key text, verdict text, silent_minutes numeric, opened_incident boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r            record;
  v_beat       timestamptz;
  v_silent     numeric;
  v_verdict    text;
  v_note       text;
  v_open       boolean;
  v_title      text;
  v_kind       text;
  v_severity   text;
  v_platform   jsonb;
  v_task       bigint;
begin
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_platform
  from (
    select coalesce(headers->>'sb-error-code', 'status_' || coalesce(status_code::text,'null')) as code,
           count(*) as n
    from net._http_response
    where created > timezone('utc', now()) - interval '30 minutes'
      and (status_code is null or status_code < 200 or status_code >= 300)
    group by 1 order by 2 desc limit 10
  ) x;

  for r in select * from edge_expectation where active order by fn_key loop
    v_beat := null; v_note := null; v_open := false;
    begin
      execute r.heartbeat_sql into v_beat;
    exception when others then
      v_verdict := 'PROBE FAILED';
      v_note := 'heartbeat_sql could not be evaluated: ' || left(sqlerrm, 200);
    end;

    if v_note is null then
      v_silent := case when v_beat is null then null
                       else round(extract(epoch from (now() - v_beat)) / 60.0, 1) end;
      v_verdict := case
        when v_beat is null then 'STALE'
        when v_silent > r.max_silence_minutes then 'STALE'
        else 'ALIVE' end;
    else
      v_silent := null;
    end if;

    insert into edge_health_probe (fn_key, last_beat_at, silent_minutes, verdict, note)
    values (r.fn_key, v_beat, v_silent, v_verdict, v_note);

    if v_verdict <> 'ALIVE' then
      -- 4 SEP 2026: a probe that could not run is reported as a broken probe, never as the capability's
      -- silence. Distinct kind, distinct title, its own severity; the same fn_key-keyed resolve clears it.
      if v_verdict = 'PROBE FAILED' then
        v_kind := 'probe_failed'; v_severity := 'low';
        v_title := 'Probe broken: the heartbeat_sql for ' || r.fn_key || ' could not run — ' ||
                   coalesce(v_note, 'no detail') || ' (the capability was NOT measured)';
      else
        v_kind := 'silent_failure'; v_severity := r.severity;
        v_title := 'Silent failure: ' || r.fn_key || ' has produced no effect for ' ||
                   coalesce(v_silent::text || ' minutes', 'an unknown period') ||
                   ' (threshold ' || r.max_silence_minutes || ')';
      end if;

      if not exists (
        select 1 from os_incidents
        where status = 'open' and detail->>'fn_key' = r.fn_key
      ) then
        insert into os_incidents (title, kind, severity, status, detail, opened_by)
        values (
          left(v_title, 300), v_kind, v_severity, 'open',
          jsonb_build_object(
            'fn_key', r.fn_key,
            'cron_jobname', r.cron_jobname,
            'purpose', r.purpose,
            'blast_radius', r.blast_radius,
            'last_beat_at', v_beat,
            'silent_minutes', v_silent,
            'threshold_minutes', r.max_silence_minutes,
            'probe_note', v_note,
            'heartbeat_sql', case when v_kind = 'probe_failed' then r.heartbeat_sql end,
            'platform_errors_30m', v_platform,
            'detected_by', 'fn_edge_health_scan'),
          'edge_health_watchdog');
        v_open := true;

        insert into org_tasks (dept_key, title, detail, status, tier, action_class, needs_founder)
        values (
          coalesce(r.dept_key, 'product_eng'),  -- 4 Sep 2026: 'technology' is not an org_departments row (FK 23503); Platform & Reliability is
          left(v_title, 300),
          case when v_kind = 'probe_failed' then
            'The watchdog''s own probe for ' || r.fn_key || ' failed to run, so whether the capability is alive is UNKNOWN. ' ||
            E'\n\nStatement that failed: ' || coalesce(r.heartbeat_sql, '(none)') ||
            E'\nError: ' || coalesce(v_note, '') ||
            E'\n\nFix the edge_expectation row (heartbeat_sql) or the relation it reads; do not treat this as an outage of the capability itself.'
          else
            r.purpose || E'\n\nWhat breaks while this stays down: ' || r.blast_radius ||
            E'\n\nLast observed effect: ' || coalesce(v_beat::text, 'never') ||
            E'\nCron job: ' || coalesce(r.cron_jobname, 'unknown') ||
            E'\nSeverity: ' || r.severity ||
            E'\nPlatform error codes in the last 30 minutes: ' || v_platform::text ||
            E'\n\nNote: this was detected by watching the capability''s EFFECT, not its logs. ' ||
            'A function killed by the platform (546 WORKER_RESOURCE_LIMIT, OOM, timeout) never ' ||
            'reaches its own error handler, so agent_runs will look clean. Check ' ||
            'net._http_response and the edge function logs directly.'
          end,
          'proposed', 'supervised', 'investigate',
          -- IT owns technical failures: a dark capability is the technology department's to
          -- investigate and auto-heal, never the founder's to triage. Only refunds reach the founder
          -- (founder standing rule, 2 Sep 2026). The task carries dept_key so the owning department
          -- picks it up; needs_founder stays false. Audit AP-01.
          false);
      end if;
    else
      update os_incidents
         set status = 'resolved', resolved_at = now(), resolved_by = 'edge_health_watchdog',
             resolution = 'Capability resumed producing effects; last beat ' || coalesce(v_beat::text,'?')
       where status = 'open' and detail->>'fn_key' = r.fn_key;
      -- 5 SEP 2026: a recovered capability closes its investigate task through fn_org_task_close_as_fact,
      -- so the close carries the deliverable, the decider, a decision_trace and a review — what the spine
      -- records — instead of status='done' with result NULL. The guard a10_org_task_done_needs_a_determination
      -- refuses the bare form now.
      for v_task in
        select t.id from org_tasks t
         where t.status in ('proposed','assigned','in_progress')
           and t.action_class = 'investigate'
           and (t.title like 'Silent failure: ' || r.fn_key || ' %' or t.title like 'Probe broken: the heartbeat_sql for ' || r.fn_key || ' %')
      loop
        perform fn_org_task_close_as_fact(v_task, 'edge_health_watchdog',
          'Capability ' || r.fn_key || ' resumed producing effects; last beat ' || coalesce(v_beat::text, '?')
            || ' (threshold ' || r.max_silence_minutes || ' minutes). ' || coalesce(r.purpose, '')
            || ' The watchdog measures the EFFECT of the capability, not its logs, so this close is the observed recovery itself.',
          jsonb_build_object('fn_key', r.fn_key, 'last_beat_at', v_beat, 'threshold_minutes', r.max_silence_minutes,
                             'auto_closed', 'capability recovered', 'source', 'fn_edge_health_scan'));
      end loop;
    end if;

    fn_key := r.fn_key; verdict := v_verdict; silent_minutes := v_silent; opened_incident := v_open;
    return next;
  end loop;
end $function$
;


-- ---------------------------------------------------------------------------------------------------
-- THE GUARD. Refuses, in words, a transition into 'done' that carries no determination.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_done_needs_a_determination()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.status = 'done' and (tg_op = 'INSERT' or coalesce(old.status, '') <> 'done') then
    if coalesce(btrim(new.result->>'deliverable'), '') = '' or coalesce(btrim(new.decided_by), '') = '' then
      raise exception
        'org_tasks #% (%) cannot close to done without a determination: % — a task is done when it carries '
        'result.deliverable (what was determined or resolved) and decided_by (who decided it). Close it through '
        'the spine (fn_org_task_deterministic_done: playbook, review, decision_trace) or, for a recorded fact such '
        'as a resolved incident, through fn_org_task_close_as_fact(task, resolver, resolution). A bare status flip '
        'is the second closing path this guard exists to refuse.',
        new.id, left(coalesce(new.title, ''), 70),
        case when coalesce(btrim(new.result->>'deliverable'), '') = '' and coalesce(btrim(new.decided_by), '') = ''
             then 'no deliverable and no decided_by'
             when coalesce(btrim(new.result->>'deliverable'), '') = '' then 'no deliverable'
             else 'no decided_by' end
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end
$function$;

drop trigger if exists a10_org_task_done_needs_a_determination on public.org_tasks;
create trigger a10_org_task_done_needs_a_determination
  before insert or update of status on public.org_tasks
  for each row execute function public.fn_org_task_done_needs_a_determination();

revoke execute on function public.fn_org_task_close_as_fact(bigint, text, text, jsonb) from public;

commit;
