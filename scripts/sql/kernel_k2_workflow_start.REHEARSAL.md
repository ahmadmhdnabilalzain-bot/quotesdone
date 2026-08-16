# K2 — fn_kernel_workflow_start: aborted-transaction rehearsal

Both migrations, in order, in ONE transaction that ends in `raise exception`. Production is
untouched: verified after the run below with
`select count(*) from pg_proc where proname like 'fn_kernel_%'` → the six new routines are absent,
`phase_c_event_outbox` = 14 rows, `phase_c_workflow_run` = 8, `phase_c_task` = 32,
`information_schema.columns … causation_id` = 0, `founder_command_plan_item` = 0 tables.

```
begin;
\i scripts/sql/kernel_k5_factual_outbox.sql     -- K5 FIRST: K2 emits through it
\i scripts/sql/kernel_k2_workflow_start.sql
-- then probe block A below
rollback;   -- the raise aborts it first
```

and, for the founder half:

```
begin;
\i scripts/sql/kernel_k5_factual_outbox.sql
\i scripts/sql/kernel_k2_workflow_start.sql
\i scripts/sql/kernel_k2b_founder_submit_calls_kernel.sql
-- then probe block B below
rollback;
```

## Probe block A — the kernel creator, and delivery that creates nothing

```sql
do $probe$
declare
  s text := '';
  v jsonb; v2 jsonb; v3 jsonb;
  ob bigint; ob2 bigint; ob3 bigint; ob4 bigint;
  n int; m int;
  v_run bigint; v_run2 bigint; v_step bigint; v_task bigint; v_ho bigint;
  v_evt text; v_cnt text; v_dept text;
  v_obj  text := 'ZZ-KERNEL-REHEARSAL-A';
  v_obj2 text := 'ZZ-KERNEL-REHEARSAL-B';
  v_runs_before int; v_tasks_before int; v_ob_before int;
  r record;
  v_inv text := $inv$
    select (select count(*) filter (where c.outbox_id is not null)::text || '/' || count(*)::text
              from public.phase_c_event_outbox o
              left join public.phase_c_event_outbox c
                on o.causation_id = 'outbox:' || c.outbox_id::text and c.event_id = o.event_id) as i1,
           (select count(*) filter (where x.has_cmd and x.has_run)::text || '/' || count(*)::text from (
              select fc.command_id,
                exists (select 1 from public.phase_c_task t
                         where t.command_id = fc.command_id and t.idempotency_key like 'cmd:%') as has_cmd,
                exists (select 1 from public.phase_c_task t
                         left join public.phase_c_workflow_run rr on rr.run_id = t.run_id
                         where coalesce(t.command_id, rr.command_id) = fc.command_id
                           and t.idempotency_key like 'run:%:step:%') as has_run
              from public.founder_command fc) x) as i2,
           (select count(*) filter (where sr.trace_id is null
                      and sr.state not in ('completed','failed','cancelled','skipped','superseded'))::text
                   || '/' || count(*)::text from public.phase_c_workflow_step_run sr) as i3,
           (select count(*) filter (where tr.sealed_at is null and (
                      (tr.task_id is not null and exists (select 1 from public.phase_c_task t
                         where t.task_id = tr.task_id and t.state in ('completed','failed','cancelled','superseded')))
                   or (tr.task_id is null and tr.run_id is not null and exists (select 1 from public.phase_c_workflow_run rr
                         where rr.run_id = tr.run_id and rr.state in ('completed','cancelled','superseded')))))::text
                   || '/' || count(*)::text from public.phase_c_trace tr) as i4,
           (select count(*) filter (where tr.subject_kind = 'task' and tr.task_id is null)::text
                   || '/' || count(*)::text from public.phase_c_trace tr) as i5
  $inv$;
begin
  select count(*) into v_runs_before  from public.phase_c_workflow_run;
  select count(*) into v_tasks_before from public.phase_c_task;
  select count(*) into v_ob_before    from public.phase_c_event_outbox;
  s := format('BASE runs=%s tasks=%s outbox=%s | ', v_runs_before, v_tasks_before, v_ob_before);
  execute v_inv into r;
  s := s || format('INV_BEFORE self_emit=%s dup_cmd=%s steprun_no_trace=%s terminal_open=%s orphan_task_trace=%s | ',
        r.i1, r.i2, r.i3, r.i4, r.i5);

  -- K5 · 1. schema
  select string_agg(column_name || '=' || data_type || '/' ||
           case when is_nullable='YES' then 'null' else 'NOTNULL' end, ' ' order by column_name)
    into v_cnt
    from information_schema.columns
   where table_schema='public' and table_name='phase_c_event_outbox'
     and column_name in ('first_failure','first_failure_reason','next_attempt_at','last_sqlstate',
                         'max_attempts','correlation_id','causation_id','source_id','command_id',
                         'workflow_run_id','step_run_id');
  s := s || 'K5.1 SCHEMA ' || v_cnt || ' | ';

  select count(*) filter (where workflow_run_id is not null)::text || '/' || count(*)::text
    into v_cnt from public.phase_c_event_outbox;
  s := s || 'K5.2 BACKFILL run=' || v_cnt;
  select count(*) filter (where command_id is not null)::text || '/' || count(*)::text
    into v_cnt from public.phase_c_event_outbox;
  s := s || ' cmd=' || v_cnt;
  select count(*) filter (where correlation_id is not null)::text || '/' || count(*)::text
    into v_cnt from public.phase_c_event_outbox;
  s := s || ' corr=' || v_cnt || '(not guessed) | ';

  -- K2 · 3. the create
  v := public.fn_kernel_workflow_start(jsonb_build_object(
        'workflow_id','W03', 'business_object_id', v_obj,
        'source_kind','autonomous', 'source_ref','autonomous:probe:W03',
        'requested_by','kernel:k2:rehearsal',
        'trigger_ctx', jsonb_build_object('reason','aborted-transaction rehearsal')));
  v_run := (v->>'run_id')::bigint; v_step := (v->>'step_run_id')::bigint;
  v_task := (v->>'task_id')::bigint; v_ho := (v->>'handoff_run_id')::bigint;
  ob := (v->>'outbox_id')::bigint;
  s := s || format('K2.3 CREATE ok=%s dup=%s run=%s state=%s step_run=%s task=%s handoff=%s outbox=%s event=%s owner=%s step_owner=%s | ',
        v->>'ok', v->>'duplicate', v_run, v->>'state', v_step, v_task, v_ho, ob,
        v->>'event_id', v->>'accountable_role_id', v->>'step_accountable_role_id');

  select (select count(*) from public.phase_c_workflow_step_run where run_id = v_run) as step_runs,
         (select count(*) from public.phase_c_task              where run_id = v_run) as tasks,
         (select count(*) from public.phase_c_event_outbox      where workflow_run_id = v_run) as events,
         (select count(*) from public.phase_c_handoff_run       where run_id = v_run) as handoffs,
         (select state from public.phase_c_workflow_run where run_id = v_run) as run_state
    into r;
  s := s || format('K2.3 COUNTS step_runs=%s tasks=%s events=%s handoffs=%s run_state=%s | ',
        r.step_runs, r.tasks, r.events, r.handoffs, r.run_state);

  select h.status as st, (h.due_at is not null) as due_set,
         (h.accountable_until_accept_role_id = h.sending_role_id) as retains,
         h.sending_role_id as snd, h.receiving_role_id as rcv
    into r from public.phase_c_handoff_run h where h.handoff_run_id = v_ho;
  s := s || format('K2.3 HANDOFF status=%s due_set=%s sender_retains=%s %s->%s | ',
        r.st, r.due_set, r.retains, r.snd, r.rcv);

  select (select status from public.phase_c_trace where trace_id = (v->>'run_trace_id')::bigint) as run_st,
         (select parent_trace_id from public.phase_c_trace where trace_id = (v->>'task_trace_id')::bigint) as task_parent,
         (select parent_trace_id from public.phase_c_trace where trace_id = (v->>'step_trace_id')::bigint) as step_parent,
         (select parent_trace_id from public.phase_c_trace where trace_id = (v->>'handoff_trace_id')::bigint) as ho_parent,
         (select task_id from public.phase_c_trace where trace_id = (v->>'task_trace_id')::bigint) as task_subj,
         (select trace_id from public.phase_c_workflow_step_run where step_run_id = v_step) as sr_trace
    into r;
  s := s || format('K2.4 TRACES root=%s(%s) step_parent=%s task_parent=%s handoff_parent=%s step_run.trace_id=%s task_trace.task_id=%s | ',
        v->>'run_trace_id', r.run_st, r.step_parent, r.task_parent, r.ho_parent, r.sr_trace, r.task_subj);

  select o.correlation_id as c1, o.causation_id as c2, o.source_id as c3,
         o.workflow_run_id as c4, o.step_run_id as c5, o.producer as c6, o.status as c7,
         o.dedupe_value as c8
    into r from public.phase_c_event_outbox o where o.outbox_id = ob;
  s := s || format('K2.5 EVENT corr=%s caus=%s src=%s run=%s step_run=%s producer=%s status=%s dedupe=%s | ',
        r.c1, r.c2, r.c3, r.c4, r.c5, r.c6, r.c7, r.c8);

  -- K2 · 6. idempotency
  v2 := public.fn_kernel_workflow_start(jsonb_build_object(
        'workflow_id','W03', 'business_object_id', v_obj,
        'source_kind','autonomous', 'source_ref','autonomous:probe:W03',
        'requested_by','kernel:k2:rehearsal'));
  select (select count(*) from public.phase_c_task where run_id = v_run) as t,
         (select count(*) from public.phase_c_event_outbox where workflow_run_id = v_run) as e,
         (select count(*) from public.phase_c_workflow_step_run where run_id = v_run) as sr
    into r;
  s := s || format('K2.6 SECOND_CALL dup=%s same_run=%s tasks=%s events=%s step_runs=%s | ',
        v2->>'duplicate', ((v2->>'run_id')::bigint = v_run), r.t, r.e, r.sr);

  -- K2 · 7. an entry step for which the registry declares no handoff
  v3 := public.fn_kernel_workflow_start(jsonb_build_object(
        'workflow_id','W04', 'business_object_id', v_obj2,
        'source_kind','autonomous', 'source_ref','autonomous:probe:W04',
        'requested_by','kernel:k2:rehearsal'));
  v_run2 := (v3->>'run_id')::bigint;
  s := s || format('K2.7 NO_HANDOFF ok=%s handoff=%s traces=%s step=%s | ',
        v3->>'ok', coalesce((v3->>'handoff_run_id'),'null'), v3->'created'->>'traces', v3->>'step_id');

  -- K2 · 8. refusals
  begin
    v := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W99',
      'business_object_id','x','source_kind','autonomous','source_ref','x','requested_by','x'));
    s := s || 'K2.8a UNKNOWN_WF_ACCEPTED=BAD | ';
  exception when others then s := s || 'K2.8a unknown_wf=' || sqlstate || ' | '; end;
  begin
    v := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W03',
      'business_object_id','x','source_kind','magic','source_ref','x','requested_by','x'));
    s := s || 'K2.8b BAD_SOURCE_ACCEPTED=BAD | ';
  exception when others then s := s || 'K2.8b bad_source_kind=' || sqlstate || ' | '; end;
  begin
    v := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W03',
      'business_object_id','x','source_kind','founder_command','source_ref','x','requested_by','x'));
    s := s || 'K2.8c CMD_NO_ID_ACCEPTED=BAD | ';
  exception when others then s := s || 'K2.8c founder_cmd_no_id=' || sqlstate || ' | '; end;

  -- K5 · 9. re-entry refusal, directly
  perform set_config('kernel.in_delivery','1', true);
  begin
    v := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W11',
      'business_object_id','ZZ-REENTRY','source_kind','autonomous','source_ref','x','requested_by','x'));
    s := s || 'K5.9 REENTRY_ACCEPTED=BAD | ';
  exception when others then s := s || 'K5.9 reentry_refused=' || sqlstate || ' | '; end;
  perform set_config('kernel.in_delivery','0', true);

  -- K5 · 10. delivering .started creates NOTHING
  select count(*) into v_runs_before  from public.phase_c_workflow_run;
  select count(*) into v_tasks_before from public.phase_c_task;
  select count(*) into v_ob_before    from public.phase_c_event_outbox;
  v := public.fn_kernel_outbox_deliver(50, 'rehearsal');
  select (select count(*) from public.phase_c_workflow_run)  - v_runs_before  as dr,
         (select count(*) from public.phase_c_task)          - v_tasks_before as dt,
         (select count(*) from public.phase_c_event_outbox)  - v_ob_before    as de,
         (select status from public.phase_c_event_outbox where outbox_id = ob) as st
    into r;
  s := s || format('K5.10 DELIVER %s runs_delta=%s tasks_delta=%s outbox_delta=%s started_status=%s | ',
        v::text, r.dr, r.dt, r.de, r.st);

  -- K5 · 11. terminal failure, REAL consumer
  select event_id into v_evt from public.phase_b_event
   where event_name not like '%.started' and event_name not like '%.completed'
   order by event_id limit 1;
  ob2 := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_evt, 'producer','kernel:probe', 'dedupe_value','probe:terminal:'||clock_timestamp()::text,
    'correlation_id','probe','causation_id','probe','source_id','probe',
    'payload', jsonb_build_object('probe', true)));
  perform public.fn_kernel_outbox_deliver(5, 'rehearsal');
  select o.status as st, (o.first_failure is not null) as ff, o.next_attempt_at as na,
         o.attempts as at, o.last_sqlstate as ss, left(o.last_error,55) as le
    into r from public.phase_c_event_outbox o where o.outbox_id = ob2;
  s := s || format('K5.11 TERMINAL status=%s first_failure_set=%s next_attempt=%s attempts=%s err=%s | ',
        r.st, r.ff, coalesce(r.na::text,'NULL'), r.at, r.le);
  select a.ok as ok, a.retryable as rt, left(a.error,30) as er
    into r from public.phase_c_event_delivery_attempt a where a.outbox_id = ob2 order by a.attempt_id desc limit 1;
  s := s || format('K5.11 ATTEMPT ok=%s retryable=%s | ', r.ok, r.rt);

  -- K5 · 12. the claim lease
  ob3 := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_evt, 'producer','kernel:probe', 'dedupe_value','probe:lease:'||clock_timestamp()::text,
    'correlation_id','probe','causation_id','probe','source_id','probe',
    'payload', jsonb_build_object('probe', true)));
  update public.phase_c_event_outbox
     set status='claimed', claimed_at = now() - interval '30 minutes' where outbox_id = ob3;
  v := public.fn_kernel_outbox_deliver(5,'rehearsal');
  select o.status as st into r from public.phase_c_event_outbox o where o.outbox_id = ob3;
  s := s || format('K5.12 LEASE stranded_claimed_now=%s claimed_this_pass=%s | ', r.st, v->>'claimed');

  -- K5 · 13. retryable failure, FORCED (the deliver's branch is under test, so the consumer is stubbed)
  execute $ddl$
    create or replace function public.fn_kernel_event_consume(p_outbox_id bigint)
    returns table(handled boolean, downstream_ref text, result jsonb, reason text)
    language plpgsql security definer set search_path to 'public','pg_temp' as $stub$
    begin
      raise exception 'forced serialization failure' using errcode = '40001';
    end $stub$;
  $ddl$;
  ob4 := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_evt, 'producer','kernel:probe', 'dedupe_value','probe:retry:'||clock_timestamp()::text,
    'correlation_id','probe','causation_id','probe','source_id','probe',
    'payload', jsonb_build_object('probe', true)));
  perform public.fn_kernel_outbox_deliver(5,'rehearsal');
  select o.status as st, (o.first_failure is not null) as ff, (o.next_attempt_at > now()) as fut,
         o.attempts as at, o.last_sqlstate as ss, left(o.first_failure_reason,35) as fr
    into r from public.phase_c_event_outbox o where o.outbox_id = ob4;
  s := s || format('K5.13 RETRY status=%s first_failure_set=%s backoff_in_future=%s attempts=%s sqlstate=%s reason=%s | ',
        r.st, r.ff, r.fut, r.at, r.ss, r.fr);

  update public.phase_c_event_outbox
     set status='pending', attempts = max_attempts, next_attempt_at = now() where outbox_id = ob4;
  perform public.fn_kernel_outbox_deliver(5,'rehearsal');
  select o.status as st, o.next_attempt_at as na, o.attempts as at
    into r from public.phase_c_event_outbox o where o.outbox_id = ob4;
  s := s || format('K5.13b AT_MAX status=%s attempts=%s next_attempt=%s | ',
        r.st, r.at, coalesce(r.na::text,'NULL'));

  -- K5 · 14. re-entry THROUGH delivery: a consumer that calls the producer
  execute $ddl$
    create or replace function public.fn_kernel_event_consume(p_outbox_id bigint)
    returns table(handled boolean, downstream_ref text, result jsonb, reason text)
    language plpgsql security definer set search_path to 'public','pg_temp' as $stub$
    declare x jsonb;
    begin
      x := public.fn_kernel_workflow_start(jsonb_build_object(
        'workflow_id','W11','business_object_id','ZZ-FROM-DELIVERY','source_kind','autonomous',
        'source_ref','consumer','requested_by','consumer'));
      return query select true, 'x'::text, x, null::text;
    end $stub$;
  $ddl$;
  ob4 := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_evt, 'producer','kernel:probe', 'dedupe_value','probe:reentry:'||clock_timestamp()::text,
    'correlation_id','probe','causation_id','probe','source_id','probe',
    'payload', jsonb_build_object('probe', true)));
  perform public.fn_kernel_outbox_deliver(5,'rehearsal');
  select o.status as st, o.last_sqlstate as ss, left(o.last_error,60) as le,
         (select count(*) from public.phase_c_workflow_run where business_object_id='ZZ-FROM-DELIVERY') as made
    into r from public.phase_c_event_outbox o where o.outbox_id = ob4;
  s := s || format('K5.14 REENTRY_VIA_DELIVERY status=%s sqlstate=%s runs_created=%s err=%s | ',
        r.st, r.ss, r.made, r.le);

  -- K5 · 15. the kernel identity contract
  begin
    insert into public.phase_c_event_outbox
      (event_id, workflow_id, producer, accountable_role_id, dedupe_value, payload)
    select e.event_id, e.workflow_id, 'kernel:no_identity', 'ceo',
           'probe:ck:'||clock_timestamp()::text, '{}'::jsonb
      from public.phase_b_event e where e.event_id = v_evt;
    s := s || 'K5.15 IDENTITY_CK_NOT_ENFORCED=BAD | ';
  exception when others then s := s || 'K5.15 identity_ck=' || sqlstate || ' | '; end;

  -- 16. the invariants, after
  execute v_inv into r;
  s := s || format('INV_AFTER self_emit=%s dup_cmd=%s steprun_no_trace=%s terminal_open=%s orphan_task_trace=%s | ',
        r.i1, r.i2, r.i3, r.i4, r.i5);

  -- K2 · 17. the owner must resolve CANONICAL, and is never defaulted.
  -- Forced without touching a frozen table: fn_phase_c_resolve_actor checks phase_c_system_actor
  -- BEFORE org_role, so registering W11's accountable role as a system actor makes it resolve to
  -- kind='system_actor'. org_role itself carries z90_phase_a_freeze and cannot be edited at all.
  select primary_department_id into v_dept from public.org_role where role_id = 'supplier_coverage';
  insert into public.phase_c_system_actor
    (system_actor_id, description, accountable_role_id, department_id, allowed_actions,
     forbidden_actions, trace_policy_id)
  values ('supplier_coverage','rehearsal probe','supplier_coverage', coalesce(v_dept,'exec'),
          'none','all','TRACE-SYSTEM-EXECUTION');
  begin
    v := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W11',
      'business_object_id','ZZ-NONCANONICAL','source_kind','autonomous',
      'source_ref','x','requested_by','x'));
    s := s || 'K2.17 NONCANONICAL_OWNER_ACCEPTED=BAD | ';
  exception when others then s := s || 'K2.17 noncanonical_owner=' || sqlstate || ' | '; end;
  select count(*) into n from public.phase_c_workflow_run where business_object_id = 'ZZ-NONCANONICAL';
  s := s || format('K2.17 runs_created=%s', n);

  raise exception 'KERNEL K5+K2 REHEARSAL :: %', s;
end $probe$;
```

