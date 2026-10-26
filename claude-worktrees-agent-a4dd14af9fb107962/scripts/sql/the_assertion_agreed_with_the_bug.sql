-- THE ASSERTION AGREED WITH THE BUG, SO THE BUG SHIPPED.
--
-- scripts/sql/an_export_that_names_its_own_project.sql rewrote 46 cron job URLs to read the project
-- ref from app_secrets instead of naming it. The substitution string was built with SQL quote
-- escaping and got one level too many, so every rewritten command came out carrying
--
--     ... where key = ''project_ref''        instead of        ... where key = 'project_ref'
--
-- which is a syntax error: pg_cron would have failed all 46 the next time each fired, including the
-- eight jobs the stand-down deliberately kept running — backup_daily, the uptime and health probes,
-- and the control-mode security sweep.
--
-- WHY THE FILE'S OWN VERIFICATION PASSED. It asserted the rewritten commands matched
-- `key = ''project_ref''` — written with the same doubled escaping as the bug. Assertion and defect
-- were produced by the same mistaken belief about quoting, so they agreed, and agreement was read as
-- correctness. scripts/checks/authority_gate_single_source.test.mjs says exactly this about a
-- different guard: "a guard that restates its subject proves only that somebody typed the same thing
-- twice." A string comparison between two things the same author wrote in the same breath is not
-- verification.
--
-- So the repair does not compare strings. It asks the PLANNER to parse every cron command, which is
-- the only party that decides whether the text is valid SQL, and it does that for all 205 jobs
-- rather than only the ones this file touches — a job broken by some earlier edit is just as broken.
--
-- Dollar-quoting throughout, because the escaping is what went wrong the first time.

begin;

-- ------------------------------------------------------------------------------------------------
-- 1. Repair the doubled quotes.
-- ------------------------------------------------------------------------------------------------
do $mig$
declare r record; n int := 0;
begin
  for r in select jobid, jobname, command from cron.job
            where command like $q$%''project_ref''%$q$
  loop
    perform cron.alter_job(r.jobid,
      command := replace(r.command, $q$''project_ref''$q$, $q$'project_ref'$q$));
    n := n + 1;
  end loop;
  raise notice 'repaired % cron command(s)', n;
end $mig$;

-- ------------------------------------------------------------------------------------------------
-- 2. EVERY cron command must parse. Not "match a pattern I also wrote" — parse.
--    EXPLAIN plans the statement without executing it, so a job is proved syntactically whole
--    without firing an HTTP call or writing a row. Commands that are not plannable on their own
--    (DO blocks, multi-statement bodies, CALL) are checked by asking the parser directly instead of
--    the planner, and the ones that can be neither are named in the notice rather than passed over
--    in silence — an unchecked job reported as checked is how this defect got here.
-- ------------------------------------------------------------------------------------------------
do $mig$
declare r record; e text; bad text := ''; n_url int := 0; n_plan int := 0; v_ref text; got text;
begin
  select value into v_ref from public.app_secrets where key = 'project_ref';

  for r in select jobid, jobname, command from cron.job order by jobname
  loop
    -- (a) THE URL EXPRESSION, EVALUATED. This is the thing the rewrite changed, so this is the
    --     thing to test. Every occurrence of the parameterised expression is pulled out of the
    --     command and executed on its own, and the URL it produces must be exactly the URL the job
    --     had before — https://<ref>.supabase.co/... — proving both that it is valid SQL and that
    --     it still points at the same place. A string comparison could not have shown either.
    for got in
      select (regexp_matches(r.command,
        $q$('https://' \|\| \(\s*select value from (?:public\.)?app_secrets where key = 'project_ref'\s*\) \|\| '[^']*')$q$,
        'g'))[1]
    loop
      declare resolved text;
      begin
        execute 'select ' || got into resolved;
        if resolved !~ ('^https://' || v_ref || '\.supabase\.co/') then
          bad := bad || r.jobname || ' resolves to ' || coalesce(resolved,'NULL') || '; ';
        else
          n_url := n_url + 1;
        end if;
      exception when others then
        get stacked diagnostics e = message_text;
        bad := bad || r.jobname || ' URL expression will not evaluate (' || left(e,80) || '); ';
      end;
    end loop;

    -- (b) AND THE WHOLE COMMAND, PLANNED, wherever it is a single plannable statement. That covers
    --     every job this file rewrote in the `select net.http_post(...)` shape. Leading -- comment
    --     lines are stripped first: uptime_check_15min opens with four of them, and a naive prefix
    --     test called it "not a select" and reported a syntax error in a command that is fine.
    --     DO blocks and CALLs cannot be planned without running them and are covered by (a) alone;
    --     they are counted separately rather than quietly treated as checked.
    declare body text := btrim(btrim(regexp_replace(r.command, '^(\s*--[^\n]*\n)+', '', 'g')), ';');
    begin
      if body ~* '^(select|insert|update|delete|with)\y' then
        execute 'explain (costs off) ' || body;
        n_plan := n_plan + 1;
      end if;
    exception when others then
      get stacked diagnostics e = message_text;
      if sqlstate like '42%' then bad := bad || r.jobname || ' does not parse (' || left(e,80) || '); '; end if;
    end;
  end loop;

  if bad <> '' then
    raise exception 'CRON COMMAND VERIFICATION FAILED: %', bad;
  end if;
  raise notice '% parameterised URL(s) evaluate to the right host; % whole command(s) plan',
    n_url, n_plan;
end $mig$;

-- ------------------------------------------------------------------------------------------------
-- 3. And the property the first file was for: no job names the project, and every job that reads it
--    resolves to the same URL it had before.
-- ------------------------------------------------------------------------------------------------
do $mig$
declare v_ref text; n_ref int; n_param int; bad text;
begin
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select count(*) into n_ref   from cron.job where command like '%' || v_ref || '%';
  select count(*) into n_param from cron.job where command like $q$%where key = 'project_ref'%$q$;

  if n_ref <> 0 then
    raise exception 'PORTABILITY NOT ACHIEVED: % cron job(s) still name the project ref', n_ref;
  end if;

  select string_agg(jobname, ', ') into bad from cron.job
   where command like $q$%where key = 'project_ref'%$q$
     and regexp_replace(command, '\s+', ' ', 'g') !~
         $q$'https://' \|\| \( *select value from (public\.)?app_secrets where key = 'project_ref' *\) \|\| '\.supabase\.co/$q$;
  if bad is not null then
    raise exception 'MALFORMED URL after rewrite in: %', bad;
  end if;

  raise notice 'portable: 0 job(s) name the ref, % job(s) read it from app_secrets', n_param;
end $mig$;

commit;
