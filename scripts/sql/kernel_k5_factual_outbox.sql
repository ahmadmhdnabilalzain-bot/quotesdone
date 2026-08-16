-- ============================================================================================
-- KERNEL K5 — THE FACTUAL OUTBOX
--
-- APPLY ORDER: THIS FILE FIRST, THEN scripts/sql/kernel_k2_workflow_start.sql.
-- K2 emits through fn_kernel_outbox_emit and reads the delivery marker
-- fn_kernel_assert_not_in_delivery, both of which are created here.
--
-- WHAT THIS REPLACES, AND WHY
--
-- 1. THE SHAPE.  A `.started` row in phase_c_event_outbox is currently a COMMAND: the command
--    router emits it, fn_phase_c_outbox_deliver claims it, fn_phase_c_event_consume hands it to
--    fn_phase_c_event_ingress, and the ingress CREATES the workflow run and then EMITS THE SAME
--    EVENT ID AGAIN (outbox 250, 251 and 317 in production, all after the "fix"; the second
--    generation is only hidden because its dedupe_value differs, so the unique index never sees
--    it).  In the kernel a domain event is FACTUAL: it records a state change that has already
--    happened, and no consumer may make the change.  fn_kernel_event_consume therefore never
--    creates a workflow run; it acknowledges, projects and fans out.  The refusal is enforced at
--    runtime, not by convention: the consumer marks the transaction `kernel.in_delivery` and every
--    kernel writer raises 23514 if it is entered while that mark is set.
--
-- 2. THE IDENTITY COLUMNS.  correlation_id, causation_id, source_id, command_id, workflow_run_id
--    and step_run_id existed only as payload keys, on 1 to 8 of the 14 rows, under a key name
--    (`run_id`) that does not match the column name it stands for.  They become real columns.
--    trace_id and dedupe_value already exist and are REUSED, not duplicated.
--
--      correlation_id  stable for the whole causal chain      e.g. 'cmd:227', 'auto:lead:8891'
--      causation_id    the immediate cause, '<kind>:<id>'     e.g. 'command:227', 'outbox:317'
--      source_id       the record the work is about           e.g. 'founder_command:227'
--
--    causation_id names ANOTHER OUTBOX ROW only in the form 'outbox:<outbox_id>'.  That is what
--    makes self-emission checkable: an outbox row whose causation_id resolves to a row carrying
--    the same event_id is the defect above, and scripts/checks/kernel_invariants.test.mjs counts
--    exactly that, over the full table.
--
-- 3. THE FAILURE BRANCH THAT COULD NEVER COMPLETE.  Measured in an aborted transaction on
--    16 Aug 2026 (outbox 354, rolled back):
--
--      A=42804 COALESCE types text and timestamp with time zone cannot be matched
--      B=23502 null value in column "next_attempt_at" ... violates not-null constraint
--      C=NO_ERROR(control)
--
--    first_failure is `text NOT NULL default ''` and next_attempt_at is `timestamptz NOT NULL`, so
--    `first_failure = coalesce(first_failure, now())` cannot plan and `next_attempt_at = null`
--    cannot be written.  The branch is live, reachable, and always throws — inside the `for` loop
--    and outside any handler, so ONE failing row aborted the whole cron pass and stranded every
--    row it had already claimed.  retry_wait and dead_letter have never been written by anything
--    in the life of this database.  Retyping alone would not prove the fix, so the rehearsal
--    (kernel_k5_factual_outbox.REHEARSAL.md) FORCES both branches to execute and reads back the
--    row.  A branch you have not made execute is not implemented.
--
-- NOTHING IS DROPPED.  The 14 historical rows keep their payloads; first_failure's text content is
-- preserved into first_failure_reason before the retype; delivered and superseded rows are never
-- rewritten.  The UNIQUE (event_id, dedupe_value) index is the idempotency contract every emitter
-- depends on and it survives untouched.
-- ============================================================================================

