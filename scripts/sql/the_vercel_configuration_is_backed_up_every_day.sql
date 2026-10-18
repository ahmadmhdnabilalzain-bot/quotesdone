-- the_vercel_configuration_is_backed_up_every_day.sql
--
-- Assigned: it_engineer. The founder, 12 Oct 2026 ("fix it", the backup workflow): the code is in GitHub and the
-- routes and crons are in vercel.json, but the Vercel project settings and the env var NAMES were backed up
-- nowhere. resilience_ping's daily step vercelSnapshot reads the project (framework, build settings, git link),
-- its domains, its env var names per environment (no value is ever requested or kept) and its crons, writes
-- them to the private backups bucket (engineering/vercel/<day>.json) and files that same file for Dropbox under
-- Company/Vercel/<month>/ through doc_backups, the one uploader. The same step records which env var the app
-- needs that Vercel does not hold, and which has no recoverable source.
-- Measured 12 Oct 2026 (read only): 5 domains, 16 env var names, 1 cron; the app reads CRON_SECRET and
-- SITE_ERROR_INGEST_SECRET, which are not set in Vercel and have no recoverable source.
--
-- prevented by: scripts/checks/the_vercel_configuration_is_backed_up_every_day.test.mjs and
-- supabase/functions/_shared/vercel_snapshot.test.ts

-- the file is filed for Dropbox under Company/Vercel/, not swept into Storage/
create or replace function public.fn_vercel_snapshot_filed(p_path text, p_summary jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_day text;
begin
  if coalesce(p_path, '') !~ '^engineering/vercel/\d{4}-\d{2}-\d{2}\.json$' then
    raise exception 'fn_vercel_snapshot_filed: the snapshot lives at engineering/vercel/<YYYY-MM-DD>.json (got %)', p_path;
  end if;
  v_day := substring(p_path from '(\d{4}-\d{2}-\d{2})');
  insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key)
  values ('company', 'vercel:' || v_day, 'Vercel configuration', 'backups', p_path, v_day || ' vercel-project.json',
          '/QuotesDone Backup/Company/Vercel/' || left(v_day, 7) || '/' || v_day || ' vercel-project.json', 'storage', 'VERCEL:' || v_day)
  on conflict do nothing;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', case when coalesce(jsonb_array_length(p_summary->'no_recoverable_source'), 0) > 0 then 'warn' else 'ok' end,
          jsonb_build_object('job', 'vercel_snapshot') || coalesce(p_summary, '{}'::jsonb),
          left('Vercel configuration backed up (' || p_path || '): ' || coalesce(p_summary->>'domains', '?') || ' domains, '
               || coalesce(p_summary->>'env_names', '?') || ' env var names; needed but not in Vercel: '
               || coalesce(p_summary->>'missing_in_vercel', '[]') || '; no recoverable source: ' || coalesce(p_summary->>'no_recoverable_source', '[]') || '.', 500),
          now(), now());
  return jsonb_build_object('filed', p_path);
end $function$;
revoke execute on function public.fn_vercel_snapshot_filed(text, jsonb) from public, anon, authenticated;

-- once a day, after the backups tick
insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('vercelSnapshot', interval '1 day', 8000, 'plan', 0,
   'it_engineer: the Vercel project configuration (domains, env var names, crons, build settings; never a value) to the backups bucket and Dropbox Company/Vercel/', 'it_engineer')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
                                rank = excluded.rank, note = excluded.note, owner_seat = excluded.owner_seat;

-- probe: a wrong path is refused; a right one is filed under Company/Vercel/ once; nothing is left
do $probe$
declare v_fail text := ''; v_p text;
begin
  begin perform public.fn_vercel_snapshot_filed('elsewhere/x.json', '{}'::jsonb); v_fail := v_fail || ' bad_path_accepted';
  exception when raise_exception then null; end;
  perform public.fn_vercel_snapshot_filed('engineering/vercel/1999-01-02.json', '{"domains":1}'::jsonb);
  perform public.fn_vercel_snapshot_filed('engineering/vercel/1999-01-02.json', '{"domains":1}'::jsonb);
  select string_agg(dropbox_path, ',') into v_p from public.doc_backups where dedupe_key = 'VERCEL:1999-01-02';
  if v_p is distinct from '/QuotesDone Backup/Company/Vercel/1999-01/1999-01-02 vercel-project.json' then v_fail := v_fail || ' path:' || coalesce(v_p, 'none'); end if;
  delete from public.doc_backups where dedupe_key = 'VERCEL:1999-01-02';
  delete from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'vercel_snapshot' and note like '%1999-01-02%';
  if exists (select 1 from public.doc_backups where dedupe_key = 'VERCEL:1999-01-02') then v_fail := v_fail || ' left'; end if;
  perform set_config('qd.probe_vercel', coalesce(nullif(v_fail, ''), 'ok'), true);
end $probe$;
select case when current_setting('qd.probe_vercel', true) = 'ok' then 'PROBE OK'
            else 'PROBE FAILED: ' || coalesce(current_setting('qd.probe_vercel', true), 'no verdict') end as verdict;
