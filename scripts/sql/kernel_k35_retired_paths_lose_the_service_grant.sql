-- K35 — every retired path could still be invoked by service_role.
--
-- §5 requires "direct RPC grants bypassing kernel: 0". Measured across all eight routines in
-- kernel_retired_path:
--
--   COMPATIBILITY_WRAPPER_TO_KERNEL  fn_phase_c_event_consume    callers 0  postgres, service_role
--   COMPATIBILITY_WRAPPER_TO_KERNEL  fn_phase_c_outbox_deliver   callers 1  postgres, service_role
--   DISABLED                         fn_phase_c_event_ingress    callers 0  postgres, service_role
--   DISABLED                         fn_phase_c_step_advance     callers 0  postgres, service_role
--   KERNEL_INTERNAL_PRIMITIVE        fn_phase_c_outbox_claim     callers 1  postgres, service_role
--   KERNEL_INTERNAL_PRIMITIVE        fn_phase_c_task_create      callers 2  postgres, service_role
--   KERNEL_INTERNAL_PRIMITIVE        fn_phase_c_workflow_start   callers 0  postgres, service_role
--   READ_ONLY_HISTORICAL             fn_phase_c_outbox_settle    callers 0  postgres, service_role
--
-- Every one of them is executable by the role every Edge Function holds.
--
-- THE ONE THAT IS NOT MERELY UNTIDY. fn_phase_c_outbox_settle is recorded READ_ONLY_HISTORICAL and
-- it is not read-only: called, it UPDATES phase_c_event_outbox. The guard suite found it by
-- accident — the case "a delivery reported ok with NO downstream record is not counted as
-- delivered" has been failing with
--
--   invalid input syntax for type timestamp with time zone: ""
--
-- which is a routine that RAN and got as far as writing, not one that refused. A routine anyone
-- with the service key can call, which writes the domain-event outbox, is a live bypass whatever
-- its disposition column says. The other seven refuse when called — the DISABLED pair raise, the
-- internal primitives are behind fn_kernel_assert_in_kernel — so for them the grant is untidy
-- rather than dangerous. It goes anyway: a routine nothing calls does not need a grant, and §5
-- says restrict the delivery and consume wrappers to the internal worker identity, which is
-- postgres, not service_role.
--
-- CHECKED BEFORE REVOKING. Zero database routines call any of the eight except the internal
-- kernel callers already counted above, and grepping supabase/functions and src for all eight
-- names returns nothing: no Edge Function and no frontend path invokes one over RPC. postgres
-- keeps EXECUTE, which is the identity cron runs as and the identity the kernel's own
-- SECURITY DEFINER routines run as, so nothing that works today stops.
--
-- Rollback: scripts/sql/rollback/kernel_k35_retired_paths_lose_the_service_grant.rollback.sql

begin;

do $k35$
declare r record; n int := 0;
begin
  for r in select path_name, disposition from public.kernel_retired_path order by path_name loop
    -- Revoke from every ordinary role, not only service_role. anon and authenticated should never
    -- have held these either, and a revoke that names one role leaves the others to be discovered
    -- later by somebody who assumed the sweep was complete.
    execute format('revoke all on function public.%I from public, anon, authenticated, service_role',
                   r.path_name);
    n := n + 1;
  end loop;
  raise notice 'K35: revoked ordinary-role EXECUTE on % retired path(s)', n;
end
$k35$;

-- The state board gains the line, so the next session reads it rather than re-measuring it.
create or replace function public.fn_kernel_retired_grant_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $k35_state$
with g as (
  select r.path_name, r.disposition,
         coalesce((select string_agg(rp.grantee || ':' || rp.privilege_type, ', ')
                     from information_schema.routine_privileges rp
                    where rp.routine_schema = 'public' and rp.routine_name = r.path_name
                      and rp.grantee in ('anon','authenticated','service_role','PUBLIC')), '') ordinary
    from public.kernel_retired_path r
)
select 'retired_paths_executable_by_an_ordinary_role'::text,
       '0 of ' || (select count(*)::text from g),
       (select count(*)::text from g where ordinary <> '') || ' of ' || (select count(*)::text from g)
         || coalesce(' [' || (select string_agg(path_name || ' -> ' || ordinary, '; ')
              from g where ordinary <> '') || ']', ''),
       (select count(*) = 0 from g where ordinary <> '')
union all
select 'retired_paths_with_a_recorded_final_state',
       (select count(*)::text from g) || ' of ' || (select count(*)::text from g),
       (select string_agg(disposition || ' ' || n::text, '; ' order by disposition)
          from (select disposition, count(*) n from g group by 1) d),
       (select count(*) = 0 from g where coalesce(btrim(disposition),'') = '')
union all
-- A compatibility wrapper must reach the kernel and nothing else. Measured from the deployed body,
-- comments stripped, because both wrappers discuss the kernel in prose.
select 'compatibility_wrappers_not_calling_the_kernel',
       '0 of ' || (select count(*)::text from g where disposition = 'COMPATIBILITY_WRAPPER_TO_KERNEL'),
       (select count(*)::text from g
         join pg_proc p on p.proname = g.path_name
         join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
        where g.disposition = 'COMPATIBILITY_WRAPPER_TO_KERNEL'
          and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
              !~ '\yfn_kernel_')
         || ' of ' || (select count(*)::text from g where disposition = 'COMPATIBILITY_WRAPPER_TO_KERNEL'),
       (select count(*) = 0 from g
         join pg_proc p on p.proname = g.path_name
         join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
        where g.disposition = 'COMPATIBILITY_WRAPPER_TO_KERNEL'
          and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
              !~ '\yfn_kernel_');
$k35_state$;

revoke all on function public.fn_kernel_retired_grant_state() from public, anon, authenticated;
grant execute on function public.fn_kernel_retired_grant_state() to service_role;

commit;