-- ------------------------------------------------------------------ 1. the identity columns
-- All six nullable at the table level: the 14 existing rows cannot be given a correlation_id
-- without inventing one, and inventing one is how a fabricated audit trail starts.  The contract
-- is enforced where it is actually true — on rows the kernel produced (§2).
alter table public.phase_c_event_outbox
  add column if not exists correlation_id      text,
  add column if not exists causation_id        text,
  add column if not exists source_id           text,
  add column if not exists command_id          bigint,
  add column if not exists workflow_run_id     bigint,
  add column if not exists step_run_id         bigint,
  add column if not exists first_failure_reason text,
  add column if not exists last_sqlstate       text,
  add column if not exists max_attempts        integer not null default 5;

comment on column public.phase_c_event_outbox.correlation_id is
  'Stable across the whole causal chain. Set by the kernel on every row it produces.';
comment on column public.phase_c_event_outbox.causation_id is
  'The immediate cause as <kind>:<id>. When the cause is another event it is outbox:<outbox_id>.';
comment on column public.phase_c_event_outbox.source_id is
  'The record the work is about, e.g. founder_command:227. Not the producer.';
comment on column public.phase_c_event_outbox.first_failure_reason is
  'The text that first_failure carried while it was mistyped as text. Preserved, never dropped.';

-- Backfill ONLY where the payload is unambiguous. The payload key for the run is `run_id`, not
-- `workflow_run_id`; that mismatch is why nothing found these values before.
update public.phase_c_event_outbox
   set command_id      = coalesce(command_id,      nullif(payload->>'command_id','')::bigint),
       workflow_run_id = coalesce(workflow_run_id, nullif(payload->>'run_id','')::bigint),
       step_run_id     = coalesce(step_run_id,     nullif(payload->>'step_run_id','')::bigint)
 where (payload ? 'command_id' or payload ? 'run_id' or payload ? 'step_run_id')
   and (command_id is null or workflow_run_id is null or step_run_id is null);
-- correlation_id, causation_id and source_id are NOT backfilled. No existing row carries anything
-- that determines them, and a guess here would be indistinguishable from a measurement later.

-- ------------------------------------------------------------------ 2. the kernel identity contract
-- Scoped to rows the kernel produced. It CAN fire (a kernel emit missing an id) and it CAN NOT
-- fire (every row produced by fn_phase_c_outbox_emit, founder_command_submit or the 14 historical
-- rows), which is the difference between a constraint and a decoration.
do $ck$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.phase_c_event_outbox'::regclass
                    and conname  = 'phase_c_event_outbox_kernel_identity_ck') then
    alter table public.phase_c_event_outbox
      add constraint phase_c_event_outbox_kernel_identity_ck
      check (producer not like 'kernel:%'
             or (correlation_id is not null and causation_id is not null and source_id is not null));
  end if;
end $ck$;

-- ------------------------------------------------------------------ 3. the retype that unblocks the branch
-- Guarded on the live type so the file re-applies. `first_failure` is text on the way in and
-- timestamptz on the way out; running the USING clause twice would try to btrim a timestamp.
do $retype$
declare v_type text;
begin
  select data_type into v_type from information_schema.columns
   where table_schema='public' and table_name='phase_c_event_outbox' and column_name='first_failure';

  if v_type = 'text' then
    -- preserve the diagnosis before changing the type it was stored in
    update public.phase_c_event_outbox
       set first_failure_reason = first_failure
     where coalesce(btrim(first_failure),'') <> '' and first_failure_reason is null;

    alter table public.phase_c_event_outbox alter column first_failure drop default;
    alter table public.phase_c_event_outbox alter column first_failure drop not null;
    alter table public.phase_c_event_outbox
      alter column first_failure type timestamptz
      using (case when first_failure ~ '^\d{4}-\d{2}-\d{2}' then first_failure::timestamptz else null end);
    raise notice 'K5: phase_c_event_outbox.first_failure retyped text -> timestamptz (nullable)';
  else
    raise notice 'K5: phase_c_event_outbox.first_failure already %', v_type;
  end if;
