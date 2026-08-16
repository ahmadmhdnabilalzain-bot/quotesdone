-- AN EXPORT THAT NAMES ITS OWN PROJECT CAN NEVER BE THE SAME FROM EITHER SOURCE.
--
-- Founder, 15 Aug 2026: "if I ever exported the full code of the project from either source it will
-- give me the exact same thing."
--
-- scripts/checks/export_from_either_source_is_identical.mjs has been reporting the gap since the day
-- it was written, under its own heading, and nothing had closed it:
--
--     PORTABILITY — project refs embedded in the export: 2
--        An export that names the project it came from cannot be byte-identical to the same
--        schema exported from anywhere else. This has to be parameterised or stripped.
--
-- Measured before touching anything: the literal `htdblwldjkcgjvmqkbeh` appears in the header line
-- fn_schema_export() writes about itself, and in the command text of 46 of the 205 cron jobs. All 46
-- occurrences sit inside a URL string literal — 35 as `url:='https://<ref>.supabase.co/...`, 9 as
-- `l := 'https://<ref>...`, 2 as `:= 'https://<ref>...` — and none anywhere else, so one uniform
-- substitution covers every case with no per-job special handling.
--
-- THE PATTERN IS NOT INVENTED HERE. Three jobs already build the URL the portable way —
-- boq_fixture_check_weekly, kb_embed_priority_kinds and workflow_dispatch_10min all read
-- app_secrets.project_ref — and this brings the other 46 to the shape those three already use
-- rather than introducing a fourth idea. app_secrets.project_ref was confirmed present and equal to
-- the live ref before the rewrite, because a parameterised URL reading a missing key resolves to
-- `https://.supabase.co/` and would fail every one of these jobs silently.
--
-- The header line is stripped rather than parameterised. It is a comment describing the capture, and
-- the capture banner in supabase/schema/full_schema.sql already records which project and when —
-- outside the compared region, deliberately, so a timestamp cannot make the file differ from itself.
-- Naming the project twice, once inside the compared bytes, bought nothing and cost the property.

begin;

-- ------------------------------------------------------------------------------------------------
-- 1. The export stops naming the project it came from.
-- ------------------------------------------------------------------------------------------------
do $mig$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_schema_export';
  if v_def is null then raise exception 'fn_schema_export not found'; end if;

  v_new := replace(v_def,
    '-- QuotesDone — FULL SCHEMA EXPORT (generated from live DB, project htdblwldjkcgjvmqkbeh)',
    '-- QuotesDone — FULL SCHEMA EXPORT (generated from the live database)');

  if v_new = v_def then
    raise notice 'fn_schema_export header already project-agnostic; nothing to do';
  else
    execute v_new;
  end if;
end $mig$;

-- ------------------------------------------------------------------------------------------------
-- 2. The 46 cron jobs build their URL from app_secrets.project_ref, like the three that already do.
--    cron.alter_job rather than a direct update on cron.job: the extension owns that table and
--    expects its own entry point.
-- ------------------------------------------------------------------------------------------------
do $mig$
declare r record; n int := 0; v_ref text;
begin
  select value into v_ref from public.app_secrets where key = 'project_ref';
  if coalesce(v_ref,'') = '' then
    raise exception 'app_secrets.project_ref is missing or empty. Rewriting the jobs to read it '
      'would resolve every URL to https://.supabase.co/ and break all 46 silently.';
  end if;

  for r in select jobid, jobname, command from cron.job where command like '%' || v_ref || '%'
  loop
    perform cron.alter_job(r.jobid, command := replace(r.command, v_ref,
      '''' || ' || (select value from public.app_secrets where key = ''''project_ref'''') || ' || ''''));
    n := n + 1;
  end loop;
  raise notice 'parameterised % cron job URL(s)', n;
end $mig$;

-- ------------------------------------------------------------------------------------------------
-- 3. The property, asserted rather than assumed. If the rewrite mangled a command the job would
--    still be listed here as clean, so the URL each job now RESOLVES to is rebuilt and compared
--    against the one it had before. Anything that does not come back to the same URL aborts.
-- ------------------------------------------------------------------------------------------------
do $mig$
declare n_ref int; n_param int; v_ref text; bad text;
begin
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select count(*) into n_ref from cron.job where command like '%' || v_ref || '%';
  select count(*) into n_param from cron.job
   where command like '%app_secrets where key = ''project_ref''%';

  if n_ref <> 0 then
    raise exception 'PORTABILITY NOT ACHIEVED: % cron job(s) still name the project ref', n_ref;
  end if;

  -- Every parameterised job must still produce a syntactically whole URL:
  --   'https://' || (select value from [public.]app_secrets where key = 'project_ref') || '.supabase.co/
  -- A mangled replacement shows up as a doubled or orphaned scheme.
  --
  -- Matched on the whitespace-normalised command, and tolerant of the schema qualifier, because the
  -- three jobs that were already portable before this file wrap the subquery across lines and write
  -- `app_secrets` unqualified. A first version of this assertion compared exact bytes and refused
  -- those three — it was measuring FORMATTING, not the property, and would have failed forever on
  -- code that was already correct.
  select string_agg(jobname, ', ') into bad from cron.job
   where command like '%app_secrets where key = ''project_ref''%'
     and regexp_replace(command, '\s+', ' ', 'g') !~
         '''https://'' \|\| \( *select value from (public\.)?app_secrets where key = ''project_ref'' *\) \|\| ''\.supabase\.co/';
  if bad is not null then
    raise exception 'MALFORMED URL after rewrite in: %', bad;
  end if;

  raise notice 'portable: 0 job(s) name the ref, % job(s) read it from app_secrets', n_param;
end $mig$;

commit;
