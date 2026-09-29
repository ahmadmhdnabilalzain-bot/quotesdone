-- EVERY RUN LABEL AND CRON JOB NAMES ITS SEAT (30 Sep 2026; seat: it_engineer).
--
-- Senior-hire audit, ownership: "no job or task exists without an agent" (founder, 7 Sep 2026). Two things
-- ran with no seat behind them.
--
-- WHAT WAS MEASURED (30 Sep 2026, production, read-only):
--   * 81 distinct agent_runs labels in the last 7 days. A label is owned when it (or, for 'fn:<slug>', its slug)
--     is a function_owner.function_slug, or a seat_duty duty or routine. Exactly five were not:
--       backup_kick 500 runs, brief 7, company_snapshot 6, supplier_invites 7, supplier_sanctions_screen 13
--     (every one of them status ok: they work, nobody owns them).
--   * cron.job ceo-strategy-memo-monthly (0 2 2 * *, select public.fn_ceo_strategy_memo()) is scheduled
--     directly by the_ceo_writes_a_one_page_strategy_memo_every_month.sql. It is not a seat_duty, so no seat's
--     clock, failure count or finding sees it. Moving it onto the seat clock changes when and how it runs, which
--     is behaviour, not a defect; this change records its owner and leaves the schedule alone.
--
-- WHAT THIS ADDS
--   public.writer_seat (kind, name, owner_seat -> org_role): the owner of a writer that no seat_duty or
--   function_owner row already names. Owners, per the founder's seat map of 24 Sep 2026:
--     backup_kick                 it_engineer   (the platform's backups: IT monitors everything)
--     brief, company_snapshot     ceo           (the company's own picture for the chief executive)
--     supplier_invites            marketing     (the supplier registration campaign, Oct-Dec 2026)
--     supplier_sanctions_screen   accountant    (sanctions rescreening sits with money and compliance)
--     cron ceo-strategy-memo-monthly  ceo
--   fn_writers_without_a_seat(p_days) returns every agent_runs label of the last p_days days and every cron job
--   that resolves to no seat. It is the one definition of "owned", read by the check below.
--
-- Prevented by: scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs (production: the function
-- returns no rows; static: revoke, search_path, RLS and policy).
--   node scripts/apply_sql.mjs scripts/sql/every_run_label_and_cron_job_names_its_seat.sql --apply --ddl

create table if not exists public.writer_seat (
  kind        text not null check (kind in ('agent_runs_label', 'cron_job')),
  name        text not null,
  owner_seat  text not null references public.org_role (role_id),
  note        text not null,
  owner_file  text not null,
  recorded_at timestamptz not null default now(),
  primary key (kind, name)
);
alter table public.writer_seat enable row level security;
drop policy if exists writer_seat_service_role_only on public.writer_seat;
create policy writer_seat_service_role_only on public.writer_seat
  as permissive for all to public using (false) with check (false);
revoke all on public.writer_seat from anon, authenticated;
comment on table public.writer_seat is
  'The seat that owns an agent_runs label or a cron job that no seat_duty or function_owner row names (30 Sep 2026). fn_writers_without_a_seat() lists what is still unowned.';

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('agent_runs_label', 'backup_kick', 'it_engineer', 'Kicks the platform backup. IT monitors the platform.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('agent_runs_label', 'brief', 'ceo', 'The company brief read by the chief executive.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('agent_runs_label', 'company_snapshot', 'ceo', 'The company snapshot and pulse for the chief executive.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('agent_runs_label', 'supplier_invites', 'marketing', 'The supplier registration invitations (campaign Oct-Dec 2026).', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('agent_runs_label', 'supplier_sanctions_screen', 'accountant', 'Sanctions rescreening of registered suppliers.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('cron_job', 'ceo-strategy-memo-monthly', 'ceo', 'fn_ceo_strategy_memo on the 2nd of each month; scheduled outside the seat clock.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

create or replace function public.fn_writers_without_a_seat(p_days integer default 7)
returns table (kind text, name text, runs bigint)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select 'agent_runs_label', l.agent, count(*)
    from public.agent_runs l
   where l.started_at > now() - make_interval(days => greatest(coalesce(p_days, 7), 1))
     and not exists (select 1 from public.function_owner f where f.function_slug = regexp_replace(l.agent, '^fn:', ''))
     and not exists (select 1 from public.seat_duty d where l.agent in (d.duty, d.routine))
     and not exists (select 1 from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
                      where o.kind = 'agent_runs_label' and o.name = l.agent)
   group by l.agent
  union all
  select 'cron_job', j.jobname, null::bigint
    from cron.job j
   where not exists (select 1 from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
                      where o.kind = 'cron_job' and o.name = j.jobname)
$fn$;
revoke execute on function public.fn_writers_without_a_seat(integer) from public, anon, authenticated;
grant execute on function public.fn_writers_without_a_seat(integer) to service_role;

select case when exists (select 1 from public.fn_writers_without_a_seat(7) w where w.kind = 'agent_runs_label')
            then 'PROBE FAILED: ' || (select string_agg(w.name, ', ') from public.fn_writers_without_a_seat(7) w where w.kind = 'agent_runs_label') || ' has no seat'
            else 'PROBE OK: every run label of the last 7 days names its seat' end as verdict;
