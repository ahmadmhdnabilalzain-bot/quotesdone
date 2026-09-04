-- THE MANUAL RECORDS THE FOUR JOBS ENABLED TODAY (4 Sep 2026).
--
-- The executive-UI scorer's s38-manual-always-current went from MET to NOT MET this afternoon:
-- "4 active cron job(s) are undocumented and 0 documented job(s) no longer exist". The four are the
-- ones switched on today by the Phase E wiring and the dead-trigger packet, each wrapped through the
-- kernel and given an owner but never given a line in public.cron_registry -- the table that IS the
-- operations manual. A job that runs and is written down nowhere is the thing that check exists to
-- catch, and it caught us.
--
-- Each description below was written from the routine's own body (what it reads, what it writes),
-- not from its name.
--
--   node scripts/apply_sql.mjs scripts/sql/the_manual_records_the_four_jobs_enabled_today.sql --apply --ddl
begin;

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('department_conflict_scan_weekly',
   'Weekly scan for departments deciding against each other',
   'self_management',
   'Mondays 06:00 UTC. Reads public.decision_log joined to the deciding agent''s department and emits '
   || 'a department.conflict event when two departments have decided opposite ways on the same kind of '
   || 'question, so the Office of the CEO arbitrates instead of the disagreement sitting unread. Writes '
   || 'its own agent_runs row; the events go through fn_emit. Deterministic, no model, nothing outbound.'),

  ('collections_reminders_daily',
   'Daily reminder for supplier dues that have come due',
   'finance',
   'Daily 06:20 UTC. Walks public.supplier_dues past their date and writes an in-portal notification '
   || 'per supplier, updating the due''s reminder state. NO commission is ever charged on a won job '
   || '(founder policy: zero supplier commission), so this only chases the reveal-side dues that exist. '
   || 'Writes agent_runs, supplier_dues and notifications; it sends no email and no WhatsApp.'),

  ('experiment_conclude_daily',
   'Daily conclusion of A/B experiments that have enough evidence',
   'learning',
   'Daily 02:40 UTC. Reads public.experiments and concludes one only when its SMALLEST arm has reached '
   || 'the per-variant subject floor, then records the winner and closes it. Under-powered experiments '
   || 'are left open rather than called early. Writes experiments and an agent_runs row; deterministic, '
   || 'no model.'),

  ('blueprint_result_prune_weekly',
   'Weekly pruning of blueprint results older than 90 days',
   'housekeeping',
   'Sundays 03:15 UTC. Deletes public.os_blueprint_result rows older than 90 days and returns the count. '
   || 'Pure retention housekeeping: it touches no business relation, sends nothing and calls no model.')
on conflict (jobname) do update
   set human_name = excluded.human_name,
       category   = excluded.category,
       purpose    = excluded.purpose;

do $proof$
declare v_undocumented int; v_txt text;
begin
  select count(*), coalesce(string_agg(j.jobname, ', '), '(none)') into v_undocumented, v_txt
    from cron.job j
   where j.active and not exists (select 1 from public.cron_registry g where g.jobname = j.jobname);
  if v_undocumented > 0 then
    raise exception 'still undocumented: % (%)', v_undocumented, v_txt;
  end if;
  raise notice 'proof: every active cron job has a line in the manual';
end $proof$;
commit;
