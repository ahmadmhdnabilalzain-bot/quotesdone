-- A DUTY PAUSED FOR OVER A WEEK IS A FINDING (it_engineer, 4 Oct 2026, item 21).
--
-- public.duty_pause (every_duty_runner_honours_one_pause_switch.sql) had no expiry: a row stops a duty wherever it
-- runs until somebody deletes it, and nothing asked whether anybody still meant it. A pause is a decision for now,
-- not a retirement, so a pause older than 7 days now raises an it_engineer finding through the estate's one finding
-- path (fn_it_engineer_finding_upsert), and the finding closes itself when the row is deleted.
--
-- SEVERITY, deterministic. No duty carries a money/security classification column (measured 4 Oct 2026: seat_duty
-- has duty, owner_seat, every, routine, what, owner_file, enabled...; duty_pause has duty, reason, paused_by,
-- paused_at), so fn_duty_pause_stakes() states it:
--   money    - every duty of the accountant seat (seat_duty.owner_seat, else the name's seat prefix), and
--              sales_engineer.disputes;
--   security - the credential, backup and restore duties named in the list below;
--   routine  - everything else.
-- money/security raise blast 'security' (fn_it_engineer_severity: critical); routine raises 'agent_facing' with
-- affected 1 (high): a paused duty is work an agent is not doing.
--
-- WIRED into the seat clock as the daily duty it_engineer.duty_pause_expiry (fn_seat_duties_tick runs it once a day).
-- Prevented by: scripts/checks/a_duty_paused_for_over_a_week_is_a_finding.test.mjs.
--
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/a_duty_paused_for_over_a_week_is_a_finding.sql --apply --ddl

create or replace function public.fn_duty_pause_stakes(p_duty text)
returns text
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when coalesce((select sd.owner_seat from public.seat_duty sd where sd.duty = p_duty), split_part(p_duty, '.', 1)) = 'accountant'
      or p_duty = 'sales_engineer.disputes'
      then 'money'
    when p_duty = any (array[
      'resilience_ping.rotate_by_api',          -- rotates a provider API key
      'resilience_ping.renewal',                -- credential renewal reminders
      'resilience_ping.restore_overdue',        -- the restore drill is overdue
      'resilience_ping.restore_table',          -- the restore drill itself
      'it_engineer.credential_rotation_age',
      'it_engineer.backup_objectives',
      'it_engineer.dr_review'])
      then 'security'
    else 'routine' end
$fn$;
revoke execute on function public.fn_duty_pause_stakes(text) from public, anon, authenticated;
grant execute on function public.fn_duty_pause_stakes(text) to service_role;

create or replace function public.fn_it_engineer_duty_pause_expiry()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare p record; v_stakes text; v_out jsonb := '[]'::jsonb; v_closed int;
begin
  for p in select dp.* from public.duty_pause dp where dp.paused_at < now() - interval '7 days' order by dp.paused_at loop
    v_stakes := public.fn_duty_pause_stakes(p.duty);
    perform public.fn_it_engineer_finding_upsert(
      'duty_pause_expired:' || p.duty,
      'Duty ' || p.duty || ' (' || v_stakes || ') has been paused for ' || extract(day from now() - p.paused_at)::int
        || ' days, since ' || to_char(p.paused_at at time zone 'Asia/Dubai', 'YYYY-MM-DD') || ' by ' || p.paused_by || ': ' || p.reason,
      'public.duty_pause / ' || p.duty,
      case when v_stakes in ('money', 'security') then 'security' else 'agent_facing' end,
      1,
      jsonb_build_object('duty', p.duty, 'stakes', v_stakes, 'paused_at', p.paused_at, 'paused_by', p.paused_by,
                         'reason', p.reason, 'limit', '7 days'),
      '{}'::text[],
      array['whether the pause is still meant: resume = delete from public.duty_pause where duty = ''' || p.duty || ''''],
      'it_engineer');
    v_out := v_out || jsonb_build_object('duty', p.duty, 'stakes', v_stakes);
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the pause was lifted or renewed (fn_it_engineer_duty_pause_expiry)'
   where f.issue_key like 'duty_pause_expired:%' and f.closed_at is null
     and not exists (select 1 from public.duty_pause dp
                      where 'duty_pause_expired:' || dp.duty = f.issue_key and dp.paused_at < now() - interval '7 days');
  get diagnostics v_closed = row_count;
  return jsonb_build_object('expired', v_out, 'closed', v_closed);
end $fn$;
revoke execute on function public.fn_it_engineer_duty_pause_expiry() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_duty_pause_expiry() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled)
values ('it_engineer.duty_pause_expiry', 'it_engineer', interval '1 day', 'fn_it_engineer_duty_pause_expiry',
        'A duty paused in public.duty_pause for over 7 days is a finding (critical for a money or security duty); it closes when the pause is lifted.',
        'scripts/sql/a_duty_paused_for_over_a_week_is_a_finding.sql', true)
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file, enabled = true;

-- PROBE (verdict row). It drives a REAL tick: ZZ DEMO duties and pauses are seeded, every real duty is marked not due
-- for the length of the block, fn_seat_duties_tick runs (and with it the new daily duty), and the outcome is read.
-- Then the block raises, so everything it did - the seed, the tick, any finding - rolls back; the verdict leaves
-- through a temp table. The final row asserts nothing ZZ DEMO survived.
create temp table zz_duty_pause_probe (verdict text);
do $p$
declare r jsonb; v text; v_paused timestamptz; v_ctl timestamptz; b_routine text; b_money text; n_fresh int; v_exp boolean;
begin
  begin
    update public.seat_duty set last_started_at = now()
     where duty not in ('it_engineer.duty_pause_expiry', 'it_engineer.zz_demo_paused', 'it_engineer.zz_demo_control');
    update public.seat_duty set last_started_at = null where duty = 'it_engineer.duty_pause_expiry';
    insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled) values
      ('it_engineer.zz_demo_paused',  'it_engineer', interval '1 day', 'fn_seat_duty_health', 'ZZ DEMO probe: a paused duty',
       'scripts/sql/a_duty_paused_for_over_a_week_is_a_finding.sql', true),
      ('it_engineer.zz_demo_control', 'it_engineer', interval '1 day', 'fn_seat_duty_health', 'ZZ DEMO probe: the same duty, not paused',
       'scripts/sql/a_duty_paused_for_over_a_week_is_a_finding.sql', true);
    insert into public.duty_pause (duty, reason, paused_by, paused_at) values
      ('it_engineer.zz_demo_paused', 'ZZ DEMO probe', 'it_engineer', now() - interval '8 days'),
      ('accountant.zz_demo_paused',  'ZZ DEMO probe', 'it_engineer', now() - interval '8 days'),
      ('it_engineer.zz_demo_fresh',  'ZZ DEMO probe', 'it_engineer', now() - interval '1 day');

    r := public.fn_seat_duties_tick(8);

    select last_started_at into v_paused from public.seat_duty where duty = 'it_engineer.zz_demo_paused';
    select last_started_at into v_ctl    from public.seat_duty where duty = 'it_engineer.zz_demo_control';
    v_exp := exists (select 1 from jsonb_array_elements(r->'ran') e where e->>'duty' = 'it_engineer.duty_pause_expiry' and (e->>'ok')::boolean);
    select blast into b_routine from public.it_engineer_finding where issue_key = 'duty_pause_expired:it_engineer.zz_demo_paused' and closed_at is null;
    select blast into b_money   from public.it_engineer_finding where issue_key = 'duty_pause_expired:accountant.zz_demo_paused' and closed_at is null;
    select count(*) into n_fresh from public.it_engineer_finding where issue_key = 'duty_pause_expired:it_engineer.zz_demo_fresh';
    v := case
      when v_paused is not null or exists (select 1 from jsonb_array_elements(r->'ran') e where e->>'duty' = 'it_engineer.zz_demo_paused')
        then 'PROBE FAILED: the tick started a paused duty'
      when v_ctl is null then 'PROBE FAILED: the tick did not start the unpaused control duty, so the skip proves nothing'
      when not v_exp then 'PROBE FAILED: the tick did not run it_engineer.duty_pause_expiry: ' || left(r::text, 400)
      when b_routine is distinct from 'agent_facing' then 'PROBE FAILED: an 8-day routine pause raised ' || coalesce(b_routine, 'no finding')
      when b_money is distinct from 'security' then 'PROBE FAILED: an 8-day money pause raised ' || coalesce(b_money, 'no finding')
      when public.fn_it_engineer_severity(b_money, 1, now()) <> 'critical'
        or public.fn_it_engineer_severity(b_routine, 1, now()) not in ('high', 'critical')
        then 'PROBE FAILED: the money pause is not more severe than the routine one'
      when n_fresh <> 0 then 'PROBE FAILED: a 1-day pause raised a finding'
      else 'PROBE OK' end;
    -- lifted: the finding closes
    delete from public.duty_pause where duty = 'it_engineer.zz_demo_paused';
    perform public.fn_it_engineer_duty_pause_expiry();
    if v = 'PROBE OK' and exists (select 1 from public.it_engineer_finding
                                   where issue_key = 'duty_pause_expired:it_engineer.zz_demo_paused' and closed_at is null) then
      v := 'PROBE FAILED: a lifted pause left its finding open';
    end if;
    raise exception using message = 'zz_duty_pause_probe_rollback', detail = v;
  exception when others then
    if sqlerrm = 'zz_duty_pause_probe_rollback' then get stacked diagnostics v = pg_exception_detail;
    else v := 'PROBE FAILED: ' || sqlerrm; end if;
  end;
  insert into zz_duty_pause_probe values (v);
end $p$;
select verdict from zz_duty_pause_probe;
drop table zz_duty_pause_probe;
select case
  when exists (select 1 from public.duty_pause where duty like '%zz_demo%')
    or exists (select 1 from public.seat_duty where duty like '%zz_demo%')
    or exists (select 1 from public.it_engineer_finding where issue_key like 'duty_pause_expired:%zz_demo%')
    then 'PROBE FAILED: a ZZ DEMO row was left behind'
  else 'PROBE OK' end as verdict;