end $retype$;

-- A dead-lettered row has no next attempt. Saying so required this column to accept the truth.
alter table public.phase_c_event_outbox alter column next_attempt_at drop not null;

-- The status vocabulary the deliver body actually writes. 'cancelled' is removed because nothing
-- has ever written it and nothing reads it — fn_kernel_cancel supersedes, it does not cancel an
-- event that already happened. Asserted before the swap so a row can never be orphaned by it.
do $st$
declare v_bad int;
begin
  select count(*) into v_bad from public.phase_c_event_outbox
   where status not in ('pending','claimed','delivered','retry_wait','dead_letter','superseded');
  if v_bad > 0 then
    raise exception 'K5: % outbox row(s) hold a status outside the kernel vocabulary; not narrowing the check', v_bad
      using errcode = '23514';
  end if;
  if exists (select 1 from pg_constraint
              where conrelid='public.phase_c_event_outbox'::regclass
                and conname='phase_c_event_outbox_status_ck') then
    alter table public.phase_c_event_outbox drop constraint phase_c_event_outbox_status_ck;
  end if;
  alter table public.phase_c_event_outbox
    add constraint phase_c_event_outbox_status_ck
    check (status in ('pending','claimed','delivered','retry_wait','dead_letter','superseded'));
end $st$;

-- ------------------------------------------------------------------ 4. the re-entry refusal
-- A consumer calling back into the service that produced its input is the defect this whole
-- increment removes. It is refused at runtime by a transaction-local mark, not by a comment.
create or replace function public.fn_kernel_in_delivery()
returns boolean language sql stable set search_path to 'public','pg_temp' as $q$
  select coalesce(nullif(current_setting('kernel.in_delivery', true), ''), '0') = '1';
$q$;

create or replace function public.fn_kernel_assert_not_in_delivery(p_writer text)
returns void language plpgsql stable set search_path to 'public','pg_temp' as $fn$
begin
  if public.fn_kernel_in_delivery() then
    raise exception
      're-entry refused: % is a kernel writer and was called from event delivery', p_writer
      using errcode = '23514',
            hint = 'A domain event records a state change that already happened. A consumer may '
                || 'notify, project or fan out; it may not call the producer.';
  end if;
end $fn$;

revoke all on function public.fn_kernel_in_delivery() from public;
revoke all on function public.fn_kernel_assert_not_in_delivery(text) from public;
grant execute on function public.fn_kernel_in_delivery() to service_role;
grant execute on function public.fn_kernel_assert_not_in_delivery(text) to service_role;

-- ------------------------------------------------------------------ 5. the factual emitter
-- fn_phase_c_outbox_emit stays where it is (fn_founder_command_submit and _clarify are live
-- callers). This is the writer for rows that carry the kernel identity contract.
create or replace function public.fn_kernel_outbox_emit(p_input jsonb)
returns bigint language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  e public.phase_b_event%rowtype;
  v_id bigint;
  v_event  text := nullif(btrim(coalesce(p_input->>'event_id','')), '');
  v_dedupe text := nullif(btrim(coalesce(p_input->>'dedupe_value','')), '');
  v_prod   text := coalesce(nullif(btrim(p_input->>'producer'),''), 'kernel:unnamed');
  v_corr   text := nullif(btrim(coalesce(p_input->>'correlation_id','')), '');
  v_caus   text := nullif(btrim(coalesce(p_input->>'causation_id','')), '');
  v_src    text := nullif(btrim(coalesce(p_input->>'source_id','')), '');
  v_consumer text;