## Probe block B — the founder command adapter (K2b)

```sql
do $probe$
declare
  s text := ''; v jsonb; r record; n int; v_cmd bigint; v_id text;
begin
  select identity into v_id from public.phase_c_founder_identity where active order by identity limit 1;

  v := public.fn_founder_command_submit(
        v_id,
        'Increase marketing output: publish two case studies this month and report the measured effect.',
        'probe-k2b-' || clock_timestamp()::text,
        jsonb_build_object('channel','rehearsal'));
  v_cmd := (v->>'command_id')::bigint;
  s := s || format('K2b.1 SUBMIT ok=%s status=%s cmd=%s tasks_created=%s plan_items=%s run=%s step_run=%s outbox=%s event=%s | ',
        v->>'ok', v->>'status', v_cmd, v->>'tasks_created', v->>'plan_items',
        v->>'workflow_run_id', v->>'step_run_id', v->>'outbox_id', v->>'event_id');

  select (select count(*) from public.phase_c_task t where t.command_id = v_cmd) as tasks,
         (select count(*) from public.phase_c_task t where t.command_id = v_cmd
            and t.idempotency_key like 'cmd:%') as cmd_tasks,
         (select count(*) from public.phase_c_task t where t.command_id = v_cmd
            and t.idempotency_key like 'run:%:step:%') as run_tasks,
         (select count(*) from public.founder_command_plan_item i where i.command_id = v_cmd) as items,
         (select count(*) from public.phase_c_event_outbox o where o.command_id = v_cmd) as events,
         (select string_agg(t.accountable_role_id || '/' || t.idempotency_key, ' ')
            from public.phase_c_task t where t.command_id = v_cmd) as who
    into r;
  s := s || format('K2b.2 EFFECT tasks=%s cmd_shaped=%s run_shaped=%s plan_items=%s events=%s who=%s | ',
        r.tasks, r.cmd_tasks, r.run_tasks, r.items, r.events, r.who);

  select count(*) into n from public.phase_c_task t
   left join public.phase_c_workflow_run rr on rr.run_id = t.run_id
   where coalesce(t.command_id, rr.command_id) = v_cmd and t.command_id is null;
  s := s || format('K2b.3 INVISIBLE_TASKS=%s | ', n);

  select count(*) into n from public.phase_c_task;
  v := public.fn_kernel_outbox_deliver(50,'rehearsal');
  s := s || format('K2b.4 DELIVER %s tasks_delta=%s | ',
        v::text, (select count(*) from public.phase_c_task) - n);

  raise exception 'KERNEL K2b REHEARSAL :: %', s;
end $probe$;
```

