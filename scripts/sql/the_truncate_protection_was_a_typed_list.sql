-- THE PROTECTION WAS A TYPED LIST, SO IT COULD ONLY EVER COVER WHAT SOMEBODY REMEMBERED.
--
-- 18 Aug 2026, independent Phase C final acceptance. kernel_s4 introduced fn_kernel_truncate_guard
-- for exactly the right reason — a row-level BEFORE trigger cannot fire on TRUNCATE, so every
-- row guard in the estate is bypassable by one statement — and then attached it to a hand-typed
-- array of seven table names:
--
--   foreach t in array array['phase_c_workflow_run','phase_c_workflow_step_run','phase_c_task',
--                            'phase_c_handoff_run','phase_c_event_outbox','phase_c_trace',
--                            'founder_command']
--
-- The guard was right. The list was a snapshot. Measured on production today, 75 tables carry an
-- enforcing row-level trigger and 7 of them were protected; 67 of the remaining 68 could be
-- emptied by service_role with every instrument green. Proven by execution in an aborted
-- transaction:
--
--   kernel_signal_inbox       TRUNCATE ACCEPTED as service_role (before=0    after=0)
--   kernel_trigger_inbox      TRUNCATE ACCEPTED as service_role (before=1    after=0)
--   phase_c_refund_decision   TRUNCATE ACCEPTED                 (before=0    after=0)
--   org_phase_baseline        TRUNCATE ACCEPTED                 (before=2    after=0)
--   phase_c_system_execution  TRUNCATE ACCEPTED                 (before=1067 after=0)
--   security_audit_log        TRUNCATE ACCEPTED                 (before=2882 after=0)
--   phase_c_historical_repair TRUNCATE ACCEPTED                 (before=71   after=0)
--
-- The first two are the kernel's own doors: kernel_write_authority records fn_kernel_signal_submit
-- as "the only writer of the signal ledger" and fn_kernel_trigger_submit as "the only writer of the
-- inbox". phase_c_refund_decision carries an explicit immutability trigger and the founder's
-- standing rule that every refund needs him. org_phase_baseline holds the founder-approved Phase A
-- and Phase B baselines that fn_phase_a_baseline_drift() and fn_phase_b_baseline_drift() read —
-- emptying it makes both drift functions return zero rows, which is a green light produced by
-- deleting the denominator.
--
-- WHAT CHANGES HERE. Not the guard — it is correct and is reused unchanged. The POPULATION stops
-- being typed and starts being derived: any table carrying a row-level trigger whose function
-- raises is a table whose protection TRUNCATE would bypass, so that is exactly the set that gets
-- the statement-level guard. A table that gains an enforcing trigger tomorrow is covered the next
-- time this runs, and fn_kernel_truncate_protection_state() below fails the board immediately if it
-- is not.
--
-- The maintenance door is unchanged and still open: set local kernel.maintenance_reason plus the
-- table owner, recorded in kernel_maintenance_write either way. Nothing legitimate is broken —
-- the only TRUNCATE in the repository is scripts/sql/the_write_map_in_the_database.sql against
-- phase_c_edge_function_writes, which carries no enforcing trigger and is not in this population,
-- and no database routine issues one (fn_agent_context matches the word only in the phrase
-- "[… truncated here at 1,500 of N characters]").

begin;

-- ---------------------------------------------------------------- attach, by derivation
do $attach$
declare
  t          text;
  n_attached int := 0;
  n_total    int := 0;
