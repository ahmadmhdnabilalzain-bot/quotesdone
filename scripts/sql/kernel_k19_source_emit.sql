-- K19 — one wrapper, so cutting a source over is one line and cannot be done wrongly.
--
-- §3 of the brief permits it in as many words: every NEW_WORK_REQUEST source "must call
-- fn_kernel_trigger_submit or one canonical wrapper around it". This is that wrapper, and it also
-- covers the signal door, because a source should not have to know which of the two it is — the
-- register already knows.
--
--   perform public.fn_kernel_source_emit('dbtrigger:public.inquiries:trg_inquiry_received_a',
--     jsonb_build_object('source_ref', NEW.id::text, 'raw_payload', to_jsonb(NEW)));
--
-- That is the whole cutover for one source. The wrapper reads phase_c_source_cutover and does the
-- rest: which class the source is, which adapter that class is allowed to call, which trigger type
-- or signal type it maps to, and which system actor executes it. A caller cannot pick the wrong
-- adapter because a caller does not pick one.
--
-- FOUR THINGS IT REFUSES, all by class, none by guesswork:
--   * a source_key that is not in the register — an unregistered source has no route, and routing
--     it on a guess is how one arrival lands on two workflows
--   * a class-C source: a monitor may not create business work. When a threshold is crossed it
--     must raise a separate class-A request under its OWN source key, with its own dedupe key and
--     its own evidence, which is a different call and looks like one
--   * a class-D source: retired means retired
--   * a class-B source with no workflow_run_id — the signal door refuses it too, and this refuses
--     it earlier with a message that says which run it needed
--
-- WHY IT DOES NOT LET A KERNEL FAULT BLOCK A CUSTOMER.
--
-- These calls sit inside triggers on inquiries, quotes and transactions. If the kernel raised and
-- the exception propagated, a customer's inquiry would fail to insert because a workflow could not
-- start. That is worse than the workflow not starting.
--
-- But swallowing it is worse still, and this estate has already paid for that shape once: a catch
-- that returns nothing makes "the kernel refused" and "nothing ever happened" the same event, and
-- the workflow silently never starts. So the wrapper catches, and writes the failure to
-- kernel_adapter_failure with the source, the payload, SQLSTATE and the message —
-- and fn_kernel_source_emit_state counts those rows and FAILS while any is unresolved. A fault
-- here is loud and countable; it is just not fatal to the customer.
--
-- Ordinary refusals do not come through that path at all. fn_kernel_trigger_submit and
-- fn_kernel_signal_submit already record a refusal as a row with a reason and return it. Only an
-- unexpected raise reaches the catch.
--
-- Rollback: scripts/sql/rollback/kernel_k19_source_emit.rollback.sql

begin;

create table if not exists public.kernel_adapter_failure (
  failure_id   bigserial primary key,
  at           timestamptz not null default now(),
  source_key   text not null,
  input        jsonb not null,
  sqlstate     text not null,
  message      text not null,
  call_stack   text,
  resolved_at  timestamptz,
  resolution   text,
  constraint kernel_adapter_failure_resolution_has_a_reason
    check (resolved_at is null or coalesce(btrim(resolution),'') <> '')
);

comment on table public.kernel_adapter_failure is
  'K19. Every time the kernel raised unexpectedly while a source was handing work to it. The '
  'exception is caught so a kernel fault cannot stop a customer inserting an inquiry, and it is '
  'RECORDED so the catch is not a silence: fn_kernel_source_emit_state fails while any row here '
  'is unresolved. A caught error that leaves no row makes "refused" and "never happened" the same '
  'event.';

alter table public.kernel_adapter_failure enable row level security;
revoke all on public.kernel_adapter_failure from public, anon, authenticated;
grant select on public.kernel_adapter_failure to service_role;