begin
  select * into e from public.phase_b_event where event_id = v_event;
  if not found then
    raise exception 'fn_kernel_outbox_emit: % is not in the frozen Phase B event registry — fail closed',
      coalesce(v_event,'(null)') using errcode = '23503';
  end if;
  if v_dedupe is null then
    raise exception 'fn_kernel_outbox_emit: dedupe_value is required for %', v_event using errcode = '23502';
  end if;
  if v_corr is null or v_caus is null or v_src is null then
    raise exception 'fn_kernel_outbox_emit: % is missing identity (correlation_id=%, causation_id=%, source_id=%)',
      v_event, coalesce(v_corr,'(null)'), coalesce(v_caus,'(null)'), coalesce(v_src,'(null)')
      using errcode = '23514';
  end if;

  select role_id into v_consumer from public.fn_phase_c_resolve_actor(e.primary_consumer_role_id);
  v_consumer := coalesce(v_consumer, e.primary_consumer_role_id);

  insert into public.phase_c_event_outbox
    (event_id, workflow_id, object_version, producer, accountable_role_id, primary_consumer_role_id,
     payload, dedupe_value, status, correlation_id, causation_id, source_id,
     command_id, workflow_run_id, step_run_id, trace_id)
  values (e.event_id, e.workflow_id, coalesce((p_input->>'object_version')::bigint, 1),
          v_prod, v_consumer, coalesce(e.primary_consumer_role_id,''),
          coalesce(p_input->'payload', '{}'::jsonb), v_dedupe, 'pending',
          v_corr, v_caus, v_src,
          nullif(p_input->>'command_id','')::bigint,
          nullif(p_input->>'workflow_run_id','')::bigint,
          nullif(p_input->>'step_run_id','')::bigint,
          nullif(p_input->>'trace_id','')::bigint)
  on conflict (event_id, dedupe_value) do nothing
  returning outbox_id into v_id;

  -- A duplicate is not a new row and it is not an error: re-read the one that already exists.
  if v_id is null then
    select outbox_id into v_id from public.phase_c_event_outbox
     where event_id = e.event_id and dedupe_value = v_dedupe;
  end if;
  -- Error and empty must not return the same value.
  if v_id is null then
    raise exception 'fn_kernel_outbox_emit wrote no row and found none for %/%', v_event, v_dedupe
      using errcode = '23502';
  end if;
  return v_id;
end $fn$;

revoke all on function public.fn_kernel_outbox_emit(jsonb) from public;
grant execute on function public.fn_kernel_outbox_emit(jsonb) to service_role;

-- ------------------------------------------------------------------ 6. the consumer
-- It may notify, project a read model, or fan out to subscribers. It may NOT create a workflow
-- run. It sets kernel.in_delivery for its whole body, so any kernel writer reached from here —
-- directly or through six frames of plpgsql — raises 23514.
create or replace function public.fn_kernel_event_consume(p_outbox_id bigint)
returns table(handled boolean, downstream_ref text, result jsonb, reason text)
language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  o public.phase_c_event_outbox%rowtype;
  e public.phase_b_event%rowtype;
  v_next record; v_tasks bigint[] := '{}'; v_task bigint; v_owner text;
  v_run bigint; v_step text; v_prior text;
  v_handled boolean := false; v_ref text; v_result jsonb; v_reason text;
