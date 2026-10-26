-- THE ORG_TASK LANE RUNS ON THE ONE SPINE (MASTER_PLAN A1 / §4.3), 4 Sep 2026.
--
-- MEASURED on production before this file (04 Sep, 09:xx UTC):
--   * employee_task workflow_run: done 175, cancelled 83, failed 7, running 35. Every one of the 35 is
--     parked on step 1 ('Understand request', action_class 'coordinate') with 16 queued steps behind it.
--   * org_tasks: assigned 605-671 and climbing (fn_event_dispatch adds more every 15 minutes),
--     done 620, cancelled 529. By action_class the assigned pile is analysis 573, recommend 21,
--     exec_review 11; by department marketplace 138, exec 113, product_eng 76, growth 62, people_ops 50,
--     legal 50, supply 38, data_intel 36, finance 27, customer_experience 15.
--   * 639 of the assigned tasks have NO employee_task run at all.
--
-- WHY THE 35 WAIT — three findings, each measured:
--   1. fn_workflow_step_claim refuses `r.workflow_key <> 'employee_task'` outright. The comment in
--      workflow_dispatch says why: an employee_task run "mirrors an org_task that cos_execute already
--      performs and fn_task_review already reviews". cos_execute-on-org_tasks was RETIRED on 3 Sep
--      (cron 124 deactivated, §4.3 / §5.1). The refusal outlived the executor it deferred to, so the
--      step is now nobody's: the sweep cannot take it either (coordinate -> cos_execute is
--      risk_tier 'medium' and advisory_safe=false, so it fails the sweep's low-risk predicate).
--   2. fn_workflow_run_follow_task is a trigger on org_tasks: the run closes when the TASK closes.
--      With no executor on the task, nothing ever closes, so the run cannot either. The direction of
--      the follow is right; the thing being followed had stopped moving.
--   3. fn_emit_task_assigned carries GATE 1 — "never re-announce what the dispatcher itself raised
--      from an event" (decided_by <> 'fn_event_dispatch'). That gate exists to stop an event storm and
--      it must stay, but it also means the 639 event-derived tasks can never be PROMOTED into the
--      spine by the event path. §4.3's "a task needing execution promotes into a workflow_run" had no
--      mechanism for the majority of the backlog.
--
-- THE ONE-SPINE DESIGN, without re-enabling cron 124:
--   A. PROMOTE. fn_org_task_promote() starts the employee_task run for an open org_task that has none,
--      by calling fn_workflow_start directly — no event, so GATE 1 is untouched and no storm is
--      possible. Bounded by a ceiling on runs already in flight, so the queue stays shallow. It runs
--      from fn_org_task_assign (cron 262, hourly): the lane's own cron already owns "make the backlog
--      workable", and a promoter with no caller is a capability with no entry point.
--   B. CLAIM. fn_workflow_step_claim stops refusing employee_task and hands the step over with the
--      OWNING TASK's subject attached (lane='org_task'). It claims such a step only while the task is
--      still open; a task the lane has parked or closed is the follow trigger's, not the dispatcher's.
--   C. DO. workflow_dispatch applies the nearest CORROBORATED actionable company playbook to the
--      TASK (fn_apply_playbook, cosine >= 0.85 plus keyword corroboration — unchanged) and closes
--      through fn_org_task_deterministic_done: substance guards, the deliverable on the task,
--      fn_task_review as the publisher, a sealed decision_trace and a review_queue row. The status
--      change fires fn_workflow_run_follow_task, which closes the whole run in one act — which is
--      exactly what that trigger already says it is doing ("performed and reviewed as one act").
--   D. PARK. No corroborated playbook -> the step is released with the applier's own numbers; after
--      three such attempts fn_workflow_step_release parks it awaiting_model AND parks the task
--      (status 'blocked', result.parked with the reason). Neither is claimed again — never an endless
--      retry, never a silent success. The park records how much actionable knowledge the department
--      held at the time, and fn_org_task_promote un-parks it when that number rises: a park heals when
--      the company learns something, and only then.
--
-- WHAT IS DELIBERATELY NOT CHANGED: the 0.85 cosine floor, the >=2-of->=30% keyword corroboration,
-- the actionable-kind restriction, the sweep's low-risk predicate, and GATE 1 in fn_emit_task_assigned.
--
--   node scripts/apply_sql.mjs scripts/sql/org_task_lane_is_the_workflow_spine_2026_09_04.sql --apply --ddl

begin;

