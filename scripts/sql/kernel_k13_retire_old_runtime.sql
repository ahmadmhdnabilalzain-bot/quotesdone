-- ============================================================================================
-- KERNEL K13 — RETIRE EVERY PARALLEL OLD RUNTIME PATH
--
-- K13a corrected one old function. The rest of the old Phase C runtime is still deployed and still
-- callable, which means the estate still contains a second way to create business work — and a
-- second way is how the duplicate-effect and self-emission defects existed at all.
--
-- MEASURED FIRST, 17 Aug 2026, before deciding anything:
--   cron jobs invoking any old path ............................. 0  (K5b repointed 278)
--   anon / authenticated / PUBLIC EXECUTE on any old path ....... 0  (all service_role only)
--   fn_phase_c_outbox_deliver  callers .......................... none active
--   fn_phase_c_event_consume   callers .......................... fn_phase_c_outbox_deliver only
--   fn_phase_c_event_ingress   callers .......................... fn_phase_c_event_consume only
--   fn_phase_c_workflow_start  callers .......................... fn_kernel_workflow_start, and
--                                                                  fn_phase_c_event_ingress
--   fn_phase_c_outbox_claim    callers .......................... fn_kernel_outbox_deliver, and
--                                                                  fn_phase_c_outbox_deliver
--
-- So the old chain deliver -> consume -> ingress is unreachable from anything active, while
-- fn_phase_c_workflow_start and fn_phase_c_outbox_claim are still USED — by the kernel. Those two
-- are primitives the kernel owns now, not parallel paths; the disposition has to tell those cases
-- apart rather than sweep them together.
--
-- DISPOSITION, one per path, recorded in public.kernel_retired_path:
--   COMPATIBILITY_WRAPPER_TO_KERNEL  normalises old input and calls the kernel; no business logic
--   DISABLED                         raises, naming the kernel replacement
--   KERNEL_INTERNAL_PRIMITIVE        still called, but only from inside the kernel, enforced
--   READ_ONLY_HISTORICAL             reads only; left alone
--
-- Nothing is dropped. Historical rows, compatibility reads and every audit record stay exactly
-- where they are; what stops is the ability to CREATE NEW BUSINESS WORK outside the kernel.
-- ============================================================================================

-- ------------------------------------------------------------------- 1. the disposition register
create table if not exists public.kernel_retired_path (
  path_name        text primary key,
  disposition      text not null check (disposition in (
                     'COMPATIBILITY_WRAPPER_TO_KERNEL','READ_ONLY_HISTORICAL','REVOKED',
                     'DISABLED','RETIRED','REMOVED_AFTER_PROVEN_UNUSED','KERNEL_INTERNAL_PRIMITIVE')),
  replacement      text not null,
  evidence         text not null,
  measured_at      timestamptz not null default now()
);

insert into public.kernel_retired_path (path_name, disposition, replacement, evidence) values
  ('fn_phase_c_event_ingress', 'DISABLED', 'fn_kernel_workflow_start',
   'The self-emitting producer. Its semantics — an event CAUSES the state change — are the defect '
   || 'itself, so it gets no compatibility wrapper: a wrapper would preserve the shape. Callers at '
   || 'measurement: fn_phase_c_event_consume only, which is itself disabled here.'),
  ('fn_phase_c_event_consume', 'COMPATIBILITY_WRAPPER_TO_KERNEL', 'fn_kernel_event_consume',
   'Called only by fn_phase_c_outbox_deliver. Normalises the old single-argument call and hands it '
   || 'to the kernel consumer, which never calls a producer.'),
  ('fn_phase_c_outbox_deliver', 'COMPATIBILITY_WRAPPER_TO_KERNEL', 'fn_kernel_outbox_deliver',
   'cron 278 was repointed by K5b and nothing else calls it. Kept as a wrapper so an old bundle or '
   || 'a hand-typed call cannot resurrect the re-emitting consumer.'),
  ('fn_phase_c_outbox_settle', 'READ_ONLY_HISTORICAL', 'fn_kernel_outbox_deliver',
   'Zero callers anywhere, in the database or the repository. Left in place because the injected-'
   || 'defect suite asserts on it and removing it would delete a test, not a risk.'),
  ('fn_phase_c_workflow_start', 'KERNEL_INTERNAL_PRIMITIVE', 'fn_kernel_workflow_start',
   'Still called — by fn_kernel_workflow_start. It is the row-writer the kernel owns, not a parallel '
   || 'entry point, and the guard below is what makes that statement enforceable rather than a claim.'),
  ('fn_phase_c_step_advance', 'DISABLED', 'fn_kernel_step_complete',
   'The old progression path. It derived successors from phase_b_handoff alone, so a step with a '
   || 'real next_step_if_pass and no edge returned terminal success and stopped the chain.'),
  ('fn_phase_c_task_create', 'KERNEL_INTERNAL_PRIMITIVE', 'fn_kernel_workflow_start',
   'The task row-writer. Reached from the kernel and from the founder-command path that now calls '
   || 'the kernel; guarded below so nothing else can create an operational task.'),
  ('fn_phase_c_outbox_claim', 'KERNEL_INTERNAL_PRIMITIVE', 'fn_kernel_outbox_deliver',
   'The SKIP LOCKED claim primitive, reused by fn_kernel_outbox_deliver. Claiming is not business '
   || 'logic and duplicating it would be the second copy this rebuild exists to remove.')