begin
  v_prior := coalesce(nullif(current_setting('kernel.in_delivery', true),''), '0');
  perform set_config('kernel.in_delivery', '1', true);

  select * into o from public.phase_c_event_outbox where outbox_id = p_outbox_id;
  if not found then
    v_reason := 'unknown_outbox_row';
  else
    select * into e from public.phase_b_event where event_id = o.event_id;
    if not found then
      v_reason := format('%s is not in the frozen Phase B event registry', o.event_id);

    -- A row naming a command must be for a workflow that command actually selected. Three
    -- pre-fix rows announcing EV-W01-STARTED for W20 commands put three marketing orders in
    -- front of the CEO before the quarantine reached them.
    elsif coalesce(o.command_id::text, o.payload->>'command_id') is not null
      and not exists (select 1 from public.founder_command_workflow_link l
                       where l.command_id = coalesce(o.command_id, (o.payload->>'command_id')::bigint)
                         and l.workflow_id = o.workflow_id) then
      v_reason := format('event %s names workflow %s but command %s selected a different workflow',
                         o.event_id, o.workflow_id, coalesce(o.command_id::text, o.payload->>'command_id'));

    elsif e.event_name like '%.started' then
      -- THE WHOLE POINT. workflow.started is a RECORD of a run that fn_kernel_workflow_start
      -- already created in its own transaction. There is nothing to create here.
      v_run := coalesce(o.workflow_run_id, nullif(o.payload->>'run_id','')::bigint);
      if v_run is null then
        v_reason := format('%s carries no workflow_run_id: it was produced as a command, not as a '
                        || 'record of a run. The kernel creates the run and then emits.', o.event_id);
      elsif not exists (select 1 from public.phase_c_workflow_run where run_id = v_run) then
        v_reason := format('%s names workflow run %s, which does not exist', o.event_id, v_run);
      else
        v_handled := true;
        v_ref     := 'run:' || v_run;
        v_result  := jsonb_build_object('projected','workflow_run', 'run_id', v_run,
                       'workflow_id', o.workflow_id, 'correlation_id', o.correlation_id,
                       'step_run_id', o.step_run_id, 'created_by', o.producer);
      end if;

    elsif e.event_name like '%.completed' and (o.step_run_id is not null or o.payload ? 'step_id') then
      v_run  := coalesce(o.workflow_run_id, nullif(o.payload->>'run_id','')::bigint);
      v_step := coalesce(o.payload->>'step_id',
                         (select step_id from public.phase_c_workflow_step_run
                           where step_run_id = o.step_run_id));
      if v_run is null or v_step is null then
        v_reason := format('completed event %s carries no run (%s) or no step (%s)',
                           o.event_id, coalesce(v_run::text,'null'), coalesce(v_step,'null'));
      else
        -- Fan out to the subscribers the frozen registry declares. This creates TASKS on an
        -- existing run; it does not create a run, and it never calls the producer.
        for v_next in
          select h.to_step_id, s.accountable_role_id, s.independent_reviewer_role_id
            from public.phase_b_handoff h
            join public.phase_b_workflow_step s on s.step_id = h.to_step_id
           where h.from_step_id = v_step
           order by h.to_step_id
        loop
          select role_id into v_owner from public.fn_phase_c_resolve_actor(v_next.accountable_role_id);
          continue when v_owner is null or not public.fn_phase_c_actor_may_own(v_owner);
          v_task := public.fn_phase_c_task_create(jsonb_build_object(
            'source_kind','workflow_event', 'source_ref', o.event_id || ':' || v_next.to_step_id,
            'command_id', o.command_id, 'run_id', v_run,
            'workflow_id', e.workflow_id, 'step_id', v_next.to_step_id,
            'accountable_role_id', v_owner,
            'objective', format('%s completed; %s is now yours for run %s.', v_step, v_next.to_step_id, v_run),
            'requested_output','The step output required by the frozen Phase B contract, with evidence.',
            'reviewer_required', (coalesce(v_next.independent_reviewer_role_id,'') <> ''),
            'reviewer_role_id', coalesce(v_next.independent_reviewer_role_id,''),
            'idempotency_key', 'run:' || v_run || ':step:' || v_next.to_step_id));
          v_tasks := v_tasks || v_task;
        end loop;
        v_handled := true;
        if cardinality(v_tasks) = 0 then
          -- 66 steps declare next_step_if_pass and carry no handoff edge. Saying "terminal" over
          -- one of those is how the chain stops silently, so the two cases are NAMED apart.
          v_ref := case when exists (select 1 from public.phase_b_workflow_step s
                                      where s.step_id = v_step and s.next_step_if_pass = 'WORKFLOW_COMPLETE')
                        then 'terminal_step:' || v_step
                        else 'no_edge_for_declared_successor:' || v_step end;
          v_result := jsonb_build_object('successors', 0, 'run_id', v_run,
                        'declared_successor', (select next_step_if_pass from public.phase_b_workflow_step
                                                where step_id = v_step));
        else
          v_ref := 'tasks:' || array_to_string(v_tasks, ',');
          v_result := jsonb_build_object('tasks', to_jsonb(v_tasks), 'run_id', v_run);
        end if;
      end if;

    else
      v_reason := format('no canonical consumer for %s (%s)', o.event_id, e.event_name);
    end if;
  end if;

  perform set_config('kernel.in_delivery', v_prior, true);
  return query select v_handled, v_ref, v_result, v_reason;