-- ---------------------------------------------------------------------------------------------------
-- The task's SUBJECT: what a company playbook could possibly corroborate.
--
-- fn_apply_playbook's second key is keyword corroboration — at least 2 of the query's lexemes, and at
-- least 30% of them, must appear in the record. A task title carries an opaque identifier ("quote.received
-- on quote d448c629-775e-42e9-b83d-ca46d6ca4752" -> 8 lexemes, 6 of them fragments of one uuid), and NO
-- playbook can ever contain a primary key. Counting those in the denominator fails a genuine match for
-- the arbitrary shape of an id: 2 of 8 is 25%, under the floor, while the same task with a small integer
-- id passes at 67%. workflow_dispatch already made this call once, for the same reason, when it chose to
-- corroborate a workflow step on "process + step" rather than on the trigger-context blob.
--
-- So the corroboration text is the title with identifiers removed, plus the two routing words the task
-- carries in its own columns. The EMBEDDING still sees the whole title and detail — meaning is not
-- narrowed here, only the set of words a record is asked to share.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_subject(p_title text, p_action_class text, p_dept_key text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select btrim(regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(coalesce(p_title, ''),
                 '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', ' ', 'gi'),
               '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?', ' ', 'g'),
             '\m[0-9]+\M', ' ', 'g'),
           '\s+', ' ', 'g'))
      || ' ' || coalesce(p_action_class, '')
      || ' ' || coalesce(p_dept_key, '');
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_workflow_step_claim: the employee_task lane is opened. The ONLY change to the queue's own logic
-- is that an employee_task step is claimable while its owning org_task is still open; everything else
-- (the reflection ceiling, the founder gate, the actor resolution, the awaiting_model park, branches
-- (a) and (b)) is byte-for-byte what it was. The handed-over item gains the task's subject so the
-- dispatcher applies knowledge to THE WORK, not to the generic loop step it is recorded under.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_claim(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_out jsonb; v_today int; v_cap int; v_demand_ready int; v_held boolean;
begin
  v_held := coalesce((public.fn_kernel_paid_provider_gate('anthropic/claude-sonnet-5')->>'allowed')::boolean, false) = false;

  update public.workflow_step_run sr
     set status = 'ready'
   where sr.status = 'running'
     and sr.finished_at is null
     and sr.started_at < now() - interval '15 minutes'
     and not exists (select 1 from public.action_execution x
                      where x.workflow_step_run_id = sr.id
                        and x.status in ('queued','running','succeeded'));

  select coalesce((value #>> '{}')::int, 6) into v_cap
    from public.decision_policy where key = 'workflow_reflection_steps_per_day';
  v_cap := coalesce(v_cap, 6);

  -- NON-DEMAND ONLY, and MODEL WORK ONLY: the ceiling exists to bound paid reasoning. A deterministic
  -- determination costs nothing and is not counted against it.
  select count(*) into v_today
    from public.workflow_step_run sr
   where sr.output->>'worked_by' = 'workflow_dispatch'
     and coalesce(sr.output->>'used_llm', 'true') <> 'false'
     and sr.finished_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'
     and not public.fn_task_is_demand(sr.action_class);

  select count(*) into v_demand_ready
    from public.workflow_step_run sr
    join public.workflow_run r on r.id = sr.workflow_run_id
   where sr.status = 'ready'
     and sr.finished_at is null
     and r.status = 'running'
     and r.workflow_key <> 'employee_task'
     and coalesce(sr.input->>'gate','') <> 'founder'
     and public.fn_task_is_demand(sr.action_class)
     and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
     and not exists (
           select 1 from public.org_action_executor e
            where e.action_class = sr.action_class and e.active and e.kind = 'edge'
              and e.risk_tier = 'low' and e.advisory_safe and e.reversible
              and not e.notifies_human
              and coalesce(e.required_authority,'') <> 'founder');

  if not v_held and v_today >= v_cap and v_demand_ready = 0 then
    return jsonb_build_object('capped', true, 'worked_today', v_today, 'cap', v_cap,
             'demand_ready', 0,
             'note', 'the daily reflection ceiling is spent and no revenue-path step is waiting; see '
                     || 'scripts/sql/the_dispatchers_ceiling_counted_revenue_work_against_reflection.sql');
  end if;

  with pick as (
    select sr.id
      from public.workflow_step_run sr
      join public.workflow_run r on r.id = sr.workflow_run_id
     where sr.status = 'ready'
       and sr.finished_at is null
       and r.status = 'running'
       -- THE ORG_TASK LANE (§4.3). An employee_task run is the promotion of one org_task into the
       -- spine; the dispatcher works it while the task is still open, and the follow trigger owns it
       -- once the task has closed or parked. A run whose task is gone is nobody's work.
       and (r.workflow_key <> 'employee_task'
            or exists (select 1 from public.org_tasks t
                        where t.id::text = r.context->>'task_id'
                          and t.status in ('assigned','in_progress')))
       and coalesce(sr.input->>'gate','') <> 'founder'
       -- the reflection ceiling is untouched: it bounds PAID reasoning, and while the model is held
       -- (v_held) nothing here can reach a paid provider. When the hold lifts the lane obeys it.
       and (public.fn_task_is_demand(sr.action_class) or v_today < v_cap or v_held)
       and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
       -- parked awaiting the model: not claimed again until the hold lifts
       and not (v_held and coalesce(sr.error->>'disposition','') = 'awaiting_model')
       and (
         -- the org_task lane is always the dispatcher's: its executor (cos_execute on coordinate) was
         -- retired on 3 Sep and the sweep's low-risk predicate never accepted it
         r.workflow_key = 'employee_task'
         -- (a) no safe executor owns it: the dispatcher's row, as before
         or not exists (
             select 1 from public.org_action_executor e
              where e.action_class = sr.action_class and e.active and e.kind = 'edge'
                and e.risk_tier = 'low' and e.advisory_safe and e.reversible
                and not e.notifies_human
                and coalesce(e.required_authority,'') <> 'founder')
         -- (b) the model is held and the safe executor cannot finish it: it runs on the model, or it
         --     already left only terminal (held/cancelled/stalled) executions behind
         or (v_held and (
               exists (select 1 from public.org_action_executor e
                        where e.action_class = sr.action_class and e.active
                          and public.fn_executor_needs_model(e.target))
            -- stranded: parked held/stalled, or cancelled on a REFUSAL or a missing decision record.
            -- (A never-dispatched cancel is the sweep's to re-queue, not the dispatcher's.)
            or (exists (select 1 from public.action_execution x
                         where x.workflow_step_run_id = sr.id
                           and (x.status in ('held','stalled')
                                or (x.status = 'cancelled'
                                    and (x.response->>'invoker' = 'refused' or (x.request ? 'decision_record_id')))))
                and not exists (select 1 from public.action_execution x
                                 where x.workflow_step_run_id = sr.id
                                   and x.status in ('queued','running','succeeded')))))
       )
     -- fresh steps before retries: 24 change_deployment step-1 retries (3 attempts each before they
     -- park) must not starve a step that has never been looked at
     order by coalesce(sr.attempts, 0), sr.id
     limit greatest(least(coalesce(p_limit, 5),
                          case when v_held then coalesce(p_limit, 5)
                               else greatest(v_cap - v_today, 0) + v_demand_ready end), 1)
     for update of sr skip locked
  ), claimed as (
    update public.workflow_step_run sr
       set status = 'running', started_at = now()
      from pick
     where sr.id = pick.id
    returning sr.id, sr.workflow_run_id, sr.step_no, sr.actor, sr.action_class, sr.input, sr.attempts, sr.error
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'step_run_id',  c.id,
           'run_id',       c.workflow_run_id,
           'step_no',      c.step_no,
           'employee',     public.fn_workflow_actor_resolve(c.workflow_run_id, c.actor),
           'addressed_as', coalesce(c.input->>'addressed_as', c.actor),
           'action_class', c.action_class,
           'step',         c.input->>'step',
           'gate',         c.input->>'gate',
           'workflow_key', r.workflow_key,
           'workflow',     w.name,
           'context',      r.context,
           'attempts',     coalesce(c.attempts, 0),
           'model_held',   v_held,
           'deterministic_only', v_held,
           -- THE ORG_TASK LANE: the work is the task, not the loop step it is recorded under.
           'lane',                 case when r.workflow_key = 'employee_task' and t.id is not null then 'org_task' else 'workflow_step' end,
           'org_task_id',           t.id,
           'org_task_title',        t.title,
           'org_task_detail',       left(coalesce(t.detail, ''), 2000),
           'org_task_dept',         t.dept_key,
           'org_task_action_class', t.action_class,
           'org_task_subject',      case when t.id is null then null
                                         else public.fn_org_task_subject(t.title, t.action_class, t.dept_key) end,
           'stranded_reason', case
              when exists (select 1 from public.org_action_executor e
                            where e.action_class = c.action_class and e.active and e.kind = 'edge'
                              and e.risk_tier = 'low' and e.advisory_safe and e.reversible
                              and not e.notifies_human)
               then coalesce((select 'executor ' || coalesce(x.executor, e2.target) || ' left status=' || x.status
                                     || coalesce(' (' || (x.response->>'reason') || ')', '')
                                from public.action_execution x
                                join public.org_action_executor e2 on e2.action_class = c.action_class and e2.active
                               where x.workflow_step_run_id = c.id
                               order by x.created_at desc limit 1),
                             'executor runs on the held paid model; not queued')
              else null end,
           'prior_steps', (select coalesce(jsonb_agg(jsonb_build_object(
                                    'step_no', p.step_no,
                                    'step',    p.input->>'step',
                                    'by',      coalesce(p.output->>'employee', p.actor),
                                    'outcome', left(coalesce(p.output->>'outcome',
                                                             p.output->>'note', ''), 600))
                                  order by p.step_no), '[]'::jsonb)
                             from (select p2.* from public.workflow_step_run p2
                                    where p2.workflow_run_id = c.workflow_run_id
                                      and p2.step_no < c.step_no
                                      and p2.status = 'done'
                                      and coalesce(p2.output->>'outcome', p2.output->>'note','') <> ''
                                    order by p2.step_no desc
                                    limit 3) p)
         ) order by c.id), '[]'::jsonb)
    into v_out
    from claimed c
    join public.workflow_run r on r.id = c.workflow_run_id
    left join public.workflow w on w.workflow_key = r.workflow_key
    left join public.org_tasks t on r.workflow_key = 'employee_task'
                                and t.id::text = r.context->>'task_id';

  return v_out;
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_workflow_step_release: unchanged for a workflow step. For an ORG_TASK LANE step it also parks the
-- owning task, so the backlog says what the run says: this work has no company knowledge behind it yet.
-- The park records how many actionable, embedded, in-scope records the department held at that moment
-- — fn_org_task_promote re-opens it only when that number has risen.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_workflow_step_release(p_step_run_id bigint, p_reason text)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_attempts int; v_disp text; v_task bigint; v_dept text; v_known int; v_parked int := 0;
begin
  select coalesce(attempts,0) + 1 into v_attempts from public.workflow_step_run
   where id = p_step_run_id and status = 'running' and finished_at is null;
  if not found then return 'not held'; end if;

  v_disp := case when v_attempts >= 3 and coalesce(p_reason,'') ~* '^no company playbook'
                 then 'awaiting_model' else 'retry' end;

  update public.workflow_step_run
     set status   = 'ready',
         attempts = v_attempts,
         error    = jsonb_build_object('released_at', now(), 'reason', left(coalesce(p_reason,''), 500),
                                       'released_by', 'workflow_dispatch',
                                       'attempts', v_attempts,
                                       'disposition', v_disp,
                                       'note', case when v_disp = 'awaiting_model'
                                                    then 'parked: no company playbook covered this step in ' || v_attempts
                                                      || ' deterministic attempts; it waits for the ~5% model path (held) and is not retried until the hold lifts'
                                                    else null end)
   where id = p_step_run_id and status = 'running' and finished_at is null;

  if v_disp = 'awaiting_model' then
    select t.id, t.dept_key into v_task, v_dept
      from public.workflow_step_run s
      join public.workflow_run r on r.id = s.workflow_run_id and r.workflow_key = 'employee_task'
      join public.org_tasks t on t.id::text = r.context->>'task_id'
     where s.id = p_step_run_id and t.status in ('assigned','in_progress');

    if v_task is not null then
      v_known := public.fn_org_task_lane_knowledge(v_dept);
      update public.org_tasks
         set status     = 'blocked',
             updated_at = now(),
             last_run_at = now(),
             result     = coalesce(result, '{}'::jsonb) || jsonb_build_object(
               'parked', jsonb_build_object(
                 'at', now(), 'by', 'workflow_dispatch (org_task lane)',
                 'attempts', v_attempts,
                 'reason', left(coalesce(p_reason,''), 500),
                 'knowledge_at_park', v_known,
                 'note', 'No corroborated actionable company playbook covers this task, so it was not '
                      || 'closed and it is not retried in a loop. The org_task lane is deterministic '
                      || 'only — its model executor (cos_execute on coordinate) was retired on 3 Sep — '
                      || 'so what this waits for is AUTHORED KNOWLEDGE, not inference. '
                      || 'fn_org_task_promote re-opens it when the department holds more actionable '
                      || 'in-scope knowledge than the ' || v_known || ' records it held here.'))
       where id = v_task;
      get diagnostics v_parked = row_count;
    end if;
  end if;

  return case when v_disp = 'awaiting_model'
              then 'parked awaiting model' || case when v_parked > 0 then ' (org_task ' || v_task || ' parked)' else '' end
              else 'released' end;
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- How much ACTIONABLE, embedded, in-scope company knowledge a department can currently be answered by.
-- This is the exact population fn_apply_playbook searches, so a park that records it is recording the
-- thing that has to change before a retry could possibly come out differently.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_lane_knowledge(p_dept text)
returns integer
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select count(*)::int
    from public.ops_knowledge k
   where k.runtime_eligible
     and k.supersession_state = 'current'
     and k.embedding_gte is not null
     and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')
     and (k.scope_type in ('company','external_source')
          or (k.scope_type = 'department' and k.dept_key = any(public.fn_dept_scope(coalesce(p_dept,'exec')))));
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_org_task_deterministic_done: the ONLY way the org_task lane closes a task.
--
-- It refuses a determination without substance (a runtime-eligible playbook id, cosine at or above the
-- applier's floor, the corroboration the applier demands, a deliverable long enough to be one), writes
-- the deliverable onto the task, and then lets fn_task_review PUBLISH it — the department head, the
-- Chief of Staff, the ownership record and the cross-department challenge, unchanged. Only a review
-- that reaches 'published'/'approve' closes the task; anything else leaves it open with the reviewer's
-- reason and the caller releases the step. The status change fires fn_workflow_run_follow_task, which
-- closes the mirroring employee_task run in one act.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_deterministic_done(p_task_id bigint, p_step_run_id bigint, p_output jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  t            record;
  v_floor      numeric := 0.85;      -- fn_apply_playbook's floor; a caller cannot lower it here
  v_sim        numeric;
  v_terms      int;
  v_total      int;
  v_deliv      text;
  v_outcome    text;
  v_employee   text;
  v_review     jsonb;
  v_verdict    text;
  v_trace      uuid;
  v_queue      bigint;
  v_rc         text;
  v_att        numeric;
  v_band       text;
begin
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.tier, o.status, o.assigned_agent
    into t from public.org_tasks o where o.id = p_task_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such org_task ' || p_task_id);
  end if;
  if t.status not in ('assigned','in_progress') then
    return jsonb_build_object('ok', false, 'reason', 'org_task ' || p_task_id || ' is ' || t.status || ', not open work');
  end if;

  v_deliv   := coalesce(p_output->>'deliverable', '');
  v_outcome := coalesce(nullif(p_output->>'outcome',''), left(v_deliv, 280));
  v_sim     := nullif(p_output->>'similarity', '')::numeric;
  v_terms   := coalesce(nullif(p_output->>'terms_matched','')::int, 0);
  v_total   := coalesce(nullif(p_output->>'terms_total','')::int, 0);
  v_employee := coalesce(nullif(p_output->>'employee',''), t.assigned_agent, t.dept_key);

  -- FALSE-SUCCESS GUARDS. Nothing below runs unless the determination has substance.
  if coalesce(p_output->>'playbook_record_id','') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no playbook_record_id: a determination must cite the company knowledge it applied');
  end if;
  if not exists (select 1 from public.ops_knowledge k
                  where k.record_id = p_output->>'playbook_record_id'
                    and k.runtime_eligible and k.supersession_state = 'current'
                    and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')) then
    return jsonb_build_object('ok', false, 'reason', 'playbook ' || (p_output->>'playbook_record_id')
             || ' is not a current, runtime-eligible, ACTIONABLE ops_knowledge record');
  end if;
  if v_sim is null or v_sim < v_floor then
    return jsonb_build_object('ok', false, 'reason', 'similarity ' || coalesce(v_sim::text,'null') || ' is below the apply floor ' || v_floor);
  end if;
  if v_terms < 2 or v_total < 1 or (v_terms::numeric / v_total) < 0.30 then
    return jsonb_build_object('ok', false, 'reason', 'corroboration ' || v_terms || ' of ' || v_total
             || ' task terms is under the 2-and-30% bar the applier demands');
  end if;
  if length(v_deliv) < 300 then
    return jsonb_build_object('ok', false, 'reason', 'deliverable shorter than 300 characters is not a determination');
  end if;

  -- The org_task quality standard requires a RESULT: line (major severity). The determination is the
  -- playbook's own content, which does not carry one, so the applier's outcome sentence becomes it.
  if v_deliv !~* '(^|\n)\s*RESULT:' then
    v_deliv := v_deliv || E'\n\nRESULT: ' || left(v_outcome, 300);
  end if;

  -- A KPI-miss task cannot close without a root cause (trg_org_task_root_cause). The honest
  -- deterministic diagnosis available without the model is the ATTAINMENT BAND, read from the task's
  -- own numbers, which fn_kpi_review wrote into the detail as "actual X (Y% of target)". A band is a
  -- class of cause, and it says which class it is rather than inventing a specific one.
  if t.title ilike 'KPI missed%' then
    v_att := nullif(substring(coalesce(t.detail,'') from '\(([0-9]+(?:\.[0-9]+)?)% of target\)'), '')::numeric;
    v_band := case
      when v_att is null      then 'unmeasured: the task carries no attainment figure, so the variance class cannot be read from it'
      when v_att < 5          then 'no throughput: attainment ' || v_att || '% means the input that feeds this metric has not started, not that it under-performed'
      when v_att < 50         then 'capacity or conversion shortfall: attainment ' || v_att || '% is real activity falling well short of the target'
      when v_att < 100        then 'target above current capability: attainment ' || v_att || '% is near-miss performance against a target set higher than the process currently reaches'
      else 'measurement: attainment ' || v_att || '% is at or above target, so the miss is in how the metric is measured or dated, not in the work' end;
    v_rc := left('Root cause (deterministic band, no model call): ' || v_band
              || '. Closing action taken from company playbook "' || coalesce(p_output->>'playbook_title','') || '" ('
              || (p_output->>'playbook_record_id') || ', cosine ' || v_sim || ', corroborated ' || v_terms || '/' || v_total || ').', 500);
  end if;

  -- The deliverable must be ON THE ROW before the review: fn_task_review reads it off org_tasks.
  update public.org_tasks
     set result = jsonb_build_object(
                    'deliverable', left(v_deliv, 20000),
                    'summary',     left(v_outcome, 300),
                    'mode',        'determined',
                    'used_llm',    false,
                    'lane',        'org_task',
                    'worked_by',   'workflow_dispatch',
                    'employee',    v_employee,
                    'playbook_record_id',   p_output->>'playbook_record_id',
                    'playbook_title',       p_output->>'playbook_title',
                    'playbook_record_type', p_output->>'playbook_record_type',
                    'similarity',   v_sim,
                    'terms_matched', v_terms,
                    'terms_total',   v_total,
                    'workflow_step_run_id', p_step_run_id,
                    'at', now())
                  || case when coalesce(result,'{}'::jsonb) ? 'parked'
                          then jsonb_build_object('previously_parked', result->'parked') else '{}'::jsonb end,
         root_cause  = coalesce(v_rc, root_cause),
         decided_by  = 'workflow_dispatch',
         last_run_at = now(),
         attempts    = coalesce(attempts, 0) + 1,
         updated_at  = now()
   where id = p_task_id;

  -- THE PUBLISHER. Department head -> Chief of Staff -> ownership -> cross-department challenge.
  v_review  := public.fn_task_review(p_task_id);
  v_verdict := coalesce(v_review->>'outcome', 'unknown');

  if v_verdict not in ('published','approve') then
    -- Not a close, and not a silent one either: the reviewer's verdict stays on the row and the caller
    -- releases the step with this reason.
    update public.org_tasks
       set result = coalesce(result,'{}'::jsonb) || jsonb_build_object('review', v_review),
           updated_at = now()
     where id = p_task_id;
    return jsonb_build_object('ok', false, 'reason', 'review returned ' || v_verdict
             || coalesce(': ' || left((v_review->'violations')::text, 300), ''), 'review', v_review);
  end if;

  -- The sealed record of what was decided, on what, by which rule, with what confidence.
  insert into public.decision_trace(
      correlation_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      gen_random_uuid(), 'org_task', p_task_id::text, 'deterministic_playbook_application',
      v_employee, 'fn_apply_playbook', array['deterministic_first','org_task_lane']::text[],
      jsonb_build_array(jsonb_build_object('record_id', p_output->>'playbook_record_id',
                                           'title', p_output->>'playbook_title',
                                           'similarity', v_sim,
                                           'terms_matched', v_terms, 'terms_total', v_total)),
      jsonb_build_array(jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                                           'title', t.title, 'action_class', t.action_class,
                                           'workflow_step_run_id', p_step_run_id,
                                           'review', v_review)),
      coalesce(p_output->'candidates', '[]'::jsonb),
      jsonb_build_array('the nearest CORROBORATED actionable company playbook is the applicable one for this task'),
      jsonb_build_object('level', 'low', 'note', 'advisory determination; moves no money, sends nothing, approves nobody'),
      v_sim,
      jsonb_build_object('mode', 'advisory', 'tier', t.tier, 'paid_provider', 'held'),
      jsonb_build_object('determination', left(v_deliv, 8000), 'outcome', left(v_outcome, 400),
                         'basis', 'nearest corroborated company knowledge by meaning; no model call'),
      'pending', v_employee, t.dept_key, 'org_task',
      '{}'::jsonb, jsonb_build_object('ops_knowledge', 'live at decision time'), '{}'::text[], '{}'::text[], '[]'::jsonb,
      'low-confidence deterministic disposition: the corroborated playbook was applied, not reasoned over; queued for review',
      'review_queued', 'close the org_task with a deterministic disposition',
      'the mirroring employee_task run closes with it; a reviewer can overturn the determination',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  insert into public.review_queue(kind, dept_key, title, summary, payload, status)
  values ('deterministic_org_task', t.dept_key,
          left('Deterministic determination: org_task ' || p_task_id || ' — ' || coalesce(t.title,''), 240),
          left(v_outcome, 600),
          jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                             'workflow_step_run_id', p_step_run_id,
                             'employee', v_employee,
                             'playbook_record_id', p_output->>'playbook_record_id',
                             'playbook_title', p_output->>'playbook_title',
                             'similarity', v_sim, 'terms_matched', v_terms, 'terms_total', v_total,
                             'decision_trace_id', v_trace, 'review', v_review,
                             'disposition', 'deterministic_low_confidence'),
          'pending')
  returning id into v_queue;

  update public.org_tasks
     set status     = 'done',
         updated_at = now(),
         result     = coalesce(result,'{}'::jsonb) || jsonb_build_object(
                        'review', v_review,
                        'decision_trace_id', v_trace,
                        'review_queue_id', v_queue,
                        'disposition', 'deterministic_low_confidence')
   where id = p_task_id;

  return jsonb_build_object('ok', true, 'org_task_id', p_task_id, 'review_outcome', v_verdict,
                            'decision_trace_id', v_trace, 'review_queue_id', v_queue,
                            'root_cause', v_rc);
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_org_task_promote: §4.3's promotion, and the un-park.
--
-- (1) UN-PARK first. A task parked for want of knowledge is re-opened only when its department holds
--     MORE actionable in-scope knowledge than it did at the park. Nothing else re-opens it, so a park
--     is not a retry loop and not a grave either.
-- (2) PROMOTE. An open org_task with no employee_task run gets one, by calling fn_workflow_start
--     directly — no company_event, so fn_emit_task_assigned's GATE 1 stays exactly as it is and no
--     event storm is possible. Bounded twice: by p_limit, and by a ceiling on runs already in flight,
--     so the spine's queue never grows faster than the dispatcher drains it.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_promote(p_limit integer default 12, p_in_flight_ceiling integer default 60)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; v_run uuid;
  v_unparked int := 0; v_promoted int := 0; v_in_flight int; v_room int; v_backlog int;
begin
  -- (1) un-park what the company has since learned how to do
  for r in
    select t.id, t.dept_key, coalesce((t.result->'parked'->>'knowledge_at_park')::int, 0) was
      from public.org_tasks t
     where t.status = 'blocked' and (t.result ? 'parked')
     order by t.id
     limit 200
  loop
    if public.fn_org_task_lane_knowledge(r.dept_key) > r.was then
      update public.org_tasks
         set status = 'assigned', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'unparked', jsonb_build_object('at', now(),
                 'knowledge_at_park', r.was,
                 'knowledge_now', public.fn_org_task_lane_knowledge(r.dept_key),
                 'reason', 'the department now holds more actionable in-scope knowledge than when this parked'))
       where id = r.id;
      update public.workflow_step_run sr
         set status = 'ready', attempts = 0, error = null
        from public.workflow_run wr
       where wr.id = sr.workflow_run_id and wr.workflow_key = 'employee_task'
         and wr.context->>'task_id' = r.id::text
         and sr.finished_at is null
         and coalesce(sr.error->>'disposition','') = 'awaiting_model';
      v_unparked := v_unparked + 1;
    end if;
  end loop;

  -- (2) promote, within the in-flight ceiling
  select count(*) into v_in_flight
    from public.workflow_run r where r.workflow_key = 'employee_task' and r.status = 'running';
  v_room := greatest(least(coalesce(p_limit, 12), coalesce(p_in_flight_ceiling, 60) - v_in_flight), 0);

  select count(*) into v_backlog
    from public.org_tasks t
   where t.status in ('assigned','in_progress')
     and not exists (select 1 from public.workflow_run r
                      where r.workflow_key = 'employee_task' and r.context->>'task_id' = t.id::text);

  if v_room > 0 then
    for r in
      select t.id, t.dept_key
        from public.org_tasks t
       where t.status in ('assigned','in_progress')
         and coalesce(t.needs_founder, false) = false
         and not exists (select 1 from public.workflow_run wr
                          where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text)
       order by t.priority desc nulls last, t.created_at, t.id
       limit v_room
    loop
      begin
        v_run := public.fn_workflow_start('employee_task', null, 'org_task', r.id::text,
                   jsonb_build_object('task_id', r.id::text, 'dept_key', r.dept_key,
                                      'promoted_by', 'fn_org_task_promote',
                                      'promoted_at', now()));
        if v_run is not null then v_promoted := v_promoted + 1; end if;
      exception when others then
        -- one task that cannot be promoted (no resolvable actor, say) must not stop the sweep
        null;
      end;
    end loop;
  end if;

  return jsonb_build_object('unparked', v_unparked, 'promoted', v_promoted,
                            'in_flight_before', v_in_flight, 'room', v_room,
                            'backlog_without_a_run', v_backlog, 'ran_at', now());
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- The promoter's ENTRY POINT. fn_org_task_assign is the org_task lane's own hourly cron (job 262); it
-- already owns "make the backlog workable". Giving an unowned task an owner and putting an owned task
-- on the spine is one act, and a promoter reachable from nowhere is a capability with no entry point.
-- Everything above the added block is fn_org_task_assign unchanged.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_assign(p_limit integer default 200)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record; v_pick text;
  v_assigned int := 0; v_no_capacity int := 0; v_considered int := 0; v_saturated text;
  v_promote jsonb;
  REVIEW_CLASSES constant text[] := array['review','audit','verify','qa_gate','security_review',
                                          'compliance_check','legal_review','supplier_verify',
                                          'capability_review','self_review'];
begin
  -- ONE TASK AT A TIME, TO THE CURRENTLY-LEAST-LOADED ELIGIBLE COLLEAGUE. Assigning inside the
  -- transaction makes each pick see the assignments already made in this sweep, so the load spreads
  -- breadth-first across the department and a single sweep fills it.
  --
  -- 4 Sep 2026: priority first. fn_priority_backlog_reorder raises it on the open tasks of a
  -- cross-OS episode that concluded with a high/medium assessed severity (priority.updated), so a
  -- re-prioritisation changes who gets served next instead of only minting a task about it.
  for r in
    select t.id, t.dept_key, t.action_class
      from public.org_tasks t
     where t.assigned_agent is null
       and t.status in ('assigned','in_progress')
     order by t.priority desc, t.created_at, t.id
     limit greatest(coalesce(p_limit, 200), 1)
  loop
    v_considered := v_considered + 1;
    select a.agent_key into v_pick
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role rr on rr.runtime_agent_key = a.agent_key and rr.status = 'active'
     where a.active
       and coalesce(a.available, true)
       and (a.unavailable_until is null or a.unavailable_until < now())
       and a.department = r.dept_key
       -- AN INDEPENDENT REVIEWER CARRYING THE DEPARTMENT'S ROUTINE QUEUE IS NOT INDEPENDENT OF IT.
       -- Review work still reaches them: the review action classes are the exception, and
       -- fn_pick_reviewer routes review directly rather than through this queue.
       and (coalesce(rr.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer'
            or coalesce(r.action_class, '') = any (REVIEW_CLASSES))
       -- REMAINING CAPACITY, RECOMPUTED EACH PICK so it counts what this sweep already assigned.
       and (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key
               and o.status in ('assigned','in_progress')) < coalesce(a.max_open_tasks, 6)
     order by case when p.tier = 'probation' then 1 else 0 end,
              (select count(*) from public.org_tasks o
                where o.assigned_agent = a.agent_key
                  and o.status in ('assigned','in_progress')),
              a.agent_key
     limit 1;

    if v_pick is not null then
      update public.org_tasks set assigned_agent = v_pick, updated_at = now() where id = r.id;
      v_assigned := v_assigned + 1;
    else
      v_no_capacity := v_no_capacity + 1;
    end if;
  end loop;

  -- Departments that genuinely could not take all their open work: every eligible colleague was at
  -- max_open_tasks. Now that a sweep fills a department, this is a TRUE saturation signal.
  select string_agg(x.dept_key||' '||x.unowned||'/'||x.capacity, ', ' order by x.unowned desc)
    into v_saturated
    from (select t.dept_key, count(*) as unowned,
                 (select coalesce(sum(coalesce(a.max_open_tasks,6)),0) from public.org_agents a
                   where a.active and coalesce(a.available,true) and a.department = t.dept_key) as capacity
            from public.org_tasks t
           where t.assigned_agent is null and t.status in ('assigned','in_progress')
           group by t.dept_key
          having count(*) > 0
           order by count(*) desc
           limit 6) x;

  -- ONTO THE SPINE (§4.3). An owned task that needs doing is promoted into its employee_task run, and
  -- a task parked for want of knowledge is re-opened when the department has since acquired some.
  begin
    v_promote := public.fn_org_task_promote();
  exception when others then
    v_promote := jsonb_build_object('error', sqlerrm);
  end;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('org_task_assign', now(), now(), 'ok',
          jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                             'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'),
                             'promoted_to_spine', v_promote),
          'Assigned '||v_assigned||' of '||v_considered||' unowned open task(s) to the currently '
          ||'least-loaded named colleague in the owning department, spreading within the department '
          ||'and skipping independent reviewers for non-review work. '||v_no_capacity||' left unowned '
          ||'only where every eligible colleague was already at max_open_tasks - deliberate: an '
          ||'unowned task is visible, an overloaded one is not. Departments still carrying more open '
          ||'work than they staff (unowned/capacity): '||coalesce(v_saturated,'none')||'. Promoted onto '
          ||'the workflow spine: '||coalesce(v_promote::text,'{}')||'.');

  return jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                            'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'),
                            'promoted_to_spine', v_promote);
end
$function$;

revoke execute on function public.fn_org_task_deterministic_done(bigint, bigint, jsonb) from public;
revoke execute on function public.fn_org_task_promote(integer, integer) from public;
revoke execute on function public.fn_org_task_lane_knowledge(text) from public;
revoke execute on function public.fn_org_task_subject(text, text, text) from public;

commit;