create or replace function public.fn_kernel_source_emit(p_source_key text, p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k19_emit$
declare
  v_class   text;
  v_vocab   text;
  v_wf      text;
  v_actor   text;
  v_active  text;
  v_ref     text := nullif(btrim(coalesce(p_input->>'source_ref','')), '');
  v_run     bigint := nullif(p_input->>'workflow_run_id','')::bigint;
  v_out     jsonb;
  v_ctx     text;
begin
  select c.source_class, c.target_step_or_signal, c.target_workflow, c.system_actor,
         c.current_activation
    into v_class, v_vocab, v_wf, v_actor, v_active
    from public.phase_c_source_cutover c where c.source_component_id = p_source_key;

  if v_class is null then
    raise exception 'fn_kernel_source_emit: % is not in the source cutover register', p_source_key
      using errcode = '23503',
            hint = 'Every autonomous source is classified in public.phase_c_source_cutover. A '
                || 'source with no row has no route, and routing it on a guess is how one arrival '
                || 'lands on two workflows. Classify it in scripts/phase_c/source_classification.mjs '
                || 'and regenerate.';
  end if;

  if v_class = 'C READ_ONLY_MONITOR' then
    raise exception 'fn_kernel_source_emit: % is a READ_ONLY_MONITOR and may not create business work',
      p_source_key using errcode = '42501',
        hint = 'A monitor collects status and may update approved operational state. When a '
            || 'threshold is crossed it raises a SEPARATE class-A request under its own source '
            || 'key, with its own dedupe key and its own evidence — a different call, which looks '
            || 'like one.';
  end if;

  if v_class = 'D RETIRE_OR_HISTORICAL' then
    raise exception 'fn_kernel_source_emit: % is retired', p_source_key
      using errcode = '42501',
            hint = 'Retired means retired. If this source must live again it needs a row saying so, '
                || 'not a call.';
  end if;

  if v_ref is null then
    raise exception 'fn_kernel_source_emit: % supplied no source_ref', p_source_key
      using errcode = '22023',
            hint = 'source_ref is the external identity of the thing this is about — the inquiry '
                || 'id, the quote id, the transaction id. The idempotency key is built from it, '
                || 'and a key that is different every time is not a key.';
  end if;

  begin
    if v_class = 'A NEW_WORK_REQUEST' then
      v_out := public.fn_kernel_trigger_submit(jsonb_build_object(
        'source_class',    (select source_class from public.kernel_trigger_type
                             where trigger_type = v_vocab),
        'source_system',   p_source_key,
        'source_ref',      v_ref,
        'external_ref',    p_input->>'external_ref',
        'trigger_type',    v_vocab,
        'raw_payload',     coalesce(p_input->'raw_payload', '{}'::jsonb),
        'requested_by',    coalesce(nullif(btrim(p_input->>'requested_by'),''), v_actor),
        'object_version',  p_input->>'object_version',
        'priority',        p_input->>'priority',
        'idempotency_key', p_input->>'idempotency_key',
        'correlation_id',  p_input->>'correlation_id',
        'causation_id',    p_input->>'causation_id'));
    else
      if v_run is null then
        raise exception 'fn_kernel_source_emit: % is an EXISTING_WORKFLOW_SIGNAL and named no workflow_run_id',
          p_source_key using errcode = '22023',
            hint = 'A signal attaches to a run that already exists. If there is no run yet, this '
                || 'is new work and belongs to a class-A source, not to this one.';
      end if;
      v_out := public.fn_kernel_signal_submit(jsonb_build_object(
        'source_type',     p_source_key,
        'source_id',       v_ref,
        'workflow_run_id', v_run,
        'signal_type',     v_vocab,
        'payload',         coalesce(p_input->'raw_payload', '{}'::jsonb),
        'requested_by',    coalesce(nullif(btrim(p_input->>'requested_by'),''), v_actor),
        'idempotency_key', p_input->>'idempotency_key',
        'correlation_id',  p_input->>'correlation_id',
        'causation_id',    p_input->>'causation_id'));
    end if;
  exception
    -- Deliberately narrow: the four raises above are the wrapper's own contract violations and
    -- must reach the developer, not be filed as a runtime fault. Everything else is a kernel
    -- fault, and a kernel fault must not stop a customer inserting an inquiry.
    when sqlstate '23503' or sqlstate '42501' or sqlstate '22023' then
      raise;
    when others then
      get diagnostics v_ctx = pg_context;
      insert into public.kernel_adapter_failure (source_key, input, sqlstate, message, call_stack)
      values (p_source_key, p_input, sqlstate, sqlerrm, v_ctx);
      return jsonb_build_object('ok', false, 'recorded_failure', true, 'source_key', p_source_key,
        'sqlstate', sqlstate, 'error', sqlerrm,
        'note', 'the kernel raised; the business row was not blocked and the fault is recorded in '
             || 'kernel_adapter_failure, where fn_kernel_source_emit_state fails while it is unresolved');
  end;

  return coalesce(v_out, '{}'::jsonb) || jsonb_build_object('source_key', p_source_key,
    'source_class', v_class, 'vocabulary', v_vocab, 'activation', v_active);
end
$k19_emit$;

revoke all on function public.fn_kernel_source_emit(text, jsonb) from public, anon, authenticated;
grant execute on function public.fn_kernel_source_emit(text, jsonb) to service_role;

comment on function public.fn_kernel_source_emit(text, jsonb) is
  'K19. The one canonical wrapper a cut-over source calls. It reads phase_c_source_cutover for the '
  'source''s class and picks the adapter from it, so a caller cannot choose the wrong door — a '
  'caller does not choose. It refuses an unregistered source, a read-only monitor, a retired '
  'source and a signal with no run. A kernel fault is caught so it cannot block the customer''s '
  'row, and RECORDED in kernel_adapter_failure so the catch is not a silence.';

create or replace function public.fn_kernel_source_emit_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $k19_state$
with f as (select * from public.kernel_adapter_failure)
select 'unresolved_adapter_failures'::text,
       '0 of ' || (select count(*)::text from f),
       (select count(*)::text from f where resolved_at is null)
         || ' of ' || (select count(*)::text from f)
         || coalesce(' [' || (select string_agg(distinct source_key || ' ' || sqlstate, ', ')
              from f where resolved_at is null) || ']', ''),
       (select count(*) = 0 from f where resolved_at is null)
union all
select 'sources_cut_over_to_the_wrapper',
       'reported; it rises as each increment lands',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '\yfn_kernel_source_emit\s*\(')
         || ' database routines call fn_kernel_source_emit',
       true
union all
-- The wrapper must not become a second way to reach the creator. It may call the two adapters and
-- nothing else; the check reads the DEPLOYED body with comments stripped, because the body
-- discusses fn_kernel_workflow_start in prose.
select 'wrapper_reaching_past_its_two_adapters',
       '0 — the body may name only fn_kernel_trigger_submit and fn_kernel_signal_submit',
       (select case when src ~ '\yfn_kernel_(workflow_start|open_step|step_complete|cancel|outbox_emit)\s*\('
                    then 'IT REACHES PAST THEM' else '0' end
          from (select regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g') src
                  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'fn_kernel_source_emit') b),
       (select src !~ '\yfn_kernel_(workflow_start|open_step|step_complete|cancel|outbox_emit)\s*\('
          from (select regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g') src
                  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'fn_kernel_source_emit') b);
$k19_state$;

revoke all on function public.fn_kernel_source_emit_state() from public, anon, authenticated;
grant execute on function public.fn_kernel_source_emit_state() to service_role;

commit;