## Every probe, and its required answer

| Probe | Asserts | Required answer | Measured 17 Aug 2026 |
|---|---|---|---|
| K2.3 CREATE | one call produces a run, a step run, a task, a handoff and an event, atomically | `ok=true dup=false`, all five ids non-null, `state=active` | `run=151 step_run=90 task=973 handoff=78 outbox=377 event=EV-W03-STARTED` |
| K2.3 CREATE owner | the accountable role comes from the registry, resolved | `owner=chief_revenue_officer` (phase_b_workflow.accountable_role_id for W03), never `chief_of_staff` | `owner=chief_revenue_officer step_owner=chief_revenue_officer` |
| K2.3 COUNTS | **exactly one** of each | `step_runs=1 tasks=1 events=1 handoffs=1 run_state=active` | exactly that |
| K2.3 HANDOFF | opened only where the registry declares it, sender retains accountability, SLA dated | `status=open due_set=t sender_retains=t` | `open / t / t`, `chief_revenue_officer->marketing_performance_analyst` (H-W03-01-02) |
| K2.4 TRACES | root trace open; step, task and handoff traces all parented to it; the task trace names its task | `step_parent = task_parent = handoff_parent = run_trace_id`, `step_run.trace_id` non-null, `task_trace.task_id = task_id` | root `1018(open)`, all three parents `1018`, `step_run.trace_id=1019`, `task_trace.task_id=973` |
| K2.5 EVENT | the factual row carries the identity K5 added | `corr`/`caus`/`src` set, `run` and `step_run` set, `producer=kernel:workflow_start` | all set; `dedupe=kernel:started:W03:ZZ-KERNEL-REHEARSAL-A:1` |
| K2.6 SECOND_CALL | idempotent on (workflow, object, version): the same run, and NOTHING new | `dup=true same_run=t tasks=1 events=1 step_runs=1` | exactly that |
| K2.7 NO_HANDOFF | 14 of 30 entry steps declare no handoff; none is invented for them | `ok=true handoff=null traces=3` | `ok=true handoff=null traces=3 step=W04-S01` |
| K2.8a | unknown workflow | `23503`, no run | `23503` |
| K2.8b | source_kind outside {founder_command, autonomous} | `22023` | `22023` |
| K2.8c | founder_command without a command_id | `22023` | `22023` |
| K5.9 | a kernel writer entered from delivery | `23514` | `23514` |
| **K5.10 DELIVER** | **the headline: consuming `workflow.started` creates nothing** | `runs_delta=0 tasks_delta=0 outbox_delta=0`, `started_status=delivered` | `claimed=2 delivered=2`, all three deltas `0`, `delivered` |
| K5.11 TERMINAL | a declined verdict reaches dead_letter with its failure fields written | `dead_letter`, `first_failure_set=t`, `next_attempt=NULL` | exactly that, `attempts=1`, `ok=f retryable=f` |
| K5.12 LEASE | a row stranded in `claimed` is claimed again | `claimed_this_pass=1`, row leaves `claimed` | `stranded_claimed_now=dead_letter claimed_this_pass=1` |
| K5.13 RETRY | an infrastructure SQLSTATE reaches retry_wait with backoff | `retry_wait`, `backoff_in_future=t`, `sqlstate=40001` | exactly that |
| K5.13b AT_MAX | the same failure at max_attempts is terminal | `dead_letter`, `next_attempt=NULL` | `dead_letter attempts=6 NULL` |
| **K5.14** | **a consumer that calls the producer is refused at runtime** | `dead_letter`, `sqlstate=23514`, `runs_created=0` | exactly that |
| K5.15 | a `kernel:%` row with no correlation/causation/source | `23514` | `23514` |
| K2.17 | the workflow owner must resolve CANONICAL; it is never defaulted | `23514`, `runs_created=0` | `23514`, `0` |
| K2b.1 SUBMIT | the founder path produces ONE operational task | `tasks_created=1`, `plan_items` > 0, a run and an event | `status=tasks_created tasks_created=1 plan_items=4 run=150 outbox=370 event=EV-W20-STARTED` |
| K2b.2 EFFECT | the four `cmd:N:*` tasks are gone; the plan is recorded instead | `cmd_shaped=0 run_shaped=1 events=1` | `tasks=1 cmd_shaped=0 run_shaped=1 plan_items=4 events=1`, `marketing_director/run:150:step:W20-S01` |
| K2b.3 | no task derived from the command is invisible to it | `INVISIBLE_TASKS=0` | `0` |
| K2b.4 | delivering the command's own event creates no fifth task | `tasks_delta=0` | `claimed=1 delivered=1 tasks_delta=0` |