end $fn$;

revoke all on function public.fn_kernel_event_consume(bigint) from public;
grant execute on function public.fn_kernel_event_consume(bigint) to service_role;

-- ------------------------------------------------------------------ 7. the delivery worker
create or replace function public.fn_kernel_outbox_deliver(p_limit integer default 25,
                                                           p_worker text default null)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  c record; r record; v_attempt bigint; v_worker text;
  v_ok int := 0; v_retry int := 0; v_dead int := 0; v_claimed int := 0;
  v_err text; v_state text; v_retryable boolean;
begin
  v_worker := coalesce(nullif(btrim(p_worker),''), 'pid:' || pg_backend_pid()::text);

  -- Claim: FOR UPDATE SKIP LOCKED, one statement, attempts incremented at claim so a crash cannot
  -- lose the count. coalesce on next_attempt_at because the column is now nullable and a NULL
  -- there would silently make a row unclaimable forever. The 15-minute lease is the fix for the
  -- other half of the old defect: the raise aborted the pass and left every claimed row in
  -- 'claimed', which fn_phase_c_outbox_claim never looks at again.
  for c in
    update public.phase_c_event_outbox o set
      status = 'claimed', claimed_at = now(), attempts = o.attempts + 1
    where o.outbox_id in (
      select s.outbox_id from public.phase_c_event_outbox s
       where (s.status in ('pending','retry_wait') and coalesce(s.next_attempt_at, now()) <= now())
          or (s.status = 'claimed' and s.claimed_at < now() - interval '15 minutes')
       order by s.outbox_id
       for update skip locked
       limit greatest(1, coalesce(p_limit, 25)))
    returning o.*
  loop
    v_claimed := v_claimed + 1;

    -- BEFORE the consumer runs. This insert is outside the handler below on purpose: when the
    -- consumer raises, its subtransaction rolls back and this row is the only surviving evidence
    -- that the attempt happened at all.
    insert into public.phase_c_event_delivery_attempt
      (outbox_id, attempt_no, started_at, ok, worker_id)
    values (c.outbox_id, c.attempts, clock_timestamp(), false, v_worker)
    returning attempt_id into v_attempt;

    -- THE MARK GOES HERE, NOT ONLY IN THE CONSUMER. The first rehearsal of this file proved why:
    -- with the mark set only inside fn_kernel_event_consume, a consumer swapped for another body
    -- carried no mark, called fn_kernel_workflow_start, and CREATED A RUN FROM DELIVERY — status
    -- delivered, runs_created=1. Delivery is the thing that is delivery; whichever consumer runs
    -- inside it is inside it.
    perform set_config('kernel.in_delivery', '1', true);
    begin
      select * into r from public.fn_kernel_event_consume(c.outbox_id);
      if r is null or r.handled is null then
        v_err := 'consumer returned no verdict'; v_retryable := false;   -- null is not success
      elsif r.handled then
        v_err := null; v_retryable := null;
      else
        v_err := coalesce(r.reason, 'consumer declined without a reason'); v_retryable := false;
      end if;
    exception when others then
      v_err := SQLSTATE || ' ' || SQLERRM;
      -- Only infrastructure faults are worth trying again. A constraint violation or a bad payload
      -- fails identically forever, and retrying it hides it.
      v_retryable := SQLSTATE in ('40001','40P01','55P03','57014','53100','53200','53300',
                                  '08000','08003','08006');
      r := null;
    end;
    -- Reset outside the block so it happens on the exception path too. (A subtransaction abort
    -- would restore a GUC set inside the block, but not one set before it.)
    perform set_config('kernel.in_delivery', '0', true);

    if v_err is null then
      update public.phase_c_event_delivery_attempt set
        finished_at = clock_timestamp(), ok = true, downstream_ref = coalesce(r.downstream_ref,''),
        result_hash = encode(sha256(convert_to(coalesce(r.result::text,''), 'UTF8')), 'hex'),
        retryable = null
      where attempt_id = v_attempt;
      -- delivered is written in the success branch and nowhere else
      update public.phase_c_event_outbox set
        status = 'delivered', delivered_at = now(), last_error = '', next_attempt_at = null
      where outbox_id = c.outbox_id;
      v_ok := v_ok + 1;

    else
      v_state := case when v_retryable and c.attempts < c.max_attempts then 'retry_wait'
                      else 'dead_letter' end;
      update public.phase_c_event_delivery_attempt set
        finished_at = clock_timestamp(), ok = false, error = left(v_err, 500),
        result_hash = '', retryable = v_retryable
      where attempt_id = v_attempt;
      update public.phase_c_event_outbox set
        status = v_state,
        last_error = left(v_err, 500),
        last_sqlstate = left(coalesce(substring(v_err from '^[0-9A-Z]{5}'), ''), 5),
        -- the FIRST failure is the diagnosis; a retry must not overwrite it. Both sides are
        -- timestamptz now, and the column is nullable, so this coalesce can finally do its job.
        first_failure = coalesce(first_failure, now()),
        first_failure_reason = coalesce(first_failure_reason, left(v_err, 500)),
        next_attempt_at = case when v_state = 'retry_wait'
                               then now() + (interval '1 minute' * power(2, least(c.attempts, 6)))
                               else null end
      where outbox_id = c.outbox_id;
      if v_state = 'retry_wait' then v_retry := v_retry + 1; else v_dead := v_dead + 1; end if;
    end if;
  end loop;

  return jsonb_build_object('worker', v_worker, 'claimed', v_claimed, 'delivered', v_ok,
                            'retry_wait', v_retry, 'dead_letter', v_dead, 'at', now());
