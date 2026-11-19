-- NO TASK EXISTS WITHOUT A SEAT (ceo, 19 Nov 2026).
--
-- Assigned: ceo - the ownership rule is the company's; the detector it adds is it_engineer's duty and the three rows
-- name accountant and it_engineer. Founder ruling 1743, 19 Nov 2026: "there shouldnt be a single task that is not
-- owned by an agent. otherwise its not a real company." (The rule of 7 Sep 2026, restated.)
--
-- MEASURED 19 Nov 2026, production, read-only:
--   * 154 active cron jobs, 0 inactive. 130 are seat_duty:<duty> jobs, each matching a seat_duty row whose owner_seat
--     is an active org_role; 23 are registered in public.writer_seat (kind cron_job) under an active seat.
--   * ONE has no owner anywhere: accountant_payment_checks (8,23,38,53 * * * *, fn_accountant_payment_checks_sweep()),
--     scheduled by a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql, whose
--     header says "Assigned: accountant". It never wrote its writer_seat row.
--   * dropbox_backup_second_scheduler (41 */6, fn_backup_kick('pg_cron_second_scheduler','enqueue')) is registered to
--     sales_engineer. It kicks the platform's Dropbox backup; the backup_kick label it writes is it_engineer's
--     (every_run_label_and_cron_job_names_its_seat.sql), and backups are IT's. It moves to it_engineer.
--   * the only Vercel cron, /api/resilience-ping every 15 minutes (vercel.json), had no seat recorded anywhere.
--     writer_seat.kind admitted only agent_runs_label and cron_job, so the kind vercel_cron is added. resilience_ping is
--     the platform tick (it_engineer, fn_it_detect D3 reads it as "the scheduler").
--   * 776 pending agent_actions; every one names an active seat (0 orphans). 0 seat_duty rows on an unknown seat
--     (owner_seat is NOT NULL with a foreign key to org_role, so only a deactivated seat can orphan one).
--
-- WHAT THIS ADDS
--   1. writer_seat: the three rows above (kind vercel_cron added to writer_seat_kind_check).
--   2. fn_unowned_work(): every active cron.job with no writer_seat row on an active seat and no seat_duty owning it
--      (seat_duty:<duty>); every seat_duty whose owner_seat is null or not an active seat; every seat named, or left
--      null, by a pending agent_action that is not an active seat. Read-only; the one definition of "unowned work".
--   3. fn_it_engineer_unowned_work(), the hourly duty it_engineer.unowned_work: each row is an IT finding
--      'unowned_work:<kind>:<name>' through the estate's one finding path (fn_it_engineer_finding_upsert, blast
--      agent_facing, affected 1: work nobody owns is work no seat notices), closed when the row stops being true.
--      A separate duty, not an arm in fn_it_detect: its ledger (it_watch_finding) resolves every key it did not raise
--      itself each tick, so a second writer there would be closed every 15 minutes. No trigger on cron.job.
--   4. it_playbook class work_without_a_seat for the prefix, so a cleared finding never parks for want of a class.
--
-- CREATE (not OR REPLACE over an old ACL) of two new routines grants EXECUTE to PUBLIC, so each is revoked by its exact
-- signature (each has one; enumerated 19 Nov 2026: neither name existed). search_path pinned on both.
-- Prevented by: scripts/checks/no_task_exists_without_a_seat.test.mjs (repo: every cron.schedule in scripts/sql and
-- every vercel.json cron has an owner, with known-bad controls; production: fn_unowned_work() returns no row).
--
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/no_task_exists_without_a_seat.sql --apply --ddl
-- Rollback: delete from public.seat_duty where duty = 'it_engineer.unowned_work';
--           delete from public.it_playbook where failure_class = 'work_without_a_seat';
--           drop function public.fn_it_engineer_unowned_work(); drop function public.fn_unowned_work();
--           delete from public.writer_seat where (kind, name) in (('cron_job','accountant_payment_checks'),('vercel_cron','/api/resilience-ping'));
--           update public.writer_seat set owner_seat = 'sales_engineer' where kind = 'cron_job' and name = 'dropbox_backup_second_scheduler';
--           (then restore writer_seat_kind_check to the two kinds).

set local lock_timeout = '5s';

-- ── 1. THE KIND FOR A VERCEL CRON ─────────────────────────────────────────────────────────────────────
alter table public.writer_seat drop constraint if exists writer_seat_kind_check;
alter table public.writer_seat add constraint writer_seat_kind_check
  check (kind in ('agent_runs_label', 'cron_job', 'vercel_cron'));

