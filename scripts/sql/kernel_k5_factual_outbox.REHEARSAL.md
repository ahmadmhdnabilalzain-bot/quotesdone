# K5 — the factual outbox: aborted-transaction rehearsal

Everything below runs in ONE transaction that ends in `raise exception`, so production is untouched.
Verified after the run reported here: `fn_kernel_*` routines live = 0, `phase_c_event_outbox` rows = 14,
`causation_id` column exists = 0. Nothing was committed.

```
begin;
\i scripts/sql/kernel_k5_factual_outbox.sql
-- then the probe block below
rollback;   -- the raise aborts it first
```

The same thing without psql (this is how the output below was produced) — a single POST of
`begin; <file>; <probe>; rollback;` to `/v1/projects/htdblwldjkcgjvmqkbeh/database/query`.

K5 stands alone: none of these probes needs K2. The combined K5 → K2 rehearsal, which proves that
delivering a `workflow.started` row creates nothing, is in `kernel_k2_workflow_start.REHEARSAL.md`.

## Probe block

```sql
do $probe$
declare
  s text := ''; v jsonb; r record; ob bigint; v_evt text; v_cnt text;
begin
  -- 1. the retype, and the columns that were payload keys
  select string_agg(column_name || '=' || data_type || '/' ||
           case when is_nullable='YES' then 'null' else 'NOTNULL' end, ' ' order by column_name)
    into v_cnt from information_schema.columns
   where table_schema='public' and table_name='phase_c_event_outbox'
     and column_name in ('first_failure','first_failure_reason','next_attempt_at','last_sqlstate',
                         'max_attempts','correlation_id','causation_id','source_id','command_id',
                         'workflow_run_id','step_run_id');
  s := s || 'K5.1 SCHEMA ' || v_cnt || ' | ';

  select count(*) filter (where workflow_run_id is not null)::text || '/' || count(*)::text ||
         ' cmd=' || count(*) filter (where command_id is not null)::text || '/' || count(*)::text ||
         ' step_run=' || count(*) filter (where step_run_id is not null)::text || '/' || count(*)::text ||
         ' corr=' || count(*) filter (where correlation_id is not null)::text || '/' || count(*)::text
    into v_cnt from public.phase_c_event_outbox;
  s := s || 'K5.2 BACKFILL run=' || v_cnt || ' | ';

  -- 2. the marker, directly
  perform set_config('kernel.in_delivery','1', true);
  begin
    perform public.fn_kernel_assert_not_in_delivery('probe_writer');
    s := s || 'K5.3 MARKER_NOT_ENFORCED=BAD | ';
  exception when others then s := s || 'K5.3 marker_refuses=' || sqlstate || ' | '; end;
  perform set_config('kernel.in_delivery','0', true);
  begin
    perform public.fn_kernel_assert_not_in_delivery('probe_writer');
    s := s || 'K5.4 marker_allows_outside_delivery=ok | ';
  exception when others then s := s || 'K5.4 MARKER_ALWAYS_FIRES=BAD | '; end;

  -- 3. a terminal failure, with the REAL consumer
  select event_id into v_evt from public.phase_b_event
   where event_name not like '%.started' and event_name not like '%.completed'
   order by event_id limit 1;
  ob := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_evt, 'producer','kernel:probe', 'dedupe_value','probe:terminal:'||clock_timestamp()::text,
    'correlation_id','probe','causation_id','probe','source_id','probe',
    'payload', jsonb_build_object('probe', true)));
  v := public.fn_kernel_outbox_deliver(5,'rehearsal');
  select o.status as st, (o.first_failure is not null) as ff, o.next_attempt_at as na,
         o.attempts as at, left(o.last_error,45) as le
    into r from public.phase_c_event_outbox o where o.outbox_id = ob;
  s := s || format('K5.5 TERMINAL_REAL status=%s first_failure_set=%s next_attempt=%s attempts=%s err=%s | ',
        r.st, r.ff, coalesce(r.na::text,'NULL'), r.at, r.le);
  select a.ok as ok, a.retryable as rt into r
    from public.phase_c_event_delivery_attempt a where a.outbox_id = ob order by a.attempt_id desc limit 1;
  s := s || format('K5.5 ATTEMPT ok=%s retryable=%s | ', r.ok, r.rt);

  -- 4. the claim lease: a row stranded in 'claimed' is picked up again
  ob := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_evt, 'producer','kernel:probe', 'dedupe_value','probe:lease:'||clock_timestamp()::text,
    'correlation_id','probe','causation_id','probe','source_id','probe',
    'payload', jsonb_build_object('probe', true)));
  update public.phase_c_event_outbox
     set status='claimed', claimed_at = now() - interval '30 minutes' where outbox_id = ob;
  v := public.fn_kernel_outbox_deliver(5,'rehearsal');
  select o.status as st into r from public.phase_c_event_outbox o where o.outbox_id = ob;
  s := s || format('K5.6 LEASE stranded_now=%s claimed_this_pass=%s | ', r.st, v->>'claimed');

  -- 5. a RETRYABLE failure, forced. The branch under test is the deliver's, so the consumer is
  --    stubbed to raise a serialization failure; it is rolled back with everything else.
  execute $ddl$
    create or replace function public.fn_kernel_event_consume(p_outbox_id bigint)
    returns table(handled boolean, downstream_ref text, result jsonb, reason text)
    language plpgsql security definer set search_path to 'public','pg_temp' as $stub$
    begin raise exception 'forced serialization failure' using errcode = '40001'; end $stub$;
  $ddl$;
  ob := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_evt, 'producer','kernel:probe', 'dedupe_value','probe:retry:'||clock_timestamp()::text,
    'correlation_id','probe','causation_id','probe','source_id','probe',
    'payload', jsonb_build_object('probe', true)));
  perform public.fn_kernel_outbox_deliver(5,'rehearsal');
  select o.status as st, (o.first_failure is not null) as ff, (o.next_attempt_at > now()) as fut,
         o.attempts as at, o.last_sqlstate as ss, left(o.first_failure_reason,35) as fr
    into r from public.phase_c_event_outbox o where o.outbox_id = ob;
  s := s || format('K5.7 RETRY status=%s first_failure_set=%s backoff_in_future=%s attempts=%s sqlstate=%s reason=%s | ',
        r.st, r.ff, r.fut, r.at, r.ss, r.fr);

  -- 6. the same failure at max_attempts is terminal, and the first diagnosis is not overwritten
  update public.phase_c_event_outbox
     set status='pending', attempts = max_attempts, next_attempt_at = now() where outbox_id = ob;
  perform public.fn_kernel_outbox_deliver(5,'rehearsal');
  select o.status as st, o.attempts as at, o.next_attempt_at as na,
         (o.first_failure is not null) as ff into r
    from public.phase_c_event_outbox o where o.outbox_id = ob;
  s := s || format('K5.8 AT_MAX status=%s attempts=%s next_attempt=%s first_failure_preserved=%s | ',
        r.st, r.at, coalesce(r.na::text,'NULL'), r.ff);

  -- 7. any code reached from delivery is inside delivery, whatever the consumer body is
  execute $ddl$
    create or replace function public.fn_kernel_event_consume(p_outbox_id bigint)
    returns table(handled boolean, downstream_ref text, result jsonb, reason text)
    language plpgsql security definer set search_path to 'public','pg_temp' as $stub$
    begin
      perform public.fn_kernel_assert_not_in_delivery('pretend_kernel_writer');
      return query select true, 'x'::text, '{}'::jsonb, null::text;
    end $stub$;
  $ddl$;
  ob := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_evt, 'producer','kernel:probe', 'dedupe_value','probe:mark:'||clock_timestamp()::text,
    'correlation_id','probe','causation_id','probe','source_id','probe',
    'payload', jsonb_build_object('probe', true)));
  perform public.fn_kernel_outbox_deliver(5,'rehearsal');
  select o.status as st, o.last_sqlstate as ss, left(o.last_error,55) as le into r
    from public.phase_c_event_outbox o where o.outbox_id = ob;
  s := s || format('K5.9 MARK_REACHES_CONSUMER status=%s sqlstate=%s err=%s | ', r.st, r.ss, r.le);

  -- 8. the kernel identity contract
  begin
    insert into public.phase_c_event_outbox
      (event_id, workflow_id, producer, accountable_role_id, dedupe_value, payload)
    select e.event_id, e.workflow_id, 'kernel:no_identity', 'ceo',
           'probe:ck:'||clock_timestamp()::text, '{}'::jsonb
      from public.phase_b_event e where e.event_id = v_evt;
    s := s || 'K5.10 IDENTITY_CK_NOT_ENFORCED=BAD | ';
  exception when others then s := s || 'K5.10 identity_ck=' || sqlstate || ' | '; end;
  begin
    insert into public.phase_c_event_outbox
      (event_id, workflow_id, producer, accountable_role_id, dedupe_value, payload)
    select e.event_id, e.workflow_id, 'system.command_router', 'ceo',
           'probe:ck2:'||clock_timestamp()::text, '{}'::jsonb
      from public.phase_b_event e where e.event_id = v_evt;
    s := s || 'K5.11 non_kernel_row_still_allowed=ok';
  exception when others then s := s || 'K5.11 NON_KERNEL_ROW_BLOCKED=BAD ' || sqlstate; end;

  raise exception 'KERNEL K5 REHEARSAL :: %', s;
end $probe$;
```