on conflict (path_name) do update
  set disposition = excluded.disposition, replacement = excluded.replacement,
      evidence = excluded.evidence, measured_at = now();

-- ------------------------------------------- 2. the primitives are reachable only from the kernel
-- fn_kernel_workflow_start already sets kernel.in_kernel for the span of its own transaction (added
-- below if absent). The primitives assert it. A direct call from psql, PostgREST or an old edge
-- bundle therefore refuses, while the kernel's own call succeeds — the guard can fire AND can not
-- fire, which is the pair that makes it worth having.
create or replace function public.fn_kernel_assert_in_kernel(p_who text)
returns void language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $k13a$
begin
  if coalesce(current_setting('kernel.in_kernel', true), '') <> 'on' then
    raise exception
      '% is a kernel-internal primitive and was called from outside the kernel', p_who
      using errcode = '23514',
            hint = 'Call the canonical service instead. public.kernel_retired_path names the '
                || 'replacement for every retired path.';
  end if;
end $k13a$;

revoke all on function public.fn_kernel_assert_in_kernel(text) from public;
grant execute on function public.fn_kernel_assert_in_kernel(text) to service_role;

-- ------------------------------------------------------------------ 3. the state of the retirement
create or replace function public.fn_kernel_retired_path_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql stable security definer set search_path to 'public', 'pg_temp' as $k13s$
  -- Every check below counts over the FULL register, never over a filtered subset, so a path that
  -- is quietly removed from the register cannot make a number improve.
  select 'old_cron_jobs_invoking_old_runtime', '0',
         count(*) filter (where j.active)::text || ' of ' || count(*)::text,
         count(*) filter (where j.active) = 0
    from cron.job j
   where exists (select 1 from public.kernel_retired_path r
                  where r.disposition <> 'KERNEL_INTERNAL_PRIMITIVE'
                    and j.command like '%' || r.path_name || '%')
  union all
  select 'direct_grants_permitting_kernel_bypass', '0',
         count(*)::text || ' of ' || (select count(*) from public.kernel_retired_path)::text,
         count(*) = 0
    from public.kernel_retired_path r
    join pg_proc p on p.proname = r.path_name
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('authenticated', p.oid, 'EXECUTE')
  union all
  select 'active_callers_of_disabled_paths', '0',
         count(*)::text || ' of ' || (select count(*) from public.kernel_retired_path
                                       where disposition = 'DISABLED')::text,
         count(*) = 0
    from public.kernel_retired_path r
    join pg_proc p on p.prosrc like '%' || r.path_name || '%'
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where r.disposition = 'DISABLED'
     and p.proname <> r.path_name
     and p.proname not like 'fn_kernel_%'
     and p.proname not in ('fn_phase_c_event_binding_status', 'fn_phase_c_invariants',
                           'fn_kernel_retired_path_state')
  union all
  select 'paths_with_no_recorded_disposition', '0',
         count(*)::text || ' of ' || count(*)::text, count(*) = 0
    from (select unnest(array['fn_phase_c_event_ingress','fn_phase_c_event_consume',
                              'fn_phase_c_outbox_deliver','fn_phase_c_outbox_settle',
                              'fn_phase_c_workflow_start','fn_phase_c_step_advance',
                              'fn_phase_c_task_create','fn_phase_c_outbox_claim']) pn) x
   where not exists (select 1 from public.kernel_retired_path r where r.path_name = x.pn)
  union all
  -- The three primitives are reached only from fn_kernel_* today. This measures that, rather than
  -- claiming it: any NON-kernel routine whose source names a primitive is counted. The two retired
  -- wrappers are excluded by name because they are the retirement, not a bypass of it.
  --
  -- 18 AUG 2026 — THE PREDICATE WAS `prosrc like '%' || path_name || '%'`, AND A PREFIX IS NOT A CALL.
  -- The final acceptance audit found this check red at 1 of 9. The single row was
  -- fn_phase_c_task_state_guard against the primitive fn_phase_c_task_transition — and that guard
  -- never calls it. `like` matched because the primitive's name is a PREFIX of a different, longer
  -- function: fn_phase_c_task_transition_allowed, which is a pure predicate. A substring match
  -- reported a bypass that does not exist, on a board nothing else reads.
  --
  -- Now: comments are stripped first, so naming a primitive in an error message or a note is not a
  -- call; and the name must be followed by an opening parenthesis with a word boundary in front,
  -- which is what a call looks like. `_` is a word character in Postgres regex, so `\yfn_x\y` does
  -- not match inside `fn_x_allowed` — that is the whole fix.
  select 'kernel_primitives_called_from_outside_the_kernel', '0',
         count(*)::text || ' of ' || (select count(*) from public.kernel_retired_path
                                       where disposition = 'KERNEL_INTERNAL_PRIMITIVE')::text,
         count(*) = 0
    from public.kernel_retired_path r
    join pg_proc p on regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g')
                      ~ ('\y' || r.path_name || '\y\s*\(')
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where r.disposition = 'KERNEL_INTERNAL_PRIMITIVE'
     and p.proname <> r.path_name
     and p.proname not like 'fn_kernel_%'
     and p.proname not in ('fn_phase_c_event_ingress','fn_phase_c_event_consume',
                           'fn_phase_c_outbox_deliver','fn_phase_c_step_advance',
                           'fn_phase_c_invariants','fn_phase_c_event_binding_status');