-- ── 2. THE THREE OWNERS ───────────────────────────────────────────────────────────────────────────────
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'accountant_payment_checks', 'accountant',
   'fn_accountant_payment_checks_sweep() at 8,23,38,53 past the hour: the accountant''s reconcile, books and refund clock of every paid reveal. Its file says Assigned: accountant; it never wrote this row (found 19 Nov 2026, ruling 1743).',
   'scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql'),
  ('cron_job', 'dropbox_backup_second_scheduler', 'it_engineer',
   'fn_backup_kick(pg_cron_second_scheduler, enqueue) every 6 h at :41: the Dropbox backup''s second scheduler. Moved from sales_engineer 19 Nov 2026 (ruling 1743): it kicks the platform backup, its backup_kick label is it_engineer''s and backups are IT''s; nothing in it is sales work.',
   'scripts/sql/the_github_schedules_that_can_move_run_on_pg_cron_while_actions_are_off.sql'),
  ('vercel_cron', '/api/resilience-ping', 'it_engineer',
   'Vercel Cron, */15: GET /api/resilience-ping -> resilience_ping, the platform tick every heartbeat duty and fn_it_detect hang from. The only Vercel cron; no seat was recorded for it until 19 Nov 2026 (ruling 1743).',
   'vercel.json')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- ── 3. THE ONE DEFINITION OF UNOWNED WORK ─────────────────────────────────────────────────────────────
create or replace function public.fn_unowned_work()
returns table (kind text, name text, detail jsonb)
language sql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select 'cron_job', j.jobname, jsonb_build_object('schedule', j.schedule, 'command', left(j.command, 300), 'jobid', j.jobid)
    from cron.job j
   where j.active
     and not exists (select 1 from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
                      where o.kind = 'cron_job' and o.name = j.jobname)
     and not exists (select 1 from public.seat_duty d join public.org_role r on r.role_id = d.owner_seat and r.status = 'active'
                      where j.jobname = 'seat_duty:' || d.duty)
  union all
  select 'seat_duty', d.duty, jsonb_build_object('owner_seat', d.owner_seat, 'routine', d.routine, 'enabled', d.enabled)
    from public.seat_duty d
   where d.owner_seat is null
      or not exists (select 1 from public.org_role r where r.role_id = d.owner_seat and r.status = 'active')
  union all
  select 'agent_action', coalesce(a.agent, '(null)'),
         jsonb_build_object('pending', count(*), 'oldest', min(a.created_at), 'ids', (array_agg(a.id order by a.id))[1:10])
    from public.agent_actions a
   where a.status = 'pending'
     and (a.agent is null
          or not exists (select 1 from public.org_role r where r.role_id = a.agent and r.status = 'active'))
   group by a.agent
$fn$;
revoke execute on function public.fn_unowned_work() from public, anon, authenticated;
grant execute on function public.fn_unowned_work() to service_role;

-- ── 4. THE DUTY THAT RAISES IT ────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_engineer_unowned_work()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare u record; v_keys text[] := '{}'; v_out jsonb := '[]'::jsonb; v_closed int; v_key text;
begin
  for u in select * from public.fn_unowned_work() order by 1, 2 loop
    v_key := 'unowned_work:' || u.kind || ':' || u.name;
    v_keys := v_keys || v_key;
    perform public.fn_it_engineer_finding_upsert(
      v_key,
      case u.kind
        when 'cron_job' then 'Cron job ' || u.name || ' (' || coalesce(u.detail->>'schedule', '?') || ') runs with no seat: no writer_seat row on an active seat and no seat_duty owns it'
        when 'seat_duty' then 'Seat duty ' || u.name || ' names ' || coalesce(u.detail->>'owner_seat', 'no seat') || ', which is not an active seat'
        else (u.detail->>'pending') || ' pending agent_actions name ' || u.name || ', which is not an active seat' end,
      case u.kind when 'cron_job' then 'cron.job / ' when 'seat_duty' then 'public.seat_duty / ' else 'public.agent_actions / ' end || u.name,
      'agent_facing', 1,
      u.detail || jsonb_build_object('kind', u.kind, 'name', u.name, 'rule', 'ruling 1743: no task exists without a seat',
        'fix', case u.kind
          when 'cron_job' then 'register it: insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values (''cron_job'', <jobname>, <live seat>, ...), in the file that schedules it'
          when 'seat_duty' then 'give the duty a live seat or remove it with its seat'
          else 'address the actions to a live seat or close them' end),
      '{}'::text[],
      array['which live seat owns it: the file that created it says, or the founder does'],
      'it_engineer');
    v_out := v_out || jsonb_build_object('kind', u.kind, 'name', u.name);
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the work names a live seat now (fn_it_engineer_unowned_work)'
   where f.issue_key like 'unowned_work:%' and f.closed_at is null and not (f.issue_key = any (v_keys));
  get diagnostics v_closed = row_count;
  return jsonb_build_object('unowned', v_out, 'closed', v_closed);