## Every probe, and its required answer

| Probe | Asserts | Required answer | Measured 17 Aug 2026 |
|---|---|---|---|
| K5.1 SCHEMA | the retype landed and the six identity columns exist | `first_failure=timestamp with time zone/null`, `next_attempt_at=.../null`, all six identity columns present | exactly that, plus `first_failure_reason`, `last_sqlstate`, `max_attempts=integer/NOTNULL` |
| K5.2 BACKFILL | payload keys became columns where unambiguous, and were NOT guessed where not | `run=8/14 cmd=6/14 step_run=1/14`, `corr=0/14` | `run=8/14 cmd=6/14 step_run=1/14 corr=0/14` — matches the measured payload-key coverage exactly |
| K5.3 marker refuses | a kernel writer entered from delivery raises | `23514` | `23514` |
| K5.4 marker allows | the same writer OUTSIDE delivery is not refused — the guard can not-fire | `ok` | `ok` |
| K5.5 TERMINAL_REAL | a real consumer verdict of `handled=false` reaches **dead_letter**, and the failure fields are written | `status=dead_letter`, `first_failure_set=t`, `next_attempt=NULL`, `attempts=1` | all four; `err=no canonical consumer for EV-W01-BLOCKED` |
| K5.5 ATTEMPT | the attempt row records the failure | `ok=f retryable=f` | `ok=f retryable=f` |
| K5.6 LEASE | a row stranded in `claimed` by a dead pass is claimed again | `claimed_this_pass=1` and the row leaves `claimed` | `stranded_now=dead_letter claimed_this_pass=1` |
| K5.7 RETRY | an infrastructure SQLSTATE reaches **retry_wait** with exponential backoff | `status=retry_wait`, `backoff_in_future=t`, `sqlstate=40001` | all three, `attempts=1`, `first_failure_set=t` |
| K5.8 AT_MAX | the same retryable failure at `max_attempts` becomes terminal, and the FIRST diagnosis survives | `status=dead_letter`, `next_attempt=NULL`, `first_failure_preserved=t` | `dead_letter`, `attempts=6`, `NULL`, `t` |
| K5.9 MARK_REACHES_CONSUMER | the mark is set by DELIVERY, so it covers any consumer body | `status=dead_letter sqlstate=23514` | `dead_letter`, `23514`, `re-entry refused: pretend_kernel_writer is a kernel writer…` |
| K5.10 identity_ck | a `kernel:%` row without correlation/causation/source is refused | `23514` | `23514` |
| K5.11 non-kernel row | the same constraint does NOT block the existing emitters | `ok` | `ok` |

## The two lines the old body could never execute

Before this file, both of these raised — measured in an aborted transaction on 16 Aug (outbox 354,
rolled back): `A=42804 COALESCE types text and timestamp with time zone cannot be matched`,
`B=23502 null value in column "next_attempt_at"`. After it, K5.5 / K5.7 / K5.8 execute them and
read the row back. `retry_wait` and `dead_letter` had never been written by anything in the life of
this database; they are written three times in this rehearsal.

## One thing K5.9 caught that the first draft got wrong

The first version of this file set `kernel.in_delivery` only inside `fn_kernel_event_consume`. The
combined K2 rehearsal then swapped the consumer for one that calls `fn_kernel_workflow_start`, and
it **succeeded**: `status=delivered runs_created=1`. A mark that only the well-behaved consumer sets
is not a guard. `fn_kernel_outbox_deliver` now sets it around the consumer call — delivery is the
thing that is delivery — and the same probe returns `dead_letter / 23514 / runs_created=0`.
