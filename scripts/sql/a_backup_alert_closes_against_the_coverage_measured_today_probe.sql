-- a_backup_alert_closes_against_the_coverage_measured_today_probe.sql (it_engineer, OPS_LOOPS, 16 Nov 2026)
-- A pure probe: run AFTER the file in the SAME transaction, which this probe always aborts (raise 'CHK<<...>>'), so nothing
-- it writes survives. Its alerts are its own rows, titled ZZ DEMO; the coverage reading is passed in, so the probe reads no
-- real backup. Run on a local Postgres 16 built from the schema mirror (scripts/db/local_pg16.mjs): PROBE OK, twice.
do $probe$
declare r jsonb; v_a bigint; v_b bigint; v_c bigint; v_d bigint; v_run bigint; v_open int;
begin
  -- three copies of the coverage alarm and two of the mirror alarm, filed on different days
  insert into public.agent_actions (agent, kind, status, risk, title, detail, created_at)
  values ('it_engineer', 'backup_coverage', 'pending', 'medium', 'ZZ DEMO coverage 1', '{}'::jsonb, now() - interval '30 days') returning id into v_a;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, created_at)
  values ('it_engineer', 'backup_coverage', 'pending', 'medium', 'ZZ DEMO coverage 2', '{}'::jsonb, now() - interval '3 days') returning id into v_b;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, created_at)
  values ('it_engineer', 'backup_alert', 'pending', 'high', 'ZZ DEMO mirror 1', '{}'::jsonb, now() - interval '20 days') returning id into v_c;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, created_at)
  values ('it_engineer', 'backup_alert', 'pending', 'high', 'ZZ DEMO mirror 2', '{}'::jsonb, now() - interval '2 days') returning id into v_d;

  -- 1. the mirror has NOT run for 3 days and coverage fails: one of each stays open, newest, with today's numbers
  insert into public.agent_runs (agent, status, started_at, finished_at) values ('dropbox_backup', 'ok', now() - interval '3 days', now() - interval '3 days')
  returning id into v_run;
  delete from public.agent_runs where agent in ('dropbox_backup', 'fn:dropbox_backup') and id <> v_run;
  r := public.fn_it_backup_alerts_settle(jsonb_build_object('ok', false, 'failing', jsonb_build_array('not_done_after_48h'),
         'not_done_after_48h', 344, 'not_done_ids', jsonb_build_array(1, 2), 'sources_without_a_row', 0, 'refiles_open_past_48h', 0));
  if (r->>'mirror_stale')::boolean is not true then raise exception 'CHK<<PROBE FAILED: a 3-day-old run read as fresh: %>>', r; end if;
  if (select status from public.agent_actions where id = v_a) is distinct from 'dismissed'
     or (select status from public.agent_actions where id = v_c) is distinct from 'dismissed' then
    raise exception 'CHK<<PROBE FAILED: an older copy was not closed as superseded: %>>', r; end if;
  if (select status from public.agent_actions where id = v_b) is distinct from 'pending'
     or (select status from public.agent_actions where id = v_d) is distinct from 'pending' then
    raise exception 'CHK<<PROBE FAILED: the newest alert of a live condition was closed: %>>', r; end if;
  if (select recommendation from public.agent_actions where id = v_b) not like '%344 queued row(s) not done after 48 hours%' then
    raise exception 'CHK<<PROBE FAILED: the kept coverage alert does not carry today''s measurement>>'; end if;
  if (select evidence->>'superseded_by' from public.agent_actions where id = v_a) <> v_b::text then
    raise exception 'CHK<<PROBE FAILED: the superseded copy does not name the alert that replaced it>>'; end if;

  -- 2. the mirror runs again and coverage is measured ok: both kept alerts close 'done' with the measurement
  insert into public.agent_runs (agent, status, started_at, finished_at) values ('dropbox_backup', 'ok', now() - interval '1 hour', now() - interval '1 hour');
  r := public.fn_it_backup_alerts_settle(jsonb_build_object('ok', true, 'failing', '[]'::jsonb));
  if (select status from public.agent_actions where id = v_b) is distinct from 'done' or (select status from public.agent_actions where id = v_d) is distinct from 'done' then
    raise exception 'CHK<<PROBE FAILED: a recovered condition left its alert open: %>>', r; end if;
  if (select evidence->'coverage'->>'ok' from public.agent_actions where id = v_b) <> 'true' then
    raise exception 'CHK<<PROBE FAILED: the close does not carry the coverage it was judged on>>'; end if;
  select count(*) into v_open from public.agent_actions where kind in ('backup_coverage', 'backup_alert') and agent = 'it_engineer' and status in ('pending', 'needs_review');
  if v_open <> 0 then raise exception 'CHK<<PROBE FAILED: % alert(s) still open after recovery>>', v_open; end if;

  -- 3. a second run changes nothing (idempotent)
  r := public.fn_it_backup_alerts_settle(jsonb_build_object('ok', true, 'failing', '[]'::jsonb));
  if (r->>'closed_done')::int <> 0 or (r->>'closed_superseded')::int <> 0 then
    raise exception 'CHK<<PROBE FAILED: a second run closed something again: %>>', r; end if;

  raise exception 'CHK<<PROBE OK>>';
end $probe$;