end $fn$;
revoke execute on function public.fn_it_engineer_unowned_work() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_unowned_work() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled)
values ('it_engineer.unowned_work', 'it_engineer', interval '1 hour', 'fn_it_engineer_unowned_work',
        'An active cron job, a seat duty or a pending agent action that names no live seat is an IT finding (ruling 1743); it closes when the work names a live seat.',
        'scripts/sql/no_task_exists_without_a_seat.sql', true)
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file, enabled = true;

insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, typical_cause, added_by) values
  ('work_without_a_seat', 'unowned_work:', null, null,
   'Choosing the seat that owns a job is a decision, not a repair: the file that created the work names its seat, and the founder adds seats. The detector never assigns one itself.',
   'fn_it_engineer_unowned_work re-raises unowned_work:<kind>:<name>; scripts/checks/no_task_exists_without_a_seat.test.mjs',
   'Measured 19 Nov 2026: accountant_payment_checks was scheduled by a file whose header said Assigned: accountant, and the writer_seat row was never written, so the header was the only record of its owner.',
   'ceo (19 Nov 2026)')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix, not_automatable_reason = excluded.not_automatable_reason,
  regression_check = excluded.regression_check, typical_cause = excluded.typical_cause, added_by = excluded.added_by;

-- ── PROBE (one verdict row) ───────────────────────────────────────────────────────────────────────────
-- The sub-block schedules a ZZ DEMO job that can never fire (31 February), runs the duty, reads the finding, and raises,
-- so the job and every finding it raised roll back; the verdict leaves through a temp table. No real row is touched:
-- the one real cron job it names (accountant_payment_checks) is read, never changed.
create temp table zz_unowned_work_probe (verdict text) on commit drop;
do $p$
declare r jsonb; v text; v_demo text; v_real int;
begin
  begin
    perform cron.schedule('zz_demo_unowned_job', '0 0 31 2 *', 'select 1');
    r := public.fn_it_engineer_unowned_work();
    select title into v_demo from public.it_engineer_finding
     where issue_key = 'unowned_work:cron_job:zz_demo_unowned_job' and closed_at is null;
    select count(*) into v_real from public.it_engineer_finding
     where issue_key in ('unowned_work:cron_job:accountant_payment_checks', 'unowned_work:cron_job:dropbox_backup_second_scheduler')
       and closed_at is null;
    v := case
      when v_demo is null then 'PROBE FAILED: an unowned ZZ DEMO job raised no finding: ' || left(r::text, 400)
      when not exists (select 1 from jsonb_array_elements(r->'unowned') e where e->>'name' = 'zz_demo_unowned_job')
        then 'PROBE FAILED: the duty did not report the ZZ DEMO job'
      when v_real <> 0 then 'PROBE FAILED: a job registered by this file still raised a finding'
      else 'PROBE OK' end;
    raise exception using message = 'zz_unowned_work_probe_rollback', detail = v;
  exception when others then
    if sqlerrm = 'zz_unowned_work_probe_rollback' then get stacked diagnostics v = pg_exception_detail;
    else v := 'PROBE FAILED: ' || sqlerrm; end if;
  end;
  insert into zz_unowned_work_probe values (v);
end $p$;

select case
  when (select verdict from zz_unowned_work_probe) <> 'PROBE OK' then (select verdict from zz_unowned_work_probe)
  when (select count(*) from public.writer_seat
         where (kind, name, owner_seat) in (('cron_job', 'accountant_payment_checks', 'accountant'),
                                            ('cron_job', 'dropbox_backup_second_scheduler', 'it_engineer'),
                                            ('vercel_cron', '/api/resilience-ping', 'it_engineer'))) <> 3
    then 'PROBE FAILED: the three owner rows are not all in writer_seat'
  when exists (select 1 from cron.job where jobname like 'zz_demo%')
    or exists (select 1 from public.it_engineer_finding where issue_key like 'unowned_work:%zz_demo%')
    then 'PROBE FAILED: a ZZ DEMO row was left behind'
  when exists (select 1 from public.fn_unowned_work())
    then 'PROBE FAILED: unowned work remains: ' || (select string_agg(kind || ':' || name, ', ') from public.fn_unowned_work())
  else 'PROBE OK: 3 owner rows, the detector flagged the ZZ DEMO job, nothing unowned remains, nothing left behind' end as verdict;