## The invariants, before and after, inside the same transaction

```
INV_BEFORE self_emit=0/14 dup_cmd=6/8 steprun_no_trace=3/8  terminal_open=4/72 orphan_task_trace=10/72
INV_AFTER  self_emit=0/20 dup_cmd=6/8 steprun_no_trace=3/10 terminal_open=4/79 orphan_task_trace=10/79
```

Read the deltas, not the levels. K2 added 2 step runs and 0 to the `steprun_no_trace` numerator;
7 traces and 0 to `terminal_open` and `orphan_task_trace`; 6 outbox rows and 0 to `self_emit`.
`dup_cmd=6/8` does not move here because probe block A creates no founder command — block B is
where it moves, and the new command is `0/1` while the six pre-existing ones stay red until their
duplicate tasks are reconciled. Those three standing reds (`dup_cmd`, `steprun_no_trace`,
`terminal_open`, `orphan_task_trace`) are pre-existing production debt, not something K2 or K5
introduce; `scripts/checks/kernel_invariants.test.mjs` reports every one of them with its
denominator over the full table and exits 1.

## One defect this rehearsal found in its own migration

The first draft set `kernel.in_delivery` only inside `fn_kernel_event_consume`. K5.14 swapped the
consumer for one that calls `fn_kernel_workflow_start` and it **succeeded** —
`status=delivered runs_created=1`. A mark only the well-behaved consumer sets is not a guard.
`fn_kernel_outbox_deliver` now sets it around the consumer call. The same probe now returns
`dead_letter / 23514 / runs_created=0`.

The second: K2 created step runs with `trace_id` NULL, because `phase_c_workflow_step_run` is the
one runtime table with no trace-guard trigger. `steprun_no_trace` went 3/8 → 5/10. K2 now writes a
`TRACE-STEP` parented to the run's root, and the numerator stays at 3.