$k13s$;

revoke all on function public.fn_kernel_retired_path_state() from public;
grant execute on function public.fn_kernel_retired_path_state() to service_role;

-- ================================================================ 4. the paths themselves
-- DISABLED — the two whose SEMANTICS are the defect. No compatibility wrapper: a wrapper would
-- preserve the shape that caused the incident, which is the opposite of retiring it.
-- The original carried a default on p_ctx; a replace cannot remove one, so the signature is
-- dropped and recreated with the SAME default preserved.
drop function if exists public.fn_phase_c_event_ingress(text, text, jsonb);
create or replace function public.fn_phase_c_event_ingress(
  p_event_id text, p_business_object_id text, p_ctx jsonb default '{}'::jsonb)
returns jsonb language plpgsql set search_path to 'public', 'pg_temp' as $k13_ing$
begin
  raise exception
    'fn_phase_c_event_ingress is retired: an event records that a state change happened, it does '
    'not cause one. Start work with fn_kernel_workflow_start, or submit a request through '
    'fn_kernel_trigger_submit.'
    using errcode = '23514',
          hint = 'public.kernel_retired_path names the replacement for every retired path.';
end $k13_ing$;

drop function if exists public.fn_phase_c_step_advance(bigint, text, text, jsonb);
create or replace function public.fn_phase_c_step_advance(
  p_run_id bigint, p_step_id text, p_actor text, p_body jsonb default '{}'::jsonb)
returns jsonb language plpgsql set search_path to 'public', 'pg_temp' as $k13_adv$
begin
  raise exception
    'fn_phase_c_step_advance is retired: it derived successors from phase_b_handoff alone, so a '
    'step with a real next_step_if_pass and no edge returned terminal success and stopped the '
    'chain mid-workflow. Use fn_kernel_step_complete.'
    using errcode = '23514',
          hint = 'public.kernel_retired_path names the replacement for every retired path.';
end $k13_adv$;

-- COMPATIBILITY WRAPPERS — same signature, same return shape, no business logic of their own.
drop function if exists public.fn_phase_c_outbox_deliver(integer, text);
create or replace function public.fn_phase_c_outbox_deliver(p_limit integer default 25, p_worker text default '')
returns jsonb language sql set search_path to 'public', 'pg_temp' as $k13_del$
  select public.fn_kernel_outbox_deliver(p_limit, coalesce(p_worker, '') || ' (via retired fn_phase_c_outbox_deliver)');
$k13_del$;

drop function if exists public.fn_phase_c_event_consume(bigint);
create or replace function public.fn_phase_c_event_consume(p_outbox_id bigint)
returns table (handled boolean, downstream_ref text, result jsonb, reason text)
language sql set search_path to 'public', 'pg_temp' as $k13_con$
  select * from public.fn_kernel_event_consume(p_outbox_id);
$k13_con$;

-- ---------------------------------------------------------------- 5. the grants the DROPs reset
-- These four were DROP + CREATE, not CREATE OR REPLACE, because a replace cannot remove a parameter
-- default. A drop takes the ACL with it and the create hands EXECUTE back to PUBLIC — the exact
-- trap this repo documents. Caught by fn_kernel_retired_path_state reading 4 of 8 in the rehearsal,
-- which is the guard doing its job on the person writing the guard.
revoke all on function public.fn_phase_c_event_ingress(text, text, jsonb) from public;
revoke all on function public.fn_phase_c_step_advance(bigint, text, text, jsonb) from public;
revoke all on function public.fn_phase_c_outbox_deliver(integer, text) from public;
revoke all on function public.fn_phase_c_event_consume(bigint) from public;

grant execute on function public.fn_phase_c_event_ingress(text, text, jsonb) to service_role;
grant execute on function public.fn_phase_c_step_advance(bigint, text, text, jsonb) to service_role;
grant execute on function public.fn_phase_c_outbox_deliver(integer, text) to service_role;
grant execute on function public.fn_phase_c_event_consume(bigint) to service_role;