end $fn$;

revoke all on function public.fn_kernel_outbox_deliver(integer, text) from public;
grant execute on function public.fn_kernel_outbox_deliver(integer, text) to service_role;

-- ------------------------------------------------------------------ 8. the SLA helper K2 needs
-- The SLA target is prose ("1 minute", "4 business hours", "30 minutes when inputs are complete").
-- fn_phase_c_handoff_open parses it inline; K2 needs the same grammar and a second copy of a
-- parser is how two sibling paths end up with two different lexicons. One function, both callers.
create or replace function public.fn_kernel_sla_due(p_sla_policy_id text, p_from timestamptz default now())
returns timestamptz language sql stable set search_path to 'public','pg_temp' as $q$
  select p_from + make_interval(mins => greatest(1, round(coalesce((
    select case
             when m[2] ilike 'minute%' then m[1]::numeric / 60.0
             when m[2] ilike 'day%'    then m[1]::numeric * 24.0
             when m[2] ilike 'week%'   then m[1]::numeric * 168.0
             else m[1]::numeric
           end
      from public.phase_b_sla_policy sp,
           lateral regexp_match(sp.target,
             '(\d+)\s*(?:business\s+|calendar\s+)?(minute|hour|day|week)') m
     where sp.sla_policy_id = p_sla_policy_id), 24) * 60))::int);
$q$;

revoke all on function public.fn_kernel_sla_due(text, timestamptz) from public;
grant execute on function public.fn_kernel_sla_due(text, timestamptz) to service_role;