begin
  for t in
    select distinct c.relname
      from pg_trigger    tg
      join pg_class      c  on c.oid = tg.tgrelid
      join pg_namespace  ns on ns.oid = c.relnamespace
      join pg_proc       p  on p.oid = tg.tgfoid
     where ns.nspname = 'public'
       and not tg.tgisinternal
       -- row-level triggers only. A trigger that is ALREADY a TRUNCATE trigger is the protection,
       -- not the thing being protected, so fn_kernel_truncate_guard cannot select itself here.
       and (tg.tgtype & 32) = 0
       and p.prokind = 'f'
       and pg_get_functiondef(p.oid) ilike '%raise exception%'
     order by 1
  loop
    n_total := n_total + 1;
    -- `from public` matters: revoking from a named role is a silent no-op while the grant is held
    -- through PUBLIC.
    execute format('revoke truncate on public.%I from public, anon, authenticated, service_role', t);
    execute format('drop trigger if exists z00_kernel_truncate_guard on public.%I', t);
    execute format('create trigger z00_kernel_truncate_guard before truncate on public.%I '
                || 'for each statement execute function public.fn_kernel_truncate_guard()', t);
    n_attached := n_attached + 1;
  end loop;

  raise notice 'truncate guard: % enforcing table(s) considered, % attached', n_total, n_attached;

  if n_total = 0 then
    raise exception 'the derivation selected no tables at all, which cannot be right — refusing to '
                    'report success for a migration that protected nothing'
      using errcode = '23514';
  end if;
end
$attach$;

-- ---------------------------------------------------------------- the invariant that keeps it true
--
-- Zero arguments and the column names fn_kernel_all_boards() searches for, so it is discovered by
-- signature the moment it is deployed and needs no registration. It is NOT listed in
-- scripts/checks/kernel-boards.json, which means it is a GATE by default: any red row fails
-- kernel_boards_are_green.test.mjs. That is deliberate — there is no disclosed debt here to
-- ratchet, and a table that loses its TRUNCATE guard is a regression, not a legacy gap.
create or replace function public.fn_kernel_truncate_protection_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  with enforcing as (
    select distinct c.relname as tbl
      from pg_trigger   tg
      join pg_class     c  on c.oid = tg.tgrelid
      join pg_namespace ns on ns.oid = c.relnamespace
      join pg_proc      p  on p.oid = tg.tgfoid
     where ns.nspname = 'public'
       and not tg.tgisinternal
       and (tg.tgtype & 32) = 0
       and p.prokind = 'f'
       and pg_get_functiondef(p.oid) ilike '%raise exception%'
  ),
  guarded as (
    select distinct c.relname as tbl
      from pg_trigger   tg
      join pg_class     c  on c.oid = tg.tgrelid
      join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public'
       and not tg.tgisinternal
       and (tg.tgtype & 32) <> 0
  ),
  m as (
    select e.tbl,
           (e.tbl in (select tbl from guarded)) as has_guard,
           (   has_table_privilege('service_role',  format('public.%I', e.tbl), 'TRUNCATE')
            or has_table_privilege('authenticated', format('public.%I', e.tbl), 'TRUNCATE')
            or has_table_privilege('anon',          format('public.%I', e.tbl), 'TRUNCATE')
           ) as grants_truncate
      from enforcing e
  )
  select 'enforcing_tables_without_a_truncate_guard',
         '0',
         count(*) filter (where not has_guard)::text || ' of ' || count(*)::text,
         count(*) filter (where not has_guard) = 0
    from m
  union all
  select 'enforcing_tables_still_granting_truncate',
         '0',
         count(*) filter (where grants_truncate)::text || ' of ' || count(*)::text,
         count(*) filter (where grants_truncate) = 0
    from m
  union all
  -- Informational, and it is the number that made the defect invisible: how many tables the old
  -- typed list covered. Kept so a reader can see the population this check watches is derived.
  select 'raw_enforcing_tables_watched',
         'informational',
         count(*)::text || ' of ' || count(*)::text,
         true
    from m;
$fn$;

-- A fresh CREATE grants EXECUTE to PUBLIC. Same grant shape as fn_kernel_truncate_guard.
revoke all on function public.fn_kernel_truncate_protection_state() from public;
grant execute on function public.fn_kernel_truncate_protection_state() to service_role;

comment on function public.fn_kernel_truncate_protection_state() is
  'Board: every table carrying an enforcing row-level trigger also carries the statement-level '
  'TRUNCATE guard, and grants TRUNCATE to nobody. Derived from the catalogue, never from a typed '
  'list — kernel_s4 attached the guard to seven tables by name while 68 more needed it, and the '
  'gap was invisible because no instrument compared the two sets. A GATE, not a ratchet.';

commit;
